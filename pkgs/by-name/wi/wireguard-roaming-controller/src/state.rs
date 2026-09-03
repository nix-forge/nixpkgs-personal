#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum State {
    Connected,
    VpnUnhealthy,
    NativeVpnActive,
    NativeVpnStatusUnavailable,
    NoNetwork,
    SecretUnavailable,
    ConfigurationUnavailable,
    DnsSnapshotFailed,
    Ipv6BlockFailed,
    VpnStartFailed,
    VpnStopFailed,
    RecoveryUnverified,
    Paused,
    AutomaticConnectDisabled,
    Stopped,
    ManualDown,
    DnsRecovery,
    DnsRecoveredToAutomatic,
}

impl State {
    pub(crate) const fn as_str(self) -> &'static str {
        match self {
            Self::Connected => "connected",
            Self::VpnUnhealthy => "vpn-unhealthy",
            Self::NativeVpnActive => "native-vpn-active",
            Self::NativeVpnStatusUnavailable => "native-vpn-status-unavailable",
            Self::NoNetwork => "no-network",
            Self::SecretUnavailable => "secret-unavailable",
            Self::ConfigurationUnavailable => "configuration-unavailable",
            Self::DnsSnapshotFailed => "dns-snapshot-failed",
            Self::Ipv6BlockFailed => "ipv6-block-failed",
            Self::VpnStartFailed => "vpn-start-failed",
            Self::VpnStopFailed => "vpn-stop-failed",
            Self::RecoveryUnverified => "recovery-unverified",
            Self::Paused => "paused",
            Self::AutomaticConnectDisabled => "automatic-connect-disabled",
            Self::Stopped => "stopped",
            Self::ManualDown => "manual-down",
            Self::DnsRecovery => "dns-recovery",
            Self::DnsRecoveredToAutomatic => "dns-recovered-to-automatic",
        }
    }

    pub(crate) fn parse(value: &str) -> Option<Self> {
        [
            Self::Connected,
            Self::VpnUnhealthy,
            Self::NativeVpnActive,
            Self::NativeVpnStatusUnavailable,
            Self::NoNetwork,
            Self::SecretUnavailable,
            Self::ConfigurationUnavailable,
            Self::DnsSnapshotFailed,
            Self::Ipv6BlockFailed,
            Self::VpnStartFailed,
            Self::VpnStopFailed,
            Self::RecoveryUnverified,
            Self::Paused,
            Self::AutomaticConnectDisabled,
            Self::Stopped,
            Self::ManualDown,
            Self::DnsRecovery,
            Self::DnsRecoveredToAutomatic,
        ]
        .into_iter()
        .find(|state| state.as_str() == value)
    }
}

#[cfg(test)]
mod tests {
    use super::State;

    #[test]
    fn state_labels_round_trip() {
        for state in [
            State::Connected,
            State::VpnUnhealthy,
            State::NativeVpnActive,
            State::NativeVpnStatusUnavailable,
            State::NoNetwork,
            State::SecretUnavailable,
            State::ConfigurationUnavailable,
            State::DnsSnapshotFailed,
            State::Ipv6BlockFailed,
            State::VpnStartFailed,
            State::VpnStopFailed,
            State::RecoveryUnverified,
            State::Paused,
            State::AutomaticConnectDisabled,
            State::Stopped,
            State::ManualDown,
            State::DnsRecovery,
            State::DnsRecoveredToAutomatic,
        ] {
            assert_eq!(State::parse(state.as_str()), Some(state));
        }
        assert_eq!(State::parse("observed-secret-value"), None);
    }
}
