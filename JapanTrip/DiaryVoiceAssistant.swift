import AVFoundation
import Foundation
import Speech

@MainActor
final class DiaryVoiceRecorder: ObservableObject {
    @Published var transcript = ""
    @Published private(set) var isRecording = false
    @Published var errorMessage: String?

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var transcriptBeforeRecording = ""
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "pt-BR"))

    func toggleRecording() async {
        if isRecording { stop(); return }
        guard await requestPermissions() else {
            errorMessage = "Ativa o Microfone e o Reconhecimento de Fala nas Definições para usar o ditado."
            return
        }
        start()
    }

    func stop() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func start() {
        stop()
        transcriptBeforeRecording = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.addsPunctuation = true
            recognitionRequest = request

            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
                request.append(buffer)
            }
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true

            recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    if let self, let result {
                        let current = result.bestTranscription.formattedString
                        self.transcript = self.transcriptBeforeRecording.isEmpty
                            ? current
                            : self.transcriptBeforeRecording + "\n\n" + current
                    }
                    if error != nil || result?.isFinal == true { self?.stop() }
                }
            }
        } catch {
            stop()
            errorMessage = "Não foi possível iniciar o ditado: \(error.localizedDescription)"
        }
    }

    private func requestPermissions() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        let microphone = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
        return speech == .authorized && microphone
    }

    deinit {
        recognitionTask?.cancel()
        if audioEngine.isRunning { audioEngine.stop() }
    }
}

struct DiaryAIResult: Decodable {
    let text: String
    let highlight: String?
}

struct DiaryAIService {
    private let functionURL = URL(string: "https://oiprckdaqhgganwtxcui.supabase.co/functions/v1/diary-writer")!
    private let publishableKey = "sb_publishable_GYwIq70ROI6Rx6LzMyASJA_4DtkY5hL"

    func rewrite(transcript: String, day: TripDay, accessToken: String) async throws -> DiaryAIResult {
        var request = URLRequest(url: functionURL)
        request.httpMethod = "POST"
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "transcript": transcript,
            "day": day.date.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "pt_BR"))),
            "title": day.title,
            "activities": day.activities.map { "\($0.time) · \($0.title)" }
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw DiaryVoiceError.ai(message ?? "A IA não conseguiu preparar a entrada.")
        }
        return try JSONDecoder().decode(DiaryAIResult.self, from: data)
    }
}

private enum DiaryVoiceError: LocalizedError {
    case ai(String)
    var errorDescription: String? { if case .ai(let message) = self { return message }; return nil }
}
