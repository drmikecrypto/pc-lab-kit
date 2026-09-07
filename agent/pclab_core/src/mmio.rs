//! R2 — Blackwell MMIO therm read stub (Windows Ring0 via external helper in full build).
//! Returns structured JSON for probe merge; real BAR0 reads delegated to PcLabHwMon until ported.

use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct MmioThermSample {
    pub slot: String,
    pub celsius: f64,
    pub source: String,
    pub valid: bool,
}

/// Placeholder decode — mirrors Q8.8 Blackwell THERM layout for contract tests.
pub fn decode_blackwell_q8_8(raw: u16) -> Option<f64> {
    if raw == 0 || raw == 0xFF00 {
        return None;
    }
    let signed = raw as i16;
    Some((signed as f64) / 256.0)
}

pub fn mock_blackwell_sensors(hotspot_c: f64) -> Vec<MmioThermSample> {
    (1..=6)
        .map(|i| MmioThermSample {
            slot: format!("S{i}"),
            celsius: hotspot_c + (i as f64 - 3.5) * 0.4,
            source: "blackwell_therm_mmio_r2".into(),
            valid: true,
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn q8_8_decode() {
        assert!((decode_blackwell_q8_8(0x2800).unwrap() - 40.0).abs() < 0.01);
    }
}
