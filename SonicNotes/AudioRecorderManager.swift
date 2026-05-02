//
//  AudioRecorderManager.swift
//  SonicNotes
//
//  Created by 何宇晖 on 2026/5/2.
//

import Foundation
import AVFoundation
import Combine
import SwiftUI

struct AudioInputOption: Identifiable, Hashable {
    let id: String
    let name: String
    let portType: AVAudioSession.Port

    var subtitle: String {
        switch portType {
        case .bluetoothHFP, .bluetoothA2DP, .bluetoothLE:
            return "Bluetooth"
        case .builtInMic:
            return "Built-in Microphone"
        case .headsetMic:
            return "Headset Microphone"
        case .usbAudio:
            return "USB Audio"
        default:
            return "Audio Input"
        }
    }
}

enum RecordingFormat: String, CaseIterable, Identifiable {
    case m4a = "M4A"
    case wav = "WAV"

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .m4a:
            return "m4a"
        case .wav:
            return "wav"
        }
    }

    func description(sampleRate: RecordingSampleRate) -> String {
        switch self {
        case .m4a:
            return "AAC \(sampleRate.label)"
        case .wav:
            return "PCM \(sampleRate.label)"
        }
    }
}

enum RecordingSampleRate: String, CaseIterable, Identifiable {
    case hz96k = "96kHz"
    case hz48k = "48kHz"
    case hz44_1k = "44.1kHz"

    var id: String { rawValue }

    var label: String { rawValue }

    var value: Double {
        switch self {
        case .hz96k:
            return 96_000
        case .hz48k:
            return 48_000
        case .hz44_1k:
            return 44_100
        }
    }

    var shortFileLabel: String {
        switch self {
        case .hz96k:
            return "96kHz"
        case .hz48k:
            return "48kHz"
        case .hz44_1k:
            return "44.1kHz"
        }
    }
}

enum RecordingChannelMode: String, CaseIterable, Identifiable {
    case mono = "Mono"
    case stereo = "Stereo"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .mono:
            return "MONO"
        case .stereo:
            return "STEREO"
        }
    }

    var channelCount: Int {
        switch self {
        case .mono:
            return 1
        case .stereo:
            return 2
        }
    }
}

@MainActor
final class AudioRecorderManager: NSObject, ObservableObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    private static let recordingNameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd HH:mm:ss"
        return formatter
    }()

    @Published var recordings: [RecordingItem] = []

    @Published var selectedFormat: RecordingFormat = .wav
    @Published var selectedSampleRate: RecordingSampleRate = .hz48k
    @Published var selectedChannelMode: RecordingChannelMode = .mono

    @Published var isRecording = false
    @Published var isPlaying = false
    @Published var currentPlayingURL: URL?

    @Published var elapsedTime: TimeInterval = 0
    @Published var playbackProgress: Double = 0

    @Published var inputLevel: Float = 0
    @Published var peakLevel: Float = 0
    @Published var secondaryInputLevel: Float = 0
    @Published var secondaryPeakLevel: Float = 0

    @Published var permissionDenied = false
    @Published var currentFileName: String = "ready"
    @Published var availableInputs: [AudioInputOption] = []
    @Published var selectedInputID: String?

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?

    private var meterTimer: Timer?
    private var playbackTimer: Timer?

    private let folderName = "SonicNotes"
    private let ubiquityContainerIdentifier = "iCloud.com.yuhui.SonicNotes"
    private let fileManager = FileManager.default
    private let localRecordingsFolder: URL
    private var preferredRecordingsFolder: URL

    override init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let localFolder = documents.appendingPathComponent(folderName)
        self.localRecordingsFolder = localFolder
        self.preferredRecordingsFolder = localFolder
        super.init()

        createRecordingFolderIfNeeded(at: localFolder)
        refreshAvailableInputs()
        loadRecordings()
        resolvePreferredRecordingsFolder()
    }

    var recordingsFolder: URL {
        preferredRecordingsFolder
    }

    private func createRecordingFolderIfNeeded(at folder: URL) {
        if !fileManager.fileExists(atPath: folder.path) {
            do {
                try fileManager.createDirectory(
                    at: folder,
                    withIntermediateDirectories: true
                )
            } catch {
                print("Create folder failed:", error.localizedDescription)
            }
        }
    }

    private func resolvePreferredRecordingsFolder() {
        let localFolder = localRecordingsFolder
        let containerIdentifier = ubiquityContainerIdentifier
        let folderName = folderName

        Task.detached(priority: .utility) {
            let fileManager = FileManager.default

            guard let ubiquityContainer = fileManager.url(forUbiquityContainerIdentifier: containerIdentifier) else {
                return
            }

            let iCloudFolder = ubiquityContainer
                .appendingPathComponent("Documents", isDirectory: true)
                .appendingPathComponent(folderName, isDirectory: true)

            do {
                try fileManager.createDirectory(at: iCloudFolder, withIntermediateDirectories: true)
            } catch {
                print("Create iCloud folder failed:", error.localizedDescription)
                return
            }

            guard fileManager.fileExists(atPath: localFolder.path) else {
                await MainActor.run {
                    self.preferredRecordingsFolder = iCloudFolder
                    self.loadRecordings()
                }
                return
            }

            do {
                let localFiles = try fileManager.contentsOfDirectory(
                    at: localFolder,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )

                for fileURL in localFiles {
                    let destinationURL = iCloudFolder.appendingPathComponent(fileURL.lastPathComponent)
                    guard !fileManager.fileExists(atPath: destinationURL.path) else { continue }
                    try fileManager.moveItem(at: fileURL, to: destinationURL)
                }
            } catch {
                print("Move recordings to iCloud failed:", error.localizedDescription)
            }

            await MainActor.run {
                self.preferredRecordingsFolder = iCloudFolder
                self.loadRecordings()
            }
        }
    }

    func requestPermissionIfNeeded(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)

        case .denied:
            permissionDenied = true
            completion(false)

        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    self.permissionDenied = !granted
                    completion(granted)
                }
            }

        case .restricted:
            permissionDenied = true
            completion(false)

        @unknown default:
            permissionDenied = true
            completion(false)
        }
    }

    func refreshAvailableInputs() {
        let session = AVAudioSession.sharedInstance()
        let currentInputID = session.currentRoute.inputs.first?.uid

        availableInputs = (session.availableInputs ?? []).map {
            AudioInputOption(id: $0.uid, name: $0.portName, portType: $0.portType)
        }
        selectedInputID = currentInputID ?? availableInputs.first?.id
    }

    func selectInput(id: String) {
        let session = AVAudioSession.sharedInstance()
        guard let input = session.availableInputs?.first(where: { $0.uid == id }) else { return }

        do {
            try session.setPreferredInput(input)
            selectedInputID = input.uid
            refreshAvailableInputs()
        } catch {
            print("Select input failed:", error.localizedDescription)
        }
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func prewarmRecordingPathIfAuthorized() {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { return }
        guard !isRecording else { return }

        let sampleRate = selectedSampleRate.value

        Task.detached(priority: .utility) {
            let session = AVAudioSession.sharedInstance()

            do {
                try session.setCategory(
                    .playAndRecord,
                    mode: .default,
                    options: [
                        .defaultToSpeaker,
                        .allowBluetoothHFP,
                        .allowBluetoothA2DP
                    ]
                )
                try session.setPreferredSampleRate(sampleRate)
                try session.setActive(false, options: .notifyOthersOnDeactivation)
            } catch {
                print("Prewarm recording path failed:", error.localizedDescription)
            }
        }
    }

    func startRecording() {
        refreshAvailableInputs()
        requestPermissionIfNeeded { [weak self] granted in
            guard let self else { return }
            guard granted else { return }

            Task { @MainActor in
                self.beginRecording()
            }
        }
    }

    private func beginRecording() {
        stopPlayback()
        stopMetering()

        do {
            let session = AVAudioSession.sharedInstance()

            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [
                    .defaultToSpeaker,
                    .allowBluetoothHFP,
                    .allowBluetoothA2DP
                ]
            )

            try session.setPreferredSampleRate(selectedSampleRate.value)
            try session.setActive(true)

            let fileURL = makeNewRecordingURL(format: selectedFormat)

            let settings: [String: Any]

            switch selectedFormat {
            case .m4a:
                settings = [
                    AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                    AVSampleRateKey: selectedSampleRate.value,
                    AVNumberOfChannelsKey: selectedChannelMode.channelCount,
                    AVEncoderAudioQualityKey: AVAudioQuality.max.rawValue,
                    AVEncoderBitRateKey: 256_000
                ]

            case .wav:
                settings = [
                    AVFormatIDKey: Int(kAudioFormatLinearPCM),
                    AVSampleRateKey: selectedSampleRate.value,
                    AVNumberOfChannelsKey: selectedChannelMode.channelCount,
                    AVLinearPCMBitDepthKey: 24,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false
                ]
            }

            let newRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
            newRecorder.delegate = self
            newRecorder.isMeteringEnabled = true
            newRecorder.prepareToRecord()

            guard newRecorder.record() else {
                currentFileName = "ready"
                try? session.setActive(false, options: .notifyOthersOnDeactivation)
                return
            }

            recorder = newRecorder
            isRecording = true
            isPlaying = false
            currentPlayingURL = nil

            elapsedTime = 0
            playbackProgress = 0
            inputLevel = 0
            peakLevel = 0
            secondaryInputLevel = 0
            secondaryPeakLevel = 0

            currentFileName = fileURL.lastPathComponent

            startMetering()

        } catch {
            print("Recording failed:", error.localizedDescription)
        }
    }

    func stopRecording() {
        guard let recorder else { return }
        recorder.stop()
        isRecording = false
        stopMetering()
    }

    private func startMetering() {
        meterTimer?.invalidate()

        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.035, repeats: true) { [weak self] _ in
            guard let self else { return }

            Task { @MainActor in
                guard let recorder = self.recorder else { return }

                recorder.updateMeters()

                self.elapsedTime = recorder.currentTime

                let channelCount = (recorder.settings[AVNumberOfChannelsKey] as? Int) ?? 1
                let secondaryAveragePower = channelCount > 1
                    ? recorder.averagePower(forChannel: 1)
                    : nil
                let secondaryPeakPower = channelCount > 1
                    ? recorder.peakPower(forChannel: 1)
                    : nil

                self.updateMeterLevels(
                    primaryAveragePower: recorder.averagePower(forChannel: 0),
                    primaryPeakPower: recorder.peakPower(forChannel: 0),
                    secondaryAveragePower: secondaryAveragePower,
                    secondaryPeakPower: secondaryPeakPower
                )
            }
        }
    }

    private func stopMetering() {
        meterTimer?.invalidate()
        meterTimer = nil

        inputLevel = 0
        peakLevel = 0
        secondaryInputLevel = 0
        secondaryPeakLevel = 0
        elapsedTime = 0
    }

    private func updateMeterLevels(
        primaryAveragePower: Float,
        primaryPeakPower: Float,
        secondaryAveragePower: Float?,
        secondaryPeakPower: Float?
    ) {
        inputLevel = normalizedPowerLevel(from: primaryAveragePower)
        peakLevel = normalizedPowerLevel(from: primaryPeakPower)

        guard selectedChannelMode == .stereo,
              let secondaryAveragePower,
              let secondaryPeakPower else {
            secondaryInputLevel = 0
            secondaryPeakLevel = 0
            return
        }

        secondaryInputLevel = normalizedPowerLevel(from: secondaryAveragePower)
        secondaryPeakLevel = normalizedPowerLevel(from: secondaryPeakPower)
    }

    private func normalizedPowerLevel(from decibels: Float) -> Float {
        if decibels < -60 {
            return 0
        }

        if decibels >= 0 {
            return 1
        }

        return (decibels + 60) / 60
    }

    private func makeNewRecordingURL(format: RecordingFormat) -> URL {
        let timestamp = Self.recordingNameFormatter.string(from: Date())
        let fileName = "\(timestamp).\(format.fileExtension)"

        return recordingsFolder.appendingPathComponent(fileName)
    }

    func loadRecordings() {
        let folder = recordingsFolder

        Task.detached(priority: .utility) {
            do {
                let urls = try FileManager.default.contentsOfDirectory(
                    at: folder,
                    includingPropertiesForKeys: [
                        .creationDateKey,
                        .fileSizeKey
                    ],
                    options: [.skipsHiddenFiles]
                )

                let loadedRecordings = urls
                    .filter { url in
                        let ext = url.pathExtension.lowercased()
                        return ext == "m4a" || ext == "wav"
                    }
                    .map { RecordingItem.from(url: $0) }
                    .sorted { $0.createdAt > $1.createdAt }

                await MainActor.run {
                    guard self.recordingsFolder == folder else { return }
                    self.recordings = loadedRecordings
                }
            } catch {
                await MainActor.run {
                    guard self.recordingsFolder == folder else { return }
                    self.recordings = []
                }
                print("Load recordings failed:", error.localizedDescription)
            }
        }
    }

    func play(_ item: RecordingItem) {
        if currentPlayingURL == item.url, isPlaying {
            pausePlayback()
            return
        }

        do {
            stopPlayback()

            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)

            let newPlayer = try AVAudioPlayer(contentsOf: item.url)
            newPlayer.delegate = self
            newPlayer.isMeteringEnabled = true
            newPlayer.prepareToPlay()
            newPlayer.play()

            player = newPlayer

            currentPlayingURL = item.url
            currentFileName = item.url.lastPathComponent

            isPlaying = true
            isRecording = false

            startPlaybackTimer()

        } catch {
            print("Playback failed:", error.localizedDescription)
        }
    }

    func pausePlayback() {
        player?.pause()
        isPlaying = false
    }

    func resumePlayback() {
        player?.play()
        isPlaying = true
    }

    func stopPlayback() {
        player?.stop()
        player?.delegate = nil
        player = nil

        currentPlayingURL = nil
        isPlaying = false

        stopPlaybackTimer()
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )

        if !isRecording {
            elapsedTime = 0
            playbackProgress = 0
            currentFileName = "ready"
        }
    }

    func scrub(by seconds: TimeInterval) {
        guard let player else { return }

        let target = max(0, min(player.duration, player.currentTime + seconds))
        player.currentTime = target

        elapsedTime = target
        playbackProgress = player.duration > 0 ? target / player.duration : 0
    }

    private func startPlaybackTimer() {
        playbackTimer?.invalidate()

        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.035, repeats: true) { [weak self] _ in
            guard let self else { return }

            Task { @MainActor in
                guard let player = self.player else { return }

                player.updateMeters()

                self.elapsedTime = player.currentTime
                self.playbackProgress = player.duration > 0
                    ? player.currentTime / player.duration
                    : 0

                let secondaryAveragePower = player.numberOfChannels > 1
                    ? player.averagePower(forChannel: 1)
                    : nil
                let secondaryPeakPower = player.numberOfChannels > 1
                    ? player.peakPower(forChannel: 1)
                    : nil

                self.updateMeterLevels(
                    primaryAveragePower: player.averagePower(forChannel: 0),
                    primaryPeakPower: player.peakPower(forChannel: 0),
                    secondaryAveragePower: secondaryAveragePower,
                    secondaryPeakPower: secondaryPeakPower
                )
            }
        }
    }

    private func stopPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil

        inputLevel = 0
        peakLevel = 0
        secondaryInputLevel = 0
        secondaryPeakLevel = 0
    }

    func delete(_ item: RecordingItem) {
        if currentPlayingURL == item.url {
            stopPlayback()
        }

        do {
            try FileManager.default.removeItem(at: item.url)
            loadRecordings()
        } catch {
            print("Delete failed:", error.localizedDescription)
        }
    }

    private func handleRecordingFailure(_ error: Error?) {
        print("Recording encoding failed:", error?.localizedDescription ?? "Unknown error")

        recorder?.stop()
        recorder?.delegate = nil
        recorder = nil

        isRecording = false
        currentFileName = "ready"
        stopMetering()

        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }

    private func handlePlaybackFailure(_ error: Error?) {
        print("Playback decoding failed:", error?.localizedDescription ?? "Unknown error")
        stopPlayback()
    }
}

extension AudioRecorderManager {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.stopPlayback()
        }
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            if self.recorder === recorder {
                self.recorder?.delegate = nil
                self.recorder = nil
            }

            self.currentFileName = "ready"

            if flag {
                self.loadRecordings()
            }

            try? AVAudioSession.sharedInstance().setActive(
                false,
                options: .notifyOthersOnDeactivation
            )
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            self.handleRecordingFailure(error)
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            self.handlePlaybackFailure(error)
        }
    }
}
