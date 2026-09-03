use std::ffi::OsString;
use std::path::{Path, PathBuf};
use std::time::Duration;

use crate::error::{Error, Result};

pub(crate) const USAGE: &str =
    "usage: wireguard-roaming {run|reconcile|up|down|pause|resume|status|recover-dns}";

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum Action {
    Run,
    Reconcile,
    Up,
    Down,
    Pause,
    Resume,
    Status,
    RecoverDns,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum Ipv6Policy {
    AllowBypass,
    BlockWhileConnected,
}

#[derive(Clone)]
pub(crate) struct Config {
    pub(crate) action: Action,
    pub(crate) private_key_file: PathBuf,
    pub(crate) interface_name: String,
    pub(crate) auto_connect: bool,
    pub(crate) ipv6_policy: Ipv6Policy,
    pub(crate) reconcile_interval: Duration,
    pub(crate) activation_timeout: Duration,
    pub(crate) connectivity_check_url: Option<String>,
}

impl Config {
    #[allow(
        clippy::too_many_lines,
        reason = "keeping argument parsing in one function makes duplicate and required-option checks auditable"
    )]
    pub(crate) fn parse(arguments: impl IntoIterator<Item = OsString>) -> Result<Self> {
        let mut values = arguments.into_iter();
        let _program = values.next();
        let mut private_key_file = None;
        let mut interface_name = None;
        let mut auto_connect = None;
        let mut ipv6_policy = None;
        let mut reconcile_interval = None;
        let mut activation_timeout = None;
        let mut connectivity_check_url = None;
        let mut action = None;

        while let Some(argument) = values.next() {
            let argument = argument
                .into_string()
                .map_err(|_| Error::usage("arguments must be valid UTF-8"))?;
            match argument.as_str() {
                "--private-key-file" => set_once(
                    &mut private_key_file,
                    PathBuf::from(next_string(&mut values, "--private-key-file")?),
                    "--private-key-file",
                )?,
                "--interface" => set_once(
                    &mut interface_name,
                    next_string(&mut values, "--interface")?,
                    "--interface",
                )?,
                "--auto-connect" => {
                    let value = parse_bool(&next_string(&mut values, "--auto-connect")?)?;
                    set_once(&mut auto_connect, value, "--auto-connect")?;
                }
                "--ipv6-policy" => {
                    let value = match next_string(&mut values, "--ipv6-policy")?.as_str() {
                        "allow-bypass" => Ipv6Policy::AllowBypass,
                        "block-while-connected" => Ipv6Policy::BlockWhileConnected,
                        _ => return Err(Error::usage("invalid IPv6 policy")),
                    };
                    set_once(&mut ipv6_policy, value, "--ipv6-policy")?;
                }
                "--reconcile-interval" => {
                    let value = parse_seconds(
                        &next_string(&mut values, "--reconcile-interval")?,
                        15,
                        3_600,
                        "reconcile interval",
                    )?;
                    set_once(&mut reconcile_interval, value, "--reconcile-interval")?;
                }
                "--activation-timeout" => {
                    let value = parse_seconds(
                        &next_string(&mut values, "--activation-timeout")?,
                        3,
                        60,
                        "activation timeout",
                    )?;
                    set_once(&mut activation_timeout, value, "--activation-timeout")?;
                }
                "--connectivity-check-url" => {
                    let value = next_string(&mut values, "--connectivity-check-url")?;
                    let value = if value.is_empty() { None } else { Some(value) };
                    set_once(
                        &mut connectivity_check_url,
                        value,
                        "--connectivity-check-url",
                    )?;
                }
                "--help" | "-h" => return Err(Error::usage(USAGE)),
                value if value.starts_with('-') => {
                    return Err(Error::usage("unknown option"));
                }
                value => {
                    if action.is_some() || values.next().is_some() {
                        return Err(Error::usage("exactly one action is required"));
                    }
                    action = Some(parse_action(value)?);
                }
            }
        }

        let config = Self {
            action: action.ok_or_else(|| Error::usage("an action is required"))?,
            private_key_file: private_key_file
                .ok_or_else(|| Error::usage("--private-key-file is required"))?,
            interface_name: interface_name
                .ok_or_else(|| Error::usage("--interface is required"))?,
            auto_connect: auto_connect.ok_or_else(|| Error::usage("--auto-connect is required"))?,
            ipv6_policy: ipv6_policy.ok_or_else(|| Error::usage("--ipv6-policy is required"))?,
            reconcile_interval: reconcile_interval
                .ok_or_else(|| Error::usage("--reconcile-interval is required"))?,
            activation_timeout: activation_timeout
                .ok_or_else(|| Error::usage("--activation-timeout is required"))?,
            connectivity_check_url: connectivity_check_url
                .ok_or_else(|| Error::usage("--connectivity-check-url is required"))?,
        };
        config.validate()?;
        Ok(config)
    }

    pub(crate) fn runtime_directory(&self) -> PathBuf {
        Path::new("/private/var/run/wireguard-roaming").join(&self.interface_name)
    }

    pub(crate) fn persistent_directory(&self) -> PathBuf {
        Path::new("/private/var/db/wireguard-roaming").join(&self.interface_name)
    }

    pub(crate) fn wireguard_config_file(&self) -> PathBuf {
        Path::new("/etc/wireguard").join(format!("{}.conf", self.interface_name))
    }

    pub(crate) fn wireguard_name_file(&self) -> PathBuf {
        Path::new("/private/var/run/wireguard").join(format!("{}.name", self.interface_name))
    }

    fn validate(&self) -> Result<()> {
        if !valid_interface_name(&self.interface_name) {
            return Err(Error::usage("invalid WireGuard interface name"));
        }
        validate_secret_path(&self.private_key_file, "private key")?;
        if let Some(url) = &self.connectivity_check_url
            && (url.len() > 2_048
                || !url.starts_with("https://")
                || url.bytes().any(|byte| byte.is_ascii_control()))
        {
            return Err(Error::usage(
                "connectivity check URL must be a valid HTTPS URL",
            ));
        }
        Ok(())
    }
}

fn set_once<T>(slot: &mut Option<T>, value: T, name: &str) -> Result<()> {
    if slot.replace(value).is_some() {
        return Err(Error::usage(format!("duplicate option: {name}")));
    }
    Ok(())
}

fn next_string(values: &mut impl Iterator<Item = OsString>, option: &str) -> Result<String> {
    values
        .next()
        .ok_or_else(|| Error::usage(format!("missing value for {option}")))?
        .into_string()
        .map_err(|_| Error::usage(format!("invalid value for {option}")))
}

fn parse_bool(value: &str) -> Result<bool> {
    match value {
        "true" => Ok(true),
        "false" => Ok(false),
        _ => Err(Error::usage("boolean values must be true or false")),
    }
}

fn parse_seconds(value: &str, minimum: u64, maximum: u64, name: &str) -> Result<Duration> {
    Ok(Duration::from_secs(parse_number(
        value, minimum, maximum, name,
    )?))
}

fn parse_number(value: &str, minimum: u64, maximum: u64, name: &str) -> Result<u64> {
    let number = value
        .parse::<u64>()
        .map_err(|_| Error::usage(format!("invalid {name}")))?;
    if !(minimum..=maximum).contains(&number) {
        return Err(Error::usage(format!("invalid {name}")));
    }
    Ok(number)
}

fn parse_action(value: &str) -> Result<Action> {
    match value {
        "run" => Ok(Action::Run),
        "reconcile" => Ok(Action::Reconcile),
        "up" => Ok(Action::Up),
        "down" => Ok(Action::Down),
        "pause" => Ok(Action::Pause),
        "resume" => Ok(Action::Resume),
        "status" => Ok(Action::Status),
        "recover-dns" => Ok(Action::RecoverDns),
        _ => Err(Error::usage("unknown action")),
    }
}

fn valid_interface_name(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 15
        && value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || b"_=+.-".contains(&byte))
}

fn validate_secret_path(path: &Path, label: &str) -> Result<()> {
    if !path.is_absolute() || path.starts_with("/nix/store") {
        return Err(Error::usage(format!(
            "{label} path must be absolute and outside /nix/store"
        )));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::{Action, Config};
    use crate::error::Result;
    use std::ffi::OsString;

    fn arguments(action: &str) -> Vec<OsString> {
        [
            "controller",
            "--private-key-file",
            "/private/var/db/secrets/private-key",
            "--interface",
            "home-vpn",
            "--auto-connect",
            "true",
            "--ipv6-policy",
            "block-while-connected",
            "--reconcile-interval",
            "60",
            "--activation-timeout",
            "15",
            "--connectivity-check-url",
            "https://example.test/success",
            action,
        ]
        .into_iter()
        .map(OsString::from)
        .collect()
    }

    #[test]
    fn parses_the_stable_command_interface() -> Result<()> {
        let config = Config::parse(arguments("run"))?;
        assert_eq!(config.action, Action::Run);
        assert_eq!(config.interface_name, "home-vpn");
        assert!(config.auto_connect);
        Ok(())
    }

    #[test]
    fn rejects_non_https_probe_urls() {
        let mut values = arguments("run");
        let index = values
            .iter()
            .position(|value| value == "--connectivity-check-url")
            .map(|value| value + 1);
        if let Some(index) = index {
            values[index] = OsString::from("file:///private/etc/passwd");
        }
        assert!(Config::parse(values).is_err());
    }

    #[test]
    fn rejects_duplicate_options() {
        let mut values = arguments("run");
        values.insert(1, OsString::from("--interface"));
        values.insert(2, OsString::from("other"));
        assert!(Config::parse(values).is_err());
    }
}
