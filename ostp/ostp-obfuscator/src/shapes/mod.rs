#[derive(Debug, Clone, Copy)]
pub enum TrafficProfile {
    JsonRpc,
    HttpsBurst,
    VideoStream,
}

impl TrafficProfile {
    pub fn target_size(&self, current: usize) -> usize {
        match self {
            TrafficProfile::JsonRpc => align_up(current.max(220), 64).min(1408),
            TrafficProfile::HttpsBurst => align_up(current.max(1200), 128).min(1472),
            TrafficProfile::VideoStream => align_up(current.max(900), 188).min(1472),
        }
    }
}

fn align_up(v: usize, align: usize) -> usize {
    ((v + align - 1) / align) * align
}
