//
//  AudioDevices.swift
//  Stash
//
//  The Mac's speakers and headphones, for choosing where classic games play sound.
//  The choice reaches StashAudio/AudioFilter.c as STASH_AUDIO_DEVICE.
//

import CoreAudio
import Foundation

struct AudioOutputDevice: Identifiable, Hashable {
    let uid: String
    let name: String
    /// Virtual and combined devices (VB-Cable, BlackHole, Multi-Output) crash some games
    let isSupported: Bool

    var id: String { uid }
}

enum AudioDevices {
    /// The UserDefaults key for the chosen device's UID. Empty means automatic.
    static let settingKey = "gameAudioDevice"

    static var chosenUID: String? {
        let uid = UserDefaults.standard.string(forKey: settingKey) ?? ""
        return uid.isEmpty ? nil : uid
    }

    static func outputs() -> [AudioOutputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr
        else { return [] }
        var devices = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices)
            == noErr else { return [] }

        return devices.compactMap { device in
            guard hasOutput(device), let uid = string(device, kAudioDevicePropertyDeviceUID),
                  let name = string(device, kAudioObjectPropertyName) else { return nil }
            return AudioOutputDevice(uid: uid, name: name, isSupported: isSupported(device))
        }
    }

    private static func hasOutput(_ device: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func isSupported(_ device: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var type: UInt32 = kAudioDeviceTransportTypeUnknown
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(device, &address, 0, nil, &size, &type)
        return ![kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate,
                 kAudioDeviceTransportTypeAutoAggregate, kAudioDeviceTransportTypeUnknown].contains(type)
    }

    private static func string(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr,
              let value else { return nil }
        return value.takeRetainedValue() as String
    }
}
