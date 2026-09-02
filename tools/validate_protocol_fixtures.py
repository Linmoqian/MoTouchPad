"""Validate the protocol v1 golden byte fixtures.

Created on 2026-09-02; updated 2026-09-02.
@author: https://github.com/Linmoqian
"""

from __future__ import annotations

import json
import math
import struct
from pathlib import Path


HEADER_SIZE = 24
CONTACT_SIZE = 24
MAX_CONTACTS = 5
MAGIC = 0x3150544D
VERSION = 1


def read_hex(path: Path) -> bytes:
    tokens = path.read_text(encoding="utf-8").split()
    if any(len(token) != 2 for token in tokens):
        raise ValueError(f"{path.name}: every token must contain two hex digits")
    try:
        return bytes(int(token, 16) for token in tokens)
    except ValueError as error:
        raise ValueError(f"{path.name}: invalid hexadecimal byte") from error


def decode(data: bytes) -> dict:
    if len(data) < HEADER_SIZE:
        raise ValueError("frame is shorter than the header")
    magic, version, frame_type, flags = struct.unpack_from("<IBBH", data)
    if magic != MAGIC:
        raise ValueError("invalid magic")
    if version != VERSION:
        raise ValueError("invalid version")
    if frame_type not in (1, 2):
        raise ValueError("invalid type")
    if flags != 0:
        raise ValueError("invalid header flags")

    sequence, timestamp = struct.unpack_from("<Iq", data, 8)
    count, buttons, sensitivity, settings = struct.unpack_from(
        "<BBBB", data, 20
    )
    if count > MAX_CONTACTS:
        raise ValueError("invalid contact count")
    if sensitivity != 0 and not 50 <= sensitivity <= 200:
        raise ValueError("invalid sensitivity")
    if settings & 0xFE:
        raise ValueError("invalid settings flags")
    expected_length = HEADER_SIZE + count * CONTACT_SIZE
    if len(data) != expected_length:
        raise ValueError("invalid frame length")
    if frame_type == 1 and count != 0:
        raise ValueError("hello must be empty")

    contacts = []
    for index in range(count):
        offset = HEADER_SIZE + index * CONTACT_SIZE
        identifier, state, reserved = struct.unpack_from("<BBH", data, offset)
        if state not in (0, 1) or reserved != 0:
            raise ValueError("invalid contact state or reserved field")
        values = struct.unpack_from("<fffff", data, offset + 4)
        if any(not math.isfinite(value) or not 0 <= value <= 1 for value in values):
            raise ValueError("invalid contact value")
        contacts.append((identifier, state, *values))

    return {
        "type": frame_type,
        "sequence": sequence,
        "timestamp": timestamp,
        "buttons": buttons,
        "sensitivity": 100 if sensitivity == 0 else sensitivity,
        "settings": settings,
        "contacts": contacts,
    }


def encode(frame: dict) -> bytes:
    sensitivity = 100 if frame["sensitivity"] == 0 else frame["sensitivity"]
    header = struct.pack(
        "<IBBHIqBBBB",
        MAGIC,
        VERSION,
        frame["type"],
        0,
        frame["sequence"],
        frame["timestamp"],
        len(frame["contacts"]),
        frame["buttons"],
        sensitivity,
        frame["settings"],
    )
    contacts = b"".join(
        struct.pack("<BBHfffff", identifier, state, 0, *values)
        for identifier, state, *values in frame["contacts"]
    )
    return header + contacts


def split_stream(data: bytes) -> list[bytes]:
    frames = []
    offset = 0
    while offset < len(data):
        if len(data) - offset < HEADER_SIZE:
            raise ValueError("truncated stream header")
        count = data[offset + 20]
        total_length = HEADER_SIZE + count * CONTACT_SIZE
        if len(data) - offset < total_length:
            raise ValueError("truncated stream frame")
        frames.append(data[offset : offset + total_length])
        offset += total_length
    return frames


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    fixture_root = root / "protocol" / "fixtures"
    manifest = json.loads(
        (fixture_root / "manifest.json").read_text(encoding="utf-8")
    )

    for name in manifest["valid"]:
        data = read_hex(fixture_root / name)
        if name == "stream-two-frames.hex":
            frames = split_stream(data)
            if len(frames) != 2:
                raise AssertionError("stream fixture must contain two frames")
            for frame_data in frames:
                frame = decode(frame_data)
                if encode(frame) != frame_data:
                    raise AssertionError(f"{name}: stream frame is not canonical")
            continue
        frame = decode(data)
        if encode(frame) != data:
            raise AssertionError(f"{name}: fixture is not canonical")

    for name in manifest["invalid"]:
        try:
            decode(read_hex(fixture_root / name))
        except ValueError:
            continue
        raise AssertionError(f"{name}: invalid fixture was accepted")

    fragmented = read_hex(fixture_root / "stream-two-frames.hex")
    chunks = [fragmented[:1], fragmented[1:7], fragmented[7:31], fragmented[31:]]
    merged = b"".join(chunks)
    if len(split_stream(merged)) != 2:
        raise AssertionError("fragmented and coalesced stream was not reconstructed")
    print(f"Validated {len(manifest['valid'])} valid and "
          f"{len(manifest['invalid'])} invalid protocol fixtures.")


if __name__ == "__main__":
    main()
