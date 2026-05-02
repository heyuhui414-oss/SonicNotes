//
//  RecordingItem.swift
//  SonicNotes
//
//  Created by 何宇晖 on 2026/5/2.
//

import Foundation
import AVFoundation

struct RecordingItem: Identifiable, Hashable {
    let url: URL
    let name: String
    let createdAt: Date
    let duration: TimeInterval
    let fileSize: Int64
    let fileType: String
    let channelCount: Int
    let sampleRate: Double

    var id: URL { url }

    nonisolated static func from(url: URL) -> RecordingItem {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let createdAt = attributes?[.creationDate] as? Date ?? Date()
        let fileSize = attributes?[.size] as? Int64 ?? 0

        let metadata = readAudioMetadata(from: url)

        return RecordingItem(
            url: url,
            name: url.deletingPathExtension().lastPathComponent,
            createdAt: createdAt,
            duration: metadata.duration,
            fileSize: fileSize,
            fileType: url.pathExtension.uppercased(),
            channelCount: metadata.channelCount,
            sampleRate: metadata.sampleRate
        )
    }

    var displayDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var displaySize: String {
        let mb = Double(fileSize) / 1024.0 / 1024.0
        return String(format: "%.1f MB", mb)
    }

    var displayFileStamp: String {
        name
    }

    var displaySampleRate: String {
        if sampleRate >= 1000 {
            let khz = sampleRate / 1000
            if abs(khz.rounded() - khz) < 0.05 {
                return String(format: "%.0f kHz", khz)
            }
            return String(format: "%.1f kHz", khz)
        }
        return String(format: "%.0f Hz", sampleRate)
    }

    var channelLabel: String {
        channelCount > 1 ? "STEREO" : "MONO"
    }

    nonisolated private static func readAudioMetadata(from url: URL) -> (duration: TimeInterval, channelCount: Int, sampleRate: Double) {
        guard let audioFile = try? AVAudioFile(forReading: url) else {
            return (0, 1, 0)
        }

        let sampleRate = audioFile.processingFormat.sampleRate
        let duration = sampleRate > 0
            ? Double(audioFile.length) / sampleRate
            : 0

        return (duration, Int(audioFile.processingFormat.channelCount), sampleRate)
    }
}
