use std::ffi::OsString;
use std::fs::{self, DirBuilder, File, OpenOptions};
use std::io::{ErrorKind, Read, Write};
use std::os::unix::fs::{DirBuilderExt, FileTypeExt, MetadataExt, OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use rustix::fs::OFlags;

use crate::command::{CURL, Runner, WG, WG_QUICK, arguments};
use crate::config::{Config, Ipv6Policy};
use crate::dns::{DnsRecord, DnsSnapshot, parse_networksetup_values};
use crate::error::{Error, Result};
use crate::state::State;

const COMMAND_TIMEOUT: Duration = Duration::from_secs(10);
const MAX_SMALL_FILE_BYTES: u64 = 4_096;
const IPV6_ROUTES: [&str; 2] = ["::/1", "8000::/1"];
const IPV6_JOURNAL: &[u8] = b"WGRIPV6v1\n::/1\n8000::/1\n";

pub(crate) trait System {
    type LockGuard;

    fn prepare(&mut self) -> Result<()>;
    fn acquire_daemon_lock(&mut self) -> Result<Self::LockGuard>;
    fn acquire_transition_lock(&mut self, timeout: Duration) -> Result<Self::LockGuard>;
    fn paused(&mut self) -> Result<bool>;
    fn set_paused(&mut self, paused: bool) -> Result<()>;
    fn state(&mut self) -> Result<Option<State>>;
    fn set_state(&mut self, state: State) -> Result<()>;
    fn native_vpn_connected(&mut self) -> Result<bool>;
    fn tunnel_interface(&mut self) -> Result<Option<String>>;
    fn check_connectivity(&mut self) -> Result<bool>;
    fn ordinary_default_route(&mut self) -> Result<bool>;
    fn private_key_ready(&mut self) -> bool;
    fn wireguard_config_ready(&mut self) -> bool;
    fn capture_dns_snapshot(&mut self) -> Result<()>;
    fn has_dns_snapshot(&mut self) -> Result<bool>;
    fn restore_dns_snapshot(&mut self) -> Result<()>;
    fn discard_dns_snapshot(&mut self) -> Result<()>;
    fn reset_dns_to_automatic(&mut self) -> Result<()>;
    fn add_ipv6_blocks(&mut self) -> Result<()>;
    fn remove_ipv6_blocks(&mut self) -> Result<()>;
    fn wg_quick_up(&mut self) -> Result<bool>;
    fn wg_quick_down(&mut self) -> Result<bool>;
    fn wait_for_fresh_handshake(&mut self, started_at: u64) -> Result<bool>;
    fn remove_tunnel_routes_and_artifacts(&mut self, interface: &str) -> Result<()>;
    fn sleep(&mut self, duration: Duration);
    fn epoch_seconds(&mut self) -> Result<u64>;
}

pub(crate) struct MacosSystem {
    config: Config,
    runtime_directory: PathBuf,
    persistent_directory: PathBuf,
}

impl MacosSystem {
    pub(crate) fn new(config: Config) -> Self {
        let runtime_directory = config.runtime_directory();
        let persistent_directory = config.persistent_directory();
        Self {
            config,
            runtime_directory,
            persistent_directory,
        }
    }

    fn state_file(&self) -> PathBuf {
        self.runtime_directory.join("state")
    }

    fn pause_file(&self) -> PathBuf {
        self.runtime_directory.join("paused")
    }

    fn ipv6_journal_file(&self) -> PathBuf {
        self.runtime_directory.join("ipv6-blackholes")
    }

    fn dns_snapshot_file(&self) -> PathBuf {
        self.persistent_directory.join("dns-snapshot")
    }

    fn command_status(
        label: &'static str,
        program: &str,
        arguments: &[OsString],
        timeout: Duration,
    ) -> Result<bool> {
        Runner::status(label, Path::new(program), arguments, timeout)
    }

    fn command_output(
        label: &'static str,
        program: &str,
        arguments: &[OsString],
        timeout: Duration,
    ) -> Result<Option<Vec<u8>>> {
        Runner::output(label, Path::new(program), arguments, timeout)
    }

    fn network_services() -> Result<Vec<String>> {
        let output = Self::command_output(
            "network service listing",
            "/usr/sbin/networksetup",
            &arguments(["-listallnetworkservices"]),
            COMMAND_TIMEOUT,
        )?
        .ok_or_else(|| Error::unavailable("could not list network services"))?;
        parse_network_services(&output)
    }

    fn query_network_values(service: &str, option: &str) -> Result<Vec<String>> {
        let output = Self::command_output(
            "network configuration query",
            "/usr/sbin/networksetup",
            &[OsString::from(option), OsString::from(service)],
            COMMAND_TIMEOUT,
        )?
        .ok_or_else(|| Error::unavailable("network configuration query failed"))?;
        parse_networksetup_values(&output)
    }

    fn set_network_values(service: &str, option: &str, values: &[String]) -> Result<()> {
        let mut arguments = vec![OsString::from(option), OsString::from(service)];
        if values.is_empty() {
            arguments.push(OsString::from("Empty"));
        } else {
            arguments.extend(values.iter().map(OsString::from));
        }
        if !Self::command_status(
            "network configuration restore",
            "/usr/sbin/networksetup",
            &arguments,
            COMMAND_TIMEOUT,
        )? {
            return Err(Error::unavailable("network configuration restore failed"));
        }
        Ok(())
    }

    fn capture_current_dns() -> Result<DnsSnapshot> {
        let services = Self::network_services()?;
        if services.is_empty() {
            return Err(Error::unavailable("no network services were available"));
        }
        let mut records = Vec::with_capacity(services.len());
        for service in services {
            records.push(DnsRecord {
                servers: Self::query_network_values(&service, "-getdnsservers")?,
                search_domains: Self::query_network_values(&service, "-getsearchdomains")?,
                service,
            });
        }
        Ok(DnsSnapshot { records })
    }

    fn restore_dns(snapshot: &DnsSnapshot) -> Result<()> {
        for record in &snapshot.records {
            Self::set_network_values(&record.service, "-setdnsservers", &record.servers)?;
            Self::set_network_values(&record.service, "-setsearchdomains", &record.search_domains)?;
        }
        Ok(())
    }

    fn netstat_routes(family: &str) -> Result<Vec<Route>> {
        let Some(output) = Self::command_output(
            "route table query",
            "/usr/sbin/netstat",
            &arguments(["-nr", "-f", family]),
            COMMAND_TIMEOUT,
        )?
        else {
            return Err(Error::unavailable("could not read the route table"));
        };
        parse_routes(&output)
    }

    fn remove_route(family: &str, destination: &str) -> Result<bool> {
        Self::command_status(
            "route removal",
            "/sbin/route",
            &[
                OsString::from("-q"),
                OsString::from("-n"),
                OsString::from("delete"),
                OsString::from(family),
                OsString::from(destination),
            ],
            COMMAND_TIMEOUT,
        )
    }

    fn read_dns_snapshot(&self) -> Result<DnsSnapshot> {
        let bytes = read_private_file(&self.dns_snapshot_file(), 1024 * 1024)?;
        DnsSnapshot::decode(&bytes)
    }

    fn acquire_lock(&self, name: &str, timeout: Duration) -> Result<File> {
        let path = self.runtime_directory.join(name);
        let file = open_private_for_lock(&path)?;
        let deadline = Instant::now() + timeout;
        loop {
            match file.try_lock() {
                Ok(()) => return Ok(file),
                Err(std::fs::TryLockError::WouldBlock) => {
                    if Instant::now() >= deadline {
                        return Err(Error::temporary("another transition is already running"));
                    }
                    thread::sleep(Duration::from_millis(50));
                }
                Err(std::fs::TryLockError::Error(error)) => {
                    return Err(Error::software(format!(
                        "could not acquire controller lock: {error}"
                    )));
                }
            }
        }
    }
}

impl System for MacosSystem {
    type LockGuard = File;

    fn prepare(&mut self) -> Result<()> {
        if !rustix::process::geteuid().is_root() {
            return Err(Error::permission("this command must run as root"));
        }
        ensure_private_directory(Path::new("/private/var/run/wireguard-roaming"))?;
        ensure_private_directory(&self.runtime_directory)?;
        ensure_private_directory(Path::new("/private/var/db/wireguard-roaming"))?;
        ensure_private_directory(&self.persistent_directory)?;
        Ok(())
    }

    fn acquire_daemon_lock(&mut self) -> Result<Self::LockGuard> {
        self.acquire_lock("daemon.lock", Duration::ZERO)
            .map_err(|_| Error::temporary("another roaming daemon is already running"))
    }

    fn acquire_transition_lock(&mut self, timeout: Duration) -> Result<Self::LockGuard> {
        self.acquire_lock("transition.lock", timeout)
    }

    fn paused(&mut self) -> Result<bool> {
        private_file_exists(&self.pause_file())
    }

    fn set_paused(&mut self, paused: bool) -> Result<()> {
        if paused {
            write_private_atomic(&self.runtime_directory, "paused", &[])
        } else {
            remove_if_exists(&self.pause_file())
        }
    }

    fn state(&mut self) -> Result<Option<State>> {
        if !private_file_exists(&self.state_file())? {
            return Ok(None);
        }
        let bytes = read_private_file(&self.state_file(), 128)?;
        let value = std::str::from_utf8(&bytes)
            .map_err(|_| Error::software("controller state is not UTF-8"))?
            .trim_end_matches(['\r', '\n']);
        State::parse(value)
            .map(Some)
            .ok_or_else(|| Error::software("controller state is invalid"))
    }

    fn set_state(&mut self, state: State) -> Result<()> {
        if self.state()? == Some(state) {
            return Ok(());
        }
        let mut bytes = state.as_str().as_bytes().to_vec();
        bytes.push(b'\n');
        write_private_atomic(&self.runtime_directory, "state", &bytes)?;
        println!("wireguard-roaming: {}", state.as_str());
        Ok(())
    }

    fn native_vpn_connected(&mut self) -> Result<bool> {
        let output = Self::command_output(
            "native VPN query",
            "/usr/sbin/scutil",
            &arguments(["--nc", "list"]),
            COMMAND_TIMEOUT,
        )?
        .ok_or_else(|| Error::unavailable("native VPN status is unavailable"))?;
        parse_native_vpn_connected(&output)
    }

    fn tunnel_interface(&mut self) -> Result<Option<String>> {
        let name_file = self.config.wireguard_name_file();
        if !private_file_exists_unchecked_mode(&name_file)? {
            return Ok(None);
        }
        let bytes = read_nofollow_file(&name_file, 64)?;
        let candidate = std::str::from_utf8(&bytes)
            .map_err(|_| Error::software("WireGuard interface name is not UTF-8"))?
            .trim_end_matches(['\r', '\n']);
        if !valid_utun(candidate) {
            return Err(Error::software("WireGuard interface name is invalid"));
        }
        let socket = Path::new("/private/var/run/wireguard").join(format!("{candidate}.sock"));
        let metadata = match fs::symlink_metadata(socket) {
            Ok(metadata) => metadata,
            Err(error) if error.kind() == ErrorKind::NotFound => return Ok(None),
            Err(error) => {
                return Err(Error::software(format!(
                    "could not inspect WireGuard socket: {error}"
                )));
            }
        };
        if !metadata.file_type().is_socket() {
            return Ok(None);
        }
        let active = Self::command_status(
            "WireGuard interface query",
            WG,
            &[OsString::from("show"), OsString::from(candidate)],
            COMMAND_TIMEOUT,
        )?;
        Ok(active.then(|| candidate.to_owned()))
    }

    fn check_connectivity(&mut self) -> Result<bool> {
        let Some(url) = &self.config.connectivity_check_url else {
            return Ok(true);
        };
        let timeout = self.config.activation_timeout.as_secs().to_string();
        Self::command_status(
            "HTTPS connectivity check",
            CURL,
            &[
                OsString::from("--disable"),
                OsString::from("--ipv4"),
                OsString::from("--fail"),
                OsString::from("--silent"),
                OsString::from("--show-error"),
                OsString::from("--location"),
                OsString::from("--max-redirs"),
                OsString::from("3"),
                OsString::from("--proto"),
                OsString::from("=https"),
                OsString::from("--proto-redir"),
                OsString::from("=https"),
                OsString::from("--connect-timeout"),
                OsString::from("4"),
                OsString::from("--max-time"),
                OsString::from(&timeout),
                OsString::from("--output"),
                OsString::from("/dev/null"),
                OsString::from("--"),
                OsString::from(url),
            ],
            self.config.activation_timeout + Duration::from_secs(2),
        )
    }

    fn ordinary_default_route(&mut self) -> Result<bool> {
        Self::command_status(
            "ordinary default route query",
            "/sbin/route",
            &arguments(["-n", "get", "-inet", "default"]),
            COMMAND_TIMEOUT,
        )
    }

    fn private_key_ready(&mut self) -> bool {
        validate_secret_file(&self.config.private_key_file, 256).is_ok()
    }

    fn wireguard_config_ready(&mut self) -> bool {
        fs::metadata(self.config.wireguard_config_file()).is_ok_and(|metadata| metadata.is_file())
    }

    fn capture_dns_snapshot(&mut self) -> Result<()> {
        if self.has_dns_snapshot()? {
            return Ok(());
        }
        let snapshot = Self::capture_current_dns()?;
        let bytes = snapshot.encode()?;
        write_private_atomic(&self.persistent_directory, "dns-snapshot", &bytes)
    }

    fn has_dns_snapshot(&mut self) -> Result<bool> {
        private_file_exists(&self.dns_snapshot_file())
    }

    fn restore_dns_snapshot(&mut self) -> Result<()> {
        let snapshot = self.read_dns_snapshot()?;
        Self::restore_dns(&snapshot)
    }

    fn discard_dns_snapshot(&mut self) -> Result<()> {
        remove_if_exists(&self.dns_snapshot_file())
    }

    fn reset_dns_to_automatic(&mut self) -> Result<()> {
        for service in Self::network_services()? {
            Self::set_network_values(&service, "-setdnsservers", &[])?;
            Self::set_network_values(&service, "-setsearchdomains", &[])?;
        }
        self.discard_dns_snapshot()
    }

    fn add_ipv6_blocks(&mut self) -> Result<()> {
        if self.config.ipv6_policy == Ipv6Policy::AllowBypass {
            return self.remove_ipv6_blocks();
        }
        let journal_path = self.ipv6_journal_file();
        if private_file_exists(&journal_path)? {
            let journal = read_private_file(&journal_path, MAX_SMALL_FILE_BYTES)?;
            if journal == IPV6_JOURNAL {
                let routes = Self::netstat_routes("inet6")?;
                let all_active = IPV6_ROUTES.iter().all(|expected| {
                    routes.iter().any(|route| {
                        route.destination == *expected
                            && route.interface.starts_with("lo")
                            && matches!(route.gateway.as_str(), "::1" | "localhost")
                    })
                });
                if all_active {
                    return Ok(());
                }
            }
            self.remove_ipv6_blocks()?;
        }
        let routes = Self::netstat_routes("inet6")?;
        if IPV6_ROUTES
            .iter()
            .any(|route| routes.iter().any(|entry| entry.destination == *route))
        {
            return Err(Error::unavailable("an IPv6 blocking route already exists"));
        }
        write_private_atomic(&self.runtime_directory, "ipv6-blackholes", IPV6_JOURNAL)?;
        for route in IPV6_ROUTES {
            let added = Self::command_status(
                "IPv6 blocking route creation",
                "/sbin/route",
                &[
                    OsString::from("-q"),
                    OsString::from("-n"),
                    OsString::from("add"),
                    OsString::from("-inet6"),
                    OsString::from(route),
                    OsString::from("::1"),
                    OsString::from("-blackhole"),
                ],
                COMMAND_TIMEOUT,
            )?;
            if !added {
                self.remove_ipv6_blocks()?;
                return Err(Error::unavailable("could not install IPv6 blocking routes"));
            }
        }
        Ok(())
    }

    fn remove_ipv6_blocks(&mut self) -> Result<()> {
        let path = self.ipv6_journal_file();
        if !private_file_exists(&path)? {
            return Ok(());
        }
        let journal = read_private_file(&path, MAX_SMALL_FILE_BYTES)?;
        let current_format = journal == IPV6_JOURNAL;
        let legacy_format =
            journal == b"::/1\n8000::/1\n" || journal == b"::/1\n" || journal == b"8000::/1\n";
        if !current_format && !legacy_format {
            return Err(Error::software("IPv6 route journal is invalid"));
        }
        let routes = Self::netstat_routes("inet6")?;
        for route in IPV6_ROUTES {
            let is_managed = routes.iter().any(|entry| {
                entry.destination == route
                    && entry.interface.starts_with("lo")
                    && matches!(entry.gateway.as_str(), "::1" | "localhost")
            });
            if is_managed && !Self::remove_route("-inet6", route)? {
                return Err(Error::unavailable(
                    "could not remove an IPv6 blocking route",
                ));
            }
        }
        let remaining = Self::netstat_routes("inet6")?;
        if IPV6_ROUTES.iter().any(|route| {
            remaining.iter().any(|entry| {
                entry.destination == *route
                    && entry.interface.starts_with("lo")
                    && matches!(entry.gateway.as_str(), "::1" | "localhost")
            })
        }) {
            return Err(Error::unavailable("an IPv6 blocking route remains active"));
        }
        remove_if_exists(&path)
    }

    fn wg_quick_up(&mut self) -> Result<bool> {
        Self::command_status(
            "WireGuard activation",
            WG_QUICK,
            &[
                OsString::from("up"),
                self.config.wireguard_config_file().into_os_string(),
            ],
            self.config.activation_timeout + Duration::from_secs(15),
        )
    }

    fn wg_quick_down(&mut self) -> Result<bool> {
        Self::command_status(
            "WireGuard deactivation",
            WG_QUICK,
            &[
                OsString::from("down"),
                self.config.wireguard_config_file().into_os_string(),
            ],
            self.config.activation_timeout + Duration::from_secs(15),
        )
    }

    fn wait_for_fresh_handshake(&mut self, started_at: u64) -> Result<bool> {
        let deadline = Instant::now() + self.config.activation_timeout;
        loop {
            // This probe only stimulates traffic; the handshake timestamp below is authoritative.
            drop(Self::command_status(
                "WireGuard handshake probe",
                "/sbin/ping",
                &arguments(["-q", "-c", "1", "-W", "1000", "1.1.1"]),
                Duration::from_secs(3),
            ));
            let Some(interface) = self.tunnel_interface()? else {
                return Ok(false);
            };
            let output = Self::command_output(
                "WireGuard handshake query",
                WG,
                &[
                    OsString::from("show"),
                    OsString::from(interface),
                    OsString::from("latest-handshakes"),
                ],
                COMMAND_TIMEOUT,
            )?;
            if output
                .as_deref()
                .and_then(parse_latest_handshake)
                .is_some_and(|latest| latest >= started_at)
            {
                return Ok(true);
            }
            if Instant::now() >= deadline {
                return Ok(false);
            }
            thread::sleep(Duration::from_secs(1));
        }
    }

    fn remove_tunnel_routes_and_artifacts(&mut self, interface: &str) -> Result<()> {
        if !valid_utun(interface) {
            return Err(Error::software(
                "refusing to remove an invalid tunnel interface",
            ));
        }
        let ipv4 = Self::netstat_routes("inet")?;
        for route in ipv4
            .iter()
            .filter(|route| route.interface == interface)
            .take(256)
        {
            let _removed = Self::remove_route("-inet", &route.destination)?;
        }
        let ipv6 = Self::netstat_routes("inet6")?;
        for route in ipv6
            .iter()
            .filter(|route| {
                route.interface == interface
                    || (route.interface.starts_with("lo") && route.gateway == interface)
            })
            .take(256)
        {
            let _removed = Self::remove_route("-inet6", &route.destination)?;
        }
        if Self::netstat_routes("inet")?
            .iter()
            .chain(Self::netstat_routes("inet6")?.iter())
            .any(|route| route.interface == interface)
        {
            return Err(Error::unavailable("tunnel routes remain active"));
        }
        let socket = Path::new("/private/var/run/wireguard").join(format!("{interface}.sock"));
        remove_if_exists(&socket)?;
        remove_if_exists(&self.config.wireguard_name_file())
    }

    fn sleep(&mut self, duration: Duration) {
        thread::sleep(duration);
    }

    fn epoch_seconds(&mut self) -> Result<u64> {
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|duration| duration.as_secs())
            .map_err(|_| Error::software("system clock is before the Unix epoch"))
    }
}

#[derive(Debug, Eq, PartialEq)]
struct Route {
    destination: String,
    gateway: String,
    interface: String,
}

fn ensure_private_directory(path: &Path) -> Result<()> {
    match fs::symlink_metadata(path) {
        Ok(metadata) => validate_private_directory(&metadata)?,
        Err(error) if error.kind() == ErrorKind::NotFound => {
            let mut builder = DirBuilder::new();
            builder.mode(0o700);
            builder.create(path).map_err(|error| {
                Error::software(format!("could not create runtime directory: {error}"))
            })?;
        }
        Err(error) => {
            return Err(Error::software(format!(
                "could not inspect runtime directory: {error}"
            )));
        }
    }
    fs::set_permissions(path, fs::Permissions::from_mode(0o700)).map_err(|error| {
        Error::software(format!("could not protect runtime directory: {error}"))
    })?;
    let metadata = fs::symlink_metadata(path)
        .map_err(|error| Error::software(format!("could not verify runtime directory: {error}")))?;
    validate_private_directory(&metadata)
}

fn validate_private_directory(metadata: &fs::Metadata) -> Result<()> {
    if metadata.file_type().is_symlink()
        || !metadata.is_dir()
        || metadata.uid() != 0
        || metadata.mode() & 0o077 != 0
    {
        return Err(Error::permission(
            "runtime directory is not private and root-owned",
        ));
    }
    Ok(())
}

fn nofollow_flags() -> Result<i32> {
    i32::try_from(OFlags::NOFOLLOW.bits())
        .map_err(|_| Error::software("O_NOFOLLOW does not fit the platform command flag type"))
}

fn open_private_for_lock(path: &Path) -> Result<File> {
    let file = OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .mode(0o600)
        .custom_flags(nofollow_flags()?)
        .open(path)
        .map_err(|error| Error::software(format!("could not open controller lock: {error}")))?;
    validate_private_regular_file(&file.metadata().map_err(|error| {
        Error::software(format!("could not inspect controller lock: {error}"))
    })?)?;
    file.set_permissions(fs::Permissions::from_mode(0o600))
        .map_err(|error| Error::software(format!("could not protect controller lock: {error}")))?;
    Ok(file)
}

fn validate_secret_file(path: &Path, maximum: u64) -> Result<File> {
    if !path.is_absolute() || path.starts_with("/nix/store") {
        return Err(Error::permission("secret path is not allowed"));
    }
    let file = OpenOptions::new()
        .read(true)
        .custom_flags(nofollow_flags()?)
        .open(path)
        .map_err(|_| Error::unavailable("secret file is unavailable"))?;
    let metadata = file
        .metadata()
        .map_err(|_| Error::unavailable("secret file metadata is unavailable"))?;
    validate_private_regular_file(&metadata)
        .map_err(|_| Error::permission("secret file is not private and root-owned"))?;
    if metadata.len() > maximum {
        return Err(Error::permission("secret file exceeded its size limit"));
    }
    Ok(file)
}

fn read_private_file(path: &Path, maximum: u64) -> Result<Vec<u8>> {
    let file = OpenOptions::new()
        .read(true)
        .custom_flags(nofollow_flags()?)
        .open(path)
        .map_err(|error| Error::software(format!("could not open controller state: {error}")))?;
    let metadata = file
        .metadata()
        .map_err(|error| Error::software(format!("could not inspect controller state: {error}")))?;
    validate_private_regular_file(&metadata)?;
    if metadata.len() > maximum {
        return Err(Error::software("controller state exceeded its size limit"));
    }
    let mut bytes = Vec::new();
    file.take(maximum + 1)
        .read_to_end(&mut bytes)
        .map_err(|error| Error::software(format!("could not read controller state: {error}")))?;
    if bytes.len() as u64 > maximum {
        return Err(Error::software("controller state exceeded its size limit"));
    }
    Ok(bytes)
}

fn read_nofollow_file(path: &Path, maximum: u64) -> Result<Vec<u8>> {
    let file = OpenOptions::new()
        .read(true)
        .custom_flags(nofollow_flags()?)
        .open(path)
        .map_err(|error| Error::software(format!("could not open WireGuard state: {error}")))?;
    let metadata = file
        .metadata()
        .map_err(|error| Error::software(format!("could not inspect WireGuard state: {error}")))?;
    if !metadata.is_file() || metadata.len() > maximum {
        return Err(Error::software("WireGuard state is invalid"));
    }
    let mut bytes = Vec::new();
    file.take(maximum + 1)
        .read_to_end(&mut bytes)
        .map_err(|error| Error::software(format!("could not read WireGuard state: {error}")))?;
    if bytes.len() as u64 > maximum {
        return Err(Error::software("WireGuard state exceeded its size limit"));
    }
    Ok(bytes)
}

fn validate_private_regular_file(metadata: &fs::Metadata) -> Result<()> {
    if !metadata.is_file()
        || metadata.uid() != 0
        || metadata.mode() & 0o077 != 0
        || metadata.mode() & 0o400 == 0
    {
        return Err(Error::permission("file is not private and root-owned"));
    }
    Ok(())
}

fn write_private_atomic(directory: &Path, name: &str, bytes: &[u8]) -> Result<()> {
    let temporary_name = format!(".{name}.new");
    let temporary_path = directory.join(&temporary_name);
    remove_if_exists(&temporary_path)?;
    let mut file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .custom_flags(nofollow_flags()?)
        .open(&temporary_path)
        .map_err(|error| Error::software(format!("could not create controller state: {error}")))?;
    file.write_all(bytes)
        .and_then(|()| file.sync_all())
        .map_err(|error| Error::software(format!("could not write controller state: {error}")))?;
    fs::rename(&temporary_path, directory.join(name))
        .map_err(|error| Error::software(format!("could not publish controller state: {error}")))?;
    File::open(directory)
        .and_then(|directory| directory.sync_all())
        .map_err(|error| Error::software(format!("could not sync controller state: {error}")))
}

fn private_file_exists(path: &Path) -> Result<bool> {
    let exists = private_file_exists_unchecked_mode(path)?;
    if !exists {
        return Ok(false);
    }
    let file = OpenOptions::new()
        .read(true)
        .custom_flags(nofollow_flags()?)
        .open(path)
        .map_err(|error| Error::software(format!("could not open controller state: {error}")))?;
    validate_private_regular_file(&file.metadata().map_err(|error| {
        Error::software(format!("could not inspect controller state: {error}"))
    })?)?;
    Ok(true)
}

fn private_file_exists_unchecked_mode(path: &Path) -> Result<bool> {
    match fs::symlink_metadata(path) {
        Ok(metadata) if metadata.file_type().is_symlink() => {
            Err(Error::permission("refusing a symlinked state file"))
        }
        Ok(metadata) if metadata.is_file() => Ok(true),
        Ok(_) => Err(Error::software("state path is not a regular file")),
        Err(error) if error.kind() == ErrorKind::NotFound => Ok(false),
        Err(error) => Err(Error::software(format!(
            "could not inspect state path: {error}"
        ))),
    }
}

fn remove_if_exists(path: &Path) -> Result<()> {
    match fs::remove_file(path) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == ErrorKind::NotFound => Ok(()),
        Err(error) => Err(Error::software(format!(
            "could not remove controller state: {error}"
        ))),
    }
}

fn parse_network_services(output: &[u8]) -> Result<Vec<String>> {
    let text = std::str::from_utf8(output)
        .map_err(|_| Error::unavailable("network service listing is not UTF-8"))?;
    let mut services = Vec::new();
    for line in text.lines().skip(1) {
        let line = line.strip_suffix('\r').unwrap_or(line);
        let line = line.strip_prefix('*').unwrap_or(line);
        if line.is_empty() {
            continue;
        }
        if line.len() > 4_096 || line.bytes().any(|byte| byte.is_ascii_control()) {
            return Err(Error::unavailable("network service name is invalid"));
        }
        services.push(line.to_owned());
        if services.len() > 128 {
            return Err(Error::unavailable("too many network services"));
        }
    }
    Ok(services)
}

fn parse_native_vpn_connected(output: &[u8]) -> Result<bool> {
    let text = std::str::from_utf8(output)
        .map_err(|_| Error::unavailable("native VPN status is not UTF-8"))?;
    Ok(text
        .lines()
        .any(|line| line.trim_start().starts_with('*') && line.contains("(Connected)")))
}

fn parse_latest_handshake(output: &[u8]) -> Option<u64> {
    let text = std::str::from_utf8(output).ok()?;
    text.lines()
        .filter_map(|line| line.split_ascii_whitespace().nth(1))
        .filter_map(|value| value.parse::<u64>().ok())
        .max()
}

fn parse_routes(output: &[u8]) -> Result<Vec<Route>> {
    let text =
        std::str::from_utf8(output).map_err(|_| Error::unavailable("route table is not UTF-8"))?;
    let mut destination_index = None;
    let mut gateway_index = None;
    let mut interface_index = None;
    let mut routes = Vec::new();
    for line in text.lines() {
        let fields: Vec<&str> = line.split_ascii_whitespace().collect();
        if fields.first() == Some(&"Destination") {
            destination_index = fields.iter().position(|field| *field == "Destination");
            gateway_index = fields.iter().position(|field| *field == "Gateway");
            interface_index = fields.iter().position(|field| *field == "Netif");
            continue;
        }
        let (Some(destination), Some(gateway), Some(interface)) =
            (destination_index, gateway_index, interface_index)
        else {
            continue;
        };
        let (Some(destination), Some(gateway), Some(interface)) = (
            fields.get(destination),
            fields.get(gateway),
            fields.get(interface),
        ) else {
            continue;
        };
        routes.push(Route {
            destination: (*destination).to_owned(),
            gateway: (*gateway).to_owned(),
            interface: (*interface).to_owned(),
        });
        if routes.len() > 16_384 {
            return Err(Error::unavailable("route table exceeded its size limit"));
        }
    }
    if destination_index.is_none() || gateway_index.is_none() || interface_index.is_none() {
        return Err(Error::unavailable("route table columns are unavailable"));
    }
    Ok(routes)
}

fn valid_utun(value: &str) -> bool {
    value.strip_prefix("utun").is_some_and(|suffix| {
        !suffix.is_empty() && suffix.bytes().all(|byte| byte.is_ascii_digit())
    })
}

#[cfg(test)]
mod tests {
    use super::{
        Route, parse_latest_handshake, parse_native_vpn_connected, parse_network_services,
        parse_routes,
    };
    use crate::error::Result;

    #[test]
    fn parses_native_vpn_state() -> Result<()> {
        assert!(parse_native_vpn_connected(b"* (Connected) Example\n")?);
        assert!(!parse_native_vpn_connected(b"  (Disconnected) Example\n")?);
        assert!(parse_native_vpn_connected(&[0xff]).is_err());
        Ok(())
    }

    #[test]
    fn parses_latest_handshake_without_retaining_peer_keys() {
        assert_eq!(parse_latest_handshake(b"peer-a 10\npeer-b 42\n"), Some(42));
        assert_eq!(parse_latest_handshake(b"peer-a invalid\n"), None);
    }

    #[test]
    fn discovers_netstat_columns_instead_of_assuming_positions() -> Result<()> {
        let modern = b"Routing tables\nDestination Gateway Flags Netif Expire\ndefault 192.0.2.1 UGScg en0\n0/1 utun7 USc utun7\n";
        assert_eq!(
            parse_routes(modern)?,
            [
                Route {
                    destination: "default".into(),
                    gateway: "192.0.2.1".into(),
                    interface: "en0".into(),
                },
                Route {
                    destination: "0/1".into(),
                    gateway: "utun7".into(),
                    interface: "utun7".into(),
                },
            ]
        );

        let legacy =
            b"Destination Gateway Flags Refs Use Netif Expire\ndefault 192.0.2.1 UGSc 12 34 en0\n";
        assert_eq!(parse_routes(legacy)?[0].interface, "en0");
        Ok(())
    }

    #[test]
    fn parses_network_service_names_as_arguments() -> Result<()> {
        let output = b"An asterisk denotes that a network service is disabled.\nWi-Fi\n*Thunderbolt Bridge\n";
        assert_eq!(
            parse_network_services(output)?,
            ["Wi-Fi", "Thunderbolt Bridge"]
        );
        Ok(())
    }
}
