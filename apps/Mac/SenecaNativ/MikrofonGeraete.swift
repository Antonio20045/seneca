import Foundation
import AVFoundation
import CoreAudio
import AudioToolbox

enum MikrofonGeraete {
    static func verfuegbare() -> [MikrofonAuswahl.Geraet] {
        geraeteIDs().compactMap { id in
            guard hatEingabe(id), let uid = uid(id) else { return nil }
            return MikrofonAuswahl.Geraet(uid: uid, name: name(id) ?? uid, istEingebaut: istEingebaut(id))
        }
    }

    static func setze(_ engine: AVAudioEngine, aufUID zielUID: String?) {
        guard let zielUID, let geraet = deviceID(fuerUID: zielUID), let unit = engine.inputNode.audioUnit else { return }
        var d = geraet
        AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &d, UInt32(MemoryLayout<AudioDeviceID>.size))
    }

    static func standard() -> (uid: String, name: String)? {
        var id = AudioDeviceID(0), groesse = UInt32(MemoryLayout<AudioDeviceID>.size)
        var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &groesse, &id) == noErr, let u = uid(id) else { return nil }
        return (u, name(id) ?? u)
    }

    private static func geraeteIDs() -> [AudioDeviceID] {
        var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var groesse: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &groesse) == noErr, groesse > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(groesse) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &groesse, &ids) == noErr else { return [] }
        return ids
    }

    private static func hatEingabe(_ id: AudioDeviceID) -> Bool {
        var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration, mScope: kAudioObjectPropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        var groesse: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &a, 0, nil, &groesse) == noErr, groesse > 0 else { return false }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(groesse), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &groesse, raw) == noErr else { return false }
        let abl = raw.assumingMemoryBound(to: AudioBufferList.self)
        return UnsafeMutableAudioBufferListPointer(abl).reduce(UInt32(0)) { $0 + $1.mNumberChannels } > 0
    }

    private static func uid(_ id: AudioDeviceID) -> String? {
        var cf: CFString = "" as CFString
        var groesse = UInt32(MemoryLayout<CFString>.size)
        var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &groesse, &cf) == noErr else { return nil }
        return cf as String
    }

    private static func name(_ id: AudioDeviceID) -> String? {
        var cf: CFString = "" as CFString
        var groesse = UInt32(MemoryLayout<CFString>.size)
        var a = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &groesse, &cf) == noErr else { return nil }
        return cf as String
    }

    private static func istEingebaut(_ id: AudioDeviceID) -> Bool {
        var transport: UInt32 = 0
        var groesse = UInt32(MemoryLayout<UInt32>.size)
        var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &groesse, &transport) == noErr else { return false }
        return transport == kAudioDeviceTransportTypeBuiltIn
    }

    private static func deviceID(fuerUID uid: String) -> AudioDeviceID? {
        var geraet = AudioDeviceID(0)
        var cf = uid as CFString
        var eingabe = AudioValueTranslation(mInputData: &cf, mInputDataSize: UInt32(MemoryLayout<CFString>.size), mOutputData: &geraet, mOutputDataSize: UInt32(MemoryLayout<AudioDeviceID>.size))
        var groesse = UInt32(MemoryLayout<AudioValueTranslation>.size)
        var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslateUIDToDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &groesse, &eingabe) == noErr, geraet != 0 else { return nil }
        return geraet
    }
}
