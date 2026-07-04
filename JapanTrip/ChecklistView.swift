import SwiftUI

struct ChecklistCloudRecord: Codable, Hashable {
    let id: String
    let title: String
    let section: String
    let scope: String
    let isCompleted: Bool
    let ownerUserID: UUID?
    let ownerEmail: String?

    enum CodingKeys: String, CodingKey {
        case id, title, section, scope
        case isCompleted = "is_completed"
        case ownerUserID = "owner_user_id"
        case ownerEmail = "owner_email"
    }

    var item: ChecklistItem? {
        guard let section = ChecklistItem.Section(rawValue: section),
              let scope = ChecklistItem.Scope(rawValue: scope) else { return nil }
        return .init(id: id, title: title, section: section, scope: scope)
    }
}

protocol ChecklistSharingServicing {
    func fetch(accessToken: String) async throws -> [ChecklistCloudRecord]
    func upsert(_ record: ChecklistCloudRecord, accessToken: String) async throws
    func delete(id: String, accessToken: String) async throws
}

struct SupabaseChecklistSharingService: ChecklistSharingServicing {
    private let projectURL = URL(string: "https://oiprckdaqhgganwtxcui.supabase.co")!
    private let publishableKey = "sb_publishable_GYwIq70ROI6Rx6LzMyASJA_4DtkY5hL"
    private let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func fetch(accessToken: String) async throws -> [ChecklistCloudRecord] {
        var components = URLComponents(url: projectURL.appending(path: "rest/v1/trip_checklist_items"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "select", value: "id,title,section,scope,is_completed,owner_user_id,owner_email"),
            .init(name: "order", value: "scope.asc,created_at.asc")
        ]
        var request = authorizedRequest(url: components.url!, accessToken: accessToken)
        request.httpMethod = "GET"
        return try JSONDecoder().decode([ChecklistCloudRecord].self, from: try await perform(request))
    }

    func upsert(_ record: ChecklistCloudRecord, accessToken: String) async throws {
        var components = URLComponents(url: projectURL.appending(path: "rest/v1/trip_checklist_items"), resolvingAgainstBaseURL: false)!
        components.queryItems = [.init(name: "on_conflict", value: "id")]
        var request = authorizedRequest(url: components.url!, accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONEncoder().encode(record)
        _ = try await perform(request)
    }

    func delete(id: String, accessToken: String) async throws {
        var components = URLComponents(url: projectURL.appending(path: "rest/v1/trip_checklist_items"), resolvingAgainstBaseURL: false)!
        components.queryItems = [.init(name: "id", value: "eq.\(id)")]
        var request = authorizedRequest(url: components.url!, accessToken: accessToken)
        request.httpMethod = "DELETE"
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        _ = try await perform(request)
    }

    private func authorizedRequest(url: URL, accessToken: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ChecklistSharingError.invalidResponse }
        guard 200..<300 ~= http.statusCode else {
            if http.statusCode == 401 { throw SupabaseAuthError.invalidCredentials }
            let message = (try? JSONDecoder().decode(ChecklistServiceError.self, from: data).message)
            throw ChecklistSharingError.server(message ?? "Não foi possível sincronizar a checklist.")
        }
        return data
    }
}

private struct ChecklistServiceError: Decodable { let message: String? }
private enum ChecklistSharingError: LocalizedError {
    case invalidResponse
    case server(String)
    var errorDescription: String? {
        switch self {
        case .invalidResponse: "Resposta inválida do serviço de checklist."
        case .server(let message): message
        }
    }
}

struct ChecklistView: View {
    @EnvironmentObject private var tripState: TripState
    @EnvironmentObject private var authentication: AuthenticationManager
    @State private var editingItem: ChecklistItem?
    @State private var showsNewItem = false
    @State private var showsRestoreConfirmation = false
    @State private var selectedScope: ChecklistItem.Scope = .general

    private var visibleItems: [ChecklistItem] { tripState.items(in: selectedScope) }

    private var completedCount: Int {
        visibleItems.filter(tripState.isCompleted).count
    }

    var body: some View {
        List {
            Section {
                Picker("Tipo de checklist", selection: $selectedScope) {
                    ForEach(ChecklistItem.Scope.allCases) { scope in
                        Label(scope.title, systemImage: scope.symbol).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                Text(selectedScope.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Preparação").font(.headline)
                        Spacer()
                        Text("\(completedCount)/\(visibleItems.count)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    ProgressView(value: Double(completedCount), total: Double(max(visibleItems.count, 1))).tint(.indigo)
                    if tripState.isSyncingChecklist {
                        Label("A sincronizar…", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if let date = tripState.checklistLastSyncedAt {
                        Label("Sincronizada \(date.formatted(.relative(presentation: .named)))", systemImage: "checkmark.circle.fill")
                            .font(.caption).foregroundStyle(.green)
                    }
                }
                .padding(.vertical, 6)
            }

            ForEach(ChecklistItem.Section.allCases, id: \.rawValue) { section in
                Section(section.rawValue) {
                    ForEach(visibleItems.filter { $0.section == section }) { item in
                        Button {
                            withAnimation(.snappy) { tripState.toggle(item) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: tripState.isCompleted(item) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(tripState.isCompleted(item) ? .green : .secondary)
                                Text(item.title)
                                    .foregroundStyle(tripState.isCompleted(item) ? .secondary : .primary)
                                    .strikethrough(tripState.isCompleted(item))
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                tripState.deleteChecklistItem(item)
                            } label: {
                                Label("Apagar", systemImage: "trash")
                            }
                            Button {
                                editingItem = item
                            } label: {
                                Label("Editar", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                }
            }
        }
        .navigationTitle("Checklist")
        .listStyle(.insetGrouped)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                HStack {
                    Button {
                        showsRestoreConfirmation = true
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .accessibilityLabel("Restaurar checklist")
                    }
                    Button {
                        Task { await tripState.syncChecklist(authentication: authentication) }
                    } label: {
                        if tripState.isSyncingChecklist { ProgressView() }
                        else { Image(systemName: "arrow.triangle.2.circlepath") }
                    }
                    .disabled(tripState.isSyncingChecklist)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsNewItem = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .accessibilityLabel("Adicionar item")
                }
            }
        }
        .sheet(isPresented: $showsNewItem) {
            ChecklistEditorView(mode: .new(selectedScope))
                .environmentObject(tripState)
        }
        .sheet(item: $editingItem) { item in
            ChecklistEditorView(mode: .edit(item))
                .environmentObject(tripState)
        }
        .confirmationDialog("Restaurar checklist \(selectedScope.title.lowercased())?", isPresented: $showsRestoreConfirmation) {
            Button("Restaurar", role: .destructive) { tripState.restoreDefaultChecklist(scope: selectedScope) }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text(selectedScope == .general
                 ? "A lista geral voltará aos itens originais para todo o grupo."
                 : "Todos os teus itens pessoais serão removidos.")
        }
        .task { await tripState.syncChecklist(authentication: authentication) }
        .alert("Sincronização da checklist", isPresented: Binding(
            get: { tripState.checklistErrorMessage != nil },
            set: { if !$0 { tripState.checklistErrorMessage = nil } }
        )) {
            Button("OK") { tripState.checklistErrorMessage = nil }
        } message: {
            Text(tripState.checklistErrorMessage ?? "")
        }
    }
}

private struct ChecklistEditorView: View {
    enum Mode {
        case new(ChecklistItem.Scope)
        case edit(ChecklistItem)
    }

    @EnvironmentObject private var tripState: TripState
    @Environment(\.dismiss) private var dismiss
    let mode: Mode
    @State private var title: String
    @State private var section: ChecklistItem.Section
    @State private var scope: ChecklistItem.Scope

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .new(let scope):
            _title = State(initialValue: "")
            _section = State(initialValue: .before)
            _scope = State(initialValue: scope)
        case .edit(let item):
            _title = State(initialValue: item.title)
            _section = State(initialValue: item.section)
            _scope = State(initialValue: item.scope)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    TextField("O que precisa ser feito?", text: $title, axis: .vertical)
                        .lineLimit(2...4)
                    Picker("Grupo", selection: $section) {
                        ForEach(ChecklistItem.Section.allCases, id: \.rawValue) { section in
                            Text(section.rawValue).tag(section)
                        }
                    }
                    LabeledContent("Checklist", value: scope.title)
                }
            }
            .navigationTitle(isNew ? "Novo item" : "Editar item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var isNew: Bool {
        if case .new = mode { return true }
        return false
    }

    private func save() {
        switch mode {
        case .new:
            tripState.addChecklistItem(title: title, section: section, scope: scope)
        case .edit(let item):
            tripState.updateChecklistItem(item, title: title, section: section)
        }
        dismiss()
    }
}
