#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum DownReason {
    Paused,
    AutomaticConnectDisabled,
    NativeVpnActive,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum Decision {
    EnsureDown(DownReason),
    EnsureUp,
}

pub(crate) struct Observation {
    pub(crate) paused: bool,
    pub(crate) auto_connect: bool,
    pub(crate) native_vpn_connected: Option<bool>,
}

pub(crate) fn decide(observation: &Observation) -> Decision {
    if observation.paused {
        return Decision::EnsureDown(DownReason::Paused);
    }
    if !observation.auto_connect {
        return Decision::EnsureDown(DownReason::AutomaticConnectDisabled);
    }
    match observation.native_vpn_connected {
        Some(true) => return Decision::EnsureDown(DownReason::NativeVpnActive),
        None => return Decision::EnsureUp,
        Some(false) => {}
    }
    Decision::EnsureUp
}

#[cfg(test)]
mod tests {
    use super::{Decision, DownReason, Observation, decide};
    struct Case {
        name: &'static str,
        paused: bool,
        auto_connect: bool,
        native_vpn_connected: Option<bool>,
        expected: Decision,
    }

    #[test]
    #[allow(
        clippy::too_many_lines,
        reason = "the table keeps every policy precedence case visible in one audit-friendly test"
    )]
    fn policy_decision_matrix_is_fail_closed() {
        let cases = [
            Case {
                name: "pause wins",
                paused: true,
                auto_connect: true,
                native_vpn_connected: Some(false),
                expected: Decision::EnsureDown(DownReason::Paused),
            },
            Case {
                name: "automatic connection disabled",
                paused: false,
                auto_connect: false,
                native_vpn_connected: Some(false),
                expected: Decision::EnsureDown(DownReason::AutomaticConnectDisabled),
            },
            Case {
                name: "native VPN connected",
                paused: false,
                auto_connect: true,
                native_vpn_connected: Some(true),
                expected: Decision::EnsureDown(DownReason::NativeVpnActive),
            },
            Case {
                name: "native VPN status unavailable enables protection",
                paused: false,
                auto_connect: true,
                native_vpn_connected: None,
                expected: Decision::EnsureUp,
            },
            Case {
                name: "ordinary network enables always-on protection",
                paused: false,
                auto_connect: true,
                native_vpn_connected: Some(false),
                expected: Decision::EnsureUp,
            },
        ];

        for case in cases {
            let observation = Observation {
                paused: case.paused,
                auto_connect: case.auto_connect,
                native_vpn_connected: case.native_vpn_connected,
            };
            assert_eq!(decide(&observation), case.expected, "{}", case.name);
        }
    }
}
