use motouchpad_core::{gesture::Recognizer, traces};
use std::{hint::black_box, time::Instant};

fn main() {
    let args: Vec<_> = std::env::args().collect();
    let text = std::fs::read_to_string(args.get(1).expect("core-replay TRACE [REPEATS] [SAMPLES]"))
        .unwrap();
    let steps = traces::parse(&text).unwrap();
    let repeats: usize = args.get(2).map_or(32, |v| v.parse().unwrap());
    let samples: usize = args.get(3).map_or(51, |v| v.parse().unwrap());
    assert!(repeats > 0 && samples > 0 && !steps.is_empty());
    let mut core = Recognizer::default();
    let mut checksum = 0u64;
    for _ in 0..8 {
        for step in &steps {
            checksum = checksum.wrapping_add(black_box(traces::run(&mut core, step)).checksum());
            checksum = checksum.wrapping_add(black_box(core.deadline()).is_some() as u64);
        }
    }
    let mut ns = Vec::new();
    for _ in 0..samples {
        let start = Instant::now();
        for _ in 0..repeats {
            for step in &steps {
                checksum = checksum
                    .wrapping_add(black_box(traces::run(&mut core, black_box(step))).checksum());
                checksum = checksum.wrapping_add(black_box(core.deadline()).is_some() as u64);
            }
        }
        ns.push(start.elapsed().as_nanos() as f64 / (repeats * steps.len()) as f64);
    }
    ns.sort_by(f64::total_cmp);
    println!("{{\"path\":\"rust-native\",\"steps\":{},\"samples\":{},\"repeats\":{},\"median_ns\":{},\"p95_block_ns\":{},\"p99_block_ns\":{},\"checksum\":{},\"blocks_ns\":{:?}}}",
        steps.len(), samples, repeats, ns[samples/2], ns[(samples*95).div_ceil(100)-1], ns[(samples*99).div_ceil(100)-1], checksum, ns);
}
