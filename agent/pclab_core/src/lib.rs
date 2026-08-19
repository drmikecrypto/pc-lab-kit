//! PC Lab Kit Rust probe core (R1) — telemetry ring buffer + JSON pipe protocol.
//! PowerShell probe orchestration calls `pclab_core pipe` for hot paths.

use serde::{Deserialize, Serialize};
use std::collections::VecDeque;
use std::io::{self, BufRead, Write};

const RING_CAP: usize = 120;

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct TelemetrySample {
    pub cpu_temp: Option<f64>,
    pub gpu_temp: Option<f64>,
    pub gpu_hotspot: Option<f64>,
    pub at: String,
}

#[derive(Default)]
pub struct RingBuffer {
    inner: VecDeque<TelemetrySample>,
}

impl RingBuffer {
    pub fn push(&mut self, sample: TelemetrySample) {
        if self.inner.len() >= RING_CAP {
            self.inner.pop_front();
        }
        self.inner.push_back(sample);
    }

    pub fn history(&self) -> Vec<TelemetrySample> {
        self.inner.iter().cloned().collect()
    }
}

#[derive(Serialize)]
struct PipeResponse {
    ok: bool,
    history: Vec<TelemetrySample>,
    count: usize,
}

fn run_pipe() -> io::Result<()> {
    let stdin = io::stdin();
    let mut ring = RingBuffer::default();
    let mut stdout = io::stdout();
    for line in stdin.lock().lines() {
        let line = line?;
        if line.trim().is_empty() {
            continue;
        }
        let sample: TelemetrySample = serde_json::from_str(&line).unwrap_or(TelemetrySample {
            cpu_temp: None,
            gpu_temp: None,
            gpu_hotspot: None,
            at: chrono_now(),
        });
        ring.push(sample);
        let resp = PipeResponse {
            ok: true,
            history: ring.history(),
            count: ring.inner.len(),
        };
        writeln!(stdout, "{}", serde_json::to_string(&resp).unwrap_or_default())?;
        stdout.flush()?;
    }
    Ok(())
}

fn chrono_now() -> String {
    use std::time::{SystemTime, UNIX_EPOCH};
    let ms = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis())
        .unwrap_or(0);
    format!("{ms}")
}

pub fn add(left: u64, right: u64) -> u64 {
    left + right
}

pub fn run_cli() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() > 1 && args[1] == "pipe" {
        if let Err(e) = run_pipe() {
            eprintln!("pclab_core pipe error: {e}");
            std::process::exit(1);
        }
        return;
    }
    println!(
        r#"{{"ok":true,"crate":"pclab_core","version":"0.1.0","commands":["pipe"]}}"#
    );
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ring_respects_capacity() {
        let mut ring = RingBuffer::default();
        for i in 0..150 {
            ring.push(TelemetrySample {
                cpu_temp: Some(i as f64),
                gpu_temp: None,
                gpu_hotspot: None,
                at: format!("t{i}"),
            });
        }
        assert_eq!(ring.history().len(), RING_CAP);
    }
}
