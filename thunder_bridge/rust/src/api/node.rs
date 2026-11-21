//! The Thunder node in the app process. A phone cannot start a child
//! process, so the app runs the node on a thread of its own.

use std::{
    any::Any,
    panic::{AssertUnwindSafe, catch_unwind},
    path::Path,
    thread::JoinHandle,
};

use parking_lot::Mutex;
use thunder_app::cli::Cli;
use tokio_util::sync::CancellationToken;

/// The state of the node.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NodeStatus {
    pub running: bool,
    /// The error that ended the last run. None after a clean stop.
    pub error: Option<String>,
}

struct Run {
    shutdown: CancellationToken,
    thread: JoinHandle<Option<String>>,
}

static RUN: Mutex<Option<Run>> = Mutex::new(None);
static LAST_ERROR: Mutex<Option<String>> = Mutex::new(None);

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

/// Start the node with the command line flags of the `thunder_app` binary,
/// with no program name. The node writes its log lines to `log_path`.
/// Returns when the node thread runs, before the RPC server answers.
pub fn start_node(args: Vec<String>, log_path: String) -> anyhow::Result<()> {
    let mut run = RUN.lock();
    if run.as_ref().is_some_and(|live| !live.thread.is_finished()) {
        anyhow::bail!("the Thunder node runs already");
    }
    if let Some(ended) = run.take() {
        let _error: Option<String> = join(ended);
    }
    let config =
        Cli::try_parse_args(std::iter::once("thunder_app".to_owned()).chain(args))?.get_config()?;
    if !config.headless {
        anyhow::bail!("a phone has no Thunder GUI: give --headless");
    }
    crate::log::log_to(Path::new(&log_path))?;
    let run_config = config.run_config();
    let shutdown = CancellationToken::new();
    let thread = std::thread::Builder::new()
        .name("thunder".to_owned())
        .spawn({
            let shutdown = shutdown.clone();
            move || {
                let res = catch_unwind(AssertUnwindSafe(|| thunder_app::run(run_config, shutdown)));
                let error = match res {
                    Ok(Ok(())) => None,
                    Ok(Err(err)) => Some(error_chain(&err)),
                    Err(panic) => Some(format!("the node panicked: {}", panic_text(&panic))),
                };
                if let Some(error) = &error {
                    tracing::error!(%error, "the Thunder node stopped");
                }
                error
            }
        })?;
    *LAST_ERROR.lock() = None;
    *run = Some(Run { shutdown, thread });
    Ok(())
}

/// Ask the node to stop. The status reports when it is gone.
#[flutter_rust_bridge::frb(sync)]
pub fn stop_node() {
    if let Some(run) = RUN.lock().as_ref() {
        run.shutdown.cancel();
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn node_status() -> NodeStatus {
    let mut run = RUN.lock();
    if run.as_ref().is_some_and(|live| !live.thread.is_finished()) {
        return NodeStatus {
            running: true,
            error: None,
        };
    }
    if let Some(ended) = run.take() {
        *LAST_ERROR.lock() = join(ended);
    }
    NodeStatus {
        running: false,
        error: LAST_ERROR.lock().clone(),
    }
}

fn join(run: Run) -> Option<String> {
    match run.thread.join() {
        Ok(error) => error,
        Err(panic) => Some(format!("the node thread panicked: {}", panic_text(&panic))),
    }
}

fn error_chain(err: &dyn std::error::Error) -> String {
    let mut text = err.to_string();
    let mut source = err.source();
    while let Some(err) = source {
        text.push_str(": ");
        text.push_str(&err.to_string());
        source = err.source();
    }
    text
}

fn panic_text(panic: &(dyn Any + Send)) -> String {
    if let Some(text) = panic.downcast_ref::<&str>() {
        return (*text).to_owned();
    }
    if let Some(text) = panic.downcast_ref::<String>() {
        return text.clone();
    }
    "no message".to_owned()
}

#[cfg(test)]
mod test {
    use std::{
        net::TcpListener,
        time::{Duration, Instant},
    };

    use super::{NodeStatus, node_status, start_node, stop_node};

    fn wait_until_stopped() -> NodeStatus {
        let deadline = Instant::now() + Duration::from_secs(60);
        loop {
            let status = node_status();
            if !status.running {
                return status;
            }
            assert!(Instant::now() < deadline, "the node did not stop");
            std::thread::sleep(Duration::from_millis(50));
        }
    }

    fn free_port() -> u16 {
        TcpListener::bind("127.0.0.1:0")
            .and_then(|listener| listener.local_addr())
            .map(|addr| addr.port())
            .expect("a free port")
    }

    /// One test, because the node is one per process.
    #[test]
    fn start_stop_and_start_again() -> anyhow::Result<()> {
        let dir = tempfile::tempdir()?;
        let log_path = dir.path().join("thunder.log");
        let log_path = log_path.to_string_lossy().into_owned();
        assert_eq!(
            node_status(),
            NodeStatus {
                running: false,
                error: None
            }
        );

        let err = start_node(vec!["--no-such-flag".to_owned()], log_path.clone())
            .expect_err("an unknown flag");
        assert!(err.to_string().contains("--no-such-flag"), "{err}");
        let err = start_node(vec![], log_path.clone()).expect_err("no --headless");
        assert!(err.to_string().contains("--headless"), "{err}");

        // No mainchain answers, so the node waits for it until the stop.
        let args = vec![
            "--headless".to_owned(),
            format!("--datadir={}", dir.path().join("data").display()),
            "--network=regtest".to_owned(),
            format!("--mainchain-grpc-url=http://127.0.0.1:{}", free_port()),
            format!("--rpc-addr=127.0.0.1:{}", free_port()),
            "--net-addr=127.0.0.1:0".to_owned(),
        ];
        for _ in 0..2 {
            start_node(args.clone(), log_path.clone())?;
            assert!(node_status().running);
            let err = start_node(args.clone(), log_path.clone()).expect_err("a second node");
            assert!(err.to_string().contains("runs already"), "{err}");
            stop_node();
            assert_eq!(
                wait_until_stopped(),
                NodeStatus {
                    running: false,
                    error: None
                }
            );
        }
        let log = std::fs::read_to_string(&log_path)?;
        assert!(!log.is_empty(), "the node wrote no log lines");
        Ok(())
    }
}
