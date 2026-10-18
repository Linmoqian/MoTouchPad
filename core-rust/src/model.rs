// Created on 2026-10-13.
// @author: https://github.com/Linmoqian

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Contact {
    pub id: u8,
    pub touching: bool,
    pub x: f32,
    pub y: f32,
    pub pressure: f32,
    pub major: f32,
    pub minor: f32,
}

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Frame {
    pub kind: u8,
    pub sequence: u32,
    pub timestamp_nanos: i64,
    pub buttons: u8,
    pub sensitivity: u8,
    pub natural: bool,
    pub count: usize,
    pub contacts: [Contact; 5],
}

// Command IDs are a stable prototype ABI, independent of Rust enum layout.
pub mod command {
    pub const PAGE_BACK: i32 = 1;
    pub const PAGE_FORWARD: i32 = 2;
    pub const ZOOM_IN: i32 = 3;
    pub const ZOOM_OUT: i32 = 4;
    pub const ROTATE_CLOCKWISE: i32 = 5;
    pub const ROTATE_COUNTER_CLOCKWISE: i32 = 6;
    pub const SMART_ZOOM: i32 = 7;
    pub const LOOK_UP: i32 = 8;
    pub const MISSION_CONTROL: i32 = 9;
    pub const APP_EXPOSE: i32 = 10;
    pub const SPACE_LEFT: i32 = 11;
    pub const SPACE_RIGHT: i32 = 12;
    pub const SHOW_DESKTOP: i32 = 13;
    pub const APP_LAUNCHER: i32 = 14;
    pub const SWITCH_APP: i32 = 15;
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Action {
    pub kind: u32,
    pub code: i32,
    pub value: i32,
    pub x: f32,
    pub y: f32,
}

impl Action {
    pub fn movement(x: f32, y: f32, sensitivity: u8) -> Self {
        Self {
            kind: 1,
            code: sensitivity as i32,
            x,
            y,
            ..Self::default()
        }
    }
    pub fn click(button: i32) -> Self {
        Self {
            kind: 2,
            code: button,
            value: 1,
            ..Self::default()
        }
    }
    pub fn drag(phase: i32, x: f32, y: f32, sensitivity: u8) -> Self {
        Self {
            kind: 3,
            code: phase,
            value: sensitivity as i32,
            x,
            y,
        }
    }
    pub fn scroll(vertical: i32, horizontal: i32) -> Self {
        Self {
            kind: 4,
            code: vertical,
            value: horizontal,
            ..Self::default()
        }
    }
    pub fn command(code: i32, repeats: i32) -> Self {
        Self {
            kind: 5,
            code,
            value: repeats,
            ..Self::default()
        }
    }
}

pub const MAX_ACTIONS: usize = 8;

#[derive(Clone, Debug, Default)]
pub struct Actions {
    items: [Action; MAX_ACTIONS],
    count: usize,
}

impl Actions {
    pub fn push(&mut self, action: Action) {
        assert!(self.count < MAX_ACTIONS, "action capacity invariant");
        self.items[self.count] = action;
        self.count += 1;
    }
    pub fn extend(&mut self, other: Actions) {
        for action in other.as_slice() {
            self.push(*action);
        }
    }
    pub fn as_slice(&self) -> &[Action] {
        &self.items[..self.count]
    }
    pub fn checksum(&self) -> u64 {
        self.as_slice()
            .iter()
            .fold(self.count as u64, |sum, action| {
                sum.wrapping_add(action.kind as u64)
                    .wrapping_add(action.code as i64 as u64)
                    .wrapping_add(action.value as i64 as u64)
            })
    }
}
