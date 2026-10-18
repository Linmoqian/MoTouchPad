use crate::model::{command::*, Action, Actions, Contact, Frame};

// Swift Float.pi rounds downward; Rust's f32::consts::PI rounds upward.
// Preserve the source recognizer's thresholds at float-adjacent boundaries.
const PI: f32 = f32::from_bits(0x4049_0fda);

#[derive(Clone, Copy, Default)]
struct Point {
    x: f32,
    y: f32,
}
impl Point {
    fn sub(self, b: Self) -> Self {
        Self {
            x: self.x - b.x,
            y: self.y - b.y,
        }
    }
    fn travel(self) -> f32 {
        self.x.abs() + self.y.abs()
    }
    fn length(self) -> f32 {
        (self.x * self.x + self.y * self.y).sqrt()
    }
    fn vertical(self) -> bool {
        self.y.abs() >= self.x.abs() * 1.5
    }
    fn horizontal(self) -> bool {
        self.x.abs() >= self.y.abs() * 1.5
    }
    fn up(self) -> bool {
        self.y < 0.0 && self.vertical()
    }
}
#[derive(Clone, Copy, Default, PartialEq)]
struct Ids([u64; 4]);
impl Ids {
    fn from(points: &[Contact]) -> Self {
        let mut ids = Self::default();
        for p in points {
            ids.0[p.id as usize / 64] |= 1 << (p.id % 64);
        }
        ids
    }
    fn contains(self, id: u8) -> bool {
        self.0[id as usize / 64] & (1 << (id % 64)) != 0
    }
    fn subset(self, other: Self) -> bool {
        self.0.iter().zip(other.0).all(|(a, b)| a & !b == 0)
    }
}
#[derive(Clone, Copy, Default)]
struct Snapshot {
    ids: Ids,
    points: [Contact; 4],
    count: usize,
    center: Point,
    distance: f32,
    angle: f32,
    spread: f32,
}
impl Snapshot {
    fn new(points: &[Contact]) -> Self {
        let mut s = Self {
            ids: Ids::from(points),
            count: points.len(),
            ..Self::default()
        };
        s.points[..points.len()].copy_from_slice(points);
        for p in points {
            s.center.x += p.x;
            s.center.y += p.y;
        }
        s.center.x /= points.len() as f32;
        s.center.y /= points.len() as f32;
        if points.len() == 2 {
            let delta = Point {
                x: points[1].x - points[0].x,
                y: points[1].y - points[0].y,
            };
            s.distance = delta.length();
            s.angle = (delta.y as f64).atan2(delta.x as f64) as f32;
        }
        if points.len() == 4 {
            for p in points {
                s.spread += Point { x: p.x, y: p.y }.sub(s.center).length();
            }
            s.spread /= points.len() as f32;
        }
        s
    }
    fn near(self, points: &[Contact]) -> bool {
        points.iter().all(|p| {
            self.points[..self.count]
                .iter()
                .find(|q| q.id == p.id)
                .is_some_and(|q| (p.x - q.x).abs() + (p.y - q.y).abs() <= 0.018)
        })
    }
}
#[derive(Clone, Copy)]
struct Base {
    start: Snapshot,
    last: Snapshot,
    started: f64,
    travel: f32,
}
impl Base {
    fn new(points: &[Contact], frame: &Frame) -> Self {
        let s = Snapshot::new(points);
        Self {
            start: s,
            last: s,
            started: time(frame),
            travel: 0.0,
        }
    }
    fn elapsed(self, frame: &Frame) -> f64 {
        (time(frame) - self.started).max(0.0)
    }
    fn released(self, points: &[Contact]) -> bool {
        points.iter().any(|p| self.start.ids.contains(p.id))
    }
}
#[derive(Clone, Copy)]
struct Single {
    base: Base,
    moved: bool,
    sensitivity: u8,
    second: bool,
    dragging: bool,
}
#[derive(Clone, Copy, PartialEq)]
enum TwoKind {
    Pending,
    Scroll,
    Horizontal,
    Pinch,
    Rotate,
    Consumed,
}
#[derive(Clone, Copy)]
struct Two {
    base: Base,
    kind: TwoKind,
    vertical: f32,
    horizontal: f32,
    pinch: f32,
    rotation: f32,
    second: bool,
}
#[derive(Clone, Copy, PartialEq)]
enum ThreeKind {
    Pending,
    Dragging,
    Consumed,
}
#[derive(Clone, Copy)]
struct Three {
    base: Base,
    kind: ThreeKind,
    sensitivity: u8,
    deadline: f64,
}
#[derive(Clone, Copy)]
struct Four {
    base: Base,
    consumed: bool,
}
#[derive(Clone, Copy, Default)]
enum Mode {
    #[default]
    Idle,
    Single(Single),
    Two(Two),
    Three(Three),
    Four(Four),
}

/// Prototype parity with the Swift recognizer's default Config, plus smart-zoom toggle.
pub struct Recognizer {
    mode: Mode,
    pending: Option<(Point, f64)>,
    primary: Option<(Point, f64)>,
    suppressed: bool,
    pub smart_zoom: bool,
}
impl Default for Recognizer {
    fn default() -> Self {
        Self {
            mode: Mode::Idle,
            pending: None,
            primary: None,
            suppressed: false,
            smart_zoom: true,
        }
    }
}
impl Recognizer {
    pub fn deadline(&self) -> Option<f64> {
        let hold = match self.mode {
            Mode::Three(s)
                if s.kind == ThreeKind::Pending
                    && s.base.travel <= 0.018
                    && s.deadline.is_finite() =>
            {
                Some(s.deadline)
            }
            _ => None,
        };
        match (self.pending.map(|p| p.1), hold) {
            (Some(a), Some(b)) => Some(a.min(b)),
            (a, b) => a.or(b),
        }
    }
    pub fn flush(&mut self, now: f64) -> Actions {
        if self.pending.is_some_and(|p| now >= p.1) {
            self.emit_secondary()
        } else {
            Actions::default()
        }
    }
    pub fn advance(&mut self, now: f64) -> Actions {
        let mut out = self.flush(now);
        if let Mode::Three(mut s) = self.mode {
            if s.kind == ThreeKind::Pending && s.base.travel <= 0.018 && now >= s.deadline {
                s.kind = ThreeKind::Dragging;
                self.mode = Mode::Three(s);
                out.push(Action::drag(0, 0.0, 0.0, s.sensitivity));
            }
        }
        out
    }
    pub fn reset(&mut self) -> Actions {
        let mut out = Actions::default();
        match self.mode {
            Mode::Single(s) if s.dragging => out.push(Action::drag(2, 0.0, 0.0, s.sensitivity)),
            Mode::Three(s) if s.kind == ThreeKind::Dragging => {
                out.push(Action::drag(2, 0.0, 0.0, s.sensitivity))
            }
            _ => {}
        }
        self.mode = Mode::Idle;
        self.pending = None;
        self.primary = None;
        self.suppressed = false;
        out
    }
    fn cancel(&mut self) -> Actions {
        let out = self.reset();
        self.suppressed = true;
        out
    }
    fn emit_secondary(&mut self) -> Actions {
        let mut out = Actions::default();
        if self.pending.take().is_some() {
            out.push(Action::click(2));
        }
        out
    }
    fn begin(&mut self, points: &[Contact], frame: &Frame, now: f64, out: &mut Actions) {
        if points.is_empty() {
            return;
        }
        if points.len() != 1 {
            self.primary = None;
        }
        let base = Base::new(points, frame);
        self.mode = match points.len() {
            1 => {
                let second = self.primary.is_some_and(|(p, t)| {
                    time(frame) >= t
                        && time(frame) - t <= 0.30
                        && p.sub(base.start.center).length() <= 0.03
                });
                self.primary = None;
                Mode::Single(Single {
                    base,
                    moved: false,
                    sensitivity: frame.sensitivity,
                    second,
                    dragging: false,
                })
            }
            2 => {
                let second = self
                    .pending
                    .is_some_and(|(p, t)| now <= t && p.sub(base.start.center).length() <= 0.03);
                if self.pending.is_some() && !second {
                    out.extend(self.emit_secondary());
                }
                Mode::Two(Two {
                    base,
                    kind: TwoKind::Pending,
                    vertical: 0.0,
                    horizontal: 0.0,
                    pinch: 0.0,
                    rotation: 0.0,
                    second,
                })
            }
            3 => Mode::Three(Three {
                base,
                kind: ThreeKind::Pending,
                sensitivity: frame.sensitivity,
                deadline: now + 0.12,
            }),
            4 => Mode::Four(Four {
                base,
                consumed: false,
            }),
            _ => unreachable!(),
        };
    }
    pub fn feed(&mut self, frame: &Frame, now: f64) -> Actions {
        if frame.kind != 2 {
            return Actions::default();
        }
        let mut out = self.flush(now);
        let mut active = [Contact::default(); 5];
        let mut released = [Contact::default(); 5];
        let (mut a, mut r) = (0, 0);
        for p in &frame.contacts[..frame.count] {
            if p.touching {
                active[a] = *p;
                a += 1;
            } else {
                released[r] = *p;
                r += 1;
            }
        }
        let active = &mut active[..a];
        active.sort_unstable_by_key(|p| p.id);
        let released = &released[..r];
        if self.suppressed {
            if a == 0 {
                self.suppressed = false;
            }
            return out;
        }
        if a > 4 {
            out.extend(self.cancel());
            return out;
        }
        match self.mode {
            Mode::Idle => self.begin(active, frame, now, &mut out),
            Mode::Single(s) => self.single(s, active, released, frame, now, &mut out),
            Mode::Two(s) => self.two(s, active, released, frame, now, &mut out),
            Mode::Three(s) => self.three(s, active, released, frame, now, &mut out),
            Mode::Four(s) => self.four(s, active, released, frame, &mut out),
        }
        out
    }
    fn single(
        &mut self,
        mut s: Single,
        active: &[Contact],
        released: &[Contact],
        f: &Frame,
        now: f64,
        out: &mut Actions,
    ) {
        if active.is_empty() {
            if s.dragging {
                out.push(Action::drag(2, 0.0, 0.0, s.sensitivity));
            } else if s.base.released(released)
                && s.base.start.near(released)
                && s.base.elapsed(f) <= 0.28
                && s.base.travel <= 0.018
                && !s.moved
            {
                out.push(Action::click(1));
                self.primary = Some((s.base.last.center, time(f)));
            }
            self.mode = Mode::Idle;
            return;
        }
        if active.len() > 1 {
            if !s.moved {
                self.begin(active, f, now, out);
            } else {
                out.extend(self.cancel());
            }
            return;
        }
        let snap = Snapshot::new(active);
        if snap.ids != s.base.start.ids {
            if !s.moved {
                self.mode = Mode::Single(Single {
                    base: Base::new(active, f),
                    moved: false,
                    sensitivity: f.sensitivity,
                    second: false,
                    dragging: false,
                });
            } else {
                out.extend(self.cancel());
            }
            return;
        }
        let delta = snap.center.sub(s.base.last.center);
        let total = snap.center.sub(s.base.start.center);
        s.base.travel += delta.travel();
        if s.moved || total.travel() > 0.004 {
            let movement = if s.moved { delta } else { total };
            if s.second {
                if !s.dragging {
                    out.push(Action::drag(0, 0.0, 0.0, f.sensitivity));
                    s.dragging = true;
                }
                out.push(Action::drag(1, movement.x, movement.y, f.sensitivity));
            } else {
                out.push(Action::movement(movement.x, movement.y, f.sensitivity));
            }
            s.moved = true;
        }
        s.base.last = snap;
        s.sensitivity = f.sensitivity;
        self.mode = Mode::Single(s);
    }
    fn two(
        &mut self,
        mut s: Two,
        active: &[Contact],
        released: &[Contact],
        f: &Frame,
        now: f64,
        out: &mut Actions,
    ) {
        if active.is_empty() {
            let tap = s.base.released(released)
                && s.kind == TwoKind::Pending
                && s.base.elapsed(f) <= 0.28
                && s.base.travel <= 0.018
                && s.base.start.near(released);
            if tap && s.second {
                self.pending = None;
                out.push(Action::command(SMART_ZOOM, 1));
            } else if tap && !self.smart_zoom {
                out.push(Action::click(2));
            } else if tap {
                self.pending = Some((s.base.start.center, now + 0.30));
            } else if s.second {
                out.extend(self.emit_secondary());
            }
            self.mode = Mode::Idle;
            return;
        }
        let ids = Ids::from(active);
        if active.len() < 2 && ids.subset(s.base.start.ids) {
            if s.base.start.near(active) && s.kind == TwoKind::Pending {
                self.mode = Mode::Two(s);
            } else {
                out.extend(self.cancel());
            }
            return;
        }
        if active.len() != 2 || ids != s.base.start.ids {
            if (3..=4).contains(&active.len())
                && s.kind == TwoKind::Pending
                && s.base.travel <= 0.018
            {
                self.pending = None;
                self.begin(active, f, now, out);
            } else {
                out.extend(self.cancel());
            }
            return;
        }
        let snap = Snapshot::new(active);
        let delta = snap.center.sub(s.base.last.center);
        let total = snap.center.sub(s.base.start.center);
        s.base.travel += delta.travel();
        let duration = s.base.elapsed(f);
        let velocity = s.base.travel / duration.max(0.001) as f32;
        if s.second && s.base.travel > 0.018 {
            out.extend(self.emit_secondary());
            s.second = false;
        }
        let previous = s.kind;
        if s.kind == TwoKind::Pending {
            let ratio = if s.base.start.distance > 0.0 {
                (snap.distance - s.base.start.distance).abs() / s.base.start.distance
            } else {
                0.0
            };
            let angle = wrapped(snap.angle - s.base.start.angle).abs();
            if ratio >= 0.10 {
                s.kind = TwoKind::Pinch;
            } else if angle >= PI / 18.0 {
                s.kind = TwoKind::Rotate;
            } else if delta.vertical() && total.travel() >= 0.006 {
                s.kind = TwoKind::Scroll;
            } else if total.travel() >= 0.006
                && total.horizontal()
                && duration <= 0.35
                && total.x.abs() >= 0.12
                && velocity >= 0.35
            {
                out.push(Action::command(
                    if total.x > 0.0 {
                        PAGE_BACK
                    } else {
                        PAGE_FORWARD
                    },
                    1,
                ));
                s.kind = TwoKind::Consumed;
            } else if total.travel() >= 0.006
                && total.horizontal()
                && (duration >= 0.35 || velocity < 0.35)
            {
                s.kind = TwoKind::Horizontal;
            }
        }
        let reference = if previous == TwoKind::Pending {
            s.base.start
        } else {
            s.base.last
        };
        let delta = snap.center.sub(reference.center);
        let sign = if f.natural { 1.0 } else { -1.0 };
        match s.kind {
            TwoKind::Scroll => {
                s.vertical += delta.y * 40.0 * sign;
                let n = integral(&mut s.vertical);
                if n != 0 {
                    out.push(Action::scroll(n, 0));
                }
            }
            TwoKind::Horizontal => {
                s.horizontal += delta.x * 40.0 * sign;
                let n = integral(&mut s.horizontal);
                if n != 0 {
                    out.push(Action::scroll(0, n));
                }
            }
            TwoKind::Pinch => {
                s.pinch +=
                    (snap.distance - reference.distance) / reference.distance.max(0.001) * 24.0;
                let n = integral(&mut s.pinch);
                if n != 0 {
                    out.push(Action::command(
                        if n > 0 { ZOOM_IN } else { ZOOM_OUT },
                        n.abs(),
                    ));
                }
            }
            TwoKind::Rotate => {
                s.rotation += wrapped(snap.angle - reference.angle);
                let step = PI / 12.0;
                let n = (s.rotation / step) as i32;
                if n != 0 {
                    s.rotation -= n as f32 * step;
                    out.push(Action::command(
                        if n > 0 {
                            ROTATE_CLOCKWISE
                        } else {
                            ROTATE_COUNTER_CLOCKWISE
                        },
                        n.abs(),
                    ));
                }
            }
            _ => {}
        }
        s.base.last = snap;
        self.mode = Mode::Two(s);
    }
    fn three(
        &mut self,
        mut s: Three,
        active: &[Contact],
        released: &[Contact],
        f: &Frame,
        now: f64,
        out: &mut Actions,
    ) {
        if active.is_empty() {
            if s.kind == ThreeKind::Pending
                && s.base.released(released)
                && s.base.start.near(released)
                && s.base.elapsed(f) <= 0.28
                && s.base.travel <= 0.018
            {
                out.push(Action::command(LOOK_UP, 1));
            } else if s.kind == ThreeKind::Dragging {
                out.push(Action::drag(2, 0.0, 0.0, s.sensitivity));
            }
            self.mode = Mode::Idle;
            return;
        }
        let ids = Ids::from(active);
        if active.len() < 3 && ids.subset(s.base.start.ids) {
            if s.kind == ThreeKind::Pending && s.base.start.near(active) {
                s.deadline = f64::INFINITY;
                self.mode = Mode::Three(s);
            } else {
                out.extend(self.cancel());
            }
            return;
        }
        if active.len() != 3 || ids != s.base.start.ids {
            if active.len() == 4 && s.kind == ThreeKind::Pending && s.base.travel <= 0.018 {
                self.begin(active, f, now, out);
            } else {
                out.extend(self.cancel());
            }
            return;
        }
        let snap = Snapshot::new(active);
        let delta = snap.center.sub(s.base.last.center);
        let total = snap.center.sub(s.base.start.center);
        s.base.travel += delta.travel();
        let duration = s.base.elapsed(f);
        let velocity = s.base.travel / duration.max(0.001) as f32;
        if s.kind == ThreeKind::Pending {
            if total.y <= -0.12 && total.vertical() && duration <= 0.35 && velocity >= 0.35 {
                out.push(Action::command(APP_EXPOSE, 1));
                s.kind = ThreeKind::Consumed;
            } else if (!total.up() && total.travel() > 0.0)
                || (duration >= 0.12 && s.base.travel <= 0.04)
                || duration >= 0.35
            {
                s.kind = ThreeKind::Dragging;
                out.push(Action::drag(0, 0.0, 0.0, f.sensitivity));
            }
        }
        if s.kind == ThreeKind::Dragging && (delta.x != 0.0 || delta.y != 0.0) {
            out.push(Action::drag(1, delta.x, delta.y, f.sensitivity));
        }
        s.base.last = snap;
        s.sensitivity = f.sensitivity;
        self.mode = Mode::Three(s);
    }
    fn four(
        &mut self,
        mut s: Four,
        active: &[Contact],
        released: &[Contact],
        f: &Frame,
        out: &mut Actions,
    ) {
        if active.is_empty() {
            if !s.consumed
                && s.base.released(released)
                && s.base.start.near(released)
                && s.base.elapsed(f) <= 0.28
                && s.base.travel <= 0.018
            {
                out.push(Action::command(SWITCH_APP, 1));
            }
            self.mode = Mode::Idle;
            return;
        }
        let ids = Ids::from(active);
        if active.len() < 4 && ids.subset(s.base.start.ids) && !s.consumed {
            if s.base.start.near(active) {
                self.mode = Mode::Four(s);
            } else {
                out.extend(self.cancel());
            }
            return;
        }
        if active.len() != 4 || ids != s.base.start.ids {
            out.extend(self.cancel());
            return;
        }
        let snap = Snapshot::new(active);
        let total = snap.center.sub(s.base.start.center);
        let delta = snap.center.sub(s.base.last.center);
        s.base.travel += delta.travel();
        let duration = s.base.elapsed(f);
        let velocity = s.base.travel / duration.max(0.001) as f32;
        if !s.consumed {
            let ratio = if s.base.start.spread > 0.0 {
                (snap.spread - s.base.start.spread) / s.base.start.spread
            } else {
                0.0
            };
            if ratio.abs() >= 0.20 {
                out.push(Action::command(
                    if ratio > 0.0 {
                        SHOW_DESKTOP
                    } else {
                        APP_LAUNCHER
                    },
                    1,
                ));
                s.consumed = true;
            } else if duration <= 0.35 && s.base.travel >= 0.12 && velocity >= 0.35 {
                if total.vertical() {
                    out.push(Action::command(
                        if total.y < 0.0 {
                            MISSION_CONTROL
                        } else {
                            APP_EXPOSE
                        },
                        1,
                    ));
                    s.consumed = true;
                } else if total.horizontal() {
                    out.push(Action::command(
                        if total.x < 0.0 {
                            SPACE_LEFT
                        } else {
                            SPACE_RIGHT
                        },
                        1,
                    ));
                    s.consumed = true;
                }
            } else if duration >= 0.35 {
                s.consumed = true;
            }
        }
        s.base.last = snap;
        self.mode = Mode::Four(s);
    }
}
fn time(frame: &Frame) -> f64 {
    frame.timestamp_nanos as f64 / 1_000_000_000.0
}
fn wrapped(mut angle: f32) -> f32 {
    while angle > PI {
        angle -= PI * 2.0;
    }
    while angle < -PI {
        angle += PI * 2.0;
    }
    angle
}
fn integral(remainder: &mut f32) -> i32 {
    let adjusted = if *remainder >= 0.0 {
        *remainder + 0.0001
    } else {
        *remainder - 0.0001
    };
    let n = adjusted as i32;
    *remainder -= n as f32;
    if remainder.abs() < 0.0001 {
        *remainder = 0.0;
    }
    n
}
