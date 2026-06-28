import CryptoKit
import LocalAuthentication
import SwiftUI

@MainActor
final class AuthenticationManager: ObservableObject {
    @Published private(set) var isAuthenticated = false
    @Published private(set) var isAuthenticating = false
    @Published var errorMessage: String?

    private let passwordDigest = "958ea17de91b562488b425dc876192ea753035945abd3d9f26c72b254322514b"
    private var lockSuppressionReasons: Set<String> = []

    var biometricLabel: String {
        let context = LAContext()
        var error: NSError?
        context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        return switch context.biometryType {
        case .faceID: "Face ID"
        case .touchID: "Touch ID"
        case .opticID: "Optic ID"
        default: "código do iPhone"
        }
    }

    func authenticate() async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        errorMessage = nil

        let context = LAContext()
        context.localizedCancelTitle = "Cancelar"
        context.localizedFallbackTitle = "Usar código"
        var policyError: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            errorMessage = "Configure Face ID, Touch ID ou um código neste iPhone para proteger o roteiro."
            isAuthenticating = false
            return
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Aceda ao roteiro privado da viagem ao Japão."
            )
            isAuthenticated = success
        } catch let error as LAError {
            if error.code != .userCancel && error.code != .systemCancel && error.code != .appCancel {
                errorMessage = authenticationMessage(for: error.code)
            }
        } catch {
            errorMessage = "Não foi possível autenticar. Tente novamente."
        }
        isAuthenticating = false
    }

    func authenticate(password: String) -> Bool {
        errorMessage = nil
        let digest = SHA256.hash(data: Data(password.utf8))
            .map { String(format: "%02x", $0) }
            .joined()

        guard digest == passwordDigest else {
            errorMessage = "Senha incorreta. Tente novamente."
            return false
        }

        isAuthenticated = true
        return true
    }

    func lock() {
        isAuthenticated = false
        isAuthenticating = false
        errorMessage = nil
    }

    func lockIfAllowed() {
        guard lockSuppressionReasons.isEmpty else { return }
        lock()
    }

    func suppressAutoLock(_ reason: String, while active: Bool) {
        if active {
            lockSuppressionReasons.insert(reason)
        } else {
            lockSuppressionReasons.remove(reason)
        }
    }

    private func authenticationMessage(for code: LAError.Code) -> String {
        return switch code {
        case .authenticationFailed: "Não foi possível confirmar a identidade."
        case .biometryLockout: "A biometria está bloqueada. Use o código do iPhone."
        case .biometryNotEnrolled: "Configure a biometria nos Ajustes do iPhone."
        case .passcodeNotSet: "Configure um código nos Ajustes do iPhone."
        default: "Autenticação indisponível neste momento."
        }
    }
}

struct AuthenticationGate: View {
    @EnvironmentObject private var auth: AuthenticationManager

    var body: some View {
        Group {
            if auth.isAuthenticated {
                RootView()
                    .transition(.opacity)
            } else {
                AuthenticationView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: auth.isAuthenticated)
    }
}

private struct AuthenticationView: View {
    @EnvironmentObject private var auth: AuthenticationManager
    @State private var password = ""
    @FocusState private var passwordIsFocused: Bool

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 1, green: 0.97, blue: 0.97), .white, Color(red: 0.98, green: 0.91, blue: 0.92)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 24)

                    Image("TripLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 330)
                        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                        .shadow(color: .pink.opacity(0.18), radius: 30, y: 12)
                        .accessibilityLabel("Viagem ao Japão dos 15 anos da Raquel")

                    VStack(spacing: 8) {
                        Text("O nosso roteiro")
                            .font(.title2.bold())
                        Text("Dubai · Tóquio · Kyoto · Osaka")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 12) {
                        SecureField("Senha da viagem", text: $password)
                            .textContentType(.password)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.go)
                            .focused($passwordIsFocused)
                            .onSubmit(unlockWithPassword)
                            .padding(.horizontal, 16)
                            .frame(height: 54)
                            .background(.white, in: RoundedRectangle(cornerRadius: 16))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(.pink.opacity(0.28), lineWidth: 1)
                            }

                        Button(action: unlockWithPassword) {
                            Label("Entrar", systemImage: "lock.open.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 15)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 0.88, green: 0.35, blue: 0.43))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .disabled(password.isEmpty)
                    }

                    if let error = auth.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        Task { await auth.authenticate() }
                    } label: {
                        HStack(spacing: 8) {
                            if auth.isAuthenticating {
                                ProgressView()
                            } else {
                                Image(systemName: "faceid")
                            }
                            Text(auth.isAuthenticating ? "A autenticar…" : "Usar \(auth.biometricLabel)")
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .disabled(auth.isAuthenticating)

                    Label("Os dados permanecem apenas neste aparelho", systemImage: "lock.shield.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 28)
            }
        }
    }

    private func unlockWithPassword() {
        if auth.authenticate(password: password) {
            password = ""
            passwordIsFocused = false
        } else {
            password = ""
            passwordIsFocused = true
        }
    }
}
