// Created on 2026-10-13.
// @author: https://github.com/Linmoqian

use crate::model::{Contact, Frame};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ProtocolError {
    Truncated,
    Magic,
    Version,
    Type,
    Count,
    Length,
    Sensitivity,
    Hello,
    Value,
}

pub fn frame_size(bytes: &[u8]) -> Result<Option<usize>, ProtocolError> {
    if bytes.len() < 24 {
        return Ok(None);
    }
    if bytes[..4] != *b"MTP1" {
        return Err(ProtocolError::Magic);
    }
    if bytes[4] != 1 {
        return Err(ProtocolError::Version);
    }
    if bytes[5] != 1 && bytes[5] != 2 {
        return Err(ProtocolError::Type);
    }
    if bytes[20] > 5 {
        return Err(ProtocolError::Count);
    }
    Ok(Some(24 + bytes[20] as usize * 24))
}

pub fn decode(bytes: &[u8]) -> Result<Frame, ProtocolError> {
    let size = frame_size(bytes)?.ok_or(ProtocolError::Truncated)?;
    if bytes.len() != size {
        return Err(ProtocolError::Length);
    }
    if u16::from_le_bytes(bytes[6..8].try_into().unwrap()) != 0 || bytes[23] & 0xfe != 0 {
        return Err(ProtocolError::Length);
    }
    if bytes[22] != 0 && !(50..=200).contains(&bytes[22]) {
        return Err(ProtocolError::Sensitivity);
    }
    if bytes[5] == 1 && bytes[20] != 0 {
        return Err(ProtocolError::Hello);
    }
    let mut frame = Frame {
        kind: bytes[5],
        sequence: u32::from_le_bytes(bytes[8..12].try_into().unwrap()),
        timestamp_nanos: i64::from_le_bytes(bytes[12..20].try_into().unwrap()),
        buttons: bytes[21],
        sensitivity: if bytes[22] == 0 { 100 } else { bytes[22] },
        natural: bytes[23] & 1 != 0,
        count: bytes[20] as usize,
        ..Frame::default()
    };
    for index in 0..frame.count {
        let start = 24 + index * 24;
        if bytes[start + 1] > 1 || bytes[start + 2..start + 4] != [0, 0] {
            return Err(ProtocolError::Length);
        }
        let mut values = [0.0; 5];
        for (field, value) in values.iter_mut().enumerate() {
            let offset = start + 4 + field * 4;
            *value = f32::from_le_bytes(bytes[offset..offset + 4].try_into().unwrap());
            if !value.is_finite() || !(0.0..=1.0).contains(value) {
                return Err(ProtocolError::Value);
            }
        }
        frame.contacts[index] = Contact {
            id: bytes[start],
            touching: bytes[start + 1] == 1,
            x: values[0],
            y: values[1],
            pressure: values[2],
            major: values[3],
            minor: values[4],
        };
    }
    Ok(frame)
}

pub fn encode(frame: &Frame) -> Vec<u8> {
    assert!(frame.count <= 5);
    let mut bytes = Vec::with_capacity(24 + frame.count * 24);
    bytes.extend_from_slice(b"MTP1");
    bytes.extend_from_slice(&[1, frame.kind, 0, 0]);
    bytes.extend_from_slice(&frame.sequence.to_le_bytes());
    bytes.extend_from_slice(&frame.timestamp_nanos.to_le_bytes());
    bytes.extend_from_slice(&[
        frame.count as u8,
        frame.buttons,
        if frame.sensitivity == 0 {
            100
        } else {
            frame.sensitivity
        },
        frame.natural as u8,
    ]);
    for point in &frame.contacts[..frame.count] {
        bytes.extend_from_slice(&[point.id, point.touching as u8, 0, 0]);
        for value in [point.x, point.y, point.pressure, point.major, point.minor] {
            bytes.extend_from_slice(&value.to_le_bytes());
        }
    }
    assert!(decode(&bytes).is_ok(), "invalid domain frame");
    bytes
}

#[derive(Default)]
pub struct StreamDecoder {
    buffer: Vec<u8>,
}

impl StreamDecoder {
    pub fn append(&mut self, bytes: &[u8]) -> Result<Vec<Frame>, ProtocolError> {
        self.buffer.extend_from_slice(bytes);
        let result = (|| {
            let mut frames = Vec::new();
            let mut offset = 0;
            while let Some(size) = frame_size(&self.buffer[offset..])? {
                if self.buffer.len() - offset < size {
                    break;
                }
                frames.push(decode(&self.buffer[offset..offset + size])?);
                offset += size;
            }
            self.buffer.copy_within(offset.., 0);
            self.buffer.truncate(self.buffer.len() - offset);
            Ok(frames)
        })();
        if result.is_err() {
            self.buffer.clear();
        }
        result
    }
    pub fn buffered_len(&self) -> usize {
        self.buffer.len()
    }
}
