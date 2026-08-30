#ifndef MOTOUCHPAD_DRIVER_H
#define MOTOUCHPAD_DRIVER_H

#include <HIDDriverKit/IOUserHIDDevice.h>

/// 协议常量与 windows-driver 保持一致（protocol/PROTOCOL.md）。
static constexpr uint16_t kMaxContacts = 5;
static constexpr uint8_t kReportIdTouchpad = 1;

/// 触控点（骨架占位）：字段布局待与用户客户端接口一起定稿。
struct MoTouchPadContact {
    uint8_t id;
    uint8_t flags; // bit0 Confidence, bit1 Tip Switch
    uint16_t x;    // 16 位归一化
    uint16_t y;
    uint16_t pressure;
    uint16_t major;
    uint16_t minor;
};

/// 虚拟 Precision Touchpad 设备（骨架占位）。
/// 生命周期方法与 report descriptor 在后续提交中补齐。
class MoTouchPadDriver : public IOUserHIDDevice {
    OSDeclareDefaultStructors(MoTouchPadDriver)

public:
    bool init(OSDictionary* dictionary) override;
    void free(void) override;

    /// 由用户客户端调用：提交一帧触控快照。
    kern_return_t submitFrame(const MoTouchPadContact* contacts, uint8_t count);

protected:
    const uint8_t* getReportDescriptor(uint32_t* size) const override;

private:
    MoTouchPadContact pendingContacts[kMaxContacts];
};

#endif // MOTOUCHPAD_DRIVER_H
