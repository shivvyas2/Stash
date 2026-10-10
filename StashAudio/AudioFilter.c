//
//  AudioFilter.c
//  Stash
//
//  Stands in for CoreAudio inside the classic engine's audio driver: Stash points
//  winecoreaudio.so at this library instead of the CoreAudio framework. It answers
//  device-list questions itself and re-exports CoreAudio for everything else.
//
//  Windows games see one sound device: the one picked when the game was launched
//  (STASH_AUDIO_DEVICE, a device UID), else the Mac's default speaker, or the built-in
//  one when the default is virtual or aggregate (VB-Cable, BlackHole, Multi-Output).
//  No microphones: older games probe every device at startup, and Wine's 32-bit audio
//  crashes on some of them.
//
//  Only the audio driver loads this, and only when a game starts sound, so it can't
//  affect anything else in the game's process.
//

#include <CoreAudio/CoreAudio.h>
#include <dlfcn.h>
#include <stdbool.h>
#include <stdlib.h>

typedef OSStatus (*GetSizeFunction)(AudioObjectID, const AudioObjectPropertyAddress *, UInt32, const void *, UInt32 *);
typedef OSStatus (*GetDataFunction)(AudioObjectID, const AudioObjectPropertyAddress *, UInt32, const void *,
                                    UInt32 *, void *);

static GetSizeFunction realGetSize;
static GetDataFunction realGetData;

__attribute__((constructor)) static void loadCoreAudio(void) {
    void *coreAudio = dlopen("/System/Library/Frameworks/CoreAudio.framework/CoreAudio", RTLD_LAZY);
    realGetSize = (GetSizeFunction)dlsym(coreAudio, "AudioObjectGetPropertyDataSize");
    realGetData = (GetDataFunction)dlsym(coreAudio, "AudioObjectGetPropertyData");
}

static UInt32 transportType(AudioObjectID device) {
    AudioObjectPropertyAddress address = {
        kAudioDevicePropertyTransportType, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain
    };
    UInt32 type = kAudioDeviceTransportTypeUnknown, size = sizeof(type);
    realGetData(device, &address, 0, NULL, &size, &type);
    return type;
}

static bool isBasic(AudioObjectID device) {
    switch (transportType(device)) {
    case kAudioDeviceTransportTypeVirtual:
    case kAudioDeviceTransportTypeAggregate:
    case kAudioDeviceTransportTypeAutoAggregate:
    case kAudioDeviceTransportTypeUnknown:
        return false;
    default:
        return true;
    }
}

static bool hasOutput(AudioObjectID device) {
    AudioObjectPropertyAddress address = {
        kAudioDevicePropertyStreams, kAudioObjectPropertyScopeOutput, kAudioObjectPropertyElementMain
    };
    UInt32 size = 0;
    return realGetSize(device, &address, 0, NULL, &size) == noErr && size > 0;
}

/// The device picked at launch, if it's connected and has outputs
static AudioObjectID chosenDevice(void) {
    const char *uid = getenv("STASH_AUDIO_DEVICE");
    if (!uid || !*uid) return kAudioObjectUnknown;
    CFStringRef uidString = CFStringCreateWithCString(NULL, uid, kCFStringEncodingUTF8);
    if (!uidString) return kAudioObjectUnknown;
    AudioObjectID device = kAudioObjectUnknown;
    AudioValueTranslation translation = { &uidString, sizeof(uidString), &device, sizeof(device) };
    AudioObjectPropertyAddress address = {
        kAudioHardwarePropertyDeviceForUID, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain
    };
    UInt32 size = sizeof(translation);
    realGetData(kAudioObjectSystemObject, &address, 0, NULL, &size, &translation);
    CFRelease(uidString);
    return device != kAudioObjectUnknown && hasOutput(device) ? device : kAudioObjectUnknown;
}

/// The one output games may see
static AudioObjectID visibleOutput(void) {
    AudioObjectID chosen = chosenDevice();
    if (chosen != kAudioObjectUnknown) return chosen;

    AudioObjectPropertyAddress address = {
        kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain
    };
    AudioObjectID device = kAudioObjectUnknown;
    UInt32 size = sizeof(device);
    realGetData(kAudioObjectSystemObject, &address, 0, NULL, &size, &device);
    if (device != kAudioObjectUnknown && isBasic(device)) return device;

    address.mSelector = kAudioHardwarePropertyDevices;
    AudioObjectID devices[64];
    size = sizeof(devices);
    if (realGetData(kAudioObjectSystemObject, &address, 0, NULL, &size, devices) == noErr) {
        for (UInt32 i = 0; i < size / sizeof(AudioObjectID); i++) {
            if (transportType(devices[i]) == kAudioDeviceTransportTypeBuiltIn && hasOutput(devices[i]))
                return devices[i];
        }
    }
    return device;
}

static bool isFiltered(AudioObjectID object, const AudioObjectPropertyAddress *address) {
    if (object != kAudioObjectSystemObject || !address) return false;
    switch (address->mSelector) {
    case kAudioHardwarePropertyDevices:
    case kAudioHardwarePropertyDefaultOutputDevice:
    case kAudioHardwarePropertyDefaultSystemOutputDevice:
    case kAudioHardwarePropertyDefaultInputDevice:
        return true;
    default:
        return false;
    }
}

OSStatus AudioObjectGetPropertyDataSize(AudioObjectID object, const AudioObjectPropertyAddress *address,
                                        UInt32 qualifierSize, const void *qualifier, UInt32 *outSize) {
    if (outSize && isFiltered(object, address)) {
        bool empty = address->mSelector == kAudioHardwarePropertyDevices && visibleOutput() == kAudioObjectUnknown;
        *outSize = empty ? 0 : sizeof(AudioObjectID);
        return noErr;
    }
    return realGetSize(object, address, qualifierSize, qualifier, outSize);
}

OSStatus AudioObjectGetPropertyData(AudioObjectID object, const AudioObjectPropertyAddress *address,
                                    UInt32 qualifierSize, const void *qualifier, UInt32 *ioSize, void *outData) {
    if (ioSize && outData && isFiltered(object, address)) {
        AudioObjectID device = address->mSelector == kAudioHardwarePropertyDefaultInputDevice
            ? kAudioObjectUnknown : visibleOutput();
        if (address->mSelector == kAudioHardwarePropertyDevices) {
            *ioSize = device == kAudioObjectUnknown || *ioSize < sizeof(AudioObjectID) ? 0 : sizeof(AudioObjectID);
            if (*ioSize) *(AudioObjectID *)outData = device;
            return noErr;
        }
        if (*ioSize < sizeof(AudioObjectID)) return kAudioHardwareBadPropertySizeError;
        *(AudioObjectID *)outData = device;
        *ioSize = sizeof(AudioObjectID);
        return noErr;
    }
    return realGetData(object, address, qualifierSize, qualifier, ioSize, outData);
}
