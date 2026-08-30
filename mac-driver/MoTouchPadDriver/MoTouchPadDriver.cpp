#include "MoTouchPadDriver.hpp"

#include <DriverKit/IOLib.h>

// 骨架占位：正式 report descriptor 参照 windows-driver/driver.c 的
// PTP_FINGER_COLLECTION 布局编写，此处仅保留接口形态。
static const uint8_t gPlaceholderReportDescriptor[] = {
    0x05, 0x0D, // Usage Page (Digitizers)
    0x09, 0x05, // Usage (Touch Pad)
    0xA1, 0x01, // Collection (Application)
    0xC0,       // End Collection
};

bool MoTouchPadDriver::init(OSDictionary* dictionary)
{
    if (!IOUserHIDDevice::init(dictionary)) {
        return false;
    }
    bzero(pendingContacts, sizeof(pendingContacts));
    return true;
}

void MoTouchPadDriver::free(void)
{
    IOUserHIDDevice::free();
}

const uint8_t* MoTouchPadDriver::getReportDescriptor(uint32_t* size) const
{
    if (size != nullptr) {
        *size = sizeof(gPlaceholderReportDescriptor);
    }
    return gPlaceholderReportDescriptor;
}

kern_return_t MoTouchPadDriver::submitFrame(const MoTouchPadContact* contacts, uint8_t count)
{
    if (contacts == nullptr || count > kMaxContacts) {
        return kIOReturnBadArgument;
    }
    // 骨架占位：正式实现应填充 PTP 输入报告并调用
    // handleReport / publishReport 将快照注入 HID 栈。
    bcopy(contacts, pendingContacts, sizeof(MoTouchPadContact) * count);
    return kIOReturnSuccess;
}
