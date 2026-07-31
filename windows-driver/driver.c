#include "driver.h"

#define PTP_FINGER_COLLECTION \
    0x05, 0x0D,             /* Usage Page (Digitizers) */ \
    0x09, 0x22,             /* Usage (Finger) */ \
    0xA1, 0x02,             /* Collection (Logical) */ \
    0x15, 0x00,             /* Logical Minimum (0) */ \
    0x25, 0x01,             /* Logical Maximum (1) */ \
    0x09, 0x47,             /* Usage (Confidence) */ \
    0x09, 0x42,             /* Usage (Tip Switch) */ \
    0x95, 0x02,             /* Report Count (2) */ \
    0x75, 0x01,             /* Report Size (1) */ \
    0x81, 0x02,             /* Input (Data, Variable, Absolute) */ \
    0x95, 0x06,             /* Report Count (6) */ \
    0x75, 0x01,             /* Report Size (1) */ \
    0x81, 0x03,             /* Input (Constant) */ \
    0x27, 0xFF, 0xFF, 0xFF, 0xFF, /* Logical Maximum (0xFFFFFFFF) */ \
    0x09, 0x51,             /* Usage (Contact Identifier) */ \
    0x95, 0x01,             /* Report Count (1) */ \
    0x75, 0x20,             /* Report Size (32) */ \
    0x81, 0x02,             /* Input (Data, Variable, Absolute) */ \
    0x05, 0x01,             /* Usage Page (Generic Desktop) */ \
    0x15, 0x00,             /* Logical Minimum (0) */ \
    0x26, 0xFF, 0x0F,       /* Logical Maximum (4095) */ \
    0x75, 0x10,             /* Report Size (16) */ \
    0x55, 0x0E,             /* Unit Exponent (-2) */ \
    0x65, 0x13,             /* Unit (inch) */ \
    0x09, 0x30,             /* Usage (X) */ \
    0x35, 0x00,             /* Physical Minimum (0) */ \
    0x46, 0x90, 0x01,       /* Physical Maximum (400) */ \
    0x95, 0x01,             /* Report Count (1) */ \
    0x81, 0x02,             /* Input (Data, Variable, Absolute) */ \
    0x46, 0x13, 0x01,       /* Physical Maximum (275) */ \
    0x09, 0x31,             /* Usage (Y) */ \
    0x81, 0x02,             /* Input (Data, Variable, Absolute) */ \
    0xC0                    /* End Collection */

static UCHAR g_ReportDescriptor[] = {
    0x05, 0x0D,                         /* Usage Page (Digitizers) */
    0x09, 0x05,                         /* Usage (Touch Pad) */
    0xA1, 0x01,                         /* Collection (Application) */
    0x85, REPORT_ID_TOUCHPAD,
    PTP_FINGER_COLLECTION,
    PTP_FINGER_COLLECTION,
    PTP_FINGER_COLLECTION,
    PTP_FINGER_COLLECTION,
    PTP_FINGER_COLLECTION,
    0x55, 0x0C,                         /* Unit Exponent (-4) */
    0x66, 0x01, 0x10,                   /* Unit (seconds) */
    0x47, 0xFF, 0xFF, 0x00, 0x00,       /* Physical Maximum (65535) */
    0x27, 0xFF, 0xFF, 0x00, 0x00,       /* Logical Maximum (65535) */
    0x75, 0x10,
    0x95, 0x01,
    0x05, 0x0D,
    0x09, 0x56,                         /* Usage (Scan Time) */
    0x81, 0x02,
    0x09, 0x54,                         /* Usage (Contact Count) */
    0x25, 0x7F,
    0x95, 0x01,
    0x75, 0x08,
    0x81, 0x02,
    0x05, 0x09,                         /* Usage Page (Button) */
    0x09, 0x01,
    0x25, 0x01,
    0x75, 0x01,
    0x95, 0x01,
    0x81, 0x02,
    0x95, 0x07,
    0x81, 0x03,
    0x05, 0x0D,
    0x85, REPORT_ID_MAX_COUNT,
    0x09, 0x55,                         /* Contact Count Maximum */
    0x09, 0x59,                         /* Pad Type */
    0x75, 0x04,
    0x95, 0x02,
    0x25, 0x0F,
    0xB1, 0x02,
    0x06, 0x00, 0xFF,
    0x85, REPORT_ID_CERTIFICATION,
    0x09, 0xC5,
    0x15, 0x00,
    0x26, 0xFF, 0x00,
    0x75, 0x08,
    0x96, 0x00, 0x01,
    0xB1, 0x02,
    0xC0,

    0x05, 0x0D,                         /* Configuration collection */
    0x09, 0x0E,
    0xA1, 0x01,
    0x85, REPORT_ID_INPUT_MODE,
    0x09, 0x22,
    0xA1, 0x02,
    0x09, 0x52,                         /* Input Mode */
    0x15, 0x00,
    0x25, 0x0A,
    0x75, 0x08,
    0x95, 0x01,
    0xB1, 0x02,
    0xC0,
    0x09, 0x22,
    0xA1, 0x00,
    0x85, REPORT_ID_FUNCTION_SWITCH,
    0x09, 0x57,                         /* Surface Switch */
    0x09, 0x58,                         /* Button Switch */
    0x75, 0x01,
    0x95, 0x02,
    0x25, 0x01,
    0xB1, 0x02,
    0x95, 0x06,
    0xB1, 0x03,
    0xC0,
    0xC0
};

// Microsoft-defined default PTPHQA blob for a Precision Touchpad that has not
// received a production certification blob yet. Windows still requires the
// complete 256-byte feature report to be returned.
static const UCHAR g_DefaultCertificationBlob[256] = {
    0xfc, 0x28, 0xfe, 0x84, 0x40, 0xcb, 0x9a, 0x87, 0x0d, 0xbe, 0x57, 0x3c, 0xb6, 0x70, 0x09, 0x88,
    0x07, 0x97, 0x2d, 0x2b, 0xe3, 0x38, 0x34, 0xb6, 0x6c, 0xed, 0xb0, 0xf7, 0xe5, 0x9c, 0xf6, 0xc2,
    0x2e, 0x84, 0x1b, 0xe8, 0xb4, 0x51, 0x78, 0x43, 0x1f, 0x28, 0x4b, 0x7c, 0x2d, 0x53, 0xaf, 0xfc,
    0x47, 0x70, 0x1b, 0x59, 0x6f, 0x74, 0x43, 0xc4, 0xf3, 0x47, 0x18, 0x53, 0x1a, 0xa2, 0xa1, 0x71,
    0xc7, 0x95, 0x0e, 0x31, 0x55, 0x21, 0xd3, 0xb5, 0x1e, 0xe9, 0x0c, 0xba, 0xec, 0xb8, 0x89, 0x19,
    0x3e, 0xb3, 0xaf, 0x75, 0x81, 0x9d, 0x53, 0xb9, 0x41, 0x57, 0xf4, 0x6d, 0x39, 0x25, 0x29, 0x7c,
    0x87, 0xd9, 0xb4, 0x98, 0x45, 0x7d, 0xa7, 0x26, 0x9c, 0x65, 0x3b, 0x85, 0x68, 0x89, 0xd7, 0x3b,
    0xbd, 0xff, 0x14, 0x67, 0xf2, 0x2b, 0xf0, 0x2a, 0x41, 0x54, 0xf0, 0xfd, 0x2c, 0x66, 0x7c, 0xf8,
    0xc0, 0x8f, 0x33, 0x13, 0x03, 0xf1, 0xd3, 0xc1, 0x0b, 0x89, 0xd9, 0x1b, 0x62, 0xcd, 0x51, 0xb7,
    0x80, 0xb8, 0xaf, 0x3a, 0x10, 0xc1, 0x8a, 0x5b, 0xe8, 0x8a, 0x56, 0xf0, 0x8c, 0xaa, 0xfa, 0x35,
    0xe9, 0x42, 0xc4, 0xd8, 0x55, 0xc3, 0x38, 0xcc, 0x2b, 0x53, 0x5c, 0x69, 0x52, 0xd5, 0xc8, 0x73,
    0x02, 0x38, 0x7c, 0x73, 0xb6, 0x41, 0xe7, 0xff, 0x05, 0xd8, 0x2b, 0x79, 0x9a, 0xe2, 0x34, 0x60,
    0x8f, 0xa3, 0x32, 0x1f, 0x09, 0x78, 0x62, 0xbc, 0x80, 0xe3, 0x0f, 0xbd, 0x65, 0x20, 0x08, 0x13,
    0xc1, 0xe2, 0xee, 0x53, 0x2d, 0x86, 0x7e, 0xa7, 0x5a, 0xc5, 0xd3, 0x7d, 0x98, 0xbe, 0x31, 0x48,
    0x1f, 0xfb, 0xda, 0xaf, 0xa2, 0xa8, 0x6a, 0x89, 0xd6, 0xbf, 0xf2, 0xd3, 0x32, 0x2a, 0x9a, 0xe4,
    0xcf, 0x17, 0xb7, 0xb8, 0xf4, 0xe1, 0x33, 0x08, 0x24, 0x8b, 0xc4, 0x43, 0xa5, 0xe5, 0x24, 0xc2
};

static USHORT ScaleCoordinate(_In_ USHORT value)
{
    return (USHORT)(value >> 4);
}

NTSTATUS DriverEntry(
    _In_ PDRIVER_OBJECT DriverObject,
    _In_ PUNICODE_STRING RegistryPath)
{
    WDF_DRIVER_CONFIG config;

    ExInitializeDriverRuntime(DrvRtPoolNxOptIn);
    WDF_DRIVER_CONFIG_INIT(&config, MoTouchPadEvtDeviceAdd);
    return WdfDriverCreate(
        DriverObject,
        RegistryPath,
        WDF_NO_OBJECT_ATTRIBUTES,
        &config,
        WDF_NO_HANDLE);
}

NTSTATUS MoTouchPadEvtDeviceAdd(
    _In_ WDFDRIVER Driver,
    _Inout_ PWDFDEVICE_INIT DeviceInit)
{
    NTSTATUS status;
    WDFDEVICE device;
    WDF_OBJECT_ATTRIBUTES attributes;
    WDF_IO_QUEUE_CONFIG queueConfig;
    WDFQUEUE queue;
    UNICODE_STRING symbolicLink;
    VHF_CONFIG vhfConfig;
    PDEVICE_CONTEXT context;

    UNREFERENCED_PARAMETER(Driver);

    WdfDeviceInitSetDeviceType(DeviceInit, FILE_DEVICE_UNKNOWN);
    WdfDeviceInitSetExclusive(DeviceInit, FALSE);

    WDF_OBJECT_ATTRIBUTES_INIT_CONTEXT_TYPE(&attributes, DEVICE_CONTEXT);
    attributes.EvtCleanupCallback = MoTouchPadEvtDeviceCleanup;
    status = WdfDeviceCreate(&DeviceInit, &attributes, &device);
    if (!NT_SUCCESS(status)) {
        return status;
    }

    RtlInitUnicodeString(&symbolicLink, L"\\DosDevices\\MoTouchPad");
    status = WdfDeviceCreateSymbolicLink(device, &symbolicLink);
    if (!NT_SUCCESS(status)) {
        return status;
    }

    WDF_IO_QUEUE_CONFIG_INIT_DEFAULT_QUEUE(
        &queueConfig,
        WdfIoQueueDispatchSequential);
    queueConfig.EvtIoDeviceControl = MoTouchPadEvtIoDeviceControl;
    status = WdfIoQueueCreate(
        device,
        &queueConfig,
        WDF_NO_OBJECT_ATTRIBUTES,
        &queue);
    if (!NT_SUCCESS(status)) {
        return status;
    }

    UNREFERENCED_PARAMETER(queue);
    context = DeviceGetContext(device);
    context->VhfHandle = NULL;
    context->InputMode = 0;
    context->ScanTime = 0;

    VHF_CONFIG_INIT(
        &vhfConfig,
        WdfDeviceWdmGetDeviceObject(device),
        (USHORT)sizeof(g_ReportDescriptor),
        g_ReportDescriptor);
    vhfConfig.VendorID = 0x1209;
    vhfConfig.ProductID = 0x4D54;
    vhfConfig.VersionNumber = 0x0001;
    vhfConfig.VhfClientContext = context;
    vhfConfig.EvtVhfAsyncOperationGetFeature = MoTouchPadEvtGetFeature;
    vhfConfig.EvtVhfAsyncOperationSetFeature = MoTouchPadEvtSetFeature;

    status = VhfCreate(&vhfConfig, &context->VhfHandle);
    if (!NT_SUCCESS(status)) {
        context->VhfHandle = NULL;
        return status;
    }

    status = VhfStart(context->VhfHandle);
    if (!NT_SUCCESS(status)) {
        VhfDelete(context->VhfHandle, TRUE);
        context->VhfHandle = NULL;
    }
    return status;
}

VOID MoTouchPadEvtDeviceCleanup(_In_ WDFOBJECT DeviceObject)
{
    PDEVICE_CONTEXT context = DeviceGetContext((WDFDEVICE)DeviceObject);
    if (context->VhfHandle != NULL) {
        VhfDelete(context->VhfHandle, TRUE);
        context->VhfHandle = NULL;
    }
}

VOID MoTouchPadEvtIoDeviceControl(
    _In_ WDFQUEUE Queue,
    _In_ WDFREQUEST Request,
    _In_ size_t OutputBufferLength,
    _In_ size_t InputBufferLength,
    _In_ ULONG IoControlCode)
{
    NTSTATUS status = STATUS_INVALID_DEVICE_REQUEST;
    PMOTOUCHPAD_DRIVER_FRAME frame;
    size_t frameLength;
    WDFDEVICE device;
    PDEVICE_CONTEXT context;
    MOTOUCHPAD_HID_REPORT report;
    HID_XFER_PACKET packet;
    ULONG index;

    UNREFERENCED_PARAMETER(OutputBufferLength);
    UNREFERENCED_PARAMETER(InputBufferLength);

    if (IoControlCode != IOCTL_MOTOUCHPAD_SUBMIT_FRAME) {
        WdfRequestComplete(Request, status);
        return;
    }

    status = WdfRequestRetrieveInputBuffer(
        Request,
        sizeof(MOTOUCHPAD_DRIVER_FRAME),
        (PVOID*)&frame,
        &frameLength);
    if (!NT_SUCCESS(status)) {
        WdfRequestComplete(Request, status);
        return;
    }

    if (frameLength < sizeof(MOTOUCHPAD_DRIVER_FRAME) ||
        frame->ContactCount > MOTOUCHPAD_MAX_CONTACTS) {
        WdfRequestComplete(Request, STATUS_INVALID_BUFFER_SIZE);
        return;
    }

    device = WdfIoQueueGetDevice(Queue);
    context = DeviceGetContext(device);
    if (context->VhfHandle == NULL) {
        WdfRequestComplete(Request, STATUS_DEVICE_NOT_READY);
        return;
    }

    RtlZeroMemory(&report, sizeof(report));
    report.ReportId = REPORT_ID_TOUCHPAD;
    report.ScanTime = ++context->ScanTime;
    report.ContactCount = frame->ContactCount;
    report.Buttons = (UCHAR)(frame->Buttons & 0x01);

    for (index = 0; index < frame->ContactCount; ++index) {
        const PMOTOUCHPAD_DRIVER_CONTACT source = &frame->Contacts[index];
        PMOTOUCHPAD_HID_CONTACT target = &report.Contacts[index];
        target->Flags = (UCHAR)(source->Flags & 0x03);
        target->ContactId = source->Id;
        target->X = ScaleCoordinate(source->X);
        target->Y = ScaleCoordinate(source->Y);
    }

    packet.reportBuffer = (PUCHAR)&report;
    packet.reportBufferLen = sizeof(report);
    packet.reportId = REPORT_ID_TOUCHPAD;
    status = VhfReadReportSubmit(context->VhfHandle, &packet);
    WdfRequestCompleteWithInformation(
        Request,
        status,
        NT_SUCCESS(status) ? sizeof(MOTOUCHPAD_DRIVER_FRAME) : 0);
}

VOID MoTouchPadEvtGetFeature(
    _In_ PVOID VhfClientContext,
    _In_ VHFOPERATIONHANDLE VhfOperationHandle,
    _In_opt_ PVOID VhfOperationContext,
    _In_ PHID_XFER_PACKET HidTransferPacket)
{
    NTSTATUS status = STATUS_SUCCESS;
    PDEVICE_CONTEXT context = (PDEVICE_CONTEXT)VhfClientContext;

    UNREFERENCED_PARAMETER(VhfOperationContext);
    if (HidTransferPacket->reportBuffer == NULL ||
        HidTransferPacket->reportBufferLen == 0) {
        VhfAsyncOperationComplete(
            VhfOperationHandle,
            STATUS_INVALID_BUFFER_SIZE);
        return;
    }

    RtlZeroMemory(
        HidTransferPacket->reportBuffer,
        HidTransferPacket->reportBufferLen);
    HidTransferPacket->reportBuffer[0] = HidTransferPacket->reportId;

    switch (HidTransferPacket->reportId) {
    case REPORT_ID_MAX_COUNT:
        if (HidTransferPacket->reportBufferLen < 2) {
            status = STATUS_INVALID_BUFFER_SIZE;
        } else {
            HidTransferPacket->reportBuffer[1] = MOTOUCHPAD_MAX_CONTACTS;
        }
        break;
    case REPORT_ID_CERTIFICATION:
        if (HidTransferPacket->reportBufferLen < 257) {
            status = STATUS_INVALID_BUFFER_SIZE;
        } else {
            RtlCopyMemory(
                HidTransferPacket->reportBuffer + 1,
                g_DefaultCertificationBlob,
                sizeof(g_DefaultCertificationBlob));
        }
        break;
    case REPORT_ID_INPUT_MODE:
        if (HidTransferPacket->reportBufferLen < 2) {
            status = STATUS_INVALID_BUFFER_SIZE;
        } else {
            HidTransferPacket->reportBuffer[1] = context->InputMode;
        }
        break;
    case REPORT_ID_FUNCTION_SWITCH:
        if (HidTransferPacket->reportBufferLen < 2) {
            status = STATUS_INVALID_BUFFER_SIZE;
        } else {
            HidTransferPacket->reportBuffer[1] = 0x03;
        }
        break;
    default:
        status = STATUS_NOT_SUPPORTED;
        break;
    }

    VhfAsyncOperationComplete(VhfOperationHandle, status);
}

VOID MoTouchPadEvtSetFeature(
    _In_ PVOID VhfClientContext,
    _In_ VHFOPERATIONHANDLE VhfOperationHandle,
    _In_opt_ PVOID VhfOperationContext,
    _In_ PHID_XFER_PACKET HidTransferPacket)
{
    NTSTATUS status = STATUS_NOT_SUPPORTED;
    PDEVICE_CONTEXT context = (PDEVICE_CONTEXT)VhfClientContext;

    UNREFERENCED_PARAMETER(VhfOperationContext);
    if (HidTransferPacket->reportId == REPORT_ID_INPUT_MODE &&
        HidTransferPacket->reportBuffer != NULL &&
        HidTransferPacket->reportBufferLen >= 2) {
        context->InputMode = HidTransferPacket->reportBuffer[1];
        status = STATUS_SUCCESS;
    } else if (HidTransferPacket->reportId == REPORT_ID_FUNCTION_SWITCH) {
        status = STATUS_SUCCESS;
    }

    VhfAsyncOperationComplete(VhfOperationHandle, status);
}
