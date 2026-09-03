use std::sync::mpsc::{self, RecvTimeoutError};
use std::thread;
use std::time::Duration;

use signal_hook::consts::signal::{SIGHUP, SIGINT, SIGTERM};
use signal_hook::iterator::Signals;

use crate::config::{Action, Config};
use crate::error::{Error, Result};
use crate::policy::{Decision, DownReason, Observation, decide};
use crate::state::State;
use crate::system::System;

pub(crate) struct Controller<S> {
    config: Config,
    system: S,
}

impl<S: System> Controller<S> {
    pub(crate) const fn new(config: Config, system: S) -> Self {
        Self { config, system }
    }

    pub(crate) fn execute(&mut self, action: Action) -> Result<()> {
        self.system.prepare()?;
        match action {
            Action::Run => self.run_loop(),
            Action::Reconcile => self.with_transition(Self::reconcile),
            Action::Up => self.with_transition(|controller| {
                controller.system.set_paused(false)?;
                controller.up_tunnel()
            }),
            Action::Down => self.with_transition(|controller| {
                controller.system.set_paused(true)?;
                controller.down_tunnel(State::ManualDown)
            }),
            Action::Pause => self.with_transition(|controller| {
                controller.system.set_paused(true)?;
                controller.down_tunnel(State::Paused)
            }),
            Action::Resume => self.with_transition(|controller| {
                controller.system.set_paused(false)?;
                controller.reconcile()
            }),
            Action::Status => self.status(),
            Action::RecoverDns => self.with_transition(Self::recover_dns),
        }
    }

    fn with_transition(&mut self, operation: impl FnOnce(&mut Self) -> Result<()>) -> Result<()> {
        let timeout = self.config.activation_timeout + Duration::from_secs(15);
        let _lock = self.system.acquire_transition_lock(timeout)?;
        operation(self)
    }

    fn run_loop(&mut self) -> Result<()> {
        let _daemon_lock = self.system.acquire_daemon_lock()?;
        let mut signals = Signals::new([SIGTERM, SIGINT, SIGHUP]).map_err(|error| {
            Error::software(format!("could not register signal handling: {error}"))
        })?;
        let signal_handle = signals.handle();
        let (sender, receiver) = mpsc::sync_channel(1);
        let signal_thread = thread::Builder::new()
            .name("wireguard-signal-waiter".into())
            .spawn(move || {
                for signal in signals.forever() {
                    if sender.send(signal).is_err() || matches!(signal, SIGTERM | SIGINT) {
                        break;
                    }
                }
            })
            .map_err(|error| {
                Error::software(format!("could not start signal handling: {error}"))
            })?;

        let run_result = loop {
            if let Err(error) = self.with_transition(Self::reconcile) {
                eprintln!("wireguard-roaming: reconcile-error: {error}");
            }
            match receiver.recv_timeout(self.config.reconcile_interval) {
                Ok(SIGTERM | SIGINT) => break Ok(()),
                Ok(_) | Err(RecvTimeoutError::Timeout) => {}
                Err(RecvTimeoutError::Disconnected) => {
                    break Err(Error::software("signal handling stopped unexpectedly"));
                }
            }
        };

        signal_handle.close();
        signal_thread
            .join()
            .map_err(|_| Error::software("signal handling thread stopped unexpectedly"))?;
        let shutdown_result =
            self.with_transition(|controller| controller.down_tunnel(State::Stopped));
        run_result.and(shutdown_result)
    }

    fn status(&mut self) -> Result<()> {
        if let Some(state) = self.system.state()? {
            println!("{}", state.as_str());
        } else if self.system.tunnel_interface()?.is_some() {
            println!("connected-unmanaged");
        } else {
            println!("not-started");
        }
        Ok(())
    }

    fn reconcile(&mut self) -> Result<()> {
        let paused = self.system.paused()?;
        if paused {
            return self.apply_decision(Decision::EnsureDown(DownReason::Paused));
        }
        if !self.config.auto_connect {
            return self.apply_decision(Decision::EnsureDown(DownReason::AutomaticConnectDisabled));
        }

        let native_vpn_connected = self.system.native_vpn_connected().ok();
        if native_vpn_connected != Some(false) {
            let observation = Observation {
                paused,
                auto_connect: self.config.auto_connect,
                native_vpn_connected,
            };
            return self.apply_decision(decide(&observation));
        }

        let observation = Observation {
            paused,
            auto_connect: self.config.auto_connect,
            native_vpn_connected,
        };
        self.apply_decision(decide(&observation))
    }

    fn apply_decision(&mut self, decision: Decision) -> Result<()> {
        match decision {
            Decision::EnsureUp => self.up_tunnel(),
            Decision::EnsureDown(reason) => self.down_tunnel(state_for_down_reason(reason)),
        }
    }

    fn ordinary_network_ready(&mut self) -> Result<bool> {
        Ok(self.system.ordinary_default_route()? && self.system.check_connectivity()?)
    }

    fn restore_stale_dns_snapshot(&mut self) -> Result<()> {
        if !self.system.has_dns_snapshot()? {
            return Ok(());
        }
        self.system.restore_dns_snapshot()?;
        if !self.ordinary_network_ready()? {
            self.system.set_state(State::RecoveryUnverified)?;
            return Err(Error::unavailable(
                "ordinary connectivity could not be proved after DNS restoration",
            ));
        }
        self.system.discard_dns_snapshot()
    }

    fn up_tunnel(&mut self) -> Result<()> {
        match self.system.native_vpn_connected() {
            Ok(true) => {
                self.down_tunnel(State::NativeVpnActive)?;
                return Err(Error::unavailable("a native VPN is active"));
            }
            Err(_) => {
                self.down_tunnel(State::NativeVpnStatusUnavailable)?;
                return Err(Error::unavailable("native VPN status is unavailable"));
            }
            Ok(false) => {}
        }

        if self.system.tunnel_interface()?.is_some() {
            if self.system.add_ipv6_blocks().is_ok() && self.system.check_connectivity()? {
                self.system.set_state(State::Connected)?;
                return Ok(());
            }
            self.down_tunnel(State::VpnUnhealthy)?;
            return Err(Error::unavailable("the existing tunnel is unhealthy"));
        }

        self.restore_stale_dns_snapshot()?;
        if !self.ordinary_network_ready()? {
            self.down_tunnel(State::NoNetwork)?;
            return Err(Error::unavailable(
                "ordinary network connectivity is unavailable",
            ));
        }
        if !self.system.private_key_ready() {
            self.down_tunnel(State::SecretUnavailable)?;
            return Err(Error::unavailable("WireGuard private key is unavailable"));
        }
        if !self.system.wireguard_config_ready() {
            self.down_tunnel(State::ConfigurationUnavailable)?;
            return Err(Error::unavailable("WireGuard configuration is unavailable"));
        }
        if self.system.capture_dns_snapshot().is_err() {
            self.down_tunnel(State::DnsSnapshotFailed)?;
            return Err(Error::unavailable("DNS settings could not be saved"));
        }
        if self.system.add_ipv6_blocks().is_err() {
            self.down_tunnel(State::Ipv6BlockFailed)?;
            return Err(Error::unavailable("IPv6 blocking could not be installed"));
        }

        let started_at = self.system.epoch_seconds()?;
        if !self.system.wg_quick_up()? {
            self.down_tunnel(State::VpnStartFailed)?;
            return Err(Error::unavailable("WireGuard activation failed"));
        }
        if self.system.tunnel_interface()?.is_none()
            || !self.system.wait_for_fresh_handshake(started_at)?
            || !self.system.check_connectivity()?
        {
            self.down_tunnel(State::VpnUnhealthy)?;
            return Err(Error::unavailable(
                "WireGuard activation health check failed",
            ));
        }
        self.system.set_state(State::Connected)
    }

    fn down_tunnel(&mut self, requested_state: State) -> Result<()> {
        let initial_interface = self.system.tunnel_interface()?;
        let had_snapshot = self.system.has_dns_snapshot()?;
        if let Some(interface) = &initial_interface {
            let stopped = self.system.wg_quick_down()?;
            self.system.sleep(Duration::from_millis(500));
            if !stopped || self.system.tunnel_interface()?.is_some() {
                self.system.remove_tunnel_routes_and_artifacts(interface)?;
                self.system.sleep(Duration::from_secs(1));
            }
        }
        if self.system.tunnel_interface()?.is_some() {
            self.system.set_state(State::VpnStopFailed)?;
            return Err(Error::unavailable(
                "WireGuard interface could not be stopped",
            ));
        }

        let mut recovery_error = self.system.remove_ipv6_blocks().err();
        if had_snapshot {
            match self.system.restore_dns_snapshot() {
                Ok(()) => match self.ordinary_network_ready() {
                    Ok(true) => {
                        if let Err(error) = self.system.discard_dns_snapshot()
                            && recovery_error.is_none()
                        {
                            recovery_error = Some(error);
                        }
                    }
                    Ok(false) => {
                        if recovery_error.is_none() {
                            recovery_error = Some(Error::unavailable(
                                "ordinary connectivity could not be proved after tunnel shutdown",
                            ));
                        }
                    }
                    Err(error) => {
                        if recovery_error.is_none() {
                            recovery_error = Some(error);
                        }
                    }
                },
                Err(error) => {
                    if recovery_error.is_none() {
                        recovery_error = Some(error);
                    }
                }
            }
        }
        if let Some(error) = recovery_error {
            self.system.set_state(State::RecoveryUnverified)?;
            return Err(error);
        }
        self.system.set_state(requested_state)
    }

    fn recover_dns(&mut self) -> Result<()> {
        self.system.set_paused(true)?;
        let tunnel_result = self.down_tunnel(State::DnsRecovery);
        self.system.reset_dns_to_automatic()?;
        tunnel_result?;
        self.system.set_state(State::DnsRecoveredToAutomatic)
    }
}

const fn state_for_down_reason(reason: DownReason) -> State {
    match reason {
        DownReason::Paused => State::Paused,
        DownReason::AutomaticConnectDisabled => State::AutomaticConnectDisabled,
        DownReason::NativeVpnActive => State::NativeVpnActive,
    }
}

#[cfg(test)]
mod tests {
    use super::Controller;
    use crate::config::Config;
    use crate::error::{Error, Result};
    use crate::state::State;
    use crate::system::System;
    use std::collections::VecDeque;
    use std::ffi::OsString;
    use std::time::Duration;

    #[allow(
        clippy::struct_excessive_bools,
        reason = "independent failure switches keep the transition fixture explicit and easy to audit"
    )]
    struct FakeSystem {
        events: Vec<&'static str>,
        state: Option<State>,
        paused: bool,
        interface: Option<String>,
        connectivity_checks: VecDeque<bool>,
        ordinary_route: bool,
        private_key: bool,
        configuration: bool,
        snapshot_capture: bool,
        snapshot_exists: bool,
        ipv6_add: bool,
        ipv6_remove: bool,
        wg_up: bool,
        wg_down: bool,
        handshake: bool,
    }

    impl Default for FakeSystem {
        fn default() -> Self {
            Self {
                events: Vec::new(),
                state: None,
                paused: false,
                interface: None,
                connectivity_checks: VecDeque::from([true, true, true]),
                ordinary_route: true,
                private_key: true,
                configuration: true,
                snapshot_capture: true,
                snapshot_exists: false,
                ipv6_add: true,
                ipv6_remove: true,
                wg_up: true,
                wg_down: true,
                handshake: true,
            }
        }
    }

    impl System for FakeSystem {
        type LockGuard = ();

        fn prepare(&mut self) -> Result<()> {
            Ok(())
        }
        fn acquire_daemon_lock(&mut self) -> Result<Self::LockGuard> {
            Ok(())
        }
        fn acquire_transition_lock(&mut self, _timeout: Duration) -> Result<Self::LockGuard> {
            Ok(())
        }
        fn paused(&mut self) -> Result<bool> {
            Ok(self.paused)
        }
        fn set_paused(&mut self, paused: bool) -> Result<()> {
            self.paused = paused;
            Ok(())
        }
        fn state(&mut self) -> Result<Option<State>> {
            Ok(self.state)
        }
        fn set_state(&mut self, state: State) -> Result<()> {
            self.state = Some(state);
            self.events.push("state");
            Ok(())
        }
        fn native_vpn_connected(&mut self) -> Result<bool> {
            self.events.push("native-vpn");
            Ok(false)
        }
        fn tunnel_interface(&mut self) -> Result<Option<String>> {
            Ok(self.interface.clone())
        }
        fn check_connectivity(&mut self) -> Result<bool> {
            self.events.push("connectivity");
            Ok(self.connectivity_checks.pop_front().unwrap_or(true))
        }
        fn ordinary_default_route(&mut self) -> Result<bool> {
            self.events.push("ordinary-route");
            Ok(self.ordinary_route)
        }
        fn private_key_ready(&mut self) -> bool {
            self.events.push("private-key");
            self.private_key
        }
        fn wireguard_config_ready(&mut self) -> bool {
            self.events.push("configuration");
            self.configuration
        }
        fn capture_dns_snapshot(&mut self) -> Result<()> {
            self.events.push("dns-capture");
            if self.snapshot_capture {
                self.snapshot_exists = true;
                Ok(())
            } else {
                Err(Error::unavailable("fixture"))
            }
        }
        fn has_dns_snapshot(&mut self) -> Result<bool> {
            Ok(self.snapshot_exists)
        }
        fn restore_dns_snapshot(&mut self) -> Result<()> {
            self.events.push("dns-restore");
            Ok(())
        }
        fn discard_dns_snapshot(&mut self) -> Result<()> {
            self.events.push("dns-discard");
            self.snapshot_exists = false;
            Ok(())
        }
        fn reset_dns_to_automatic(&mut self) -> Result<()> {
            self.events.push("dns-reset");
            self.snapshot_exists = false;
            Ok(())
        }
        fn add_ipv6_blocks(&mut self) -> Result<()> {
            self.events.push("ipv6-add");
            if self.ipv6_add {
                Ok(())
            } else {
                Err(Error::unavailable("fixture"))
            }
        }
        fn remove_ipv6_blocks(&mut self) -> Result<()> {
            self.events.push("ipv6-remove");
            if self.ipv6_remove {
                Ok(())
            } else {
                Err(Error::unavailable("fixture"))
            }
        }
        fn wg_quick_up(&mut self) -> Result<bool> {
            self.events.push("wg-up");
            if self.wg_up {
                self.interface = Some("utun7".into());
            }
            Ok(self.wg_up)
        }
        fn wg_quick_down(&mut self) -> Result<bool> {
            self.events.push("wg-down");
            if self.wg_down {
                self.interface = None;
            }
            Ok(self.wg_down)
        }
        fn wait_for_fresh_handshake(&mut self, _started_at: u64) -> Result<bool> {
            self.events.push("handshake");
            Ok(self.handshake)
        }
        fn remove_tunnel_routes_and_artifacts(&mut self, _interface: &str) -> Result<()> {
            self.events.push("fallback-down");
            self.interface = None;
            Ok(())
        }
        fn sleep(&mut self, _duration: Duration) {}
        fn epoch_seconds(&mut self) -> Result<u64> {
            Ok(100)
        }
    }

    fn config() -> Result<Config> {
        Config::parse(
            [
                "controller",
                "--private-key-file",
                "/private/key",
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
                "up",
            ]
            .into_iter()
            .map(OsString::from),
        )
    }

    #[test]
    fn successful_activation_has_a_fixed_order() -> Result<()> {
        let mut controller = Controller::new(config()?, FakeSystem::default());
        controller.up_tunnel()?;
        assert_eq!(
            controller.system.events,
            [
                "native-vpn",
                "ordinary-route",
                "connectivity",
                "private-key",
                "configuration",
                "dns-capture",
                "ipv6-add",
                "wg-up",
                "handshake",
                "connectivity",
                "state",
            ]
        );
        assert_eq!(controller.system.state, Some(State::Connected));
        Ok(())
    }

    #[test]
    fn every_activation_failure_runs_the_idempotent_down_path() -> Result<()> {
        for failure in [
            "ordinary-route",
            "preflight",
            "private-key",
            "configuration",
            "dns",
            "ipv6",
            "wg-up",
            "handshake",
            "postflight",
        ] {
            let mut system = FakeSystem::default();
            match failure {
                "ordinary-route" => system.ordinary_route = false,
                "preflight" => system.connectivity_checks = VecDeque::from([false]),
                "private-key" => system.private_key = false,
                "configuration" => system.configuration = false,
                "dns" => system.snapshot_capture = false,
                "ipv6" => system.ipv6_add = false,
                "wg-up" => system.wg_up = false,
                "handshake" => system.handshake = false,
                "postflight" => {
                    system.connectivity_checks = VecDeque::from([true, false, true]);
                }
                _ => {}
            }
            let mut controller = Controller::new(config()?, system);
            assert!(controller.up_tunnel().is_err(), "{failure}");
            assert!(
                controller.system.events.contains(&"ipv6-remove"),
                "{failure}"
            );
            if controller.system.snapshot_capture
                && controller.system.events.contains(&"dns-capture")
            {
                assert!(
                    controller.system.events.contains(&"dns-restore"),
                    "{failure}"
                );
            }
        }
        Ok(())
    }

    #[test]
    fn ipv6_cleanup_failure_does_not_prevent_dns_restoration() -> Result<()> {
        let system = FakeSystem {
            interface: None,
            snapshot_exists: true,
            ipv6_remove: false,
            ..FakeSystem::default()
        };
        let mut controller = Controller::new(config()?, system);
        assert!(controller.down_tunnel(State::Stopped).is_err());
        assert!(controller.system.events.contains(&"dns-restore"));
        assert!(controller.system.events.contains(&"dns-discard"));
        assert_eq!(controller.system.state, Some(State::RecoveryUnverified));
        Ok(())
    }

    #[test]
    fn emergency_dns_recovery_resets_dns_before_reporting_tunnel_failure() -> Result<()> {
        let system = FakeSystem {
            interface: Some("utun7".into()),
            snapshot_exists: true,
            ipv6_remove: false,
            ..FakeSystem::default()
        };
        let mut controller = Controller::new(config()?, system);

        assert!(controller.recover_dns().is_err());
        assert!(controller.system.paused);
        assert!(controller.system.events.contains(&"dns-reset"));
        assert_eq!(controller.system.state, Some(State::RecoveryUnverified));
        Ok(())
    }
}
