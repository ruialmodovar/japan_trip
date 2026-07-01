import PhotosUI
import SwiftUI
import UIKit

struct PhotoJournalEntry: Identifiable, Codable, Hashable {
    let id: UUID
    let filename: String
    let createdAt: Date
    var caption: String
    var authorEmail: String? = nil
    var remotePath: String? = nil
}

@MainActor
final class PhotoJournalStore: ObservableObject {
    @Published private(set) var entries: [PhotoJournalEntry] = []
    @Published private(set) var isImporting = false
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncedAt: Date?
    @Published var errorMessage: String?

    private let fileManager = FileManager.default
    private let metadataFilename = "photo-journal.json"
    private let customJournalDirectory: URL?
    private let sharingService: any TripSharingServicing
    private weak var authentication: AuthenticationManager?
    private var pendingDeletions: [PendingPhotoDeletion] = []

    init(
        directory: URL? = nil,
        sharingService: any TripSharingServicing = SupabaseTripSharingService()
    ) {
        customJournalDirectory = directory
        self.sharingService = sharingService
        loadMetadata()
    }

    func configureSharing(authentication: AuthenticationManager) {
        self.authentication = authentication
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
                let entry = PhotoJournalEntry(
                    id: id, filename: filename, createdAt: Date(), caption: "",
                    authorEmail: authentication?.authenticatedEmail
                )
                entries.insert(entry, at: 0)
                saveMetadata()
                await upload(entry)
            }
            saveMetadata()
        } catch {
            errorMessage = "Não foi possível guardar uma das fotografias."
        }
    }

    func saveCapturedImage(_ image: UIImage) async {
        errorMessage = nil
        do {
            try fileManager.createDirectory(at: journalDirectory, withIntermediateDirectories: true)
            guard let jpeg = image.jpegData(compressionQuality: 0.9) else {
                throw CocoaError(.fileWriteUnknown)
            }
            let id = UUID()
            let filename = "\(id.uuidString).jpg"
            try jpeg.write(to: journalDirectory.appendingPathComponent(filename), options: .atomic)
            let entry = PhotoJournalEntry(
                id: id, filename: filename, createdAt: Date(), caption: "",
                authorEmail: authentication?.authenticatedEmail
            )
            entries.insert(entry, at: 0)
            saveMetadata()
            await upload(entry)
        } catch {
            errorMessage = "Não foi possível guardar a fotografia tirada."
        }
    }

    func updateCaption(for entry: PhotoJournalEntry, caption: String) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].caption = caption
        let updatedEntry = entries[index]
        saveMetadata()
        Task { await updateRemoteMetadata(for: updatedEntry) }
    }

    func delete(_ entry: PhotoJournalEntry) {
        try? fileManager.removeItem(at: imageURL(for: entry))
        entries.removeAll { $0.id == entry.id }
        if let path = entry.remotePath {
            pendingDeletions.append(.init(id: entry.id, path: path))
        }
        saveMetadata()
        Task { await flushDeletions() }
    }

    func canModify(_ entry: PhotoJournalEntry) -> Bool {
        entry.authorEmail == nil || entry.authorEmail == authentication?.authenticatedEmail
    }

    func sync(authentication: AuthenticationManager) async {
        configureSharing(authentication: authentication)
        guard authentication.isAuthenticated, !isSyncing else { return }
        isSyncing = true
        errorMessage = nil
        defer { isSyncing = false }

        do {
            await flushDeletions()
            for entry in entries where entry.remotePath == nil {
                await upload(entry)
            }
            let token = try await authentication.accessTokenForAPI()
            let remoteRecords = try await sharingService.fetchPhotos(accessToken: token)
            try fileManager.createDirectory(at: journalDirectory, withIntermediateDirectories: true)
            let remoteIDs = Set(remoteRecords.map(\.id))
            let removedRemotely = entries.filter { $0.remotePath != nil && !remoteIDs.contains($0.id) }
            for entry in removedRemotely {
                try? fileManager.removeItem(at: imageURL(for: entry))
            }
            entries.removeAll { $0.remotePath != nil && !remoteIDs.contains($0.id) }
            for record in remoteRecords {
                guard !pendingDeletions.contains(where: { $0.id == record.id }) else { continue }
                if let index = entries.firstIndex(where: { $0.id == record.id }) {
                    entries[index].caption = record.caption
                    entries[index].authorEmail = record.ownerEmail
                    entries[index].remotePath = record.storagePath
                } else {
                    let filename = "\(record.id.uuidString).jpg"
                    let data = try await sharingService.downloadPhoto(path: record.storagePath, accessToken: token)
                    try data.write(to: journalDirectory.appendingPathComponent(filename), options: .atomic)
                    entries.append(.init(
                        id: record.id, filename: filename, createdAt: record.createdAt,
                        caption: record.caption, authorEmail: record.ownerEmail,
                        remotePath: record.storagePath
                    ))
                }
            }
            entries.sort { $0.createdAt > $1.createdAt }
            lastSyncedAt = Date()
            saveMetadata()
        } catch {
            errorMessage = "Sem sincronização neste momento — as fotografias continuam guardadas neste aparelho."
        }
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
        if let data = try? Data(contentsOf: pendingDeletionsURL) {
            pendingDeletions = (try? JSONDecoder().decode([PendingPhotoDeletion].self, from: data)) ?? []
        }
    }

    private func saveMetadata() {
        do {
            try fileManager.createDirectory(at: journalDirectory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(entries)
            try data.write(to: metadataURL, options: .atomic)
            let deletions = try JSONEncoder().encode(pendingDeletions)
            try deletions.write(to: pendingDeletionsURL, options: .atomic)
        } catch {
            errorMessage = "Não foi possível atualizar o diário fotográfico."
        }
    }

    private var pendingDeletionsURL: URL { journalDirectory.appendingPathComponent("pending-photo-deletions.json") }

    private func upload(_ entry: PhotoJournalEntry) async {
        guard let authentication, authentication.isAuthenticated,
              let userID = authentication.authenticatedUserID,
              let email = authentication.authenticatedEmail,
              let data = try? Data(contentsOf: imageURL(for: entry)) else { return }
        let path = Self.storagePath(userID: userID, photoID: entry.id)
        do {
            let token = try await authentication.accessTokenForAPI()
            try await sharingService.uploadPhoto(data, path: path, accessToken: token)
            let record = SharedPhotoRecord(
                id: entry.id, ownerUserID: userID, ownerEmail: email,
                storagePath: path, caption: entry.caption, createdAt: entry.createdAt
            )
            try await sharingService.upsertPhoto(record, accessToken: token)
            if let index = entries.firstIndex(where: { $0.id == entry.id }) {
                entries[index].authorEmail = email
                entries[index].remotePath = path
                saveMetadata()
            }
            lastSyncedAt = Date()
        } catch {
            errorMessage = "A fotografia ficou guardada no aparelho, mas o Supabase respondeu: \(error.localizedDescription)"
        }
    }

    private func updateRemoteMetadata(for entry: PhotoJournalEntry) async {
        guard let authentication, authentication.isAuthenticated,
              let userID = authentication.authenticatedUserID,
              let email = authentication.authenticatedEmail,
              let path = entry.remotePath,
              canModify(entry) else { return }
        do {
            let token = try await authentication.accessTokenForAPI()
            try await sharingService.upsertPhoto(.init(
                id: entry.id, ownerUserID: userID, ownerEmail: email,
                storagePath: path, caption: entry.caption, createdAt: entry.createdAt
            ), accessToken: token)
        } catch {
            errorMessage = "Legenda guardada no aparelho; será sincronizada mais tarde."
        }
    }

    private func flushDeletions() async {
        guard let authentication, authentication.isAuthenticated else { return }
        do {
            let token = try await authentication.accessTokenForAPI()
            for deletion in pendingDeletions {
                try await sharingService.deletePhoto(id: deletion.id, path: deletion.path, accessToken: token)
                pendingDeletions.removeAll { $0.id == deletion.id }
            }
            saveMetadata()
        } catch {
            errorMessage = "A eliminação será sincronizada quando houver internet."
        }
    }

    static func storagePath(userID: UUID, photoID: UUID) -> String {
        "\(userID.uuidString.lowercased())/\(photoID.uuidString.lowercased()).jpg"
    }
}

private struct PendingPhotoDeletion: Codable, Hashable {
    let id: UUID
    let path: String
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
        .navigationTitle("Fotos")
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
                    Task { await journal.sync(authentication: authentication) }
                } label: {
                    if journal.isSyncing { ProgressView() } else { Image(systemName: "arrow.triangle.2.circlepath") }
                }
                .disabled(journal.isSyncing)
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
        .onAppear {
            journal.configureSharing(authentication: authentication)
        }
        .sheet(item: $selectedEntry) { entry in
            PhotoDetailView(entry: entry)
                .environmentObject(journal)
        }
        .fullScreenCover(isPresented: $showsCamera) {
            CameraCaptureView { image in
                Task { await journal.saveCapturedImage(image) }
            }
            .ignoresSafeArea()
        }
        .overlay {
            if journal.isImporting || journal.isSyncing {
                ProgressView(journal.isSyncing ? "A sincronizar fotografias…" : "A guardar fotografias…")
                    .padding(22)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            }
        }
        .onDisappear {
            authentication.suppressAutoLock("photo-library", while: false)
            authentication.suppressAutoLock("camera", while: false)
        }
        .task { await journal.sync(authentication: authentication) }
        .alert("Sincronização de fotografias", isPresented: Binding(
            get: { journal.errorMessage != nil },
            set: { if !$0 { journal.errorMessage = nil } }
        )) {
            Button("OK") { journal.errorMessage = nil }
        } message: {
            Text(journal.errorMessage ?? "")
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
                        Text("\(journal.entries.count) fotografias · partilhadas com o grupo").font(.caption).foregroundStyle(.secondary)
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
                            if journal.canModify(entry) {
                                Button(role: .destructive) { journal.delete(entry) } label: {
                                    Label("Apagar", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .padding(.vertical)
        }
    }
}

struct CameraCaptureView: UIViewControllerRepresentable {
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
                            .disabled(!journal.canModify(entry))
                        if let email = entry.authorEmail,
                           let participant = TripParticipant.participant(for: email) {
                            Label("Fotografia de \(participant.name)", systemImage: "person.crop.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
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
                    if journal.canModify(entry) {
                        Button("Guardar") {
                            journal.updateCaption(for: entry, caption: caption)
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { dismiss() }
                }
            }
        }
    }
}
