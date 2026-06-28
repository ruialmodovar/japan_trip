import PhotosUI
import SwiftUI
import UIKit

struct PhotoJournalEntry: Identifiable, Codable, Hashable {
    let id: UUID
    let filename: String
    let createdAt: Date
    var caption: String
}

@MainActor
final class PhotoJournalStore: ObservableObject {
    @Published private(set) var entries: [PhotoJournalEntry] = []
    @Published private(set) var isImporting = false
    @Published var errorMessage: String?

    private let fileManager = FileManager.default
    private let metadataFilename = "photo-journal.json"
    private let customJournalDirectory: URL?

    init(directory: URL? = nil) {
        customJournalDirectory = directory
        loadMetadata()
    }

    func importPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        isImporting = true
        errorMessage = nil
        defer { isImporting = false }

        do {
            try fileManager.createDirectory(at: journalDirectory, withIntermediateDirectories: true)
            for item in items {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data),
                      let jpeg = image.jpegData(compressionQuality: 0.88) else { continue }
                let id = UUID()
                let filename = "\(id.uuidString).jpg"
                try jpeg.write(to: journalDirectory.appendingPathComponent(filename), options: .atomic)
                entries.insert(.init(id: id, filename: filename, createdAt: Date(), caption: ""), at: 0)
            }
            saveMetadata()
        } catch {
            errorMessage = "Não foi possível guardar uma das fotografias."
        }
    }

    func saveCapturedImage(_ image: UIImage) {
        errorMessage = nil
        do {
            try fileManager.createDirectory(at: journalDirectory, withIntermediateDirectories: true)
            guard let jpeg = image.jpegData(compressionQuality: 0.9) else {
                throw CocoaError(.fileWriteUnknown)
            }
            let id = UUID()
            let filename = "\(id.uuidString).jpg"
            try jpeg.write(to: journalDirectory.appendingPathComponent(filename), options: .atomic)
            entries.insert(.init(id: id, filename: filename, createdAt: Date(), caption: ""), at: 0)
            saveMetadata()
        } catch {
            errorMessage = "Não foi possível guardar a fotografia tirada."
        }
    }

    func updateCaption(for entry: PhotoJournalEntry, caption: String) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].caption = caption
        saveMetadata()
    }

    func delete(_ entry: PhotoJournalEntry) {
        try? fileManager.removeItem(at: imageURL(for: entry))
        entries.removeAll { $0.id == entry.id }
        saveMetadata()
    }

    func imageURL(for entry: PhotoJournalEntry) -> URL {
        journalDirectory.appendingPathComponent(entry.filename)
    }

    private var journalDirectory: URL {
        if let customJournalDirectory { return customJournalDirectory }
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("JapanTripPhotoJournal", isDirectory: true)
    }

    private var metadataURL: URL { journalDirectory.appendingPathComponent(metadataFilename) }

    private func loadMetadata() {
        guard let data = try? Data(contentsOf: metadataURL),
              let saved = try? JSONDecoder().decode([PhotoJournalEntry].self, from: data) else { return }
        entries = saved.filter { fileManager.fileExists(atPath: imageURL(for: $0).path) }
    }

    private func saveMetadata() {
        do {
            try fileManager.createDirectory(at: journalDirectory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(entries)
            try data.write(to: metadataURL, options: .atomic)
        } catch {
            errorMessage = "Não foi possível atualizar o diário fotográfico."
        }
    }
}

struct PhotoJournalView: View {
    @EnvironmentObject private var navigation: AppNavigationState
    @EnvironmentObject private var journal: PhotoJournalStore
    @EnvironmentObject private var authentication: AuthenticationManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var selectedEntry: PhotoJournalEntry?
    @State private var showsCamera = false
    @State private var showsPhotoLibrary = false

    private let columns = [GridItem(.flexible(), spacing: 3), GridItem(.flexible(), spacing: 3), GridItem(.flexible(), spacing: 3)]

    var body: some View {
        Group {
            if journal.entries.isEmpty {
                emptyState
            } else {
                photoGrid
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Diário Fotográfico")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                    navigation.goHome()
                } label: {
                    Label("Início", systemImage: "house.fill")
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showsCamera = true
                } label: {
                    Image(systemName: "camera.fill").accessibilityLabel("Abrir câmera")
                }
                .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                Button {
                    showsPhotoLibrary = true
                } label: {
                    Image(systemName: "plus.circle.fill").accessibilityLabel("Adicionar fotografias")
                }
                Button("Fechar") { dismiss() }
            }
        }
        .onChange(of: selectedItems) { _, items in
            Task {
                await journal.importPhotos(items)
                selectedItems = []
            }
        }
        .photosPicker(isPresented: $showsPhotoLibrary, selection: $selectedItems, maxSelectionCount: 20, matching: .images)
        .onChange(of: showsPhotoLibrary) { _, isPresented in
            authentication.suppressAutoLock("photo-library", while: isPresented)
        }
        .onChange(of: showsCamera) { _, isPresented in
            authentication.suppressAutoLock("camera", while: isPresented)
        }
        .sheet(item: $selectedEntry) { entry in
            PhotoDetailView(entry: entry)
                .environmentObject(journal)
        }
        .fullScreenCover(isPresented: $showsCamera) {
            CameraCaptureView { image in
                journal.saveCapturedImage(image)
            }
            .ignoresSafeArea()
        }
        .overlay {
            if journal.isImporting {
                ProgressView("A guardar fotografias…")
                    .padding(22)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            }
        }
        .onDisappear {
            authentication.suppressAutoLock("photo-library", while: false)
            authentication.suppressAutoLock("camera", while: false)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 58))
                .foregroundStyle(.pink)
            Text("As memórias começam aqui")
                .font(.title2.bold())
            Text("Adicione fotografias da viagem, escreva pequenas legendas e crie um diário só da família.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                showsPhotoLibrary = true
            } label: {
                Label("Adicionar fotografias", systemImage: "plus")
                    .font(.headline)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.pink)
            Button {
                showsCamera = true
            } label: {
                Label("Tirar uma fotografia", systemImage: "camera.fill")
                    .font(.headline)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .tint(.pink)
            .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
            Spacer()
        }
        .padding(32)
    }

    private var photoGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Memórias da viagem").font(.title2.bold())
                        Text("\(journal.entries.count) fotografias guardadas neste aparelho").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal)

                LazyVGrid(columns: columns, spacing: 3) {
                    ForEach(journal.entries) { entry in
                        Button {
                            selectedEntry = entry
                        } label: {
                            JournalThumbnail(entry: entry)
                                .environmentObject(journal)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) { journal.delete(entry) } label: {
                                Label("Apagar", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .padding(.vertical)
        }
    }
}

private struct CameraCaptureView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onCapture: (UIImage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraCaptureView

        init(parent: CameraCaptureView) {
            self.parent = parent
        }

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

private struct JournalThumbnail: View {
    @EnvironmentObject private var journal: PhotoJournalStore
    let entry: PhotoJournalEntry

    var body: some View {
        Group {
            if let image = UIImage(contentsOfFile: journal.imageURL(for: entry).path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.gray.opacity(0.15).overlay { Image(systemName: "photo") }
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .clipped()
    }
}

private struct PhotoDetailView: View {
    @EnvironmentObject private var journal: PhotoJournalStore
    @Environment(\.dismiss) private var dismiss
    let entry: PhotoJournalEntry
    @State private var caption: String

    init(entry: PhotoJournalEntry) {
        self.entry = entry
        _caption = State(initialValue: entry.caption)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if let image = UIImage(contentsOfFile: journal.imageURL(for: entry).path) {
                        Image(uiImage: image).resizable().scaledToFit()
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Legenda").font(.headline)
                        TextField("O que tornou este momento especial?", text: $caption, axis: .vertical)
                            .lineLimit(3...6)
                            .textFieldStyle(.roundedBorder)
                        Text(entry.createdAt.formatted(.dateTime.day().month(.wide).year().hour().minute().locale(Locale(identifier: "pt_BR"))))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                }
            }
            .navigationTitle("Memória")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        journal.updateCaption(for: entry, caption: caption)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { dismiss() }
                }
            }
        }
    }
}
