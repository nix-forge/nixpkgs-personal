use std::ffi::OsString;
use std::io::Read;
use std::path::Path;
use std::process::{Command, Stdio};
use std::thread;
use std::time::Duration;

use rustix::process::{Pid, Signal, kill_process};
use wait_timeout::ChildExt;

use crate::error::{Error, Result};

const MAX_CAPTURE_BYTES: usize = 1024 * 1024;
const MAX_CAPTURE_BYTES_U64: u64 = 1024 * 1024;

pub(crate) const CURL: &str = match option_env!("WIREGUARD_ROAMING_CURL") {
    Some(value) => value,
    None => "/usr/bin/false",
};
pub(crate) const WG: &str = match option_env!("WIREGUARD_ROAMING_WG") {
    Some(value) => value,
    None => "/usr/bin/false",
};
pub(crate) const WG_QUICK: &str = match option_env!("WIREGUARD_ROAMING_WG_QUICK") {
    Some(value) => value,
    None => "/usr/bin/false",
};
const CONTROLLED_PATH: &str = match option_env!("WIREGUARD_ROAMING_PATH") {
    Some(value) => value,
    None => "/usr/bin:/bin:/usr/sbin:/sbin",
};

pub(crate) struct Runner;

impl Runner {
    pub(crate) fn status(
        label: &'static str,
        program: &Path,
        arguments: &[OsString],
        timeout: Duration,
    ) -> Result<bool> {
        Ok(Self::run(label, program, arguments, timeout, false)?.success)
    }

    pub(crate) fn output(
        label: &'static str,
        program: &Path,
        arguments: &[OsString],
        timeout: Duration,
    ) -> Result<Option<Vec<u8>>> {
        let result = Self::run(label, program, arguments, timeout, true)?;
        Ok(result.success.then_some(result.stdout))
    }

    fn run(
        label: &'static str,
        program: &Path,
        arguments: &[OsString],
        timeout: Duration,
        capture_stdout: bool,
    ) -> Result<CommandResult> {
        if !program.is_absolute() {
            return Err(Error::software(format!(
                "{label} executable path is not absolute"
            )));
        }

        let mut command = Command::new(program);
        command
            .args(arguments)
            .env_clear()
            .env("HOME", "/var/empty")
            .env("LANG", "C")
            .env("LC_ALL", "C")
            .env("PATH", CONTROLLED_PATH)
            .stdin(Stdio::null())
            .stderr(Stdio::null())
            .stdout(if capture_stdout {
                Stdio::piped()
            } else {
                Stdio::null()
            });

        let mut child = command
            .spawn()
            .map_err(|error| Error::software(format!("could not start {label}: {error}")))?;
        let output_reader = child.stdout.take().map(|stdout| {
            thread::Builder::new()
                .name("wireguard-command-output".into())
                .spawn(move || {
                    let mut bytes = Vec::new();
                    stdout
                        .take(MAX_CAPTURE_BYTES_U64 + 1)
                        .read_to_end(&mut bytes)
                        .map(|_| bytes)
                })
        });
        let output_reader = match output_reader {
            Some(Ok(handle)) => Some(handle),
            Some(Err(error)) => {
                // Preserve the output-reader error while making a best-effort cleanup.
                drop(child.kill());
                drop(child.wait());
                return Err(Error::software(format!(
                    "could not read {label} output: {error}"
                )));
            }
            None => None,
        };

        let status = child
            .wait_timeout(timeout)
            .map_err(|error| Error::software(format!("could not wait for {label}: {error}")))?;
        let timed_out = status.is_none();
        let status = if let Some(status) = status {
            status
        } else {
            // A failed TERM is followed by a forceful child kill below.
            let _term_result = kill_process(Pid::from_child(&child), Signal::TERM);
            if let Some(status) = child
                .wait_timeout(Duration::from_secs(2))
                .map_err(|error| {
                    Error::software(format!("could not wait for {label} shutdown: {error}"))
                })?
            {
                status
            } else {
                // The subsequent wait reports whether the process could be reaped.
                drop(child.kill());
                child
                    .wait()
                    .map_err(|error| Error::software(format!("could not stop {label}: {error}")))?
            }
        };

        let stdout = if let Some(reader) = output_reader {
            reader
                .join()
                .map_err(|_| Error::software(format!("{label} output reader stopped")))?
                .map_err(|error| Error::software(format!("could not read {label}: {error}")))?
        } else {
            Vec::new()
        };
        if stdout.len() > MAX_CAPTURE_BYTES {
            return Err(Error::software(format!(
                "{label} output exceeded its limit"
            )));
        }
        if timed_out {
            return Err(Error::temporary(format!("{label} timed out")));
        }

        Ok(CommandResult {
            success: status.success(),
            stdout,
        })
    }
}

struct CommandResult {
    success: bool,
    stdout: Vec<u8>,
}

pub(crate) fn arguments<const SIZE: usize>(values: [&str; SIZE]) -> Vec<OsString> {
    values.into_iter().map(OsString::from).collect()
}

#[cfg(test)]
mod tests {
    use super::{Runner, arguments};
    use crate::error::Result;
    use std::path::Path;
    use std::time::Duration;

    const TEST_FALSE: &str = match option_env!("WIREGUARD_ROAMING_TEST_FALSE") {
        Some(value) => value,
        None => "/usr/bin/false",
    };
    const TEST_PRINTF: &str = match option_env!("WIREGUARD_ROAMING_TEST_PRINTF") {
        Some(value) => value,
        None => "/usr/bin/printf",
    };
    const TEST_SLEEP: &str = match option_env!("WIREGUARD_ROAMING_TEST_SLEEP") {
        Some(value) => value,
        None => "/bin/sleep",
    };

    #[test]
    fn captures_bounded_command_output() -> Result<()> {
        let output = Runner::output(
            "printf fixture",
            Path::new(TEST_PRINTF),
            &arguments(["%s", "fixture"]),
            Duration::from_secs(2),
        )?;
        assert_eq!(output.as_deref(), Some(b"fixture".as_slice()));
        Ok(())
    }

    #[test]
    fn reports_nonzero_status_without_exposing_output() -> Result<()> {
        let success = Runner::status(
            "false fixture",
            Path::new(TEST_FALSE),
            &[],
            Duration::from_secs(2),
        )?;
        assert!(!success);
        Ok(())
    }

    #[test]
    fn terminates_commands_that_exceed_their_deadline() {
        let result = Runner::status(
            "sleep fixture",
            Path::new(TEST_SLEEP),
            &arguments(["5"]),
            Duration::from_millis(10),
        );
        assert!(result.is_err());
    }
}
