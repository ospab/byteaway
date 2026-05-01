use bytes::Bytes;
use rand_distr::{Distribution, Exp};
use std::time::Duration;

use crate::shapes::TrafficProfile;

#[derive(Debug, Clone)]
pub struct ShapingConfig {
    pub profile: TrafficProfile,
    pub mean_gap_ms: f64,
}

pub struct TrafficShaper {
    config: ShapingConfig,
}

impl TrafficShaper {
    pub fn new(config: ShapingConfig) -> Self {
        Self { config }
    }

    pub fn normalize_size(&self, payload: Bytes) -> Bytes {
        let target = self.config.profile.target_size(payload.len());
        if payload.len() >= target {
            return payload;
        }

        let mut out = Vec::with_capacity(target);
        out.extend_from_slice(&payload);
        out.resize(target, 0);
        Bytes::from(out)
    }

    pub fn next_gap(&self) -> Duration {
        let lambda = 1.0 / self.config.mean_gap_ms.max(1.0);
        let exp = Exp::new(lambda).expect("lambda > 0");
        let mut rng = rand::thread_rng();
        let sample_ms = exp.sample(&mut rng);
        Duration::from_millis(sample_ms as u64)
    }
}
