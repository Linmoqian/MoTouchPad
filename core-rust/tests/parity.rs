use motouchpad_core::{
    gesture::Recognizer,
    model::{Action, Contact, Frame},
    protocol::{self, StreamDecoder},
    traces,
};
use std::{collections::BTreeSet, path::Path};

#[test]
fn shared_trajectories_cover_every_action_and_command() {
    let steps = traces::parse(include_str!(
        "../../protocol/trajectories/gestures-v1.trace"
    ))
    .unwrap();
    let mut core = Recognizer::default();
    let mut commands = BTreeSet::new();
    let mut kinds = BTreeSet::new();
    for step in &steps {
        for a in traces::run(&mut core, step).as_slice() {
            kinds.insert(a.kind);
            if a.kind == 5 {
                commands.insert(a.code);
            }
            assert!(a.x.is_finite() && a.y.is_finite());
        }
        assert!(core.deadline().is_none_or(f64::is_finite));
    }
    assert_eq!(kinds, (1..=5).collect());
    assert_eq!(commands, (1..=15).collect());
    assert!(core.reset().as_slice().is_empty());
    assert_eq!(core.deadline(), None);
}
#[test]
fn golden_protocol_roundtrips_and_every_stream_split() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../protocol/fixtures");
    let mut checked = 0;
    for entry in std::fs::read_dir(root).unwrap() {
        let path = entry.unwrap().path();
        if path.extension().is_none_or(|e| e != "hex") {
            continue;
        }
        let bytes = traces::unhex(&std::fs::read_to_string(&path).unwrap()).unwrap();
        if path
            .file_name()
            .unwrap()
            .to_str()
            .unwrap()
            .starts_with("invalid-")
        {
            assert!(protocol::decode(&bytes).is_err(), "{}", path.display());
        } else {
            let expected = StreamDecoder::default().append(&bytes).unwrap();
            assert!(!expected.is_empty());
            let mut offset = 0;
            for f in &expected {
                let encoded = protocol::encode(f);
                assert_eq!(protocol::decode(&encoded).unwrap(), *f);
                // Golden fixtures use canonical sensitivity=100, not the 0 alias.
                assert_eq!(encoded, bytes[offset..offset + encoded.len()]);
                offset += encoded.len();
            }
            for split in 0..=bytes.len() {
                let mut stream = StreamDecoder::default();
                let mut actual = stream.append(&bytes[..split]).unwrap();
                actual.extend(stream.append(&bytes[split..]).unwrap());
                assert_eq!(actual, expected);
                assert_eq!(stream.buffered_len(), 0);
            }
            let mut stream = StreamDecoder::default();
            let mut actual = Vec::new();
            for b in &bytes {
                actual.extend(stream.append(&[*b]).unwrap());
            }
            assert_eq!(actual, expected);
        }
        checked += 1;
    }
    assert_eq!(checked, 18);
}
fn three() -> Frame {
    let mut f = Frame {
        kind: 2,
        sensitivity: 100,
        count: 3,
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
    f
}
#[test]
fn timer_reset_releases_drag_and_cancels_clicks() {
    let mut core = Recognizer::default();
    let mut f = three();
    assert!(core.feed(&f, 1.0).as_slice().is_empty());
    assert_eq!(core.deadline(), Some(1.12));
    assert_eq!(
        core.advance(1.12).as_slice(),
        &[Action::drag(0, 0.0, 0.0, 100)]
    );
    assert_eq!(core.reset().as_slice(), &[Action::drag(2, 0.0, 0.0, 100)]);
    assert_eq!(core.deadline(), None);
    assert!(core.reset().as_slice().is_empty());
    f.count = 2;
    core.feed(&f, 2.0);
    f.timestamp_nanos = 50_000_000;
    for c in &mut f.contacts[..2] {
        c.touching = false;
    }
    core.feed(&f, 2.05);
    assert!((core.deadline().unwrap() - 2.35).abs() < 1e-9);
    core.reset();
    assert!(core.advance(3.0).as_slice().is_empty());
}
#[test]
fn malformed_protocol_is_bounded_and_stream_recovers() {
    let bytes = protocol::encode(&three());
    for i in 0..bytes.len() {
        for value in [0, 1, 127, 255] {
            let mut mutated = bytes.clone();
            mutated[i] = value;
            if let Ok(frame) = protocol::decode(&mutated) {
                Recognizer::default().feed(&frame, 0.0);
            }
        }
    }
    let mut stream = StreamDecoder::default();
    let mut bad = bytes.clone();
    bad[4] = 99;
    assert!(stream.append(&bad).is_err());
    assert_eq!(stream.buffered_len(), 0);
    assert_eq!(stream.append(&bytes).unwrap().len(), 1);
}
