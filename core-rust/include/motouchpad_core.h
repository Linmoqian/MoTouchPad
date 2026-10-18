#ifndef MOTOUCHPAD_CORE_H
#define MOTOUCHPAD_CORE_H
#include <stdint.h>
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct MTPCore MTPCore;
typedef struct { uint32_t kind; int32_t code; int32_t value; float x; float y; } MTPAction;
enum { MTP_MAX_ACTIONS = 8 };
/* kind: 1 move(code=sensitivity), 2 click(code=1 primary/2 secondary,value=count),
 * 3 drag(code=0 began/1 moved/2 ended,value=sensitivity),
 * 4 scroll(code=vertical,value=horizontal), 5 command(code=ID,value=repeats).
 * command IDs 1..15: back, forward, zoomIn, zoomOut, clockwise, counterClockwise,
 * smartZoom, lookUp, missionControl, appExpose, spaceLeft, spaceRight,
 * showDesktop, appLauncher, switchApp.
 * Handle ownership: create/destroy once, serialized calls, valid aligned buffers.
 * Output capacity must be >=8; return count, -1 arguments, -2 protocol, -3 panic.
 * Rejected arguments/protocol do not mutate state. On panic the state is reset;
 * caller must release injected buttons. No system input is injected here. */
uint32_t mtp_abi_version(void);
size_t mtp_action_size(void);
uint64_t mtp_noop(uint64_t value);
MTPCore *mtp_create(void);
void mtp_destroy(MTPCore *core);
int32_t mtp_feed(MTPCore *, const uint8_t *, size_t, double, MTPAction *, size_t);
int32_t mtp_advance(MTPCore *, double, MTPAction *, size_t);
int32_t mtp_flush(MTPCore *, double, MTPAction *, size_t);
int32_t mtp_reset(MTPCore *, MTPAction *, size_t);
int32_t mtp_set_smart_zoom(MTPCore *, uint8_t enabled);
/* Returns 0 absent, 1 present, -1 invalid arguments; time uses caller's clock. */
int32_t mtp_deadline(const MTPCore *, double *deadline);
#ifdef __cplusplus
}
#endif
#endif
