import LocalAuthentication
import SwiftUI

@MainActor
final class AuthenticationManager: ObservableObject {
    @Published private(set) var isAuthenticated = false
    @Published private(set) var isAuthenticating = false
    @Published private(set) var authenticatedEmail: String?
    @Published var errorMessage: String?

    private let authService: any SupabaseAuthenticating
    private let sessionStore: any SecureSessionStoring
    private var currentSession: SupabaseSession?
    private var lockSuppressionReasons: Set<String> = []

    init(
        authService: any SupabaseAuthenticating = SupabaseAuthService(),
        sessionStore: any SecureSessionStoring = KeychainSessionStore()
    ) {
        self.authService = authService
        self.sessionStore = sessionStore
        authenticatedEmail = nil
        currentSession = sessionStore.load()
        let email = currentSession?.user.email?.lowercased()
        if let email, TripParticipant.participant(for: email) != nil {
            authenticatedEmail = email
        } else if currentSession != nil {
            sessionStore.clear()
            currentSession = nil
        }
    }

    var canUseBiometrics: Bool { authenticatedEmail != nil && currentSession != nil }
    var authenticatedName: String? {
        authenticatedEmail.flatMap { TripParticipant.participant(for: $0)?.name }
    }
    var authenticatedUserID: UUID? { currentSession?.user.id }

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
        guard canUseBiometrics else {
            errorMessage = "Entre primeiro com o seu e-mail e senha."
            return
        }
        isAuthenticating = true
        errorMessage = nil

        let context = LAContext()
        context.localizedCancelTitle = "Cancelar"
        context.localizedFallbackTitle = ""
        var policyError: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &policyError) else {
            errorMessage = "Biometria indisponível. Use o seu e-mail e senha."
            isAuthenticating = false
            return
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Aceda ao roteiro privado da viagem ao Japão."
            )
            if success {
                try await restoreSupabaseSession()
                isAuthenticated = true
            }
        } catch let error as LAError {
            if error.code != .userCancel && error.code != .systemCancel && error.code != .appCancel {
                errorMessage = authenticationMessage(for: error.code)
            }
        } catch let error as SupabaseAuthError {
            errorMessage = error.localizedDescription
        } catch is URLError {
            // A sessão foi validada anteriormente pelo Supabase e está protegida
            // pelo Keychain + biometria. Permite consultar o roteiro sem rede.
            isAuthenticated = currentSession != nil
            errorMessage = isAuthenticated ? nil : "Sem ligação para validar a sessão."
        } catch {
            errorMessage = "Não foi possível validar a sessão. Verifique a ligação à internet."
        }
        isAuthenticating = false
    }

    @discardableResult
    func authenticate(email: String, password: String) async -> Bool {
        guard !isAuthenticating else { return false }
        isAuthenticating = true
        defer { isAuthenticating = false }
        errorMessage = nil
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard TripParticipant.participant(for: normalizedEmail) != nil else {
            errorMessage = SupabaseAuthError.unauthorizedUser.localizedDescription
            return false
        }

        do {
            let session = try await authService.signIn(email: normalizedEmail, password: password)
            guard session.user.email?.lowercased() == normalizedEmail else {
                throw SupabaseAuthError.unauthorizedUser
            }
            try sessionStore.save(session)
            currentSession = session
            authenticatedEmail = normalizedEmail
            isAuthenticated = true
            return true
        } catch let error as SupabaseAuthError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = "Não foi possível entrar. Verifique a ligação à internet."
        }
        return false
    }

    func lock() {
        isAuthenticated = false
        isAuthenticating = false
        errorMessage = nil
    }

    func signOut() {
        let accessToken = currentSession?.accessToken
        lock()
        authenticatedEmail = nil
        currentSession = nil
        sessionStore.clear()
        if let accessToken {
            Task { await authService.signOut(accessToken: accessToken) }
        }
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
        case .biometryLockout: "A biometria está bloqueada. Use o seu e-mail e senha."
        case .biometryNotEnrolled: "Biometria não configurada. Use o seu e-mail e senha."
        case .passcodeNotSet: "Use o seu e-mail e senha para entrar."
        default: "Autenticação indisponível neste momento."
        }
    }

    private func restoreSupabaseSession() async throws {
        guard let refreshToken = currentSession?.refreshToken else {
            throw SupabaseAuthError.invalidCredentials
        }
        let session = try await authService.refreshSession(refreshToken: refreshToken)
        guard let email = session.user.email?.lowercased(), TripParticipant.participant(for: email) != nil else {
            throw SupabaseAuthError.unauthorizedUser
        }
        try sessionStore.save(session)
        currentSession = session
        authenticatedEmail = email
    }

    func accessTokenForAPI() async throws -> String {
        guard let session = currentSession else { throw SupabaseAuthError.invalidCredentials }
        if let expiresAt = session.expiresAt, Date().timeIntervalSince1970 < Double(expiresAt - 60) {
            return session.accessToken
        }
        try await restoreSupabaseSession()
        guard let token = currentSession?.accessToken else { throw SupabaseAuthError.invalidCredentials }
        return token
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
    @State private var email = ""
    @State private var password = ""
    @FocusState private var focusedField: Field?

    private enum Field { case email, password }

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
                        TextField("E-mail", text: $email)
                            .keyboardType(.emailAddress)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.next)
                            .focused($focusedField, equals: .email)
                            .onSubmit { focusedField = .password }
                            .padding(.horizontal, 16)
                            .frame(height: 54)
                            .background(.white, in: RoundedRectangle(cornerRadius: 16))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(.pink.opacity(0.28), lineWidth: 1)
                            }

                        SecureField("Senha", text: $password)
                            .textContentType(.password)
                            .autocorrectionDisabled()
                            .submitLabel(.go)
                            .focused($focusedField, equals: .password)
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
                        .disabled(auth.isAuthenticating || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)
                    }

                    if let error = auth.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.center)
                    }

                    if auth.canUseBiometrics {
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
                    }

                    Label("Acesso restrito a utilizadores autorizados", systemImage: "lock.shield.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 28)
            }
        }
        .task {
            if auth.canUseBiometrics {
                await auth.authenticate()
            } else {
                focusedField = .email
            }
        }
    }

    private func unlockWithPassword() {
        Task {
            if await auth.authenticate(email: email, password: password) {
                email = ""
                password = ""
                focusedField = nil
            } else {
                password = ""
                focusedField = .password
            }
        }
    }
}
