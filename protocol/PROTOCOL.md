# MoTouchPad protocol v1

All integer and floating-point fields are little-endian.

## Network frame

Every TCP message starts with this 24-byte header:

| Offset | Type | Field |
|---:|---|---|
| 0 | `uint32` | Magic `0x3150544D` (`MTP1`) |
| 4 | `uint8` | Version, currently `1` |
| 5 | `uint8` | Type: `1=hello`, `2=touch` |
| 6 | `uint16` | Flags |
| 8 | `uint32` | Sequence |
| 12 | `int64` | Android monotonic timestamp in nanoseconds |
| 20 | `uint8` | Contact count |
| 21 | `uint8` | Physical button bits |
| 22 | `uint8` | Pointer sensitivity percentage (`50`-`200`; `0` means `100`) |
| 23 | `uint8` | Settings flags (bit 0: natural/reversed two-finger scrolling) |

Touch frames append one 24-byte contact record per contact:

| Type | Field |
|---|---|
| `uint8` | Stable pointer ID |
| `uint8` | State: `0=up`, `1=touching` |
| `uint16` | Reserved |
| `float32` | Normalized X |
| `float32` | Normalized Y |
| `float32` | Pressure |
| `float32` | Normalized touch major |
| `float32` | Normalized touch minor |

Each frame is a complete snapshot. Movement frames are never retransmitted.
An UP contact is included once, followed by a snapshot without that contact.

The PC sends byte `0x7F` once per second as a transport heartbeat. Android
discards inbound control bytes in protocol v1. This keeps ADB-forwarded streams
fully open and also gives the Android server prompt disconnect detection.

## Driver IOCTL frame

The Windows application sends a fixed 128-byte structure to
`IOCTL_MOTOUCHPAD_SUBMIT_FRAME` (`0x22A000`).

- 8-byte header: sequence, contact count, buttons, reserved.
- Five 24-byte contact slots.

Each driver contact contains ID, flags and normalized 16-bit X/Y, pressure,
major and minor values. Unused slots are zero.
