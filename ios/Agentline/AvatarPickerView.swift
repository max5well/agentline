import PhotosUI
import SwiftUI

// Avatar picker (DESIGN-SPEC §5), stage 2: photo / camera / generated
// avatars upload to the avatars bucket; emoji + monogram stay pure data.
struct AvatarPickerView: View {
    @Binding var agent: Agent
    @Environment(\.dismiss) private var dismiss
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var uploading = false
    @State private var errorMessage: String?

    private static let suggestedEmoji = [
        "📜", "🌱", "🗣️", "🧠", "🎓", "💼", "🧭", "🎨",
        "⚖️", "🔬", "🏛️", "💪", "🍳", "🎹", "✈️", "📈",
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ZStack {
                        AgentAvatar(agent: agent, size: 96)
                        if uploading { ProgressView() }
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity)
                            .listRowBackground(Color.clear)
                    }
                }

                Section {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Choose Image", systemImage: "photo.on.rectangle")
                    }
                    Button {
                        showCamera = true
                    } label: {
                        Label("Take Photo", systemImage: "camera")
                    }
                    NavigationLink {
                        GenerateAvatarView(agent: $agent)
                    } label: {
                        Label("Generate Avatar", systemImage: "sparkles")
                    }
                }

                Section("Emoji") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 10) {
                        ForEach(Self.suggestedEmoji, id: \.self) { emoji in
                            Button {
                                agent.emoji = emoji
                                agent.avatarUrl = nil
                            } label: {
                                Text(emoji)
                                    .font(.system(size: 26))
                                    .frame(width: 36, height: 36)
                                    .background(
                                        agent.emoji == emoji && agent.avatarUrl == nil
                                            ? Color.accentColor.opacity(0.2) : .clear,
                                        in: Circle()
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Button {
                        agent.emoji = ""
                        agent.avatarUrl = nil
                    } label: {
                        HStack {
                            Text("Monogram (\(agent.monogram))")
                                .foregroundStyle(.primary)
                            Spacer()
                            if agent.emoji.isEmpty && agent.avatarUrl == nil {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                } footer: {
                    Text("Initials on the agent's color — the default for new agents.")
                }
            }
            .navigationTitle("Avatar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.bold()
                }
            }
            .onChange(of: photoItem) {
                guard let photoItem else { return }
                Task { await upload(item: photoItem) }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in
                    Task { await upload(image: image) }
                }
                .ignoresSafeArea()
            }
        }
    }

    private func upload(item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            errorMessage = "Could not read that image."
            return
        }
        await upload(image: image)
    }

    private func upload(image: UIImage) async {
        guard let backend = AppStore.backendIfConfigured() else {
            errorMessage = "Avatar photos need the backend (demo mode is offline)."
            return
        }
        uploading = true
        errorMessage = nil
        do {
            guard let jpeg = image.squareAvatarJPEG(side: 512) else { throw URLError(.cannotDecodeContentData) }
            agent.avatarUrl = try await backend.uploadAvatar(jpeg)
        } catch {
            errorMessage = error.localizedDescription
        }
        uploading = false
    }
}

// Generated avatars (§5 source 3): description → two variants →
// explicit select + confirm.
struct GenerateAvatarView: View {
    @Binding var agent: Agent
    @Environment(\.dismiss) private var dismiss
    @State private var description = ""
    @State private var variants: [String] = []
    @State private var selectedUrl: String?
    @State private var busy = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                TextField("Describe the avatar — looks, vibe, colors…", text: $description, axis: .vertical)
                    .lineLimit(2...5)
            } header: {
                Text("Description")
            }

            Section {
                Button {
                    Task { await generate() }
                } label: {
                    if busy {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text(variants.isEmpty ? "Generate" : "Regenerate")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(description.trimmingCharacters(in: .whitespaces).isEmpty || busy)
                .listRowInsets(EdgeInsets())
                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }
            } footer: {
                if busy { Text("Generating two variants — takes ~15 seconds.") }
            }

            if !variants.isEmpty {
                Section("Tap to choose") {
                    HStack(spacing: 16) {
                        ForEach(variants, id: \.self) { urlString in
                            Button {
                                selectedUrl = urlString
                            } label: {
                                ZStack(alignment: .bottomTrailing) {
                                    AsyncImage(url: URL(string: urlString)) { image in
                                        image.resizable().scaledToFill()
                                    } placeholder: {
                                        ProgressView()
                                    }
                                    .frame(width: 120, height: 120)
                                    .clipShape(Circle())
                                    .overlay(
                                        Circle().stroke(
                                            selectedUrl == urlString ? Color.accentColor : Color(.separator),
                                            lineWidth: selectedUrl == urlString ? 4 : 1
                                        )
                                    )
                                    if selectedUrl == urlString {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.title2)
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, Color.accentColor)
                                            .offset(x: -4, y: -4)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)

                    Button {
                        agent.avatarUrl = selectedUrl
                        agent.emoji = ""
                        dismiss()
                    } label: {
                        Text("Use this avatar")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedUrl == nil)
                    .listRowInsets(EdgeInsets())
                }
            }
        }
        .navigationTitle("Generate Avatar")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func generate() async {
        guard let backend = AppStore.backendIfConfigured() else {
            errorMessage = "Avatar generation needs the backend (demo mode is offline)."
            return
        }
        busy = true
        errorMessage = nil
        do {
            variants = try await backend.generateAvatars(description: description)
        } catch {
            errorMessage = error.localizedDescription
        }
        busy = false
    }
}

// UIImagePickerController wrapper for the camera source.
struct CameraPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onCapture: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.cameraDevice = UIImagePickerController.isCameraDeviceAvailable(.front) ? .front : .rear
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

extension UIImage {
    // Center-crop to square, downscale, JPEG-compress. format.scale = 1
    // is load-bearing: the default renderer scale is the device's 3×,
    // which turned "512" into 1536px and megabytes of PNG.
    func squareAvatarJPEG(side: CGFloat) -> Data? {
        let shortest = min(size.width, size.height)
        let scale = side / shortest
        let origin = CGPoint(x: (size.width - shortest) / 2, y: (size.height - shortest) / 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        let result = renderer.image { _ in
            draw(in: CGRect(x: -origin.x * scale, y: -origin.y * scale,
                            width: size.width * scale, height: size.height * scale))
        }
        return result.jpegData(compressionQuality: 0.85)
    }
}
