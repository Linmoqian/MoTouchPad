//! C callers own valid, aligned pointers and serialize operations on each handle.
use crate::{
    gesture::Recognizer,
    model::{Action, Actions, MAX_ACTIONS},
    protocol,
};
use std::panic::{catch_unwind, AssertUnwindSafe};

#[no_mangle]
pub extern "C" fn mtp_abi_version() -> u32 {
    1
}
#[no_mangle]
pub extern "C" fn mtp_action_size() -> usize {
    std::mem::size_of::<Action>()
}
#[no_mangle]
pub extern "C" fn mtp_noop(value: u64) -> u64 {
    value
}
#[no_mangle]
pub extern "C" fn mtp_create() -> *mut Recognizer {
    Box::into_raw(Box::new(Recognizer::default()))
}
#[no_mangle]
pub unsafe extern "C" fn mtp_destroy(core: *mut Recognizer) {
    if !core.is_null() {
        drop(Box::from_raw(core));
    }
}

unsafe fn output(
    core: *mut Recognizer,
    out: *mut Action,
    capacity: usize,
    operation: impl FnOnce(&mut Recognizer) -> Result<Actions, i32>,
) -> i32 {
    if core.is_null() || out.is_null() || capacity < MAX_ACTIONS {
        return -1;
    }
    match catch_unwind(AssertUnwindSafe(|| operation(&mut *core))) {
        Ok(Ok(actions)) => {
            std::ptr::copy_nonoverlapping(
                actions.as_slice().as_ptr(),
                out,
                actions.as_slice().len(),
            );
            actions.as_slice().len() as i32
        }
        Ok(Err(code)) => code,
        Err(_) => {
            (*core).reset();
            -3
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn mtp_feed(
    core: *mut Recognizer,
    bytes: *const u8,
    length: usize,
    now: f64,
    out: *mut Action,
    capacity: usize,
) -> i32 {
    if bytes.is_null() || !(24..=144).contains(&length) || !now.is_finite() {
        return -1;
    }
    output(core, out, capacity, |core| {
        let frame = protocol::decode(std::slice::from_raw_parts(bytes, length)).map_err(|_| -2)?;
        Ok(core.feed(&frame, now))
    })
}
#[no_mangle]
pub unsafe extern "C" fn mtp_advance(
    core: *mut Recognizer,
    now: f64,
    out: *mut Action,
    capacity: usize,
) -> i32 {
    if !now.is_finite() {
        return -1;
    }
    output(core, out, capacity, |core| Ok(core.advance(now)))
}
#[no_mangle]
pub unsafe extern "C" fn mtp_flush(
    core: *mut Recognizer,
    now: f64,
    out: *mut Action,
    capacity: usize,
) -> i32 {
    if !now.is_finite() {
        return -1;
    }
    output(core, out, capacity, |core| Ok(core.flush(now)))
}
#[no_mangle]
pub unsafe extern "C" fn mtp_reset(
    core: *mut Recognizer,
    out: *mut Action,
    capacity: usize,
) -> i32 {
    output(core, out, capacity, |core| Ok(core.reset()))
}
#[no_mangle]
pub unsafe extern "C" fn mtp_set_smart_zoom(core: *mut Recognizer, enabled: u8) -> i32 {
    if core.is_null() || enabled > 1 {
        return -1;
    }
    (*core).smart_zoom = enabled == 1;
    0
}
#[no_mangle]
pub unsafe extern "C" fn mtp_deadline(core: *const Recognizer, deadline: *mut f64) -> i32 {
    if core.is_null() || deadline.is_null() {
        return -1;
    }
    match (*core).deadline() {
        Some(value) => {
            *deadline = value;
            1
        }
        None => 0,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{Contact, Frame};
    #[test]
    fn invalid_calls_preserve_state_and_ownership() {
        unsafe {
            let core = mtp_create();
            let mut out = [Action::default(); MAX_ACTIONS];
            let mut f = Frame {
                kind: 2,
                count: 3,
                sensitivity: 150,
                ..Frame::default()
            };
            for i in 0..3 {
                f.contacts[i] = Contact {
                    id: i as u8,
                    touching: true,
                    x: 0.4 + i as f32 * 0.05,
                    y: 0.5,
                    ..Contact::default()
                };
            }
            let bytes = protocol::encode(&f);
            assert_eq!(
                mtp_feed(
                    core,
                    bytes.as_ptr(),
                    bytes.len(),
                    1.0,
                    out.as_mut_ptr(),
                    MAX_ACTIONS
                ),
                0
            );
            let mut deadline = 0.0;
            assert_eq!(mtp_deadline(core, &mut deadline), 1);
            assert_eq!(deadline, 1.12);
            let mut invalid = bytes.clone();
            invalid[5] = 99;
            assert_eq!(
                mtp_feed(
                    core,
                    invalid.as_ptr(),
                    invalid.len(),
                    1.1,
                    out.as_mut_ptr(),
                    MAX_ACTIONS
                ),
                -2
            );
            assert_eq!(
                mtp_advance(core, f64::NAN, out.as_mut_ptr(), MAX_ACTIONS),
                -1
            );
            assert_eq!(mtp_advance(core, 1.2, out.as_mut_ptr(), 0), -1);
            assert_eq!(
                mtp_feed(
                    core,
                    std::ptr::null(),
                    24,
                    1.1,
                    out.as_mut_ptr(),
                    MAX_ACTIONS
                ),
                -1
            );
            assert_eq!(mtp_set_smart_zoom(core, 2), -1);
            assert_eq!(mtp_deadline(core, &mut deadline), 1);
            assert_eq!(deadline, 1.12);
            assert_eq!(mtp_advance(core, 1.12, out.as_mut_ptr(), MAX_ACTIONS), 1);
            assert_eq!(out[0], Action::drag(0, 0.0, 0.0, 150));
            assert_eq!(mtp_reset(core, out.as_mut_ptr(), MAX_ACTIONS), 1);
            assert_eq!(out[0], Action::drag(2, 0.0, 0.0, 150));
            assert_eq!(
                mtp_reset(std::ptr::null_mut(), out.as_mut_ptr(), MAX_ACTIONS),
                -1
            );
            assert_eq!(mtp_action_size(), 20);
            assert_eq!(mtp_abi_version(), 1);
            mtp_destroy(core);
            mtp_destroy(std::ptr::null_mut());
        }
    }
}
