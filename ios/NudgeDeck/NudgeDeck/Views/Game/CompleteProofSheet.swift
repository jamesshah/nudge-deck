import PhotosUI
import SwiftUI
import UIKit

struct CompleteProofSheet: View {
    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss
    let play: Play

    @State private var proofType: ProofType = .photo
    @State private var note = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var loadingPhoto = false
    @StateObject private var recorder = VoiceRecorder()

    init(play: Play, initialProofType: ProofType = .photo) {
        self.play = play
        _proofType = State(initialValue: initialProofType)
    }

    private var trimmedNote: String { note.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSubmit: Bool {
        guard !store.isWorking else { return false }
        switch proofType {
        case .text: return !trimmedNote.isEmpty
        case .photo: return photoData != nil
        case .audio: return recorder.recordingURL != nil && !recorder.isRecording
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    CardFace(play: play)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section {
                    Picker("Proof", selection: $proofType) {
                        Text("Photo").tag(ProofType.photo)
                        Text("Voice note").tag(ProofType.audio)
                        Text("Note").tag(ProofType.text)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } footer: {
                    Text("\(play.fromName) reviews your proof and marks the Nudge complete. That's one for the relationship.")
                }

                switch proofType {
                case .photo: photoSection
                case .audio: audioSection
                case .text: EmptyView()
                }

                Section(proofType == .text ? "Your note" : "Add a caption (optional)") {
                    TextField(proofType == .text ? "Tell them how it went" : "Caption", text: $note, axis: .vertical)
                        .lineLimit(2...6)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.canvas)
            .navigationTitle("Nudge complete 🫡")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        recorder.discard()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if store.isWorking {
                        ProgressView()
                    } else {
                        Button("Send") { Task { await submit() } }
                            .disabled(!canSubmit)
                    }
                }
            }
            .onChange(of: photoItem) { _, item in
                Task { await loadPhoto(item) }
            }
            .errorAlert($recorder.errorMessage)
        }
    }

    private var photoSection: some View {
        Section {
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label(photoData == nil ? "Choose a photo" : "Choose a different photo", systemImage: "photo.on.rectangle")
            }
            if loadingPhoto {
                ProgressView()
            } else if let photoData, let image = UIImage(data: photoData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        } header: {
            Text("Photo")
        } footer: {
            Text("Under 3 MB.")
        }
    }

    private var audioSection: some View {
        Section {
            HStack {
                Button {
                    if recorder.isRecording {
                        recorder.stop()
                    } else {
                        Task { await recorder.start() }
                    }
                } label: {
                    Label(recorder.isRecording ? "Stop" : (recorder.recordingURL == nil ? "Record" : "Record again"),
                          systemImage: recorder.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.headline)
                }
                .tint(recorder.isRecording ? Theme.destructive : Theme.brand)
                Spacer()
                Text(Duration.seconds(recorder.elapsed).formatted(.time(pattern: .minuteSecond)))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if recorder.recordingURL != nil && !recorder.isRecording {
                Label("Voice note ready to send", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.success)
            }
        } header: {
            Text("Voice note")
        } footer: {
            Text("Up to \(Int(VoiceRecorder.maxDuration)) seconds, under 3 MB.")
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        loadingPhoto = true
        defer { loadingPhoto = false }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data)
        else {
            photoData = nil
            store.errorMessage = "That photo couldn't be loaded. Try another one."
            return
        }
        guard let jpeg = Self.downscaledJPEG(image), GameFormatting.isProofFileWithinLimit(jpeg) else {
            photoData = nil
            store.errorMessage = GameFormatting.proofFileTooLargeMessage(for: .photo)
            return
        }
        photoData = jpeg
    }

    private static func downscaledJPEG(_ image: UIImage, maxDimension: CGFloat = 1600) -> Data? {
        let largest = max(image.size.width, image.size.height)
        let scale = largest > maxDimension ? maxDimension / largest : 1
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        for quality in [0.75, 0.55, 0.4] as [CGFloat] {
            guard let data = resized.jpegData(compressionQuality: quality) else { continue }
            if GameFormatting.isProofFileWithinLimit(data) { return data }
        }
        return resized.jpegData(compressionQuality: 0.35)
    }

    private func submit() async {
        let caption = trimmedNote.isEmpty ? nil : trimmedNote
        var ok = false
        switch proofType {
        case .text:
            ok = await store.completeWithText(play, text: trimmedNote)
        case .photo:
            guard let photoData else { return }
            ok = await store.completeWithFile(play, type: .photo, data: photoData, contentType: "image/jpeg", caption: caption)
        case .audio:
            guard let url = recorder.recordingURL, let data = try? Data(contentsOf: url) else { return }
            ok = await store.completeWithFile(play, type: .audio, data: data, contentType: "audio/mp4", caption: caption)
            if ok { recorder.discard() }
        }
        if ok { dismiss() }
    }
}

#if DEBUG
#Preview("Proof sheet · photo") {
    CompleteProofSheet(play: PreviewData.incomingPending).previewEnvironment()
}

#Preview("Proof sheet · note") {
    CompleteProofSheet(play: PreviewData.incomingStackedRetry, initialProofType: .text).previewEnvironment()
}

#Preview("Proof sheet · voice note") {
    CompleteProofSheet(play: PreviewData.incomingPending, initialProofType: .audio).previewEnvironment()
}

#Preview("Proof sheet · sending") {
    CompleteProofSheet(play: PreviewData.incomingPending, initialProofType: .text)
        .previewEnvironment(GameStore(previewCouple: PreviewData.pairedCouple, isWorking: true))
}

#Preview("Proof sheet · dark") {
    CompleteProofSheet(play: PreviewData.incomingPending, initialProofType: .text)
        .previewEnvironment()
        .preferredColorScheme(.dark)
}
#endif
