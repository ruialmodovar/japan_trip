import CryptoKit
import LocalAuthentication
import PhotosUI
import QuickLook
import Security
import SwiftUI
import UniformTypeIdentifiers

struct VaultDocument: Identifiable, Codable, Hashable {
    enum Category: String, CaseIterable, Codable, Identifiable {
        case passport = "Passaportes"
        case insurance = "Seguros"
        case ticket = "Bilhetes"
        case reservation = "Reservas"
        case qrCode = "QR Codes"
        case other = "Outros"

        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .passport: "person.text.rectangle.fill"
            case .insurance: "cross.case.fill"
            case .ticket: "ticket.fill"
            case .reservation: "calendar.badge.checkmark"
            case .qrCode: "qrcode"
            case .other: "doc.fill"
            }
        }
        var color: Color {
            switch self {
            case .passport: .indigo
            case .insurance: .red
            case .ticket: .orange
            case .reservation: .blue
            case .qrCode: .purple
            case .other: .gray
            }
        }
    }

    let id: UUID
    let name: String
    let category: Category
    let encryptedFilename: String
    let fileExtension: String
    let importedAt: Date
    let originalSize: Int
}

protocol VaultKeyProviding {
    func loadOrCreateKey(authenticationContext: LAContext) throws -> SymmetricKey
}

struct BiometricVaultKeyProvider: VaultKeyProviding {
    private let service = "com.ruicoelho.JapanTrip.document-vault"
    private let account = "aes-256-key"

    func loadOrCreateKey(authenticationContext: LAContext) throws -> SymmetricKey {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationContext as String] = authenticationContext

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data {
            return SymmetricKey(data: data)
        }
        guard status == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }

        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        var accessError: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .biometryCurrentSet,
            &accessError
        ) else {
            throw accessError!.takeRetainedValue() as Error
        }

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = keyData
        addQuery[kSecAttrAccessControl as String] = accessControl
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(addStatus))
        }
        return key
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

@MainActor
final class DocumentVaultStore: ObservableObject {
    @Published private(set) var isUnlocked = false
    @Published private(set) var documents: [VaultDocument] = []
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?

    private let directory: URL
    private let keyProvider: any VaultKeyProviding
    private var encryptionKey: SymmetricKey?
    private var previewURLs: Set<URL> = []

    init(directory: URL? = nil, keyProvider: any VaultKeyProviding = BiometricVaultKeyProvider()) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PrivateDocumentVault", isDirectory: true)
        self.keyProvider = keyProvider
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: self.directory.path)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var localDirectory = self.directory
        try? localDirectory.setResourceValues(values)
    }

    func unlock() async {
        guard !isWorking, !isUnlocked else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        let context = LAContext()
        context.localizedCancelTitle = "Cancelar"
        context.localizedFallbackTitle = ""
        var policyError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &policyError) else {
            errorMessage = "Configure o Face ID ou Touch ID para abrir o cofre."
            return
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Abra o cofre privado de documentos da viagem."
            )
            guard success else { return }
            encryptionKey = try keyProvider.loadOrCreateKey(authenticationContext: context)
            documents = try loadManifest()
            isUnlocked = true
        } catch {
            errorMessage = "Não foi possível abrir o cofre. A biometria pode ter sido alterada."
            encryptionKey = nil
        }
    }

    func lock() {
        cleanupAllPreviews()
        encryptionKey = nil
        documents = []
        isUnlocked = false
        errorMessage = nil
    }

    func addDocument(data: Data, name: String, category: VaultDocument.Category, fileExtension: String) throws {
        guard let key = encryptionKey, isUnlocked else { throw VaultError.locked }
        let id = UUID()
        let encryptedFilename = "\(id.uuidString).vault"
        let encryptedURL = directory.appendingPathComponent(encryptedFilename)
        let sealed = try AES.GCM.seal(data, using: key)
        guard let combined = sealed.combined else { throw VaultError.encryptionFailed }
        try combined.write(to: encryptedURL, options: [.atomic, .completeFileProtection])

        let document = VaultDocument(
            id: id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Documento" : name,
            category: category,
            encryptedFilename: encryptedFilename,
            fileExtension: sanitizedExtension(fileExtension),
            importedAt: Date(),
            originalSize: data.count
        )
        documents.append(document)
        documents.sort { $0.importedAt > $1.importedAt }
        do {
            try saveManifest()
        } catch {
            documents.removeAll { $0.id == id }
            try? FileManager.default.removeItem(at: encryptedURL)
            throw error
        }
    }

    func importFile(_ url: URL, category: VaultDocument.Category) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        try addDocument(data: data, name: url.deletingPathExtension().lastPathComponent, category: category, fileExtension: url.pathExtension)
    }

    func delete(_ document: VaultDocument) {
        guard isUnlocked else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(document.encryptedFilename))
        documents.removeAll { $0.id == document.id }
        do { try saveManifest() } catch { errorMessage = "Não foi possível atualizar o cofre." }
    }

    func previewURL(for document: VaultDocument) throws -> URL {
        guard let key = encryptionKey, isUnlocked else { throw VaultError.locked }
        let encrypted = try Data(contentsOf: directory.appendingPathComponent(document.encryptedFilename))
        let sealedBox = try AES.GCM.SealedBox(combined: encrypted)
        let plain = try AES.GCM.open(sealedBox, using: key)
        let previewDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("JapanTripVaultPreview", isDirectory: true)
        try FileManager.default.createDirectory(at: previewDirectory, withIntermediateDirectories: true)
        let filename = sanitizedFilename(document.name) + (document.fileExtension.isEmpty ? "" : ".\(document.fileExtension)")
        let url = previewDirectory.appendingPathComponent("\(document.id.uuidString)-\(filename)")
        try plain.write(to: url, options: [.atomic, .completeFileProtection])
        previewURLs.insert(url)
        return url
    }

    func cleanupPreview(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        previewURLs.remove(url)
    }

    func unlockForTesting(with key: SymmetricKey) throws {
        encryptionKey = key
        documents = try loadManifest()
        isUnlocked = true
    }

    private func loadManifest() throws -> [VaultDocument] {
        guard let key = encryptionKey else { throw VaultError.locked }
        let url = manifestURL
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let encrypted = try Data(contentsOf: url)
        let sealedBox = try AES.GCM.SealedBox(combined: encrypted)
        let plain = try AES.GCM.open(sealedBox, using: key)
        return try JSONDecoder().decode([VaultDocument].self, from: plain)
    }

    private func saveManifest() throws {
        guard let key = encryptionKey else { throw VaultError.locked }
        let plain = try JSONEncoder().encode(documents)
        let sealed = try AES.GCM.seal(plain, using: key)
        guard let combined = sealed.combined else { throw VaultError.encryptionFailed }
        try combined.write(to: manifestURL, options: [.atomic, .completeFileProtection])
    }

    private var manifestURL: URL { directory.appendingPathComponent("manifest.vault") }

    private func cleanupAllPreviews() {
        previewURLs.forEach { try? FileManager.default.removeItem(at: $0) }
        previewURLs.removeAll()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("JapanTripVaultPreview", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
    }

    private func sanitizedExtension(_ value: String) -> String {
        String(value.lowercased().filter { $0.isLetter || $0.isNumber }.prefix(10))
    }

    private func sanitizedFilename(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        return value.components(separatedBy: invalid).joined(separator: "-")
    }
}

private enum VaultError: Error {
    case locked
    case encryptionFailed
}

struct DocumentVaultView: View {
    @EnvironmentObject private var navigation: AppNavigationState
    @EnvironmentObject private var vault: DocumentVaultStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: VaultDocument.Category = .passport
    @State private var showsFileImporter = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var previewURL: URL?

    var body: some View {
        Group {
            if vault.isUnlocked { unlockedContent } else { lockedContent }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Cofre")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                    navigation.goHome()
                } label: { Label("Início", systemImage: "house.fill") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if vault.isUnlocked {
                    Button { vault.lock() } label: { Label("Bloquear", systemImage: "lock.fill") }
                } else {
                    Button("Fechar") { dismiss() }
                }
            }
        }
        .task { if !vault.isUnlocked { await vault.unlock() } }
        .fileImporter(isPresented: $showsFileImporter, allowedContentTypes: [.pdf, .image, .data, .item], allowsMultipleSelection: true) { result in
            do {
                for url in try result.get() { try vault.importFile(url, category: selectedCategory) }
            } catch { vault.errorMessage = "Não foi possível importar o ficheiro." }
        }
        .onChange(of: photoItems) { _, items in
            Task {
                for (index, item) in items.enumerated() {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        try? vault.addDocument(data: data, name: "Imagem \(index + 1)", category: selectedCategory, fileExtension: "jpg")
                    }
                }
                photoItems = []
            }
        }
        .sheet(isPresented: Binding(get: { previewURL != nil }, set: { if !$0, let url = previewURL { vault.cleanupPreview(url); previewURL = nil } })) {
            if let previewURL { QuickLookPreview(url: previewURL).ignoresSafeArea() }
        }
    }

    private var lockedContent: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "lock.doc.fill")
                .font(.system(size: 68))
                .foregroundStyle(.indigo)
            Text("Cofre protegido").font(.title.bold())
            Text("Passaportes, seguros, bilhetes, reservas e QR Codes cifrados no aparelho.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button {
                Task { await vault.unlock() }
            } label: {
                HStack {
                    if vault.isWorking { ProgressView().tint(.white) }
                    Label("Abrir com Face ID", systemImage: "faceid")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(vault.isWorking)
            if let error = vault.errorMessage { Text(error).font(.caption).foregroundStyle(.orange).multilineTextAlignment(.center) }
            Spacer()
        }
        .padding(32)
    }

    private var unlockedContent: some View {
        List {
            Section {
                Picker("Categoria", selection: $selectedCategory) {
                    ForEach(VaultDocument.Category.allCases) { category in
                        Label(category.rawValue, systemImage: category.symbol).tag(category)
                    }
                }
                Button { showsFileImporter = true } label: { Label("Adicionar ficheiros", systemImage: "doc.badge.plus") }
                PhotosPicker(selection: $photoItems, maxSelectionCount: 20, matching: .images) {
                    Label("Adicionar foto ou QR Code", systemImage: "photo.badge.plus")
                }
            } header: {
                Text("Adicionar a \(selectedCategory.rawValue)")
            }

            ForEach(VaultDocument.Category.allCases) { category in
                let items = vault.documents.filter { $0.category == category }
                if !items.isEmpty {
                    Section(category.rawValue) {
                        ForEach(items) { document in
                            Button {
                                do { previewURL = try vault.previewURL(for: document) }
                                catch { vault.errorMessage = "Não foi possível abrir o documento." }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: category.symbol)
                                        .foregroundStyle(category.color)
                                        .frame(width: 36, height: 36)
                                        .background(category.color.opacity(0.10), in: Circle())
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(document.name).foregroundStyle(.primary)
                                        Text("\(ByteCountFormatter.string(fromByteCount: Int64(document.originalSize), countStyle: .file)) · \(document.importedAt.formatted(date: .abbreviated, time: .shortened))")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .onDelete { offsets in offsets.map { items[$0] }.forEach(vault.delete) }
                    }
                }
            }

            if vault.documents.isEmpty {
                Section {
                    ContentUnavailableView("Cofre vazio", systemImage: "lock.doc", description: Text("Adicione PDFs, imagens, bilhetes e QR Codes. Tudo será cifrado antes de ser guardado."))
                }
            }
            Section {
                Label("AES-256-GCM · chave biométrica no Keychain · sem backup na nuvem", systemImage: "checkmark.shield.fill")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }
    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }
    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { url as NSURL }
    }
}
