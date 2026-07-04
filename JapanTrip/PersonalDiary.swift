import Foundation
import SwiftUI

struct PersonalDiaryEntry: Identifiable, Codable, Hashable {
    let dayID: String
    let userID: UUID
    let email: String
    var note: String
    var mood: Int
    var highlight: String
    let createdAt: String?
    let updatedAt: String?

    var id: String { "\(dayID)-\(userID.uuidString.lowercased())" }

    enum CodingKeys: String, CodingKey {
        case dayID = "day_id"
        case userID = "user_id"
        case email, note, mood, highlight
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

protocol PersonalDiaryServicing {
    func fetch(accessToken: String) async throws -> [PersonalDiaryEntry]
    func upsert(_ entry: PersonalDiaryEntry, accessToken: String) async throws
}

struct SupabasePersonalDiaryService: PersonalDiaryServicing {
    private let projectURL = URL(string: "https://oiprckdaqhgganwtxcui.supabase.co")!
    private let publishableKey = "sb_publishable_GYwIq70ROI6Rx6LzMyASJA_4DtkY5hL"
    private let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func fetch(accessToken: String) async throws -> [PersonalDiaryEntry] {
        var components = URLComponents(url: projectURL.appending(path: "rest/v1/trip_personal_diary"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "select", value: "day_id,user_id,email,note,mood,highlight,created_at,updated_at"),
            .init(name: "order", value: "day_id.asc")
        ]
        var request = authorizedRequest(url: components.url!, accessToken: accessToken)
        request.httpMethod = "GET"
        return try JSONDecoder().decode([PersonalDiaryEntry].self, from: try await perform(request))
    }

    func upsert(_ entry: PersonalDiaryEntry, accessToken: String) async throws {
        var components = URLComponents(url: projectURL.appending(path: "rest/v1/trip_personal_diary"), resolvingAgainstBaseURL: false)!
        components.queryItems = [.init(name: "on_conflict", value: "day_id,user_id")]
        var request = authorizedRequest(url: components.url!, accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONEncoder().encode(entry)
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
        guard let response = response as? HTTPURLResponse else { throw PersonalDiaryError.invalidResponse }
        guard 200..<300 ~= response.statusCode else {
            if response.statusCode == 401 { throw SupabaseAuthError.invalidCredentials }
            let message = (try? JSONDecoder().decode(PersonalDiaryServiceError.self, from: data).message)
            throw PersonalDiaryError.server(message ?? "Não foi possível sincronizar o diário.")
        }
        return data
    }
}

@MainActor
final class PersonalDiaryStore: ObservableObject {
    @Published private(set) var entries: [PersonalDiaryEntry] = []
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncedAt: Date?
    @Published var errorMessage: String?

    private let service: any PersonalDiaryServicing
    private let defaults: UserDefaults
    private var currentEmail: String?
    private var pendingDayIDs: Set<String> = []

    init(service: any PersonalDiaryServicing = SupabasePersonalDiaryService(), defaults: UserDefaults = .standard) {
        self.service = service
        self.defaults = defaults
    }

    func configure(authentication: AuthenticationManager) {
        guard let email = authentication.authenticatedEmail?.lowercased(), email != currentEmail else { return }
        currentEmail = email
        entries = decode([PersonalDiaryEntry].self, key: cacheKey(email)) ?? []
        pendingDayIDs = Set(defaults.stringArray(forKey: pendingKey(email)) ?? [])
    }

    func entry(for day: TripDay, authentication: AuthenticationManager) -> PersonalDiaryEntry? {
        configure(authentication: authentication)
        return entries.first { $0.dayID == day.id }
    }

    func save(day: TripDay, note: String, mood: Int, highlight: String, authentication: AuthenticationManager) async {
        configure(authentication: authentication)
        guard let userID = authentication.authenticatedUserID,
              let email = authentication.authenticatedEmail else { return }
        let existing = entries.first { $0.dayID == day.id }
        let entry = PersonalDiaryEntry(
            dayID: day.id,
            userID: userID,
            email: email.lowercased(),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            mood: min(max(mood, 1), 5),
            highlight: highlight.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: existing?.createdAt,
            updatedAt: existing?.updatedAt
        )
        entries.removeAll { $0.dayID == day.id }
        entries.append(entry)
        pendingDayIDs.insert(day.id)
        persist()
        await sync(authentication: authentication)
    }

    func sync(authentication: AuthenticationManager) async {
        configure(authentication: authentication)
        guard authentication.isAuthenticated, !isSyncing, currentEmail != nil else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let token = try await authentication.accessTokenForAPI()
            for entry in entries where pendingDayIDs.contains(entry.dayID) {
                try await service.upsert(entry, accessToken: token)
                pendingDayIDs.remove(entry.dayID)
            }
            let remote = try await service.fetch(accessToken: token)
            let localPending = entries.filter { pendingDayIDs.contains($0.dayID) }
            let pendingIDs = Set(localPending.map(\.dayID))
            entries = remote.filter { !pendingIDs.contains($0.dayID) } + localPending
            lastSyncedAt = Date()
            errorMessage = nil
            persist()
        } catch {
            errorMessage = "O diário ficou guardado no aparelho. Sincronização pendente: \(error.localizedDescription)"
            persist()
        }
    }

    static func automaticSummary(for day: TripDay) -> String {
        let activities = day.activities.map(\.title)
        guard !activities.isEmpty else { return "Um dia livre para descobrir \(day.city.rawValue)." }
        if activities.count == 1 { return "O plano do dia é \(activities[0])." }
        return "Hoje: \(activities.dropLast().joined(separator: ", ")) e \(activities.last!)."
    }

    private func persist() {
        guard let email = currentEmail else { return }
        defaults.set(try? JSONEncoder().encode(entries), forKey: cacheKey(email))
        defaults.set(Array(pendingDayIDs), forKey: pendingKey(email))
    }

    private func decode<T: Decodable>(_ type: T.Type, key: String) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    private func cacheKey(_ email: String) -> String { "personalDiary.\(email).cache" }
    private func pendingKey(_ email: String) -> String { "personalDiary.\(email).pending" }
}

struct PersonalDiaryView: View {
    @EnvironmentObject private var diary: PersonalDiaryStore
    @EnvironmentObject private var authentication: AuthenticationManager
    @EnvironmentObject private var navigation: AppNavigationState

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("O diário de \(authentication.authenticatedName ?? "viajante")", systemImage: "book.closed.fill")
                        .font(.headline)
                    Text("Cada página é criada a partir do roteiro. As tuas notas e emoções são privadas e só aparecem na tua conta.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            Section("Julho de 2026") {
                ForEach(TripData.days) { day in
                    NavigationLink {
                        PersonalDiaryEditor(day: day)
                    } label: {
                        DiaryDayRow(day: day, entry: diary.entry(for: day, authentication: authentication))
                    }
                }
            }
        }
        .navigationTitle("Meu Diário")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Home", systemImage: "house.fill") { navigation.goHome() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if diary.isSyncing { ProgressView() }
                else { Button("Sincronizar", systemImage: "arrow.triangle.2.circlepath") { Task { await diary.sync(authentication: authentication) } } }
            }
        }
        .task { await diary.sync(authentication: authentication) }
        .alert("Diário", isPresented: Binding(get: { diary.errorMessage != nil }, set: { if !$0 { diary.errorMessage = nil } })) {
            Button("OK") { diary.errorMessage = nil }
        } message: { Text(diary.errorMessage ?? "") }
    }
}

private struct DiaryDayRow: View {
    let day: TripDay
    let entry: PersonalDiaryEntry?

    var body: some View {
        HStack(spacing: 12) {
            VStack {
                Text(day.date.formatted(.dateTime.day())).font(.title3.bold())
                Text(day.date.formatted(.dateTime.month(.abbreviated))).font(.caption).textCase(.uppercase)
            }
            .frame(width: 45).foregroundStyle(.indigo)
            VStack(alignment: .leading, spacing: 4) {
                Text(day.title).font(.headline)
                Text(entry?.highlight.isEmpty == false ? entry!.highlight : PersonalDiaryStore.automaticSummary(for: day))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            if let entry {
                Text(String(repeating: "★", count: entry.mood)).font(.caption).foregroundStyle(.orange)
            } else {
                Image(systemName: "sparkles").foregroundStyle(.indigo)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct PersonalDiaryEditor: View {
    let day: TripDay
    @EnvironmentObject private var diary: PersonalDiaryStore
    @EnvironmentObject private var authentication: AuthenticationManager
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var highlight = ""
    @State private var mood = 5
    @State private var isSaving = false
    @State private var isRewriting = false
    @State private var didLoad = false
    @State private var aiErrorMessage: String?
    @StateObject private var voiceRecorder = DiaryVoiceRecorder()

    var body: some View {
        Form {
            Section("Página automática") {
                Text(PersonalDiaryStore.automaticSummary(for: day))
                ForEach(day.activities) { activity in
                    Label("\(activity.time) · \(activity.title)", systemImage: activity.kind.symbol)
                        .font(.subheadline)
                }
            }
            Section("Como foi o teu dia?") {
                HStack {
                    ForEach(1...5, id: \.self) { value in
                        Button { mood = value } label: {
                            Image(systemName: value <= mood ? "star.fill" : "star")
                                .font(.title2).foregroundStyle(.orange)
                        }.buttonStyle(.plain)
                    }
                }
                TextField("O melhor momento do dia", text: $highlight)
                TextEditor(text: $note).frame(minHeight: 150)
            }
            Section {
                Button {
                    Task { await voiceRecorder.toggleRecording() }
                } label: {
                    Label(
                        voiceRecorder.isRecording ? "Parar ditado" : "Começar a ditar",
                        systemImage: voiceRecorder.isRecording ? "stop.circle.fill" : "mic.circle.fill"
                    )
                    .foregroundStyle(voiceRecorder.isRecording ? .red : .indigo)
                }
                if voiceRecorder.isRecording {
                    Label("A ouvir… fala naturalmente sobre o teu dia.", systemImage: "waveform")
                        .font(.caption).foregroundStyle(.red)
                }
                TextEditor(text: $voiceRecorder.transcript)
                    .frame(minHeight: 110)
                    .overlay(alignment: .topLeading) {
                        if voiceRecorder.transcript.isEmpty {
                            Text("A transcrição aparecerá aqui e poderá ser corrigida antes de enviar à IA.")
                                .font(.subheadline).foregroundStyle(.tertiary).padding(.top, 8).padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
                Button {
                    voiceRecorder.stop()
                    isRewriting = true
                    Task { await rewriteDictation() }
                } label: {
                    HStack {
                        Spacer()
                        if isRewriting { ProgressView() }
                        else { Label("Transformar em diário com IA", systemImage: "sparkles") }
                        Spacer()
                    }
                }
                .disabled(isRewriting || voiceRecorder.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button {
                    appendTranscriptToNote()
                } label: {
                    Label("Usar transcrição sem IA", systemImage: "text.append")
                }
                .disabled(voiceRecorder.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: {
                Text("Contar por voz")
            } footer: {
                Text("A IA organiza apenas o que foi dito. Revê sempre o resultado antes de guardar.")
            }
            Section {
                Button {
                    isSaving = true
                    Task {
                        let finalNote = note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? voiceRecorder.transcript
                            : note
                        await diary.save(day: day, note: finalNote, mood: mood, highlight: highlight, authentication: authentication)
                        isSaving = false
                        dismiss()
                    }
                } label: {
                    HStack { Spacer(); if isSaving { ProgressView() } else { Label("Guardar memória", systemImage: "checkmark.circle.fill") }; Spacer() }
                }
                .disabled(isSaving)
            } footer: {
                Text("Guardado primeiro no aparelho e sincronizado de forma privada quando houver internet.")
            }
        }
        .navigationTitle(day.date.formatted(.dateTime.day().month(.wide)))
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { voiceRecorder.stop() }
        .alert("Assistente do diário", isPresented: Binding(
            get: { voiceRecorder.errorMessage != nil || aiErrorMessage != nil },
            set: { if !$0 { voiceRecorder.errorMessage = nil; aiErrorMessage = nil } }
        )) {
            Button("OK") { voiceRecorder.errorMessage = nil; aiErrorMessage = nil }
        } message: {
            Text(voiceRecorder.errorMessage ?? aiErrorMessage ?? "")
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            if let entry = diary.entry(for: day, authentication: authentication) {
                note = entry.note; highlight = entry.highlight; mood = entry.mood
            }
        }
    }

    private func rewriteDictation() async {
        defer { isRewriting = false }
        do {
            let token = try await authentication.accessTokenForAPI()
            let result = try await DiaryAIService().rewrite(
                transcript: voiceRecorder.transcript,
                day: day,
                accessToken: token
            )
            note = result.text
            if highlight.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let suggestedHighlight = result.highlight {
                highlight = suggestedHighlight
            }
        } catch {
            aiErrorMessage = error.localizedDescription
        }
    }

    private func appendTranscriptToNote() {
        let spokenText = voiceRecorder.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spokenText.isEmpty else { return }
        let existing = note.trimmingCharacters(in: .whitespacesAndNewlines)
        note = existing.isEmpty ? spokenText : existing + "\n\n" + spokenText
    }
}

private struct PersonalDiaryServiceError: Decodable { let message: String? }
private enum PersonalDiaryError: LocalizedError {
    case invalidResponse
    case server(String)
    var errorDescription: String? {
        switch self {
        case .invalidResponse: "Resposta inválida do serviço do diário."
        case .server(let message): message
        }
    }
}
