"""Validate cross-process measurements and print median-of-rounds, without writes."""
import json
import math
import statistics
import sys
from pathlib import Path


def summarize(directory):
    measurements = {}
    for round_number in range(1, 4):
        swift = json.loads((directory / f"swift-{round_number}.json").read_text())
        rust = json.loads((directory / f"rust-{round_number}.json").read_text())
        business = [m for m in swift["measurements"] if m["path"] != "c-abi-noop-loop"]
        assert len(business) == 3, "missing Swift paths"
        assert len({m["checksum"] for m in business + [rust]}) == 1, "native/FFI checksums differ"
        for field in ("steps", "samples", "repeats"):
            assert len({m[field] for m in business + [rust]}) == 1, f"unequal {field}"
        for m in swift["measurements"] + [rust]:
            assert len(m["blocks_ns"]) == m["samples"]
            assert all(math.isfinite(x) and x > 0 for x in m["blocks_ns"]), "invalid timing"
            measurements.setdefault(m["path"], []).append(m)
    return {
        path: {
            "median_ns": statistics.median(m["median_ns"] for m in rounds),
            "round_medians_ns": [m["median_ns"] for m in rounds],
            "p95_block_ns": statistics.median(m["p95_block_ns"] for m in rounds),
            "p99_block_ns": statistics.median(m["p99_block_ns"] for m in rounds),
        }
        for path, rounds in measurements.items()
    }


if __name__ == "__main__":
    directory = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).parent / "results"
    print(json.dumps(summarize(directory), indent=2, ensure_ascii=False))
