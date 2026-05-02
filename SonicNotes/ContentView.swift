//
//  ContentView.swift
//  SonicNotes
//
//  Created by 何宇晖 on 2026/5/2.
//

import SwiftUI
import AVFoundation
import StoreKit

struct ContentView: View {
    @StateObject private var audio = AudioRecorderManager()

    @State private var selectedForDescriptionEdit: RecordingItem?
    @State private var selectedForTagEdit: RecordingItem?
    @State private var selectedLibraryDetail: RecordingItem?
    @State private var descriptionDraftText = ""
    @State private var isSampleRateDialogPresented = false
    @State private var isChannelModeDialogPresented = false
    @State private var isLibrarySelectionMode = false
    @State private var selectedRecordingURLs: Set<URL> = []
    @State private var isBatchDeleteConfirmationPresented = false
    @State private var librarySortOrder: LibrarySortOrder = .latest
    @State private var isSoundTagStudioPresented = false
    @State private var isSettingsPresented = false
    @State private var librarySearchText = ""
    @FocusState private var isLibrarySearchFocused: Bool
    @State private var customSourceInput = ""
    @State private var soundTagPrimaryType = ""
    @State private var soundTagMood = ""
    @State private var soundTagDescriptorsRaw = ""
    @State private var activeRecordingDraftFileName: String?
    @State private var draftTagSnapshot = DraftTagSnapshot()
    @State private var selectedLibraryTagFilter = "All Tags"
    @AppStorage("customSoundSourceTags") private var customSoundSourceTagsRaw = ""
    @AppStorage("recordingDescriptions") private var recordingDescriptionsRaw = ""
    @AppStorage("recordingSoundProfiles") private var recordingSoundProfilesRaw = ""
    @Environment(\.requestReview) private var requestReview
    @Environment(\.openURL) private var openURL

    private let canvasTop = Color(red: 0.95, green: 0.94, blue: 0.91)
    private let canvasBottom = Color(red: 0.84, green: 0.82, blue: 0.78)
    private let panelFill = Color(red: 0.93, green: 0.92, blue: 0.89)
    private let panelStroke = Color.black.opacity(0.08)
    private let graphite = Color(red: 0.12, green: 0.12, blue: 0.11)
    private let accentRed = Color(red: 0.92, green: 0.19, blue: 0.12)
    private let ringBlue = Color(red: 0.20, green: 0.45, blue: 0.78)
    private let spotifyGreen = Color(red: 0.12, green: 0.73, blue: 0.33)
    private var canStopTransport: Bool { audio.isRecording || audio.isPlaying || audio.currentPlayingURL != nil }
    private var reelWindowAngles: [Double] { [316, 136] }
    private var currentPlayingItem: RecordingItem? {
        guard let currentPlayingURL = audio.currentPlayingURL else { return nil }
        return audio.recordings.first { $0.url == currentPlayingURL }
    }
    private var sortedRecordings: [RecordingItem] {
        switch librarySortOrder {
        case .latest:
            return audio.recordings.sorted { $0.createdAt > $1.createdAt }
        case .oldest:
            return audio.recordings.sorted { $0.createdAt < $1.createdAt }
        case .largest:
            return audio.recordings.sorted { $0.fileSize > $1.fileSize }
        case .smallest:
            return audio.recordings.sorted { $0.fileSize < $1.fileSize }
        }
    }
    private var selectedRecordings: [RecordingItem] {
        sortedRecordings.filter { selectedRecordingURLs.contains($0.url) }
    }
    private var recordingSoundProfiles: [String: RecordingSoundProfile] {
        guard let data = recordingSoundProfilesRaw.data(using: .utf8),
              let profiles = try? JSONDecoder().decode([String: RecordingSoundProfile].self, from: data) else {
            return [:]
        }
        return profiles
    }
    private var recordingDescriptions: [String: String] {
        guard let data = recordingDescriptionsRaw.data(using: .utf8),
              let descriptions = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return descriptions
    }
    private var selectedPrimaryTypes: Set<String> {
        Set(soundTagPrimaryType.split(separator: "|").map(String.init))
            .intersection(Set(soundTypeOptions.map { $0.title }))
    }
    private var selectedMoods: Set<String> {
        Set(soundTagMood.split(separator: "|").map(String.init))
            .intersection(Set(moodTagOptions.map { $0.title }))
    }
    private var sortedSelectedPrimaryTypes: [String] {
        selectedPrimaryTypes.sorted()
    }
    private var sortedSelectedMoods: [String] {
        selectedMoods.sorted()
    }
    private var draftSoundProfile: RecordingSoundProfile? {
        let descriptors = soundDescriptorOptions
            .filter { selectedDescriptorIDs.contains($0.id) }
            .map { $0.title }

        guard !selectedPrimaryTypes.isEmpty || !selectedMoods.isEmpty || !descriptors.isEmpty else {
            return nil
        }

        return RecordingSoundProfile(
            primaryType: sortedSelectedPrimaryTypes.joined(separator: " | "),
            mood: sortedSelectedMoods.joined(separator: " | "),
            descriptors: descriptors
        )
    }
    private var availableLibraryTagFilters: [String] {
        ["All Tags"] + Array(Set(audio.recordings.flatMap { tags(for: $0) })).sorted()
    }
    private var hasActiveLibraryFilters: Bool {
        !librarySearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || selectedLibraryTagFilter != "All Tags"
    }
    private var activeLibraryFilterCount: Int {
        var count = 0
        if !librarySearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { count += 1 }
        if selectedLibraryTagFilter != "All Tags" { count += 1 }
        return count
    }
    private var filteredSortedRecordings: [RecordingItem] {
        sortedRecordings.filter { item in
            let profile = profile(for: item)
            let typeLabels = primaryTypes(for: item)
            let moodLabels = moods(for: item)
            let descriptorLabels = profile?.descriptors ?? []
            let note = description(for: item)
            let allTags = typeLabels + moodLabels + descriptorLabels

            let matchesTag = selectedLibraryTagFilter == "All Tags"
                || allTags.contains(selectedLibraryTagFilter)

            let searchTarget = [
                item.name,
                item.displayFileStamp,
                item.fileType,
                note
            ] + allTags

            let matchesSearch = librarySearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || searchTarget.joined(separator: " ").localizedCaseInsensitiveContains(librarySearchText)

            return matchesTag && matchesSearch
        }
    }
    private var selectedDescriptorIDs: Set<String> {
        Set(soundTagDescriptorsRaw.split(separator: "|").map(String.init))
            .intersection(Set(soundDescriptorOptions.map { $0.id }))
    }
    private var activeSoundTagSummary: [String] {
        sortedSelectedPrimaryTypes + sortedSelectedMoods + soundTagPreviewDescriptors
    }
    private var soundTagPreviewDescriptors: [String] {
        soundDescriptorOptions
            .filter { selectedDescriptorIDs.contains($0.id) }
            .prefix(2)
            .map { $0.title }
    }
    private var soundTypeOptions: [SoundTagOption] {
        builtInSoundTypeOptions + customSoundTypeOptions
    }
    private var builtInSoundTypeOptions: [SoundTagOption] {
        [
            SoundTagOption(id: "solo_voice", title: "Solo Voice", subtitle: "Breath, phrasing, one clear presence", symbol: "mic.fill", color: Color(red: 0.43, green: 0.24, blue: 0.18)),
            SoundTagOption(id: "choir", title: "Choir", subtitle: "Layered voices, room bloom, shared air", symbol: "person.2.fill", color: Color(red: 0.30, green: 0.33, blue: 0.48)),
            SoundTagOption(id: "guitar", title: "Guitar", subtitle: "Wood, strings, fingers, soft noise", symbol: "guitars.fill", color: Color(red: 0.35, green: 0.27, blue: 0.16)),
            SoundTagOption(id: "piano", title: "Piano", subtitle: "Hammer felt, sustain, open decay", symbol: "pianokeys", color: Color(red: 0.19, green: 0.26, blue: 0.40)),
            SoundTagOption(id: "strings", title: "Strings", subtitle: "Bowed tension, warmth, long motion", symbol: "music.note.list", color: Color(red: 0.22, green: 0.36, blue: 0.29)),
            SoundTagOption(id: "percussion", title: "Percussion", subtitle: "Strike, tap, pulse, moving rhythm", symbol: "metronome.fill", color: Color(red: 0.45, green: 0.30, blue: 0.14)),
            SoundTagOption(id: "nature", title: "Nature", subtitle: "Leaves, wind, water, distant space", symbol: "leaf.fill", color: Color(red: 0.19, green: 0.43, blue: 0.27)),
            SoundTagOption(id: "animals", title: "Animals", subtitle: "Wings, paws, calls, wild movement", symbol: "pawprint.fill", color: Color(red: 0.42, green: 0.29, blue: 0.17)),
            SoundTagOption(id: "street", title: "Street", subtitle: "Footsteps, brakes, night crossings", symbol: "road.lanes", color: Color(red: 0.24, green: 0.31, blue: 0.35)),
            SoundTagOption(id: "room_tone", title: "Room Tone", subtitle: "Air, hum, stillness, hidden texture", symbol: "sofa.fill", color: Color(red: 0.33, green: 0.26, blue: 0.18)),
            SoundTagOption(id: "rain", title: "Rain", subtitle: "Drops, roof wash, soft grey motion", symbol: "cloud.rain.fill", color: Color(red: 0.20, green: 0.32, blue: 0.46)),
            SoundTagOption(id: "crowd", title: "Crowd", subtitle: "Bodies, chatter, shared human blur", symbol: "person.3.fill", color: Color(red: 0.36, green: 0.24, blue: 0.33))
        ]
    }
    private var customSoundSourceTags: [String] {
        Array(Set(customSoundSourceTagsRaw
            .split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }))
            .sorted()
    }
    private var customSoundTypeOptions: [SoundTagOption] {
        customSoundSourceTags.map { tag in
            SoundTagOption(
                id: "custom_\(tag.lowercased().replacingOccurrences(of: " ", with: "_"))",
                title: tag,
                subtitle: "",
                symbol: "tag.fill",
                color: Color(red: 0.28, green: 0.28, blue: 0.30)
            )
        }
    }
    private var tagPromptOptions: [SoundTagOption] {
        builtInSoundTypeOptions.filter { option in
            ["Solo Voice", "Guitar", "Nature", "Street"].contains(option.title)
        }
    }
    private var moodTagOptions: [MoodOption] {
        [
            MoodOption(id: "warm", title: "Warm", symbol: "sun.max.fill"),
            MoodOption(id: "dreamy", title: "Dreamy", symbol: "sparkles"),
            MoodOption(id: "raw", title: "Raw", symbol: "flame.fill"),
            MoodOption(id: "calm", title: "Calm", symbol: "water.waves"),
            MoodOption(id: "tense", title: "Tense", symbol: "bolt.fill"),
            MoodOption(id: "playful", title: "Playful", symbol: "face.smiling"),
            MoodOption(id: "nocturnal", title: "Nocturnal", symbol: "moon.stars.fill"),
            MoodOption(id: "fragile", title: "Fragile", symbol: "drop"),
            MoodOption(id: "melancholic", title: "Melancholic", symbol: "cloud.drizzle.fill")
        ]
    }
    private var soundDescriptorOptions: [DescriptorOption] {
        [
            DescriptorOption(id: "airy", title: "Airy", symbol: "wind"),
            DescriptorOption(id: "intimate", title: "Intimate", symbol: "ear.fill"),
            DescriptorOption(id: "grainy", title: "Grainy", symbol: "aqi.low"),
            DescriptorOption(id: "spacious", title: "Spacious", symbol: "arrow.up.left.and.arrow.down.right"),
            DescriptorOption(id: "organic", title: "Organic", symbol: "leaf.fill"),
            DescriptorOption(id: "pulse", title: "Pulse", symbol: "dot.radiowaves.left.and.right"),
            DescriptorOption(id: "cinematic", title: "Cinematic", symbol: "film.fill"),
            DescriptorOption(id: "lofi", title: "Lo-Fi", symbol: "waveform.path"),
            DescriptorOption(id: "crisp", title: "Crisp", symbol: "sparkles")
        ]
    }
    var body: some View {
        NavigationStack {
            ZStack {
                background

                TabView {
                    recorderTab
                        .tabItem {
                            Label("Record", systemImage: "record.circle")
                        }

                    libraryTab
                        .tabItem {
                            Label("Library", systemImage: "folder")
                        }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .alert("Microphone Access Needed", isPresented: $audio.permissionDenied) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Please enable microphone access in Settings to record audio.")
            }
            .sheet(item: $selectedForDescriptionEdit) { item in
                descriptionSheet(item: item)
            }
            .sheet(item: $selectedLibraryDetail) { item in
                recordingDetailSheet(item: item)
            }
            .sheet(isPresented: $isSettingsPresented) {
                settingsSheet
            }
            .fullScreenCover(isPresented: $isSoundTagStudioPresented) {
                soundTagStudio
            }
            .alert("Delete Selected Files?", isPresented: $isBatchDeleteConfirmationPresented) {
                Button("Delete", role: .destructive) {
                    deleteSelectedRecordings()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently remove \(selectedRecordingURLs.count) recording(s).")
            }
            .confirmationDialog(
                "Select Sample Rate",
                isPresented: $isSampleRateDialogPresented,
                titleVisibility: .visible
            ) {
                ForEach(RecordingSampleRate.allCases) { sampleRate in
                    Button(sampleRate.shortFileLabel) {
                        audio.selectedSampleRate = sampleRate
                    }
                }
            }
            .confirmationDialog(
                "Select Channel Mode",
                isPresented: $isChannelModeDialogPresented,
                titleVisibility: .visible
            ) {
                ForEach(RecordingChannelMode.allCases) { mode in
                    Button(mode.label) {
                        audio.selectedChannelMode = mode
                    }
                }
            }
            .onAppear {
                clearSoundTags()
                audio.prewarmRecordingPathIfAuthorized()
            }
            .onChange(of: audio.recordings) { _, _ in
                selectedRecordingURLs = selectedRecordingURLs.intersection(Set(audio.recordings.map(\.url)))
                if audio.recordings.isEmpty {
                    isLibrarySelectionMode = false
                }
            }
            .onChange(of: audio.currentFileName) { _, newValue in
                guard audio.isRecording, newValue != "ready" else { return }
                activeRecordingDraftFileName = newValue
                assignDraftProfile(toFileName: newValue)
            }
            .onChange(of: audio.isRecording) { _, isRecording in
                guard !isRecording, activeRecordingDraftFileName != nil else { return }
                clearSoundTags()
                activeRecordingDraftFileName = nil
            }
        }
    }

    private var recorderTab: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                header
                recorderCard
                recentRecordingsSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
    }

    private var libraryTab: some View {
        ZStack(alignment: .bottom) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    header
                    librarySection
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, currentPlayingItem == nil ? 48 : 186)
            }
            .scrollDismissesKeyboard(.immediately)

            if let currentPlayingItem {
                ZStack(alignment: .bottom) {
                    libraryFooterBrand
                        .padding(.bottom, 6)

                    libraryMiniPlayer(item: currentPlayingItem)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 14)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var libraryFooterBrand: some View {
        VStack(spacing: 4) {
            Text("SonicNotes")
                .font(.system(size: 24, weight: .light, design: .rounded))
                .foregroundStyle(graphite.opacity(0.16))

            Text("FIELD RECORDER")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(2.2)
                .foregroundStyle(graphite.opacity(0.12))
        }
    }

    private var soundTagStudio: some View {
        NavigationStack {
            ZStack {
                soundTagStudioBackground

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        soundTagStudioHero
                        unifiedTagPlaneSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 130)
                }

                VStack {
                    Spacer()
                    soundTagStudioFooter
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        cancelSoundTagEditing()
                    }
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(graphite.opacity(0.88))
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }

    private var soundTagStudioBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.95, blue: 0.92),
                    Color(red: 0.88, green: 0.86, blue: 0.82),
                    Color(red: 0.82, green: 0.80, blue: 0.76)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(spotifyGreen.opacity(0.14))
                .frame(width: 280, height: 280)
                .blur(radius: 90)
                .offset(x: -120, y: -250)

            Circle()
                .fill(Color.black.opacity(0.07))
                .frame(width: 260, height: 260)
                .blur(radius: 100)
                .offset(x: 150, y: -210)
        }
    }

    private var soundTagStudioHero: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Shape the Sound")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(graphite)

            Text("Pick the scene, the feeling, and the texture.")
                .font(.system(size: 13, weight: .medium, design: .default))
                .foregroundStyle(graphite.opacity(0.58))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var unifiedTagPlaneSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Text("\(activeSoundTagSummary.count)")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(graphite)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.68)))

                Text(activeSoundTagSummary.isEmpty ? "No tags selected" : "Selected tags")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(graphite.opacity(0.58))
            }

            VStack(alignment: .leading, spacing: 22) {
                unifiedTagGroup(
                    title: "Source",
                    subtitle: "Who or what is in front of the mic"
                ) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 10) {
                        ForEach(soundTypeOptions) { option in
                            let isSelected = selectedPrimaryTypes.contains(option.title)
                            Button {
                                togglePrimaryType(option.title)
                            } label: {
                                VStack(spacing: 10) {
                                    Image(systemName: option.symbol)
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(isSelected ? .white : option.color)

                                    Text(option.title)
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundStyle(isSelected ? .white : graphite)
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2)
                                }
                                .frame(maxWidth: .infinity, minHeight: 84)
                                .background(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .fill(isSelected ? option.color.opacity(0.92) : Color.white.opacity(0.56))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                                .stroke(isSelected ? option.color.opacity(0.96) : Color.black.opacity(0.07), lineWidth: 1)
                                        }
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                unifiedTagGroup(
                    title: "Mood",
                    subtitle: "What the sound feels like"
                ) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 10) {
                        ForEach(moodTagOptions) { mood in
                            let isSelected = selectedMoods.contains(mood.title)
                            Button {
                                toggleMood(mood.title)
                            } label: {
                                VStack(spacing: 10) {
                                    Image(systemName: mood.symbol)
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(isSelected ? .white : graphite.opacity(0.78))

                                    Text(mood.title)
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundStyle(isSelected ? .white : graphite)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity, minHeight: 84)
                                .background(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .fill(isSelected ? graphite : Color.white.opacity(0.56))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                                .stroke(isSelected ? graphite : Color.black.opacity(0.07), lineWidth: 1)
                                        }
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                unifiedTagGroup(
                    title: "Texture",
                    subtitle: "The image, the air, the surface"
                ) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 10) {
                        ForEach(soundDescriptorOptions) { descriptor in
                            let isSelected = selectedDescriptorIDs.contains(descriptor.id)
                            Button {
                                toggleDescriptor(id: descriptor.id)
                            } label: {
                                VStack(spacing: 10) {
                                    Image(systemName: descriptor.symbol)
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(isSelected ? .white : graphite.opacity(0.76))

                                    Text(descriptor.title)
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundStyle(isSelected ? .white : graphite)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity, minHeight: 84)
                                .background(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .fill(isSelected ? graphite.opacity(0.88) : Color.white.opacity(0.56))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                                .stroke(isSelected ? graphite.opacity(0.92) : Color.black.opacity(0.07), lineWidth: 1)
                                        }
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !activeSoundTagSummary.isEmpty {
                    unifiedTagGroup(title: "Selected", subtitle: "A quick view before saving") {
                        FlexibleTagFlow(items: activeSoundTagSummary) { value in
                            Text(value)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 9)
                            .background(Capsule().fill(graphite))
                        }
                    }
                }

                unifiedTagGroup(
                    title: "Custom Source",
                    subtitle: "Add your own reusable source tags"
                ) {
                    HStack(spacing: 10) {
                        TextField("Custom source", text: $customSourceInput)
                            .textInputAutocapitalization(.words)
                            .disableAutocorrection(true)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(graphite)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.white.opacity(0.62))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(Color.black.opacity(0.07), lineWidth: 1)
                                    }
                            )

                        Button {
                            addCustomSourceTag()
                        } label: {
                            Label("Add", systemImage: "plus")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(graphite)
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    if customSoundSourceTags.isEmpty {
                        Text("No custom sources yet")
                            .font(.system(size: 12, weight: .medium, design: .default))
                            .foregroundStyle(graphite.opacity(0.52))
                    } else {
                        FlexibleTagFlow(items: customSoundSourceTags) { tag in
                            HStack(spacing: 6) {
                                Button {
                                    togglePrimaryType(tag)
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: selectedPrimaryTypes.contains(tag) ? "tag.fill" : "tag")
                                            .font(.system(size: 11, weight: .bold))

                                        Text(tag)
                                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    }
                                    .foregroundStyle(selectedPrimaryTypes.contains(tag) ? .white : graphite)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 9)
                                    .background(
                                        Capsule()
                                            .fill(selectedPrimaryTypes.contains(tag) ? graphite : Color.white.opacity(0.56))
                                            .overlay {
                                                Capsule()
                                                    .stroke(selectedPrimaryTypes.contains(tag) ? graphite : Color.black.opacity(0.07), lineWidth: 1)
                                            }
                                    )
                                }
                                .buttonStyle(.plain)

                                Button {
                                    removeCustomSourceTag(tag)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(graphite.opacity(0.54))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.white.opacity(0.58))
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.07), radius: 12, y: 8)
            )
        }
    }

    private var soundTagStudioFooter: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    clearSoundTags()
                } label: {
                    Text("Clear")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(graphite.opacity(0.82))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color.white.opacity(0.78))
                        )
                }
                .buttonStyle(.plain)

                Button {
                    commitSoundTags()
                } label: {
                    Text("Save Labels")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(graphite)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 18)
            .background(
                Rectangle()
                    .fill(Color(red: 0.92, green: 0.90, blue: 0.86).opacity(0.96))
                    .ignoresSafeArea(edges: .bottom)
            )
        }
    }

    private var settingsSheet: some View {
        NavigationStack {
            ZStack {
                background

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        settingsHero
                        monetizationSection
                        inputDeviceSection
                        feedbackSection
                        legalSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        isSettingsPresented = false
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

    private var settingsHero: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Studio Settings")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(graphite)

            Text("Manage recording inputs, prepare premium tools, and keep your field recorder tuned for daily use.")
                .font(.system(size: 14, weight: .medium, design: .default))
                .foregroundStyle(graphite.opacity(0.60))
        }
    }

    private var monetizationSection: some View {
        settingsCard(title: "Premium Tools", subtitle: "Reserved for future paid features") {
            VStack(spacing: 12) {
                premiumPlaceholderRow(
                    title: "AI Sound Tagging",
                    subtitle: "Auto-detect scene, mood, and descriptor suggestions"
                )
                premiumPlaceholderRow(
                    title: "Batch Export Packs",
                    subtitle: "Export stems, alternate formats, and naming presets"
                )
                premiumPlaceholderRow(
                    title: "Pro Library Search",
                    subtitle: "Advanced filtering by tags, mood, and custom collections"
                )
            }
        }
    }

    private var inputDeviceSection: some View {
        settingsCard(title: "Microphone Device", subtitle: "Choose the active recording input, including Bluetooth") {
            if audio.availableInputs.isEmpty {
                Text("No external input detected. Built-in microphone will be used automatically.")
                    .font(.system(size: 13, weight: .medium, design: .default))
                    .foregroundStyle(graphite.opacity(0.58))
            } else {
                VStack(spacing: 10) {
                    ForEach(audio.availableInputs) { input in
                        Button {
                            audio.selectInput(id: input.id)
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(input.name)
                                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                                        .foregroundStyle(graphite)

                                    Text(input.subtitle)
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundStyle(graphite.opacity(0.48))
                                }

                                Spacer()

                                Image(systemName: audio.selectedInputID == input.id ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(audio.selectedInputID == input.id ? spotifyGreen : graphite.opacity(0.24))
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color.white.opacity(0.56))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .stroke(
                                                audio.selectedInputID == input.id
                                                    ? spotifyGreen.opacity(0.34)
                                                    : Color.black.opacity(0.05),
                                                lineWidth: 1
                                            )
                                    }
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var feedbackSection: some View {
        settingsCard(title: "Feedback & Sharing", subtitle: "Help the app grow") {
            VStack(spacing: 10) {
                settingsActionRow(title: "Rate SonicNotes", subtitle: "Leave a quick rating in the App Store") {
                    requestReview()
                }
                ShareLink(item: "SonicNotes - a focused field recorder for capturing ideas, textures, and musical moments.") {
                    settingsActionRowLabel(title: "Share App", subtitle: "Send SonicNotes to a collaborator or friend")
                }
                Button {
                    if let emailURL = URL(string: "mailto:hello@sonicnotes.app?subject=SonicNotes%20Feedback") {
                        openURL(emailURL)
                    }
                } label: {
                    settingsActionRowLabel(title: "Contact Us", subtitle: "Questions, bugs, or feature ideas")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var legalSection: some View {
        settingsCard(title: "Terms & Privacy", subtitle: "Policy placeholders for upcoming release") {
            VStack(spacing: 10) {
                settingsStaticRow(
                    title: "Privacy Policy",
                    subtitle: "Collection, storage, and iCloud sync details will appear here"
                )
                settingsStaticRow(
                    title: "Terms of Use",
                    subtitle: "Subscription and usage terms placeholder"
                )
            }
        }
    }

    private func settingsCard<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(graphite)

                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .foregroundStyle(graphite.opacity(0.56))
            }

            content()
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.38))
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(panelStroke, lineWidth: 1)
                }
        )
    }

    private func premiumPlaceholderRow(title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(spotifyGreen.opacity(0.18))
                .frame(width: 38, height: 38)
                .overlay {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(spotifyGreen)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(graphite)

                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .foregroundStyle(graphite.opacity(0.52))
            }

            Spacer()

            Text("SOON")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundStyle(graphite.opacity(0.42))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.50))
        )
    }

    private func settingsActionRow(title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            settingsActionRowLabel(title: title, subtitle: subtitle)
        }
        .buttonStyle(.plain)
    }

    private func settingsActionRowLabel(title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(graphite)

                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .foregroundStyle(graphite.opacity(0.52))
            }

            Spacer()

            Image(systemName: "arrow.up.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(graphite.opacity(0.28))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.50))
        )
    }

    private func settingsStaticRow(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(graphite)

            Text(subtitle)
                .font(.system(size: 12, weight: .medium, design: .default))
                .foregroundStyle(graphite.opacity(0.52))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.50))
        )
    }

    private func unifiedTagGroup<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(graphite)

                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .foregroundStyle(graphite.opacity(0.58))
            }

            content()
        }
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [canvasTop, canvasBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color.white.opacity(0.45))
                .frame(width: 260, height: 260)
                .blur(radius: 36)
                .offset(x: -110, y: -250)

            Circle()
                .fill(Color.black.opacity(0.06))
                .frame(width: 320, height: 320)
                .blur(radius: 60)
                .offset(x: 150, y: 320)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("SonicNotes")
                    .font(.system(size: 34, weight: .light, design: .rounded))
                    .foregroundStyle(graphite)

                Text("FIELD RECORDER")
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .tracking(4)
                    .foregroundStyle(graphite.opacity(0.65))
            }

            Spacer()

            Button {
                audio.refreshAvailableInputs()
                isSettingsPresented = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(graphite.opacity(0.82))
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.44))
                            .overlay {
                                Circle()
                                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
                            }
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
    }

    private var recorderCard: some View {
        VStack(spacing: 16) {
            recorderTopRow
            reelSection
            quickTagStrip
            transportControls
            formatSection
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(panelFill)
                .overlay {
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .stroke(panelStroke, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.14), radius: 24, x: 0, y: 18)
        )
    }

    private var recorderTopRow: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(audio.isRecording ? "Recording" : audio.isPlaying ? "Playback" : "Ready")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(graphite)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(audio.isRecording || audio.isPlaying || audio.currentPlayingURL != nil ? audio.currentFileName : "Begin")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(graphite.opacity(0.48))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .topLeading)

            VStack(alignment: .trailing, spacing: 8) {
                Text(timeString(audio.elapsedTime))
                    .font(.system(size: 24, weight: .semibold, design: .monospaced))
                    .foregroundStyle(graphite)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                Text(audio.selectedFormat.description(sampleRate: audio.selectedSampleRate))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(graphite.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .topTrailing)
        }
    }

    private var reelSection: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.42),
                            Color.black.opacity(0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.34), lineWidth: 1)
                }
                .shadow(color: .white.opacity(0.28), radius: 12, x: -4, y: -4)

            VStack {
                ZStack {
                    HStack {
                        recordStatusChip
                        Spacer()
                        statusIndicatorLamp
                    }

                    reelWaveSignature
                }

                Spacer()

                HStack(alignment: .bottom) {
                    Button {
                        isSampleRateDialogPresented = true
                    } label: {
                        HStack(spacing: 4) {
                            Text(audio.selectedSampleRate.shortFileLabel)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))

                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 7, weight: .bold))
                        }
                        .foregroundStyle(graphite.opacity(audio.isRecording ? 0.35 : 0.62))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(audio.isRecording ? 0.18 : 0.32))
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.black.opacity(audio.isRecording ? 0.05 : 0.12), lineWidth: 1)
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(audio.isRecording)

                    Spacer()

                    channelModePickerButton
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            channelLevelMeters

            TimelineView(.animation) { timeline in
                let active = audio.isRecording || audio.isPlaying
                let speed: Double = audio.isRecording ? 88 : audio.isPlaying ? 128 : 0
                let rotation = active
                    ? timeline.date.timeIntervalSinceReferenceDate * speed
                    : 0

                ZStack {
                    reelSurface
                    reelCutouts
                    reelHub
                }
                .frame(width: 214, height: 214)
                .rotationEffect(.degrees(rotation))
            }

            reelStatusOverlay
        }
        .frame(maxWidth: .infinity)
        .frame(height: 286)
        .padding(.vertical, 2)
    }

    private var recordStatusChip: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(audio.isRecording ? accentRed : audio.isPlaying ? spotifyGreen : graphite.opacity(0.28))
                .frame(width: 7, height: 7)

            Text(audio.isRecording ? "RECORDING" : audio.isPlaying ? "PLAYBACK" : "STANDBY")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(graphite.opacity(0.66))
        }
        .padding(.horizontal, 2)
    }

    private var quickTagStrip: some View {
        Button {
            isSoundTagStudioPresented = true
        } label: {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(graphite.opacity(0.62))

                    Text("SOUND TAGS")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(graphite.opacity(0.62))
                }

                if activeSoundTagSummary.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(tagPromptOptions) { option in
                                Image(systemName: option.symbol)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(graphite.opacity(0.44))
                                    .frame(width: 18, height: 18)
                            }
                        }
                    }
                    .scrollDisabled(true)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(activeSoundTagSummary.prefix(4)), id: \.self) { value in
                                Label(value, systemImage: symbol(forTag: value))
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(graphite)
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule()
                                            .fill(Color.white.opacity(0.56))
                                            .overlay {
                                                Capsule()
                                                    .stroke(Color.black.opacity(0.07), lineWidth: 1)
                                            }
                                    )
                            }
                        }
                    }
                    .scrollDisabled(true)
                }

                Spacer(minLength: 6)

                if !activeSoundTagSummary.isEmpty {
                    Text("\(activeSoundTagSummary.count)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(graphite.opacity(0.58))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.54))
                                .overlay {
                                    Capsule()
                                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                                }
                        )
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(graphite.opacity(0.42))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }

    private var reelWaveSignature: some View {
        Image(systemName: "waveform.path.ecg")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(graphite.opacity(0.28))
            .shadow(color: .white.opacity(0.16), radius: 2, y: -1)
    }

    private var statusIndicatorLamp: some View {
        Circle()
            .fill(statusIndicatorColor)
            .frame(width: 12, height: 12)
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.45), lineWidth: 1)
            }
            .shadow(
                color: statusIndicatorColor.opacity(audio.isRecording || audio.isPlaying ? 0.48 : 0),
                radius: 8
            )
    }

    private var reelSurface: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.16))
                .frame(width: 214, height: 214)
                .blur(radius: 8)
                .offset(y: 8)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.95, green: 0.94, blue: 0.92),
                            Color(red: 0.83, green: 0.82, blue: 0.79),
                            Color(red: 0.70, green: 0.69, blue: 0.66)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 208, height: 208)
                .shadow(color: .black.opacity(0.16), radius: 10, x: 0, y: 8)

            Circle()
                .stroke(Color.black.opacity(0.32), lineWidth: 1.2)
                .frame(width: 208, height: 208)

            Circle()
                .stroke(Color.white.opacity(0.85), lineWidth: 1.4)
                .frame(width: 202, height: 202)

            Circle()
                .stroke(Color.black.opacity(0.12), lineWidth: 1)
                .frame(width: 198, height: 198)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.34),
                            .clear
                        ],
                        center: .topLeading,
                        startRadius: 8,
                        endRadius: 124
                    )
                )
                .frame(width: 206, height: 206)
                .blendMode(.screen)

            reelGrooveRings
        }
    }

    private var reelGrooveRings: some View {
        ZStack {
            ForEach(0..<22, id: \.self) { ring in
                grooveRing(ring)
            }
        }
    }

    private func grooveRing(_ ring: Int) -> some View {
        let diameter = 52.0 + (Double(ring) * 6.5)
        let opacity = ring == 0 ? 0.06 : 0.013

        return Circle()
            .stroke(Color.black.opacity(opacity), lineWidth: 0.55)
            .frame(width: diameter, height: diameter)
    }

    private var reelCutouts: some View {
        ZStack {
            ForEach(reelWindowAngles, id: \.self) { angle in
                ZStack {
                    ReelWindowShape(startAngle: .degrees(angle), sweep: .degrees(56))
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.black,
                                    Color(red: 0.10, green: 0.10, blue: 0.10),
                                    Color.black.opacity(0.95)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay {
                            ReelWindowShape(startAngle: .degrees(angle), sweep: .degrees(56))
                                .stroke(Color.white.opacity(0.07), lineWidth: 0.8)
                        }

                    ReelWindowShape(startAngle: .degrees(angle), sweep: .degrees(56))
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.white.opacity(0.05),
                                    .clear
                                ],
                                center: .center,
                                startRadius: 8,
                                endRadius: 90
                            )
                        )

                    ReelWindowShape(startAngle: .degrees(angle), sweep: .degrees(56))
                        .stroke(Color.black.opacity(0.24), lineWidth: 1.1)
                }
                .frame(width: 168, height: 168)
            }
        }
        .overlay {
            ZStack {
                ForEach(0..<18, id: \.self) { groove in
                    Circle()
                        .stroke(Color.white.opacity(groove < 2 ? 0.08 : 0.035), lineWidth: 0.9)
                        .frame(
                            width: CGFloat(74 + groove * 6),
                            height: CGFloat(74 + groove * 6)
                        )
                }
            }
            .mask {
                ZStack {
                    ForEach(reelWindowAngles, id: \.self) { angle in
                        ReelWindowShape(startAngle: .degrees(angle), sweep: .degrees(56))
                            .frame(width: 168, height: 168)
                    }
                }
            }
            .blendMode(.screen)
            .opacity(0.65)
        }
    }

    private var reelHub: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.26))
                .frame(width: 78, height: 78)
                .blur(radius: 4)
                .offset(y: 6)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.95, green: 0.94, blue: 0.92),
                            Color(red: 0.80, green: 0.79, blue: 0.76),
                            Color(red: 0.66, green: 0.65, blue: 0.62)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 72, height: 72)
                .shadow(color: .black.opacity(0.16), radius: 8, x: 0, y: 6)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.32),
                            .clear
                        ],
                        center: .topLeading,
                        startRadius: 4,
                        endRadius: 42
                    )
                )
                .frame(width: 68, height: 68)

            Circle()
                .stroke(Color.black.opacity(0.18), lineWidth: 1)
                .frame(width: 72, height: 72)

            Circle()
                .stroke(Color.white.opacity(0.86), lineWidth: 1.6)
                .frame(width: 66, height: 66)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.78, green: 0.77, blue: 0.74),
                            Color(red: 0.62, green: 0.61, blue: 0.58)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 20, height: 20)
                .overlay {
                    Circle()
                        .stroke(Color.black.opacity(0.34), lineWidth: 1.8)
                }
        }
    }

    private var channelModePickerButton: some View {
        Button {
            isChannelModeDialogPresented = true
        } label: {
            HStack(spacing: 4) {
                Text(audio.selectedChannelMode.label)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 7, weight: .bold))
            }
            .foregroundStyle(graphite.opacity(audio.isRecording ? 0.35 : 0.62))
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(audio.isRecording ? 0.18 : 0.32))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.black.opacity(audio.isRecording ? 0.05 : 0.12), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(audio.isRecording)
    }

    private var reelStatusOverlay: some View {
        ZStack {
            if audio.isPlaying || audio.currentPlayingURL != nil {
                Circle()
                    .trim(from: 0, to: max(0.02, audio.playbackProgress))
                    .stroke(
                        ringBlue.opacity(0.9),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 216, height: 216)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.12), value: audio.playbackProgress)
            }
        }
    }

    private var statusIndicatorColor: Color {
        if audio.isRecording {
            return accentRed
        }
        if audio.isPlaying {
            return Color(red: 0.29, green: 0.67, blue: 0.34)
        }
        return graphite.opacity(0.22)
    }

    private var channelLevelMeters: some View {
        HStack {
            if audio.selectedChannelMode == .stereo {
                meterCluster(
                    label: "L",
                    segments: meterSegments(for: audio.isRecording ? audio.peakLevel : (audio.isPlaying ? audio.inputLevel : 0))
                )
                .padding(.leading, 14)

                Spacer()

                meterCluster(
                    label: "R",
                    segments: meterSegments(for: audio.isRecording ? audio.secondaryPeakLevel : (audio.isPlaying ? audio.secondaryInputLevel : 0))
                )
                .padding(.trailing, 14)
            } else {
                Spacer()
                levelMeterColumn(
                    segments: meterSegments(for: audio.isRecording ? audio.peakLevel : (audio.isPlaying ? audio.inputLevel : 0))
                )
                .padding(.trailing, 12)
            }
        }
        .padding(.horizontal, 2)
    }

    private enum MeterSegmentState {
        case inactive
        case reference
        case active
    }

    private func levelMeterColumn(segments: [MeterSegmentState]) -> some View {
        VStack(spacing: 8) {
            ForEach(Array(segments.enumerated()), id: \.offset) { index, state in
                Capsule()
                    .fill(meterSegmentColor(for: index, state: state))
                    .frame(width: 14, height: 3)
                    .shadow(
                        color: state == .active ? meterShadowColor(for: index).opacity(0.34) : .clear,
                        radius: 4
                    )
            }
        }
    }

    private func meterCluster(label: String, segments: [MeterSegmentState]) -> some View {
        VStack(spacing: 8) {
            levelMeterColumn(segments: segments)

            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(graphite.opacity(0.50))
        }
    }

    private func meterSegments(for level: Float) -> [MeterSegmentState] {
        guard level > 0.02 else {
            return Array(repeating: .inactive, count: 9)
        }

        let litCount = min(9, max(1, Int(ceil(level * 9))))
        return (0..<9).map { index in
            if index >= 9 - litCount {
                return .active
            }
            if index == 4, litCount < 5 {
                return .reference
            }
            return .inactive
        }
    }

    private func meterSegmentColor(for index: Int, state: MeterSegmentState) -> Color {
        switch state {
        case .active:
            return meterActiveColor(for: index)
        case .reference:
            return graphite.opacity(0.65)
        case .inactive:
            if index == 4 {
                return graphite.opacity(0.52)
            }
            return graphite.opacity(0.32)
        }
    }

    private func meterActiveColor(for index: Int) -> Color {
        let levelIndexFromBottom = 9 - index
        if levelIndexFromBottom == 9 {
            return accentRed
        }
        if levelIndexFromBottom >= 6 {
            return Color(red: 0.86, green: 0.67, blue: 0.18)
        }
        return Color(red: 0.28, green: 0.64, blue: 0.32)
    }

    private func meterShadowColor(for index: Int) -> Color {
        meterActiveColor(for: index)
    }

    private var statusSection: some View {
        HStack {
            Text("INPUT")
            Spacer()
            Text(audio.isRecording ? "LIVE MONITOR" : audio.isPlaying ? "PLAYBACK" : "STANDBY")
        }
        .font(.system(size: 10, weight: .bold, design: .monospaced))
        .tracking(1.4)
        .foregroundStyle(graphite.opacity(0.44))
        .padding(.top, 2)
    }

    private var transportControls: some View {
        HStack(spacing: 18) {
            smallTransportButton(
                icon: audio.isPlaying ? "pause.fill" : "play.fill",
                isActive: audio.isPlaying
            ) {
                if audio.isPlaying {
                    audio.pausePlayback()
                } else if audio.currentPlayingURL != nil {
                    audio.resumePlayback()
                } else if let first = audio.recordings.first {
                    audio.play(first)
                }
            }

            Button {
                audio.toggleRecording()
            } label: {
                ZStack {
                    Circle()
                        .fill(audio.isRecording ? accentRed : graphite)
                        .frame(width: 84, height: 84)
                        .shadow(color: .black.opacity(0.18), radius: 14, x: 0, y: 10)

                    if audio.isRecording {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.white)
                            .frame(width: 28, height: 28)
                    } else {
                        Circle()
                            .fill(accentRed)
                            .frame(width: 34, height: 34)
                            .overlay {
                                Circle()
                                    .stroke(.white.opacity(0.2), lineWidth: 1)
                            }
                    }
                }
            }
            .buttonStyle(.plain)
            .scaleEffect(audio.isRecording ? 1.0 : 0.98)
            .animation(.spring(response: 0.24, dampingFraction: 0.7), value: audio.isRecording)

            smallTransportButton(
                icon: "stop.fill",
                isActive: canStopTransport
            ) {
                if audio.isRecording {
                    audio.stopRecording()
                } else {
                    audio.stopPlayback()
                }
            }
        }
        .padding(.top, 1)
    }

    private var formatSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                ForEach(RecordingFormat.allCases) { format in
                    Button {
                        audio.selectedFormat = format
                    } label: {
                        Text(format.rawValue)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .tracking(0.8)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(audio.selectedFormat == format ? graphite : Color.clear)
                            )
                            .foregroundStyle(audio.selectedFormat == format ? Color.white : graphite.opacity(0.76))
                            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .disabled(audio.isRecording)
                }
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.58))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.black.opacity(0.06), lineWidth: 1)
                    }
            )
            .opacity(audio.isRecording ? 0.7 : 1)

            HStack {
                Text("Saved to Files / SonicNotes")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(graphite.opacity(0.46))

                Spacer()

                Text("\(audio.recordings.count) FILES")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(graphite.opacity(0.56))
            }
        }
    }

    private func smallTransportButton(
        icon: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Circle()
                .fill(isActive ? graphite : Color.white.opacity(0.7))
                .frame(width: 60, height: 60)
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(isActive ? .white : graphite)
                }
                .overlay {
                    Circle()
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .scaleEffect(isActive ? 1.02 : 1.0)
        .animation(.easeOut(duration: 0.16), value: isActive)
    }

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Library")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(graphite)

                Spacer()

                libraryHeaderControls
            }

            if isLibrarySelectionMode, !audio.recordings.isEmpty {
                librarySelectionBar
            }

            libraryDiscoveryControls

            if filteredSortedRecordings.isEmpty {
                emptyState
            } else {
                recordingList
            }
        }
    }

    private var libraryHeaderControls: some View {
        HStack(spacing: 10) {
            Text("\(filteredSortedRecordings.count)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.1)
                .foregroundStyle(graphite.opacity(0.56))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.44))
                        .overlay {
                            Capsule()
                                .stroke(panelStroke, lineWidth: 1)
                        }
                )

            Button(isLibrarySelectionMode ? "Cancel" : "Select") {
                toggleLibrarySelectionMode()
            }
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .tracking(1.2)
            .foregroundStyle(graphite.opacity(0.56))
        }
    }

    private var librarySelectionBar: some View {
        HStack(spacing: 10) {
            Text("\(selectedRecordingURLs.count) SELECTED")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(graphite.opacity(0.58))

            Spacer()

            Button(selectedRecordingURLs.count == filteredSortedRecordings.count ? "Clear All" : "Select All") {
                if selectedRecordingURLs.count == filteredSortedRecordings.count {
                    selectedRecordingURLs.removeAll()
                } else {
                    selectedRecordingURLs = Set(filteredSortedRecordings.map(\.url))
                }
            }
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .tracking(1.1)
            .foregroundStyle(graphite.opacity(0.62))

            if !selectedRecordingURLs.isEmpty {
                ShareLink(items: selectedRecordings.map(\.url)) {
                    selectionActionPill(label: "Share", systemImage: "square.and.arrow.up")
                }

                Button {
                    isBatchDeleteConfirmationPresented = true
                } label: {
                    selectionActionPill(label: "Delete", systemImage: "trash")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.42))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(panelStroke, lineWidth: 1)
                }
        )
    }

    private var libraryDiscoveryControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(graphite.opacity(0.42))

                    TextField("Search filename, notes, or tags", text: $librarySearchText)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($isLibrarySearchFocused)

                    if !librarySearchText.isEmpty {
                        Button {
                            librarySearchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(graphite.opacity(0.26))
                        }
                        .buttonStyle(.plain)
                    }

                    if isLibrarySearchFocused {
                        Button("Done") {
                            isLibrarySearchFocused = false
                        }
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(graphite.opacity(0.56))
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.42))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(panelStroke, lineWidth: 1)
                        }
                )
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Menu {
                        ForEach(LibrarySortOrder.allCases) { order in
                            Button(order.label) {
                                librarySortOrder = order
                            }
                        }
                    } label: {
                        libraryControlPill(
                            title: librarySortOrder.shortLabel,
                            systemImage: "arrow.up.arrow.down",
                            isActive: true
                        )
                    }

                    libraryFilterMenu(
                        title: selectedLibraryTagFilter == "All Tags" ? "Tag" : selectedLibraryTagFilter,
                        systemImage: "tag",
                        options: availableLibraryTagFilters,
                        isActive: selectedLibraryTagFilter != "All Tags"
                    ) { selectedLibraryTagFilter = $0 }

                    if hasActiveLibraryFilters {
                        Button {
                            resetLibraryFilters()
                        } label: {
                            libraryControlPill(
                                title: "Reset",
                                systemImage: "line.3.horizontal.decrease.circle",
                                isActive: false,
                                showChevron: false
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if hasActiveLibraryFilters {
                        Text("\(activeLibraryFilterCount)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(graphite.opacity(0.52))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.46))
                                    .overlay {
                                        Capsule()
                                            .stroke(panelStroke, lineWidth: 1)
                                    }
                            )
                    }
                }
            }
            .scrollDisabled(true)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.30))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(panelStroke, lineWidth: 1)
                }
        )
    }

    private func libraryFilterMenu(
        title: String,
        systemImage: String,
        options: [String],
        isActive: Bool,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button(option) {
                    onSelect(option)
                }
            }
        } label: {
            libraryControlPill(title: title, systemImage: systemImage, isActive: isActive)
        }
    }

    private var recentRecordingsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Recent")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(graphite)

                Spacer()

                Text(audio.recordings.isEmpty ? "EMPTY" : "LATEST 3")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(graphite.opacity(0.44))
            }

            if audio.recordings.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No recordings yet")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(graphite)

                    Text("Your latest takes will appear here for quick review.")
                        .font(.system(size: 12, weight: .medium, design: .default))
                        .foregroundStyle(graphite.opacity(0.52))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.white.opacity(0.32))
                        .overlay {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(panelStroke, lineWidth: 1)
                        }
                )
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(audio.recordings.prefix(3))) { item in
                        recentRecordingRow(item)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(graphite.opacity(0.38))

            Text("No sonic notes yet")
                .font(.headline)
                .foregroundStyle(graphite)

            Text("Record a sound, voice memo, or field texture to start your library.")
                .font(.subheadline)
                .foregroundStyle(graphite.opacity(0.55))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.34))
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(panelStroke, lineWidth: 1)
                }
        )
    }

    private var recordingList: some View {
        LazyVStack(spacing: 12) {
            ForEach(filteredSortedRecordings) { item in
                recordingRow(item)
            }
        }
    }

    private func recordingRow(_ item: RecordingItem) -> some View {
        HStack(spacing: 12) {
            if isLibrarySelectionMode {
                Button {
                    toggleSelection(for: item)
                } label: {
                    ZStack {
                        Circle()
                            .fill(selectedRecordingURLs.contains(item.url) ? graphite : Color.white.opacity(0.68))
                            .frame(width: 28, height: 28)

                        Image(systemName: selectedRecordingURLs.contains(item.url) ? "checkmark" : "circle")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(selectedRecordingURLs.contains(item.url) ? .white : graphite.opacity(0.30))
                    }
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    audio.play(item)
                } label: {
                    Circle()
                        .fill(audio.currentPlayingURL == item.url ? graphite : graphite.opacity(0.88))
                        .frame(width: 44, height: 44)
                        .overlay {
                            Image(systemName: audio.currentPlayingURL == item.url && audio.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                        }
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(item.displayFileStamp)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(graphite)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    tag(text: item.fileType)
                    Text(item.channelLabel)
                    Text("•")
                    Text(item.displaySampleRate)
                    Text("•")
                    Text(item.displayDuration)
                }
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(graphite.opacity(0.5))
                .lineLimit(1)

                recordingPreviewLine(for: item, lineLimit: 1)
            }

            Spacer(minLength: 8)

            if !isLibrarySelectionMode {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(graphite.opacity(0.24))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.36))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(panelStroke, lineWidth: 1)
                }
        )
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture {
            if isLibrarySelectionMode {
                toggleSelection(for: item)
            } else {
                selectedLibraryDetail = item
            }
        }
    }

    private func recentRecordingRow(_ item: RecordingItem) -> some View {
        HStack(spacing: 12) {
            Button {
                audio.play(item)
            } label: {
                Circle()
                    .fill(audio.currentPlayingURL == item.url ? graphite : graphite.opacity(0.88))
                    .frame(width: 42, height: 42)
                    .overlay {
                        Image(systemName: audio.currentPlayingURL == item.url && audio.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 5) {
                Text(item.displayFileStamp)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(graphite)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    tag(text: item.fileType)
                    Text(item.channelLabel)
                    Text("•")
                    Text(item.displaySampleRate)
                    Text("•")
                    Text(item.displayDuration)
                }
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(graphite.opacity(0.48))
                .lineLimit(1)

                recordingPreviewLine(for: item, lineLimit: 1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(graphite.opacity(0.24))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.36))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(panelStroke, lineWidth: 1)
                }
        )
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture {
            selectedLibraryDetail = item
        }
    }

    private func recordingDetailSheet(item: RecordingItem) -> some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    detailSectionCard(title: "OVERVIEW", subtitle: "File information and playback") {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(alignment: .top, spacing: 12) {
                                Button {
                                    audio.play(item)
                                } label: {
                                    Circle()
                                        .fill(graphite)
                                        .frame(width: 54, height: 54)
                                        .overlay {
                                            Image(systemName: audio.currentPlayingURL == item.url && audio.isPlaying ? "pause.fill" : "play.fill")
                                                .font(.system(size: 18, weight: .bold))
                                                .foregroundStyle(.white)
                                        }
                                }
                                .buttonStyle(.plain)

                                VStack(alignment: .leading, spacing: 8) {
                                    Text(item.displayFileStamp)
                                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                                        .foregroundStyle(graphite)
                                        .lineLimit(1)

                                    Text("Default filename · read only")
                                        .font(.system(size: 12, weight: .medium, design: .default))
                                        .foregroundStyle(graphite.opacity(0.46))
                                }

                                Spacer(minLength: 8)

                                ShareLink(item: item.url) {
                                    cardActionIcon("square.and.arrow.up")
                                }
                                .buttonStyle(.plain)
                            }

                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                infoTile(title: "DATE / TIME", value: item.displayFileStamp)
                                infoTile(title: "FORMAT", value: item.fileType)
                                infoTile(title: "CHANNEL", value: item.channelLabel)
                                infoTile(title: "SAMPLE RATE", value: item.displaySampleRate)
                                infoTile(title: "DURATION", value: item.displayDuration)
                                infoTile(title: "SIZE", value: item.displaySize)
                            }
                        }
                    }

                    detailSectionCard(
                        title: "NOTES",
                        subtitle: "A short description for this take",
                        actionTitle: description(for: item).isEmpty ? "Add" : "Edit"
                    ) {
                        descriptionDraftText = description(for: item)
                        selectedForDescriptionEdit = item
                    } content: {
                        descriptionDetailBlock(for: item)
                    }

                    detailSectionCard(
                        title: "TAGS",
                        subtitle: "Source, mood, and texture",
                        actionTitle: "Edit"
                    ) {
                        beginTagEditing(for: item)
                    } content: {
                        if let profile = profile(for: item), !profile.allLabels.isEmpty {
                            tagDetailBlock(labels: profile.allLabels)
                        } else {
                            tagDetailEmptyState
                        }
                    }

                    detailSectionCard(title: "ACTIONS", subtitle: "Manage or export this recording") {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            Button {
                                descriptionDraftText = description(for: item)
                                selectedForDescriptionEdit = item
                            } label: {
                                detailActionButtonLabel("Edit Notes", systemImage: "text.alignleft")
                            }
                            .buttonStyle(.plain)

                            Button {
                                beginTagEditing(for: item)
                            } label: {
                                detailActionButtonLabel("Edit Tags", systemImage: "tag")
                            }
                            .buttonStyle(.plain)

                            ShareLink(item: item.url) {
                                detailActionButtonLabel("Share", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.plain)

                            Button(role: .destructive) {
                                removeProfile(for: item.url.lastPathComponent)
                                removeDescription(for: item.url.lastPathComponent)
                                audio.delete(item)
                                selectedLibraryDetail = nil
                            } label: {
                                detailActionButtonLabel("Delete", systemImage: "trash", isDestructive: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(20)
                .padding(.bottom, 20)
            }
            .background(background)
            .navigationTitle("Recording")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        selectedLibraryDetail = nil
                    }
                }
            }
        }
    }

    private func recordingPreviewLine(for item: RecordingItem, lineLimit: Int) -> some View {
        Group {
            if !description(for: item).isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(graphite.opacity(0.34))

                    Text(description(for: item))
                        .font(.system(size: 12, weight: .medium, design: .default))
                        .foregroundStyle(graphite.opacity(0.62))
                        .lineLimit(lineLimit)
                }
            } else if let profile = profile(for: item), !profile.allLabels.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(profile.allLabels.prefix(3)), id: \.self) { label in
                            subtleTag(text: label)
                        }
                    }
                }
                .scrollDisabled(true)
            }
        }
    }

    private func descriptionDetailBlock(for item: RecordingItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "text.alignleft")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(graphite.opacity(0.34))
                .padding(.top, 2)

            Text(description(for: item).isEmpty ? "No description yet" : description(for: item))
                .font(.system(size: 13, weight: .medium, design: .default))
                .foregroundStyle(description(for: item).isEmpty ? graphite.opacity(0.48) : graphite.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.5))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.black.opacity(0.04), lineWidth: 1)
                }
        )
    }

    private func tagDetailBlock(labels: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "tag")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(graphite.opacity(0.34))

                Text("\(labels.count) selected")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(graphite.opacity(0.46))
            }

            FlexibleTagFlow(items: labels) { label in
                refinedTag(text: label)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.5))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.black.opacity(0.04), lineWidth: 1)
                }
        )
    }

    private func detailSectionCard<Content: View>(
        title: String,
        subtitle: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(1.1)
                        .foregroundStyle(graphite.opacity(0.46))

                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium, design: .default))
                        .foregroundStyle(graphite.opacity(0.56))
                }

                Spacer(minLength: 8)

                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(graphite.opacity(0.62))
                }
            }

            content()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.36))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.black.opacity(0.05), lineWidth: 1)
                }
        )
    }

    private var tagDetailEmptyState: some View {
        HStack(spacing: 10) {
            Image(systemName: "tag")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(graphite.opacity(0.34))

            Text("No tags yet")
                .font(.system(size: 13, weight: .medium, design: .default))
                .foregroundStyle(graphite.opacity(0.48))

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.5))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.black.opacity(0.04), lineWidth: 1)
                }
        )
    }

    private func libraryMiniPlayer(item: RecordingItem) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Circle()
                    .fill(graphite)
                    .frame(width: 42, height: 42)
                    .overlay {
                        Image(systemName: audio.isPlaying ? "waveform" : "pause.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(graphite)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        tag(text: item.fileType)
                        Text(audio.isPlaying ? "PLAYING" : "PAUSED")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(1)
                            .foregroundStyle(graphite.opacity(0.48))
                    }
                }

                Spacer(minLength: 8)

                HStack(spacing: 10) {
                    miniPlayerButton(icon: "gobackward.10") {
                        audio.scrub(by: -10)
                    }

                    miniPlayerButton(icon: audio.isPlaying ? "pause.fill" : "play.fill") {
                        if audio.isPlaying {
                            audio.pausePlayback()
                        } else {
                            audio.resumePlayback()
                        }
                    }

                    miniPlayerButton(icon: "stop.fill") {
                        audio.stopPlayback()
                    }
                }
            }

            VStack(spacing: 6) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(graphite.opacity(0.10))
                            .frame(height: 4)

                        Capsule()
                            .fill(ringBlue.opacity(0.92))
                            .frame(
                                width: max(8, proxy.size.width * max(0.02, audio.playbackProgress)),
                                height: 4
                            )
                    }
                }
                .frame(height: 4)

                HStack {
                    Text(timeString(audio.elapsedTime))
                    Spacer()
                    Text(item.displayDuration)
                }
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(graphite.opacity(0.46))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.94),
                            Color(red: 0.92, green: 0.91, blue: 0.88).opacity(0.96)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.72), lineWidth: 1)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.black.opacity(0.07), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.16), radius: 18, x: 0, y: 10)
        )
    }

    private func miniPlayerButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(Color.white.opacity(0.78))
                .frame(width: 34, height: 34)
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(graphite)
                }
                .overlay {
                    Circle()
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private func libraryControlPill(title: String, systemImage: String, isActive: Bool, showChevron: Bool = true) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))

            Text(title)
                .lineLimit(1)

            if showChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
        }
        .font(.system(size: 11, weight: .bold, design: .monospaced))
        .tracking(0.8)
        .foregroundStyle(isActive ? graphite : graphite.opacity(0.72))
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isActive ? Color.white.opacity(0.62) : Color.white.opacity(0.38))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(isActive ? Color.black.opacity(0.10) : panelStroke, lineWidth: 1)
                }
        )
    }

    private func selectionActionPill(label: String, systemImage: String) -> some View {
        Label(label, systemImage: systemImage)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .tracking(1)
            .foregroundStyle(graphite)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.68))
                    .overlay {
                        Capsule()
                            .stroke(Color.black.opacity(0.06), lineWidth: 1)
                    }
            )
    }

    private func cardActionIcon(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(graphite.opacity(0.72))
            .frame(width: 34, height: 34)
            .background(
                Circle()
                    .fill(Color.white.opacity(0.62))
                    .overlay {
                        Circle()
                            .stroke(Color.black.opacity(0.06), lineWidth: 1)
                    }
            )
    }

    private func infoTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.1)
                .foregroundStyle(graphite.opacity(0.44))

            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(graphite)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.36))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.black.opacity(0.05), lineWidth: 1)
                }
            )
    }

    private func detailActionButtonLabel(_ title: String, systemImage: String, isDestructive: Bool = false) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(isDestructive ? accentRed : graphite)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.58))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(
                                isDestructive ? accentRed.opacity(0.18) : Color.black.opacity(0.06),
                                lineWidth: 1
                            )
                    }
            )
    }

    private func toggleLibrarySelectionMode() {
        isLibrarySelectionMode.toggle()
        if !isLibrarySelectionMode {
            selectedRecordingURLs.removeAll()
        }
    }

    private func toggleSelection(for item: RecordingItem) {
        if selectedRecordingURLs.contains(item.url) {
            selectedRecordingURLs.remove(item.url)
        } else {
            selectedRecordingURLs.insert(item.url)
        }
    }

    private func deleteSelectedRecordings() {
        let itemsToDelete = audio.recordings.filter { selectedRecordingURLs.contains($0.url) }
        for item in itemsToDelete {
            removeProfile(for: item.url.lastPathComponent)
            removeDescription(for: item.url.lastPathComponent)
            audio.delete(item)
        }
        selectedRecordingURLs.removeAll()
        isLibrarySelectionMode = false
    }

    private func resetLibraryFilters() {
        librarySearchText = ""
        selectedLibraryTagFilter = "All Tags"
        isLibrarySearchFocused = false
    }

    private func toggleDescriptor(id: String) {
        var descriptors = selectedDescriptorIDs
        if descriptors.contains(id) {
            descriptors.remove(id)
        } else {
            descriptors.insert(id)
        }
        soundTagDescriptorsRaw = descriptors.sorted().joined(separator: "|")
    }

    private func togglePrimaryType(_ title: String) {
        var types = selectedPrimaryTypes
        if types.contains(title) {
            types.remove(title)
        } else {
            types.insert(title)
        }
        soundTagPrimaryType = types.sorted().joined(separator: "|")
    }

    private func addCustomSourceTag() {
        let cleaned = customSourceInput
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "|", with: " ")

        guard !cleaned.isEmpty else { return }

        let builtInTitles = Set(builtInSoundTypeOptions.map { $0.title.lowercased() })
        var customTags = customSoundSourceTags

        if !builtInTitles.contains(cleaned.lowercased())
            && !customTags.map({ $0.lowercased() }).contains(cleaned.lowercased()) {
            customTags.append(cleaned)
            customSoundSourceTagsRaw = customTags.sorted().joined(separator: "|")
        }

        var types = selectedPrimaryTypes
        types.insert(cleaned)
        soundTagPrimaryType = types.sorted().joined(separator: "|")
        customSourceInput = ""
    }

    private func removeCustomSourceTag(_ tag: String) {
        let updatedCustomTags = customSoundSourceTags.filter { $0.caseInsensitiveCompare(tag) != .orderedSame }
        customSoundSourceTagsRaw = updatedCustomTags.joined(separator: "|")

        var types = selectedPrimaryTypes
        if let matchedType = types.first(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
            types.remove(matchedType)
        }
        soundTagPrimaryType = types.sorted().joined(separator: "|")
    }

    private func symbol(forTag tag: String) -> String {
        if let source = soundTypeOptions.first(where: { $0.title == tag }) {
            return source.symbol
        }
        if let mood = moodTagOptions.first(where: { $0.title == tag }) {
            return mood.symbol
        }
        if let descriptor = soundDescriptorOptions.first(where: { $0.title == tag }) {
            return descriptor.symbol
        }
        return "tag.fill"
    }

    private func splitProfileField(_ value: String?) -> [String] {
        (value ?? "")
            .split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func primaryTypes(for item: RecordingItem) -> [String] {
        splitProfileField(profile(for: item)?.primaryType)
    }

    private func moods(for item: RecordingItem) -> [String] {
        splitProfileField(profile(for: item)?.mood)
    }

    private func tags(for item: RecordingItem) -> [String] {
        let profile = profile(for: item)
        return primaryTypes(for: item) + moods(for: item) + (profile?.descriptors ?? [])
    }

    private func beginTagEditing(for item: RecordingItem) {
        draftTagSnapshot = DraftTagSnapshot(
            primaryType: soundTagPrimaryType,
            mood: soundTagMood,
            descriptorsRaw: soundTagDescriptorsRaw
        )

        if let profile = profile(for: item) {
            soundTagPrimaryType = profile.primaryType
                .split(separator: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: "|")
            soundTagMood = profile.mood
                .split(separator: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: "|")

            let descriptorIDs = soundDescriptorOptions
                .filter { profile.descriptors.contains($0.title) }
                .map { $0.id }
                .sorted()
            soundTagDescriptorsRaw = descriptorIDs.joined(separator: "|")
        } else {
            soundTagPrimaryType = ""
            soundTagMood = ""
            soundTagDescriptorsRaw = ""
        }

        selectedForTagEdit = item
        isSoundTagStudioPresented = true
    }

    private func commitSoundTags() {
        if let item = selectedForTagEdit {
            var profiles = recordingSoundProfiles
            if let draftSoundProfile {
                profiles[item.url.lastPathComponent] = draftSoundProfile
            } else {
                profiles.removeValue(forKey: item.url.lastPathComponent)
            }
            saveProfiles(profiles)
            restoreDraftTagSnapshot()
            selectedForTagEdit = nil
        }

        isSoundTagStudioPresented = false
    }

    private func cancelSoundTagEditing() {
        if selectedForTagEdit != nil {
            restoreDraftTagSnapshot()
            selectedForTagEdit = nil
        }
        isSoundTagStudioPresented = false
    }

    private func restoreDraftTagSnapshot() {
        soundTagPrimaryType = draftTagSnapshot.primaryType
        soundTagMood = draftTagSnapshot.mood
        soundTagDescriptorsRaw = draftTagSnapshot.descriptorsRaw
    }

    private func toggleMood(_ mood: String) {
        var moods = selectedMoods
        if moods.contains(mood) {
            moods.remove(mood)
        } else {
            moods.insert(mood)
        }
        soundTagMood = moods.sorted().joined(separator: "|")
    }

    private func profile(for item: RecordingItem) -> RecordingSoundProfile? {
        recordingSoundProfiles[item.url.lastPathComponent]
    }

    private func description(for item: RecordingItem) -> String {
        recordingDescriptions[item.url.lastPathComponent] ?? ""
    }

    private func assignDraftProfile(toFileName fileName: String) {
        guard let draftSoundProfile else { return }
        var profiles = recordingSoundProfiles
        profiles[fileName] = draftSoundProfile
        saveProfiles(profiles)
    }

    private func removeProfile(for fileName: String) {
        var profiles = recordingSoundProfiles
        profiles.removeValue(forKey: fileName)
        saveProfiles(profiles)
    }

    private func saveDescription(_ description: String, for fileName: String) {
        var descriptions = recordingDescriptions
        let cleaned = description.trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.isEmpty {
            descriptions.removeValue(forKey: fileName)
        } else {
            descriptions[fileName] = cleaned
        }

        saveDescriptions(descriptions)
    }

    private func removeDescription(for fileName: String) {
        var descriptions = recordingDescriptions
        descriptions.removeValue(forKey: fileName)
        saveDescriptions(descriptions)
    }

    private func saveProfiles(_ profiles: [String: RecordingSoundProfile]) {
        guard let data = try? JSONEncoder().encode(profiles),
              let json = String(data: data, encoding: .utf8) else { return }
        recordingSoundProfilesRaw = json
    }

    private func saveDescriptions(_ descriptions: [String: String]) {
        guard let data = try? JSONEncoder().encode(descriptions),
              let json = String(data: data, encoding: .utf8) else { return }
        recordingDescriptionsRaw = json
    }

    private func clearSoundTags() {
        soundTagPrimaryType = ""
        soundTagMood = ""
        soundTagDescriptorsRaw = ""
        customSourceInput = ""
    }

    private func tag(text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(graphite.opacity(0.08))
            .clipShape(Capsule())
    }

    private func subtleTag(text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .default))
            .foregroundStyle(graphite.opacity(0.58))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.52))
                    .overlay {
                        Capsule()
                            .stroke(Color.black.opacity(0.04), lineWidth: 1)
                    }
            )
    }

    private func refinedTag(text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .default))
            .foregroundStyle(graphite.opacity(0.78))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.62))
                    .overlay {
                        Capsule()
                            .stroke(Color.black.opacity(0.05), lineWidth: 1)
                    }
            )
    }

    private func descriptionSheet(item: RecordingItem) -> some View {
        NavigationStack {
            VStack(spacing: 18) {
                Text(item.displayFileStamp)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(graphite)
                    .frame(maxWidth: .infinity, alignment: .leading)

                TextEditor(text: $descriptionDraftText)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: 180)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.72))
                            .overlay {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(panelStroke, lineWidth: 1)
                            }
                    )

                Button {
                    saveDescription(descriptionDraftText, for: item.url.lastPathComponent)
                    selectedForDescriptionEdit = nil
                } label: {
                        Text("Save Description")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(graphite)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Description")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        selectedForDescriptionEdit = nil
                    }
                }
            }
        }
    }

    private func timeString(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let centiseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 100)

        return String(format: "%02d:%02d.%02d", minutes, seconds, centiseconds)
    }
}

private struct SoundTagOption: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let color: Color
}

private struct MoodOption: Identifiable {
    let id: String
    let title: String
    let symbol: String
}

private struct DescriptorOption: Identifiable {
    let id: String
    let title: String
    let symbol: String
}

private struct RecordingSoundProfile: Codable, Hashable {
    let primaryType: String
    let mood: String
    let descriptors: [String]

    var allLabels: [String] {
        let primaryLabels = primaryType
            .split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let moodLabels = mood
            .split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return primaryLabels + moodLabels + descriptors
    }
}

private struct DraftTagSnapshot {
    var primaryType = ""
    var mood = ""
    var descriptorsRaw = ""
}


private struct FlexibleTagFlow<Item: Hashable, Content: View>: View {
    let items: [Item]
    let content: (Item) -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            let rows = makeRows(items: items, maxPerRow: 3)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 10) {
                    ForEach(row, id: \.self) { item in
                        content(item)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func makeRows(items: [Item], maxPerRow: Int) -> [[Item]] {
        stride(from: 0, to: items.count, by: maxPerRow).map { start in
            Array(items[start..<min(start + maxPerRow, items.count)])
        }
    }
}

private enum LibrarySortOrder: String, CaseIterable, Identifiable {
    case latest
    case oldest
    case largest
    case smallest

    var id: String { rawValue }

    var label: String {
        switch self {
        case .latest:
            return "Latest First"
        case .oldest:
            return "Oldest First"
        case .largest:
            return "Largest File"
        case .smallest:
            return "Smallest File"
        }
    }

    var shortLabel: String {
        switch self {
        case .latest:
            return "LATEST"
        case .oldest:
            return "OLDEST"
        case .largest:
            return "LARGEST"
        case .smallest:
            return "SMALLEST"
        }
    }
}

#Preview {
    ContentView()
}
private struct ReelWindowShape: Shape {
    let startAngle: Angle
    let sweep: Angle

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) * 0.5
        let innerRadius = outerRadius * 0.38
        let start = CGFloat(startAngle.radians)
        let end = CGFloat((startAngle + sweep).radians)

        func point(radius: CGFloat, angle: CGFloat) -> CGPoint {
            CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
        }

        var path = Path()
        path.move(to: point(radius: innerRadius, angle: start))
        path.addArc(
            center: center,
            radius: innerRadius,
            startAngle: .radians(Double(start)),
            endAngle: .radians(Double(end)),
            clockwise: false
        )
        path.addLine(to: point(radius: outerRadius, angle: end))
        path.addArc(
            center: center,
            radius: outerRadius,
            startAngle: .radians(Double(end)),
            endAngle: .radians(Double(start)),
            clockwise: true
        )
        path.addLine(to: point(radius: innerRadius, angle: start))
        path.closeSubpath()
        return path
    }
}
