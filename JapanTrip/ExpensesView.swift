import Charts
import SwiftUI

enum TripCurrency: String, CaseIterable, Codable, Identifiable {
    case BRL, AED, JPY, EUR, USD
    var id: String { rawValue }
    var symbol: String {
        switch self { case .BRL: "R$"; case .AED: "د.إ"; case .JPY: "¥"; case .EUR: "€"; case .USD: "$" }
    }
    var name: String {
        switch self { case .BRL: "Real brasileiro"; case .AED: "Dirham dos EAU"; case .JPY: "Iene japonês"; case .EUR: "Euro"; case .USD: "Dólar americano" }
    }
}

struct TripExpense: Identifiable, Codable, Hashable {
    enum Category: String, CaseIterable, Codable, Identifiable {
        case food = "Alimentação"
        case transport = "Transporte"
        case shopping = "Compras"
        case attraction = "Atrações"
        case hotel = "Hotel"
        case other = "Outros"

        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .food: "fork.knife"
            case .transport: "tram.fill"
            case .shopping: "bag.fill"
            case .attraction: "ticket.fill"
            case .hotel: "bed.double.fill"
            case .other: "creditcard.fill"
            }
        }
        var color: Color {
            switch self {
            case .food: .orange
            case .transport: .blue
            case .shopping: .pink
            case .attraction: .purple
            case .hotel: .indigo
            case .other: .gray
            }
        }
    }

    let id: UUID
    var title: String
    var amount: Double
    var currency: TripCurrency
    var date: Date
    var category: Category
    var payerEmail: String
    var participantEmails: Set<String>
    var note: String
    var createdByEmail: String? = nil
}

@MainActor
final class ExpenseStore: ObservableObject {
    @Published private(set) var expenses: [TripExpense] = []
    @Published private(set) var ratesPerBRL: [TripCurrency: Double] = [.BRL: 1, .AED: 0.68, .JPY: 27.5, .EUR: 0.16, .USD: 0.18]
    @Published private(set) var ratesUpdatedAt: Date?
    @Published private(set) var isRefreshingRates = false
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncedAt: Date?
    @Published var errorMessage: String?
    @Published var dailyBudgetBRL: Double {
        didSet { UserDefaults.standard.set(dailyBudgetBRL, forKey: budgetKey) }
    }

    private let directory: URL
    private let session: URLSession
    private let sharingService: any TripSharingServicing
    private weak var authentication: AuthenticationManager?
    private var pendingDeletionIDs: Set<UUID> = []
    private var pendingUploadIDs: Set<UUID> = []
    private let budgetKey = "expenses.dailyBudgetBRL"
    private let ratesKey = "expenses.exchangeRates"
    private let ratesDateKey = "expenses.exchangeRatesDate"

    init(
        directory: URL? = nil,
        session: URLSession = .shared,
        sharingService: any TripSharingServicing = SupabaseTripSharingService()
    ) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("JapanTripExpenses", isDirectory: true)
        self.session = session
        self.sharingService = sharingService
        let savedBudget = UserDefaults.standard.double(forKey: budgetKey)
        self.dailyBudgetBRL = savedBudget > 0 ? savedBudget : 1_500
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        load()
    }

    func configureSharing(authentication: AuthenticationManager) {
        self.authentication = authentication
    }

    func add(_ newExpense: TripExpense) {
        var expense = newExpense
        expense.createdByEmail = expense.createdByEmail ?? authentication?.authenticatedEmail
        expenses.append(expense)
        pendingUploadIDs.insert(expense.id)
        expenses.sort { $0.date > $1.date }
        save()
        Task { await upload(expense) }
    }

    func delete(_ expense: TripExpense) {
        expenses.removeAll { $0.id == expense.id }
        pendingUploadIDs.remove(expense.id)
        pendingDeletionIDs.insert(expense.id)
        save()
        Task { await flushDeletion(id: expense.id) }
    }

    func sync(authentication: AuthenticationManager) async {
        configureSharing(authentication: authentication)
        guard authentication.isAuthenticated, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        do {
            let token = try await authentication.accessTokenForAPI()
            for id in pendingDeletionIDs {
                try await sharingService.deleteExpense(id: id, accessToken: token)
                pendingDeletionIDs.remove(id)
            }
            guard let userID = authentication.authenticatedUserID,
                  let email = authentication.authenticatedEmail else { return }
            for expense in expenses where pendingUploadIDs.contains(expense.id) {
                try await sharingService.upsertExpense(
                    expense, ownerUserID: userID,
                    ownerEmail: expense.createdByEmail ?? email,
                    accessToken: token
                )
                pendingUploadIDs.remove(expense.id)
            }
            expenses = try await sharingService.fetchExpenses(accessToken: token).sorted { $0.date > $1.date }
            lastSyncedAt = Date()
            errorMessage = nil
            save()
        } catch {
            errorMessage = "Sem sincronização neste momento — as despesas continuam guardadas neste aparelho."
        }
    }

    func amountInBRL(_ expense: TripExpense) -> Double {
        expense.amount / max(ratesPerBRL[expense.currency] ?? 1, 0.000_001)
    }

    func converted(_ amount: Double, from currency: TripCurrency, to target: TripCurrency) -> Double {
        let inBRL = amount / max(ratesPerBRL[currency] ?? 1, 0.000_001)
        return inBRL * (ratesPerBRL[target] ?? 1)
    }

    func totalBRL(on date: Date? = nil) -> Double {
        expenses.filter { expense in
            guard let date else { return true }
            return Calendar.current.isDate(expense.date, inSameDayAs: date)
        }.reduce(0) { $0 + amountInBRL($1) }
    }

    func categoryTotalsBRL() -> [(category: TripExpense.Category, amount: Double)] {
        TripExpense.Category.allCases.map { category in
            (category, expenses.filter { $0.category == category }.reduce(0) { $0 + amountInBRL($1) })
        }.filter { $0.amount > 0 }
    }

    func balancesBRL() -> [String: Double] {
        var balances = Dictionary(uniqueKeysWithValues: TripParticipant.all.map { ($0.email, 0.0) })
        for expense in expenses where !expense.participantEmails.isEmpty {
            let value = amountInBRL(expense)
            balances[expense.payerEmail, default: 0] += value
            let share = value / Double(expense.participantEmails.count)
            for email in expense.participantEmails { balances[email, default: 0] -= share }
        }
        return balances
    }

    func refreshRates(force: Bool = false) async {
        if !force, let ratesUpdatedAt, Date().timeIntervalSince(ratesUpdatedAt) < 43_200 { return }
        isRefreshingRates = true
        errorMessage = nil
        defer { isRefreshingRates = false }
        var components = URLComponents(string: "https://api.frankfurter.dev/v2/rates")!
        components.queryItems = [.init(name: "base", value: "BRL"), .init(name: "quotes", value: "AED,JPY,EUR,USD")]
        do {
            let (data, response) = try await session.data(from: components.url!)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { throw URLError(.badServerResponse) }
            let records = try JSONDecoder().decode([ExchangeRateRecord].self, from: data)
            var updated = ratesPerBRL
            updated[.BRL] = 1
            for record in records {
                if let currency = TripCurrency(rawValue: record.quote) { updated[currency] = record.rate }
            }
            guard updated[.AED] != nil, updated[.JPY] != nil, updated[.EUR] != nil, updated[.USD] != nil else { throw URLError(.cannotParseResponse) }
            ratesPerBRL = updated
            ratesUpdatedAt = Date()
            cacheRates()
        } catch {
            errorMessage = ratesUpdatedAt == nil
                ? "Sem internet — usando taxas aproximadas até à primeira atualização."
                : "Sem internet — usando as últimas taxas guardadas."
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(expenses) else { return }
        try? data.write(to: expensesURL, options: [.atomic, .completeFileProtection])
        UserDefaults.standard.set(pendingDeletionIDs.map(\.uuidString), forKey: pendingDeletionsKey)
        UserDefaults.standard.set(pendingUploadIDs.map(\.uuidString), forKey: pendingUploadsKey)
    }

    private func load() {
        if let data = try? Data(contentsOf: expensesURL), let decoded = try? JSONDecoder().decode([TripExpense].self, from: data) {
            expenses = decoded.sorted { $0.date > $1.date }
        }
        if let data = UserDefaults.standard.data(forKey: ratesKey),
           let decoded = try? JSONDecoder().decode([TripCurrency: Double].self, from: data) {
            ratesPerBRL = decoded
        }
        ratesUpdatedAt = UserDefaults.standard.object(forKey: ratesDateKey) as? Date
        pendingDeletionIDs = Set((UserDefaults.standard.stringArray(forKey: pendingDeletionsKey) ?? []).compactMap(UUID.init(uuidString:)))
        if UserDefaults.standard.object(forKey: pendingUploadsKey) == nil {
            // First version with cloud sharing: publish existing offline records once.
            pendingUploadIDs = Set(expenses.map(\.id))
        } else {
            pendingUploadIDs = Set((UserDefaults.standard.stringArray(forKey: pendingUploadsKey) ?? []).compactMap(UUID.init(uuidString:)))
        }
    }

    private func cacheRates() {
        UserDefaults.standard.set(try? JSONEncoder().encode(ratesPerBRL), forKey: ratesKey)
        UserDefaults.standard.set(ratesUpdatedAt, forKey: ratesDateKey)
    }

    private var expensesURL: URL { directory.appendingPathComponent("expenses.json") }
    private var pendingDeletionsKey: String { "expenses.pendingDeletions.\(directory.path)" }
    private var pendingUploadsKey: String { "expenses.pendingUploads.\(directory.path)" }

    private func upload(_ expense: TripExpense) async {
        guard let authentication, authentication.isAuthenticated,
              let userID = authentication.authenticatedUserID,
              let email = authentication.authenticatedEmail else { return }
        do {
            let token = try await authentication.accessTokenForAPI()
            try await sharingService.upsertExpense(
                expense, ownerUserID: userID,
                ownerEmail: expense.createdByEmail ?? email,
                accessToken: token
            )
            pendingUploadIDs.remove(expense.id)
            save()
            lastSyncedAt = Date()
        } catch {
            errorMessage = "Despesa guardada no aparelho; será sincronizada quando houver internet."
        }
    }

    private func flushDeletion(id: UUID) async {
        guard let authentication, authentication.isAuthenticated else { return }
        do {
            let token = try await authentication.accessTokenForAPI()
            try await sharingService.deleteExpense(id: id, accessToken: token)
            pendingDeletionIDs.remove(id)
            save()
        } catch {
            errorMessage = "A eliminação será sincronizada quando houver internet."
        }
    }
}

private struct ExchangeRateRecord: Decodable {
    let quote: String
    let rate: Double
}

struct ExpensesView: View {
    @EnvironmentObject private var navigation: AppNavigationState
    @EnvironmentObject private var authentication: AuthenticationManager
    @EnvironmentObject private var store: ExpenseStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDate = TripData.days.first!.date
    @State private var showsAddExpense = false
    @State private var showsBudgetEditor = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                summaryCard
                rateCard
                categoryChart
                balancesCard
                expensesList
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Despesas")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss(); navigation.goHome() } label: { Label("Início", systemImage: "house.fill") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack {
                    Button { Task { await store.sync(authentication: authentication) } } label: {
                        if store.isSyncing { ProgressView() } else { Image(systemName: "arrow.triangle.2.circlepath") }
                    }
                    .disabled(store.isSyncing)
                    Button { showsAddExpense = true } label: { Image(systemName: "plus.circle.fill") }
                }
            }
        }
        .task { await store.refreshRates() }
        .task { await store.sync(authentication: authentication) }
        .sheet(isPresented: $showsAddExpense) {
            NavigationStack {
                ExpenseEditorView(defaultDate: selectedDate, defaultPayer: authentication.authenticatedEmail ?? TripParticipant.all[0].email)
            }
        }
        .alert("Orçamento diário", isPresented: $showsBudgetEditor) {
            TextField("Valor em BRL", value: $store.dailyBudgetBRL, format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.decimalPad)
            Button("Guardar") {}
            Button("Cancelar", role: .cancel) {}
        } message: { Text("Orçamento total do grupo por dia.") }
    }

    private var summaryCard: some View {
        let spent = store.totalBRL(on: selectedDate)
        let progress = min(spent / max(store.dailyBudgetBRL, 1), 1)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Orçamento do dia", systemImage: "wallet.bifold.fill").font(.headline)
                Spacer()
                Button { showsBudgetEditor = true } label: { Image(systemName: "pencil.circle.fill") }
            }
            DatePicker("Dia", selection: $selectedDate, in: TripData.days.first!.date...TripData.days.last!.date, displayedComponents: .date)
            HStack(alignment: .firstTextBaseline) {
                Text(formatBRL(spent)).font(.title.bold())
                Text("de \(formatBRL(store.dailyBudgetBRL))").foregroundStyle(.secondary)
                Spacer()
            }
            ProgressView(value: progress).tint(spent > store.dailyBudgetBRL ? .red : .green)
            HStack {
                Text(spent > store.dailyBudgetBRL ? "Acima do orçamento em \(formatBRL(spent - store.dailyBudgetBRL))" : "Restam \(formatBRL(store.dailyBudgetBRL - spent))")
                    .font(.caption).foregroundStyle(spent > store.dailyBudgetBRL ? .red : .secondary)
                Spacer()
                Text("Total da viagem: \(formatBRL(store.totalBRL()))").font(.caption.bold())
            }
        }
        .padding()
        .background(LinearGradient(colors: [.green.opacity(0.15), .teal.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 22))
    }

    private var rateCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 3) {
                Text("1 BRL = \(rate(.AED)) AED · \(rate(.JPY)) JPY").font(.subheadline.weight(.semibold))
                Text(store.ratesUpdatedAt.map { "Atualizado \($0.formatted(.relative(presentation: .named)))" } ?? "Taxas aproximadas — atualizar com internet")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { Task { await store.refreshRates(force: true) } } label: {
                if store.isRefreshingRates { ProgressView() } else { Image(systemName: "arrow.clockwise") }
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder private var categoryChart: some View {
        let totals = store.categoryTotalsBRL()
        if !totals.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("POR CATEGORIA").font(.caption.bold()).tracking(1).foregroundStyle(.secondary)
                Chart(totals, id: \.category) { item in
                    BarMark(x: .value("Categoria", item.category.rawValue), y: .value("BRL", item.amount))
                        .foregroundStyle(item.category.color.gradient)
                }
                .frame(height: 190)
            }
            .padding()
            .background(.background, in: RoundedRectangle(cornerRadius: 22))
        }
    }

    private var balancesCard: some View {
        let balances = store.balancesBRL()
        return VStack(alignment: .leading, spacing: 12) {
            Text("SALDOS ENTRE VIAJANTES").font(.caption.bold()).tracking(1).foregroundStyle(.secondary)
            ForEach(TripParticipant.all, id: \.email) { participant in
                balanceRow(participant, balance: balances[participant.email, default: 0])
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 22))
    }

    private var expensesList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LANÇAMENTOS").font(.caption.bold()).tracking(1).foregroundStyle(.secondary)
            Label(
                store.lastSyncedAt.map { "Partilhado com o grupo · \($0.formatted(.relative(presentation: .named)))" }
                    ?? "Sincroniza com os participantes via Supabase",
                systemImage: "person.3.fill"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            if store.expenses.isEmpty {
                ContentUnavailableView("Nenhuma despesa", systemImage: "creditcard", description: Text("Toque em + para registar o primeiro gasto."))
            } else {
                ForEach(store.expenses) { expense in
                    HStack(spacing: 12) {
                        Image(systemName: expense.category.symbol).foregroundStyle(expense.category.color)
                            .frame(width: 38, height: 38).background(expense.category.color.opacity(0.1), in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(expense.title).font(.subheadline.weight(.semibold))
                            Text("\(expense.date.formatted(date: .abbreviated, time: .omitted)) · \(TripParticipant.participant(for: expense.payerEmail)?.firstName ?? "") pagou · \(expense.participantEmails.count) pessoas")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(format(expense.amount, currency: expense.currency)).font(.subheadline.bold())
                            if expense.currency != .BRL { Text(formatBRL(store.amountInBRL(expense))).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    .contextMenu { Button("Eliminar", role: .destructive) { store.delete(expense) } }
                }
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 22))
    }

    private func rate(_ currency: TripCurrency) -> String { String(format: currency == .JPY ? "%.2f" : "%.4f", store.ratesPerBRL[currency] ?? 0) }
    private func formatBRL(_ value: Double) -> String { value.formatted(.currency(code: "BRL").locale(Locale(identifier: "pt_BR"))) }
    private func format(_ value: Double, currency: TripCurrency) -> String { value.formatted(.currency(code: currency.rawValue)) }

    private func balanceRow(_ participant: TripParticipant, balance: Double) -> some View {
        HStack {
            Text(participant.name).font(.subheadline)
            Spacer()
            Text(abs(balance) < 0.01 ? "Quitado" : balance > 0 ? "Recebe \(formatBRL(balance))" : "Deve \(formatBRL(-balance))")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(abs(balance) < 0.01 ? Color.secondary : balance > 0 ? Color.green : Color.orange)
        }
    }
}

private struct ExpenseEditorView: View {
    @EnvironmentObject private var store: ExpenseStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var amount = 0.0
    @State private var currency: TripCurrency = .JPY
    @State private var date: Date
    @State private var category: TripExpense.Category = .food
    @State private var payerEmail: String
    @State private var participants = Set(TripParticipant.all.map(\.email))
    @State private var note = ""

    init(defaultDate: Date, defaultPayer: String) {
        _date = State(initialValue: defaultDate)
        _payerEmail = State(initialValue: defaultPayer)
    }

    var body: some View {
        Form {
            Section("Despesa") {
                TextField("Descrição", text: $title)
                TextField("Valor", value: $amount, format: .number.precision(.fractionLength(0...2))).keyboardType(.decimalPad)
                Picker("Moeda", selection: $currency) { ForEach(TripCurrency.allCases) { Text("\($0.rawValue) · \($0.name)").tag($0) } }
                DatePicker("Data", selection: $date, displayedComponents: .date)
                Picker("Categoria", selection: $category) { ForEach(TripExpense.Category.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) } }
                TextField("Nota opcional", text: $note, axis: .vertical)
            }
            Section("Quem pagou") {
                Picker("Pagador", selection: $payerEmail) { ForEach(TripParticipant.all) { Text($0.name).tag($0.email) } }
            }
            Section("Dividir entre") {
                ForEach(TripParticipant.all) { participant in
                    Toggle(participant.name, isOn: Binding(
                        get: { participants.contains(participant.email) },
                        set: { enabled in
                            if enabled { participants.insert(participant.email) }
                            else { participants.remove(participant.email) }
                        }
                    ))
                }
                if amount > 0, !participants.isEmpty {
                    let converted = store.converted(amount, from: currency, to: .BRL) / Double(participants.count)
                    Text("\(converted.formatted(.currency(code: "BRL").locale(Locale(identifier: "pt_BR")))) por pessoa")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Nova despesa")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar") {
                    store.add(.init(id: UUID(), title: title.trimmingCharacters(in: .whitespacesAndNewlines), amount: amount, currency: currency, date: date, category: category, payerEmail: payerEmail, participantEmails: participants, note: note))
                    dismiss()
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || amount <= 0 || participants.isEmpty)
            }
        }
    }
}
