//
//  AudioFilter.c
//  Stash
//
//  Loaded into Wine with DYLD_INSERT_LIBRARIES. Windows games see one sound device:
//  the one chosen in Settings (STASH_AUDIO_DEVICE, a device UID), else the Mac's default
//  speaker, or the built-in one when the default is virtual or aggregate (VB-Cable,
//  BlackHole, Multi-Output). No microphones: older games probe
//  every device at startup, and Wine's 32-bit audio crashes intermittently on inputs.
//

#include <CoreAudio/CoreAudio.h>
#include <stdbool.h>
#include <stdlib.h>

#define INTERPOSE(replacement, original) \
    __attribute__((used)) static const struct { const void *r; const void *o; } \
    interpose_##original __attribute__((section("__DATA,__interpose"))) = { (const void *)replacement, (const void *)original };

static UInt32 transportType(AudioObjectID device) {
    AudioObjectPropertyAddress address = {
        kAudioDevicePropertyTransportType, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain
    };
    UInt32 type = kAudioDeviceTransportTypeUnknown, size = sizeof(type);
    AudioObjectGetPropertyData(device, &address, 0, NULL, &size, &type);
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

static bool hasStreams(AudioObjectID device, AudioObjectPropertyScope scope) {
    AudioObjectPropertyAddress address = { kAudioDevicePropertyStreams, scope, kAudioObjectPropertyElementMain };
    UInt32 size = 0;
    return AudioObjectGetPropertyDataSize(device, &address, 0, NULL, &size) == noErr && size > 0;
}

/// The default device for `selector`, or the built-in one when the default isn't a basic device
static AudioObjectID chooseDevice(AudioObjectPropertySelector selector, AudioObjectPropertyScope scope) {
    AudioObjectPropertyAddress address = {
        selector, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain
    };
    AudioObjectID device = kAudioObjectUnknown;
    UInt32 size = sizeof(device);
    AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, NULL, &size, &device);
    if (device != kAudioObjectUnknown && isBasic(device)) return device;

    address.mSelector = kAudioHardwarePropertyDevices;
    AudioObjectID devices[64];
    size = sizeof(devices);
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, NULL, &size, devices) == noErr) {
        for (UInt32 i = 0; i < size / sizeof(AudioObjectID); i++) {
            if (transportType(devices[i]) == kAudioDeviceTransportTypeBuiltIn && hasStreams(devices[i], scope))
                return devices[i];
        }
    }
    return device;
}

/// The device with the UID chosen in Settings, if it's connected and has outputs
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
    AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, NULL, &size, &translation);
    CFRelease(uidString);
    return device != kAudioObjectUnknown && hasStreams(device, kAudioObjectPropertyScopeOutput)
        ? device : kAudioObjectUnknown;
}

static AudioObjectID visibleOutput(void) {
    AudioObjectID chosen = chosenDevice();
    if (chosen != kAudioObjectUnknown) return chosen;
    return chooseDevice(kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeOutput);
}

static bool isFiltered(AudioObjectID object, const AudioObjectPropertyAddress *address, AudioObjectID *replacement) {
    if (object != kAudioObjectSystemObject) return false;
    switch (address->mSelector) {
    case kAudioHardwarePropertyDefaultOutputDevice:
    case kAudioHardwarePropertyDefaultSystemOutputDevice:
        *replacement = visibleOutput();
        return true;
    case kAudioHardwarePropertyDefaultInputDevice:
        *replacement = kAudioObjectUnknown;
        return true;
    case kAudioHardwarePropertyDevices:
        return true;
    default:
        return false;
    }
}

static OSStatus stash_GetPropertyDataSize(AudioObjectID object, const AudioObjectPropertyAddress *address,
                                          UInt32 qualifierSize, const void *qualifier, UInt32 *outSize) {
    AudioObjectID unused;
    if (address && outSize && isFiltered(object, address, &unused)) {
        if (address->mSelector == kAudioHardwarePropertyDevices) {
            *outSize = visibleOutput() == kAudioObjectUnknown ? 0 : sizeof(AudioObjectID);
        } else {
            *outSize = sizeof(AudioObjectID);
        }
        return noErr;
    }
    return AudioObjectGetPropertyDataSize(object, address, qualifierSize, qualifier, outSize);
}

static OSStatus stash_GetPropertyData(AudioObjectID object, const AudioObjectPropertyAddress *address,
                                      UInt32 qualifierSize, const void *qualifier, UInt32 *ioSize, void *outData) {
    AudioObjectID replacement = kAudioObjectUnknown;
    if (address && ioSize && outData && isFiltered(object, address, &replacement)) {
        if (address->mSelector == kAudioHardwarePropertyDevices) {
            AudioObjectID output = visibleOutput();
            *ioSize = output == kAudioObjectUnknown || *ioSize < sizeof(AudioObjectID) ? 0 : sizeof(AudioObjectID);
            if (*ioSize) *(AudioObjectID *)outData = output;
            return noErr;
        }
        if (*ioSize < sizeof(AudioObjectID)) return kAudioHardwareBadPropertySizeError;
        *(AudioObjectID *)outData = replacement;
        *ioSize = sizeof(AudioObjectID);
        return noErr;
    }
    return AudioObjectGetPropertyData(object, address, qualifierSize, qualifier, ioSize, outData);
}

INTERPOSE(stash_GetPropertyDataSize, AudioObjectGetPropertyDataSize)
INTERPOSE(stash_GetPropertyData, AudioObjectGetPropertyData)
