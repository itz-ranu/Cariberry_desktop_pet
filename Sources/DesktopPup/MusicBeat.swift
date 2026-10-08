import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

/// Listens to whatever your Mac is playing and calls `onBeat` on each beat, so she can bop her
/// head. It uses ScreenCaptureKit's *audio-only* capture (a 2x2-pixel video stream is the
/// minimum it allows and is thrown away), which is the only way to hear other apps' sound:
/// tapping her own audio engine would only ever hear her own little voice.
///
/// It's strictly opt-in (Settings ▸ Bop to my music), needs macOS's "Screen & System Audio
/// Recording" permission, and only analyses loudness. No audio is stored or sent anywhere.
final class MusicBeatDetector: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    /// Called on the main queue with a 0...1 strength.
    var onBeat: ((Double) -> Void)?
    /// Called on the main queue if capture can't start (usually: permission not granted).
    var onFailure: ((String) -> Void)?

    private var stream: SCStream?
    private let queue = DispatchQueue(label: "music.beat", qos: .utility)

    // beat tracking, touched only on `queue`
    private var recent: [Double] = []
    private var lastBeat = Date.distantPast

    private(set) var isRunning = false

    func start() {
        guard !isRunning else { return }
        isRunning = true
        Task { await begin() }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        let s = stream
        stream = nil
        Task { try? await s?.stopCapture() }
    }

    private func begin() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else { throw NSError(domain: "music", code: 1) }
            let config = SCStreamConfiguration()
            config.capturesAudio = true
            config.excludesCurrentProcessAudio = true       // never react to her own sounds
            config.sampleRate = 44_100
            config.channelCount = 1
            config.width = 2
            config.height = 2
            config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let s = SCStream(filter: filter, configuration: config, delegate: self)
            try s.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
            try await s.startCapture()
            if isRunning { stream = s } else { try? await s.stopCapture() }
        } catch {
            isRunning = false
            DispatchQueue.main.async { [weak self] in
                self?.onFailure?("couldn't listen to your music: allow Cariberry in System Settings ▸ Privacy ▸ Screen & System Audio Recording")
            }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        isRunning = false
    }

    // MARK: Beat detection

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, let energy = Self.loudness(of: sampleBuffer) else { return }
        // compare this instant to the last second or so: a beat is a sudden jump above it
        recent.append(energy)
        if recent.count > 48 { recent.removeFirst() }
        guard recent.count >= 24 else { return }
        let avg = recent.reduce(0, +) / Double(recent.count)
        let now = Date()
        if avg > 0.004, energy > avg * 1.45 + 0.004, now.timeIntervalSince(lastBeat) > 0.27 {
            lastBeat = now
            let strength = min(1, (energy - avg) / max(avg, 0.01))
            DispatchQueue.main.async { [weak self] in self?.onBeat?(strength) }
        }
    }

    /// Root-mean-square loudness of one audio buffer, or nil if it can't be read.
    private static func loudness(of buffer: CMSampleBuffer) -> Double? {
        guard let block = CMSampleBufferGetDataBuffer(buffer) else { return nil }
        let length = CMBlockBufferGetDataLength(block)
        guard length >= 4 else { return nil }
        var data = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
        let status = data.withUnsafeMutableBytes { raw in
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: raw.baseAddress!)
        }
        guard status == kCMBlockBufferNoErr, !data.isEmpty else { return nil }
        var sum: Float = 0
        for v in data { sum += v * v }
        return Double((sum / Float(data.count)).squareRoot())
    }
}
