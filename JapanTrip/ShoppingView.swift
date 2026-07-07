import PhotosUI
import SwiftUI
import UIKit
import Vision

struct DetectedPrice: Hashable {
    let amount: Double
    let currency: TripCurrency
    let sourceText: String
}

enum PriceOCRParser {
    static func yenPrices(in text: String) -> [DetectedPrice] {
        prices(in: text, defaultCurrency: .JPY)
            .map { DetectedPrice(amount: $0.amount, currency: .JPY, sourceText: $0.sourceText) }
            .reduce(into: [DetectedPrice]()) { result, candidate in
                if !result.contains(where: { $0.amount == candidate.amount }) { result.append(candidate) }
            }
            .sorted { $0.amount > $1.amount }
    }

    static func prices(in text: String, defaultCurrency: TripCurrency = .JPY) -> [DetectedPrice] {
        let normalized = text.replacingOccurrences(of: "，", with: ",")
        let patterns: [(String, TripCurrency)] = [
            (#"(?:¥|JPY\s*)\s*([0-9]{1,3}(?:[,\s][0-9]{3})+|[0-9]+)(?:\.([0-9]{1,2}))?"#, .JPY),
            (#"([0-9]{1,3}(?:[,\s][0-9]{3})+|[0-9]+)(?:\.([0-9]{1,2}))?\s*円"#, .JPY),
            (#"(?:AED|د\.إ)\s*([0-9]+(?:[,.][0-9]{1,2})?)"#, .AED),
            (#"(?:R\$|BRL\s*)\s*([0-9]+(?:[.,][0-9]{1,2})?)"#, .BRL),
            (#"(?:€|EUR\s*)\s*([0-9]+(?:[.,][0-9]{1,2})?)"#, .EUR),
            (#"(?:US\$|USD\s*|\$)\s*([0-9]+(?:[.,][0-9]{1,2})?)"#, .USD)
        ]
        var results: [DetectedPrice] = []
        for (pattern, currency) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(normalized.startIndex..., in: normalized)
            for match in regex.matches(in: normalized, range: range) {
                guard match.numberOfRanges > 1,
                      let numberRange = Range(match.range(at: 1), in: normalized),
                      let fullRange = Range(match.range(at: 0), in: normalized),
                      let amount = parseNumber(String(normalized[numberRange]), currency: currency) else { continue }
                results.append(.init(amount: amount, currency: currency, sourceText: String(normalized[fullRange])))
            }
        }

        if results.isEmpty {
            let generic = #"\b([0-9]{1,3}(?:[,\s][0-9]{3})+|[0-9]{2,})\b"#
            if let regex = try? NSRegularExpression(pattern: generic),
               let match = regex.matches(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)).last,
               let range = Range(match.range(at: 1), in: normalized),
               let amount = parseNumber(String(normalized[range]), currency: defaultCurrency) {
                results.append(.init(amount: amount, currency: defaultCurrency, sourceText: String(normalized[range])))
            }
        }
        return Array(Set(results)).sorted { $0.amount > $1.amount }
    }

    private static func parseNumber(_ value: String, currency: TripCurrency) -> Double? {
        var cleaned = value.replacingOccurrences(of: " ", with: "")
        if currency == .JPY {
            cleaned = cleaned.replacingOccurrences(of: ",", with: "")
        } else if cleaned.contains(","), cleaned.contains(".") {
            cleaned = cleaned.replacingOccurrences(of: ",", with: "")
        } else {
            cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
        }
        return Double(cleaned)
    }
}

struct ShoppingItem: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var photoFilename: String
    var amount: Double
    var currency: TripCurrency
    var storeName: String
    var createdAt: Date
    var taxFreeEnabled: Bool
    var isPurchased: Bool
}

@MainActor
final class ShoppingStore: ObservableObject {
    @Published private(set) var items: [ShoppingItem] = []
    @Published private(set) var isRecognizing = false
    @Published var errorMessage: String?

    private let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("JapanTripShopping", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        load()
    }

    func recognizePrices(in image: UIImage) async -> [DetectedPrice] {
        guard let cgImage = image.cgImage else { return [] }
        isRecognizing = true
        defer { isRecognizing = false }
        return await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ja-JP", "en-US", "pt-BR"]
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: image.cgOrientation)
            do {
                try handler.perform([request])
                let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                return PriceOCRParser.yenPrices(in: text)
            } catch { return [] }
        }.value
    }

    func add(name: String, image: UIImage, amount: Double, currency: TripCurrency, storeName: String, taxFreeEnabled: Bool) throws {
        guard let data = image.jpegData(compressionQuality: 0.88) else { throw CocoaError(.fileWriteUnknown) }
        let id = UUID()
        let filename = "\(id.uuidString).jpg"
        try data.write(to: directory.appendingPathComponent(filename), options: [.atomic, .completeFileProtection])
        items.insert(.init(id: id, name: name, photoFilename: filename, amount: amount, currency: .JPY, storeName: storeName, createdAt: Date(), taxFreeEnabled: taxFreeEnabled, isPurchased: false), at: 0)
        save()
    }

    func markPurchased(_ item: ShoppingItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isPurchased = true
        save()
    }

    func delete(_ item: ShoppingItem) {
        try? FileManager.default.removeItem(at: imageURL(for: item))
        items.removeAll { $0.id == item.id }
        save()
    }

    func imageURL(for item: ShoppingItem) -> URL { directory.appendingPathComponent(item.photoFilename) }

    private func load() {
        guard let data = try? Data(contentsOf: metadataURL), let decoded = try? JSONDecoder().decode([ShoppingItem].self, from: data) else { return }
        items = decoded.compactMap { saved in
            guard FileManager.default.fileExists(atPath: imageURL(for: saved).path) else { return nil }
            var migrated = saved
            migrated.currency = .JPY
            return migrated
        }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: metadataURL, options: [.atomic, .completeFileProtection])
    }

    private var metadataURL: URL { directory.appendingPathComponent("shopping-items.json") }
}

struct ShoppingView: View {
    @EnvironmentObject private var navigation: AppNavigationState
    @EnvironmentObject private var authentication: AuthenticationManager
    @EnvironmentObject private var shopping: ShoppingStore
    @EnvironmentObject private var expenses: ExpenseStore
    @Environment(\.dismiss) private var dismiss
    @State private var showsCamera = false
    @State private var showsPhotos = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var capturedImage: UIImage?
    @State private var editingItem: ShoppingItem?
    @State private var didOpenCaptureAutomatically = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                hero
                if shopping.items.isEmpty {
                    ContentUnavailableView("Lista de compras vazia", systemImage: "cart", description: Text("Fotografe um produto e a respetiva etiqueta para converter o preço."))
                        .padding(.vertical, 50)
                } else {
                    ForEach(shopping.items) { item in itemCard(item) }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Compras")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button { dismiss(); navigation.goHome() } label: { Label("Início", systemImage: "house.fill") } }
            ToolbarItem(placement: .topBarTrailing) { Button("Fechar") { dismiss() } }
        }
        .fullScreenCover(isPresented: $showsCamera) {
            CameraCaptureView { image in capturedImage = image }.ignoresSafeArea()
        }
        .photosPicker(isPresented: $showsPhotos, selection: $selectedPhoto, matching: .images)
        .onChange(of: selectedPhoto) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self), let image = UIImage(data: data) { capturedImage = image }
                selectedPhoto = nil
            }
        }
        .onChange(of: showsCamera) { _, value in authentication.suppressAutoLock("shopping-camera", while: value) }
        .onChange(of: showsPhotos) { _, value in authentication.suppressAutoLock("shopping-photos", while: value) }
        .sheet(isPresented: Binding(get: { capturedImage != nil }, set: { if !$0 { capturedImage = nil } })) {
            if let capturedImage { ShoppingScanEditor(image: capturedImage) }
        }
        .sheet(item: $editingItem) { item in ShoppingItemDetail(item: item) }
        .task { await expenses.refreshRates() }
        .onAppear {
            guard !didOpenCaptureAutomatically else { return }
            didOpenCaptureAutomatically = true
            DispatchQueue.main.async {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    showsCamera = true
                } else {
                    showsPhotos = true
                }
            }
        }
        .onDisappear {
            authentication.suppressAutoLock("shopping-camera", while: false)
            authentication.suppressAutoLock("shopping-photos", while: false)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 15) {
            Label("Conversor visual de preços", systemImage: "camera.viewfinder").font(.title2.bold())
            Text("Fotografe o produto e a etiqueta. O valor é tratado como iene, convertido primeiro para real e depois para as outras moedas.")
                .font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button { showsCamera = true } label: { Label("Fotografar preço", systemImage: "camera.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                Button { showsPhotos = true } label: { Label("Fotografias", systemImage: "photo.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(LinearGradient(colors: [.pink.opacity(0.18), .orange.opacity(0.10)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 22))
    }

    private func itemCard(_ item: ShoppingItem) -> some View {
        Button { editingItem = item } label: {
            HStack(spacing: 14) {
                if let image = UIImage(contentsOfFile: shopping.imageURL(for: item).path) {
                    Image(uiImage: image).resizable().scaledToFill().frame(width: 92, height: 92).clipShape(RoundedRectangle(cornerRadius: 16))
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack { Text(item.name).font(.headline); if item.isPurchased { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) } }
                    Text(amountInBRL(item).formatted(.currency(code: "BRL").locale(Locale(identifier: "pt_BR"))))
                        .font(.title3.bold()).foregroundStyle(.pink)
                    Text("Original: \(originalPrice(item))")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("\(convertedFromBRL(item, to: .EUR)) · \(convertedFromBRL(item, to: .USD))")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    if !item.storeName.isEmpty { Label(item.storeName, systemImage: "storefront.fill").font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
            }
            .padding()
            .background(.background, in: RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .contextMenu { Button("Eliminar", role: .destructive) { shopping.delete(item) } }
    }

    private func adjustedAmount(_ item: ShoppingItem) -> Double { item.taxFreeEnabled ? item.amount / 1.10 : item.amount }
    private func originalPrice(_ item: ShoppingItem) -> String { adjustedAmount(item).formatted(.currency(code: item.currency.rawValue)) + (item.taxFreeEnabled ? " tax-free*" : "") }
    private func amountInBRL(_ item: ShoppingItem) -> Double {
        expenses.converted(adjustedAmount(item), from: .JPY, to: .BRL)
    }
    private func convertedFromBRL(_ item: ShoppingItem, to currency: TripCurrency) -> String {
        expenses.converted(amountInBRL(item), from: .BRL, to: currency)
            .formatted(.currency(code: currency.rawValue))
    }
}

private struct ShoppingScanEditor: View {
    @EnvironmentObject private var shopping: ShoppingStore
    @EnvironmentObject private var expenses: ExpenseStore
    @Environment(\.dismiss) private var dismiss
    let image: UIImage
    @State private var name = ""
    @State private var amount = 0.0
    @State private var storeName = ""
    @State private var taxFree = false
    @State private var candidates: [DetectedPrice] = []

    var body: some View {
        NavigationStack {
            Form {
                Section { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 260).frame(maxWidth: .infinity) }
                Section("Preço reconhecido") {
                    if shopping.isRecognizing { HStack { ProgressView(); Text("A ler a etiqueta…") } }
                    ForEach(candidates, id: \.self) { candidate in
                        Button { amount = candidate.amount } label: {
                            HStack { Text(candidate.sourceText); Spacer(); Text(candidate.amount.formatted(.currency(code: "JPY"))).bold() }
                        }
                    }
                    TextField("Valor em ienes", value: $amount, format: .number.precision(.fractionLength(0...2))).keyboardType(.decimalPad)
                    Label("A fotografia é interpretada em JPY e convertida primeiro para BRL", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption).foregroundStyle(.secondary)
                    if amount > 0 {
                        let inBRL = expenses.converted(adjustedYen, from: .JPY, to: .BRL)
                        VStack(alignment: .leading, spacing: 7) {
                            Text("PRIMEIRO EM REAIS")
                                .font(.caption2.bold()).tracking(0.8).foregroundStyle(.secondary)
                            Text(inBRL.formatted(.currency(code: "BRL").locale(Locale(identifier: "pt_BR"))))
                                .font(.title2.bold()).foregroundStyle(.green)
                            Text("Depois: \(expenses.converted(inBRL, from: .BRL, to: .EUR).formatted(.currency(code: "EUR"))) · \(expenses.converted(inBRL, from: .BRL, to: .USD).formatted(.currency(code: "USD")))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                Section("Produto") {
                    TextField("Nome do produto", text: $name)
                    TextField("Loja opcional", text: $storeName)
                    Toggle("Estimar tax-free japonês (10%)", isOn: $taxFree)
                    if taxFree { Text("Estimativa: divide o preço com imposto por 1,10. Confirme sempre a etiqueta e elegibilidade da loja.").font(.caption).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Ler preço")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        try? shopping.add(name: name, image: image, amount: amount, currency: .JPY, storeName: storeName, taxFreeEnabled: taxFree)
                        dismiss()
                    }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || amount <= 0)
                }
            }
            .task {
                candidates = await shopping.recognizePrices(in: image)
                if let first = candidates.first { amount = first.amount }
            }
        }
    }

    private var adjustedYen: Double { taxFree ? amount / 1.10 : amount }
}

private struct ShoppingItemDetail: View {
    @EnvironmentObject private var shopping: ShoppingStore
    @EnvironmentObject private var expenses: ExpenseStore
    @EnvironmentObject private var authentication: AuthenticationManager
    @Environment(\.dismiss) private var dismiss
    let item: ShoppingItem

    var adjustedAmount: Double { item.taxFreeEnabled ? item.amount / 1.10 : item.amount }
    var amountInBRL: Double { expenses.converted(adjustedAmount, from: .JPY, to: .BRL) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if let image = UIImage(contentsOfFile: shopping.imageURL(for: item).path) { Image(uiImage: image).resizable().scaledToFit() }
                    Text(item.name).font(.title2.bold())
                    conversion("Preço original", adjustedAmount, .JPY)
                    conversion("Primeiro em reais", amountInBRL, .BRL)
                    conversion("Depois em euros", expenses.converted(amountInBRL, from: .BRL, to: .EUR), .EUR)
                    conversion("Depois em dólares", expenses.converted(amountInBRL, from: .BRL, to: .USD), .USD)
                    if !item.isPurchased {
                        Button {
                            let email = authentication.authenticatedEmail ?? TripParticipant.all[0].email
                            expenses.add(.init(id: UUID(), title: item.name, amount: amountInBRL, currency: .BRL, date: Date(), category: .shopping, payerEmail: email, participantEmails: [email], note: "Preço original: \(adjustedAmount.formatted(.currency(code: "JPY"))). Convertido primeiro para BRL pelo menu Compras."))
                            shopping.markPurchased(item)
                            dismiss()
                        } label: { Label("Comprei · adicionar às Despesas", systemImage: "cart.badge.plus").frame(maxWidth: .infinity) }
                            .buttonStyle(.borderedProminent)
                    }
                    Text("* Conversões indicativas com a última taxa guardada. O valor tax-free depende da loja e das regras aplicáveis.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("Compra")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fechar") { dismiss() } } }
        }
    }

    private func conversion(_ title: String, _ value: Double, _ currency: TripCurrency) -> some View {
        HStack { Text(title).foregroundStyle(.secondary); Spacer(); Text(value.formatted(.currency(code: currency.rawValue))).font(.headline) }
            .padding().background(.background, in: RoundedRectangle(cornerRadius: 16))
    }
}

extension UIImage {
    var cgOrientation: CGImagePropertyOrientation {
        switch imageOrientation {
        case .up: .up; case .down: .down; case .left: .left; case .right: .right
        case .upMirrored: .upMirrored; case .downMirrored: .downMirrored
        case .leftMirrored: .leftMirrored; case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }
}
