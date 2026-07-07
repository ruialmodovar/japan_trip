import PhotosUI
import SwiftUI
import Translation
import UIKit
import Vision

struct MenuTranslationResult: Equatable {
    struct Item: Identifiable, Equatable {
        let id = UUID()
        let original: String
        let portuguese: String
        let explanation: String?
        let caution: String?
    }

    let summary: String
    let items: [Item]
    let recommendations: [String]
    let cautions: [String]
}

@MainActor
final class MenuOCRStore: ObservableObject {
    @Published private(set) var isRecognizing = false
    @Published var errorMessage: String?

    func recognizeText(in image: UIImage) async -> String {
        guard let cgImage = image.cgImage else { return "" }
        isRecognizing = true
        errorMessage = nil
        defer { isRecognizing = false }

        return await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ja-JP", "en-US"]
            request.usesLanguageCorrection = true
            request.minimumTextHeight = 0.012

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: image.cgOrientation)
            do {
                try handler.perform([request])
                return (request.results ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                return ""
            }
        }.value
    }
}

enum MenuTranslatorError: LocalizedError {
    case emptyText
    case appleTranslationUnavailable

    var errorDescription: String? {
        switch self {
        case .emptyText: "Não encontrei texto legível. Tente aproximar mais a câmera e evitar reflexos."
        case .appleTranslationUnavailable: "A tradução nativa da Apple requer iOS 18 ou superior."
        }
    }
}

struct MenuTranslatorView: View {
    var body: some View {
        if #available(iOS 18.0, *) {
            MenuTranslatorContentView()
        } else {
            ContentUnavailableView(
                "Tradução indisponível",
                systemImage: "translate",
                description: Text(MenuTranslatorError.appleTranslationUnavailable.localizedDescription)
            )
        }
    }
}

@available(iOS 18.0, *)
private struct MenuTranslatorContentView: View {
    @EnvironmentObject private var navigation: AppNavigationState
    @EnvironmentObject private var authentication: AuthenticationManager
    @Environment(\.dismiss) private var dismiss

    @StateObject private var ocr = MenuOCRStore()
    @State private var showsCamera = false
    @State private var showsPhotos = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var capturedImage: UIImage?
    @State private var recognizedText = ""
    @State private var result: MenuTranslationResult?
    @State private var isTranslating = false
    @State private var errorMessage: String?
    @State private var didOpenAutomatically = false
    @State private var showsOriginalText = false
    @State private var translationConfiguration: TranslationSession.Configuration?
    @State private var pendingTranslationText = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                hero
                statusCard
                if let capturedImage {
                    Image(uiImage: capturedImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                if let result {
                    translationCard(result)
                }
                if !recognizedText.isEmpty {
                    originalTextCard
                }
            }
            .padding()
            .padding(.bottom, 20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Tradutor de Menu")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                    navigation.goHome()
                } label: { Label("Início", systemImage: "house.fill") }
            }
            ToolbarItem(placement: .topBarTrailing) { Button("Fechar") { dismiss() } }
        }
        .task { openCaptureIfNeeded() }
        .onChange(of: capturedImage) { _, image in
            guard let image else { return }
            Task { await process(image) }
        }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    capturedImage = image
                }
                selectedPhoto = nil
            }
        }
        .onChange(of: showsCamera) { _, isPresented in authentication.suppressAutoLock("menu-camera", while: isPresented) }
        .fullScreenCover(isPresented: $showsCamera) {
            CameraCaptureView { image in capturedImage = image }
                .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showsPhotos, selection: $selectedPhoto, matching: .images)
        .translationTask(translationConfiguration) { session in
            await translateRecognizedText(with: session)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Aponta para o cardápio japonês", systemImage: "text.viewfinder")
                .font(.title2.bold())
            Text("O app lê o texto em japonês e traduz para português com a tradução nativa da Apple, sem IA externa.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                Button {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) { showsCamera = true } else { showsPhotos = true }
                } label: {
                    Label("Abrir câmera", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button {
                    showsPhotos = true
                } label: {
                    Label("Foto", systemImage: "photo.fill")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [.red.opacity(0.92), .pink.opacity(0.82), .orange.opacity(0.78)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .foregroundStyle(.white)
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if ocr.isRecognizing {
                Label("A ler o texto japonês…", systemImage: "doc.text.viewfinder")
            } else if isTranslating {
                Label("A traduzir com Apple Translation…", systemImage: "translate")
            } else if result != nil {
                Label("Tradução pronta", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label("Fotografe um cardápio para começar", systemImage: "camera.metering.matrix")
                    .foregroundStyle(.secondary)
            }
            if let message = errorMessage ?? ocr.errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .font(.subheadline.weight(.semibold))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func translationCard(_ result: MenuTranslationResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
            Text("Resumo")
                    .font(.headline)
                Text(result.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !result.items.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Itens encontrados")
                        .font(.headline)
                    ForEach(result.items) { item in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.portuguese)
                                .font(.subheadline.weight(.semibold))
                            Text(item.original)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let explanation = item.explanation, !explanation.isEmpty {
                                Text(explanation)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let caution = item.caution, !caution.isEmpty {
                                Label(caution, systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }

            if !result.recommendations.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sugestões")
                        .font(.headline)
                    ForEach(result.recommendations, id: \.self) { recommendation in
                        Label(recommendation, systemImage: "fork.knife.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }

            if !result.cautions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Atenção")
                        .font(.headline)
                    ForEach(result.cautions, id: \.self) { caution in
                        Label(caution, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var originalTextCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.snappy) { showsOriginalText.toggle() }
            } label: {
                HStack {
                    Label("Texto original lido", systemImage: "doc.text.magnifyingglass")
                    Spacer()
                    Image(systemName: showsOriginalText ? "chevron.up" : "chevron.down")
                }
            }
            .buttonStyle(.plain)
            if showsOriginalText {
                Text(recognizedText)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func openCaptureIfNeeded() {
        guard !didOpenAutomatically else { return }
        didOpenAutomatically = true
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                showsCamera = true
            } else {
                showsPhotos = true
            }
        }
    }

    private func process(_ image: UIImage) async {
        result = nil
        recognizedText = ""
        pendingTranslationText = ""
        errorMessage = nil
        let text = await ocr.recognizeText(in: image)
        recognizedText = text
        guard !text.isEmpty else {
            errorMessage = MenuTranslatorError.emptyText.localizedDescription
            return
        }
        pendingTranslationText = text
        isTranslating = true
        triggerAppleTranslation()
    }

    private func triggerAppleTranslation() {
        if translationConfiguration == nil {
            translationConfiguration = TranslationSession.Configuration(
                source: Locale.Language(identifier: "ja"),
                target: Locale.Language(identifier: "pt")
            )
        } else {
            translationConfiguration?.invalidate()
        }
    }

    private func translateRecognizedText(with session: TranslationSession) async {
        guard !pendingTranslationText.isEmpty else { return }
        do {
            try await session.prepareTranslation()
            let lines = menuLines(from: pendingTranslationText)
            let responses = try await session.translations(from: lines.enumerated().map { index, line in
                TranslationSession.Request(sourceText: line, clientIdentifier: String(index))
            })
            let ordered = responses.sorted {
                Int($0.clientIdentifier ?? "0") ?? 0 < Int($1.clientIdentifier ?? "0") ?? 0
            }
            let items = ordered.map { response in
                MenuTranslationResult.Item(
                    original: response.sourceText,
                    portuguese: response.targetText,
                    explanation: nil,
                    caution: caution(for: response.sourceText + " " + response.targetText)
                )
            }
            result = MenuTranslationResult(
                summary: "Tradução feita no aparelho com Apple Translation. Confirme ingredientes críticos com o restaurante.",
                items: items,
                recommendations: [],
                cautions: Array(Set(items.compactMap(\.caution))).sorted()
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isTranslating = false
    }

    private func menuLines(from text: String) -> [String] {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 2 }
        return Array(lines.prefix(40))
    }

    private func caution(for text: String) -> String? {
        let lowered = text.lowercased()
        let checks: [(String, String)] = [
            ("豚", "Pode conter porco."),
            ("pork", "Pode conter porco."),
            ("生", "Pode ser cru ou pouco cozinhado."),
            ("raw", "Pode ser cru ou pouco cozinhado."),
            ("辛", "Pode ser picante."),
            ("spicy", "Pode ser picante."),
            ("酒", "Pode conter álcool."),
            ("alcohol", "Pode conter álcool."),
            ("海老", "Pode conter camarão/marisco."),
            (" shrimp", "Pode conter camarão/marisco."),
            ("蟹", "Pode conter caranguejo/marisco."),
            ("crab", "Pode conter caranguejo/marisco."),
            ("卵", "Pode conter ovo."),
            ("egg", "Pode conter ovo.")
        ]
        return checks.first { lowered.contains($0.0.lowercased()) }?.1
    }
}
