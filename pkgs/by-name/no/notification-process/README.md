# notification-process

A Python 3.14 library for synchronous owned POSIX commands. `run` returns a
`subprocess.CompletedProcess` and supports explicit input, output, encoding,
working directory, environment, checked status, and an overall timeout.

Pipe readiness and a blocking `waitid(WNOWAIT)` observer drive completion.
The leader retains its identity until cleanup and final reaping. Failed commands
terminate their owned process group before reaping. Python signal handlers are
deferred during observer construction, startup, cleanup, and final status transfer.

`communicate` accepts an existing process in a new session and leaves reaping to
its sole owner. `communicate_and_reap` also transfers the final status.
`wait_child` waits for an existing child through Linux pidfds or Darwin SIGCHLD
kqueue notifications. Its timeout leaves the child running and owned; callers
must drain captured pipes separately and decide how to terminate it.
`defer_cancellation` protects short owned cleanup transitions;
launch children before entering it because threads inherit signal masks.
The API supports argument vectors rather than shell commands. It does not claim
to supervise descendants that leave the process group. Kernel-uninterruptible
children can delay cleanup beyond the communication deadline; services need an
outer supervisor.

Install the package in `python3.withPackages`, or declare it in the Python
writer's `libraries`. The package checks real child processes, pipe backpressure,
encoding, failure output, timeout, descendant cleanup and cancellation.

Standalone updater recipes retain native `notification_process.py` source copies
so they work outside this catalog without a personal package dependency. Both
package contract and layout checks reject drift from this canonical source.
