use std::{
    fs::{File, OpenOptions},
    io::{self, Write},
    path::Path,
    sync::{Arc, Once},
};

use parking_lot::Mutex;
use tracing_subscriber::{EnvFilter, fmt::MakeWriter};

/// The file of the current run. A process has one tracing subscriber, so each
/// run swaps the file under it.
#[derive(Clone, Default)]
struct LogFile(Arc<Mutex<Option<File>>>);

impl Write for LogFile {
    fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
        match self.0.lock().as_mut() {
            Some(file) => file.write(buf),
            None => Ok(buf.len()),
        }
    }

    fn flush(&mut self) -> io::Result<()> {
        match self.0.lock().as_mut() {
            Some(file) => file.flush(),
            None => Ok(()),
        }
    }
}

impl<'a> MakeWriter<'a> for LogFile {
    type Writer = Self;

    fn make_writer(&'a self) -> Self::Writer {
        self.clone()
    }
}

static LOG_FILE: std::sync::LazyLock<LogFile> = std::sync::LazyLock::new(LogFile::default);
static INIT: Once = Once::new();

/// Send the log lines of the node to `path`, after the lines that are in it.
pub(crate) fn log_to(path: &Path) -> anyhow::Result<()> {
    let file = OpenOptions::new().create(true).append(true).open(path)?;
    *LOG_FILE.0.lock() = Some(file);
    let mut init_err = None;
    INIT.call_once(|| {
        let subscriber = tracing_subscriber::fmt()
            .with_ansi(false)
            .with_env_filter(EnvFilter::new("info"))
            .with_writer(LOG_FILE.clone())
            .finish();
        if let Err(err) = tracing::subscriber::set_global_default(subscriber) {
            init_err = Some(err);
        }
    });
    match init_err {
        Some(err) => Err(err.into()),
        None => Ok(()),
    }
}
