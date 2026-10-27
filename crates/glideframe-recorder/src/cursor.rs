use std::time::Instant;

use uuid::Uuid;

use crate::models::{FrameRect, PointerEvent, PointerEventKind};

#[derive(Debug)]
#[allow(dead_code)]
pub struct CursorTracker {
    bounds: FrameRect,
    started: Instant,
    events: Vec<PointerEvent>,
}

impl CursorTracker {
    pub fn start(bounds: FrameRect) -> Self {
        Self {
            bounds,
            started: Instant::now(),
            events: Vec::new(),
        }
    }

    pub fn stop(self, duration: f64) -> Vec<PointerEvent> {
        self.events
            .into_iter()
            .filter(|event| event.time <= duration)
            .collect()
    }

    #[allow(dead_code)]
    pub fn record(&mut self, x: f64, y: f64, kind: PointerEventKind) {
        self.events.push(PointerEvent {
            id: Uuid::new_v4(),
            time: self.started.elapsed().as_secs_f64(),
            x: normalize(x, self.bounds.x, self.bounds.width),
            y: normalize(y, self.bounds.y, self.bounds.height),
            kind,
        });
    }
}

#[allow(dead_code)]
fn normalize(value: f64, origin: f64, size: f64) -> f64 {
    if size <= 0.0 {
        return 0.0;
    }
    ((value - origin) / size).clamp(0.0, 1.0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cursor_events_are_normalized_and_clamped() {
        let mut tracker = CursorTracker::start(FrameRect {
            x: 100.0,
            y: 200.0,
            width: 400.0,
            height: 300.0,
        });
        tracker.record(300.0, 350.0, PointerEventKind::Click);
        tracker.record(999.0, -10.0, PointerEventKind::Move);

        let events = tracker.stop(10.0);
        assert_eq!(events.len(), 2);
        assert_eq!(events[0].x, 0.5);
        assert_eq!(events[0].y, 0.5);
        assert_eq!(events[1].x, 1.0);
        assert_eq!(events[1].y, 0.0);
    }
}
