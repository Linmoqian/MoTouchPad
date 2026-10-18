#!/bin/bash
set -euo pipefail
task_skip_build=0
if [ "${1:-}" = "--skip-build" ]; then
    task_skip_build=1
    shift
fi
task_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
task_results="$task_root/tools/RustCoreComparison/results"
task_repeats="${1:-64}"
task_samples="${2:-51}"
mkdir -p "$task_results"
if [ "$task_skip_build" = 0 ]; then
    cargo test --manifest-path "$task_root/core-rust/Cargo.toml" --locked --offline --jobs 1
    cargo build --manifest-path "$task_root/core-rust/Cargo.toml" --release --locked --offline --jobs 1
    swift build --package-path "$task_root/tools/RustCoreComparison" -c release --jobs 1
fi
# SwiftPM creates this profile symlink for the host architecture after a build.
task_swift_bin="$task_root/tools/RustCoreComparison/.build/release/CompareCore"
test -x "$task_swift_bin"
test -x "$task_root/core-rust/target/release/core-replay"
for task_round in 1 2 3; do
    # Alternate order to expose clock/load drift; never run competing benchmarks concurrently.
    if [ "$task_round" = 2 ]; then
        "$task_root/core-rust/target/release/core-replay" "$task_root/protocol/trajectories/gestures-v1.trace" "$task_repeats" "$task_samples" > "$task_results/rust-$task_round.json"
    fi
    "$task_swift_bin" "$task_root" "$task_results/swift-$task_round.json" "$task_repeats" "$task_samples"
    if [ "$task_round" != 2 ]; then
        "$task_root/core-rust/target/release/core-replay" "$task_root/protocol/trajectories/gestures-v1.trace" "$task_repeats" "$task_samples" > "$task_results/rust-$task_round.json"
    fi
done
python3 "$task_root/tools/RustCoreComparison/summarize.py" "$task_results"
printf 'Raw measurements: %s\n' "$task_results"
