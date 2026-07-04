import SwiftUI

struct FeatureHubView: View {
    @EnvironmentObject private var navigation: AppNavigationState
    @EnvironmentObject private var authentication: AuthenticationManager
    @EnvironmentObject private var locationSharing: LocationSharingManager

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                accountHeader
                featureSection("Durante a viagem", subtitle: "Tudo o que precisas para o próximo passo") {
                    FeatureTile(title: "Voos", subtitle: "Horários e assentos", symbol: "airplane", color: .blue) { navigation.showsFlights = true }
                    FeatureTile(title: "Hotéis", subtitle: "Estadias e links", symbol: "bed.double.fill", color: .indigo) { navigation.showsHotels = true }
                    FeatureTile(title: "Mobilidade", subtitle: "Metro, Uber e Shinkansen", symbol: "tram.fill", color: .teal) { navigation.showsMobility = true }
                    FeatureTile(title: "Clima", subtitle: "Agora e previsão", symbol: "cloud.sun.fill", color: .orange) { navigation.showsWeather = true }
                }
                featureSection("Grupo e despesas", subtitle: "Informação partilhada entre os viajantes") {
                    FeatureTile(title: "Localização", subtitle: "Encontrar o grupo", symbol: "location.fill.viewfinder", color: .green) { navigation.showsLocationSharing = true }
                    FeatureTile(title: "Despesas", subtitle: "Gastos e divisões", symbol: "wallet.bifold.fill", color: .mint) { navigation.showsExpenses = true }
                    FeatureTile(title: "Compras", subtitle: "Foto e conversão", symbol: "cart.fill", color: .pink) { navigation.showsShopping = true }
                    FeatureTile(title: "Fotos", subtitle: "Álbum da viagem", symbol: "photo.on.rectangle.angled", color: .purple) { navigation.showsPhotos = true }
                }
                featureSection("Memórias pessoais", subtitle: "Conteúdo privado da tua conta") {
                    FeatureTile(title: "Meu Diário", subtitle: "Momentos e emoções", symbol: "book.closed.fill", color: .brown) { navigation.showsPersonalDiary = true }
                }
                featureSection("Preparação e segurança", subtitle: "Para viajar tranquilo, mesmo sem rede") {
                    FeatureTile(title: "Offline", subtitle: "Dados no aparelho", symbol: "icloud.and.arrow.down.fill", color: .cyan) { navigation.showsOffline = true }
                    FeatureTile(title: "Notificações", subtitle: "Avisos inteligentes", symbol: "bell.badge.fill", color: .red) { navigation.showsNotifications = true }
                    FeatureTile(title: "Documentos", subtitle: "Cofre com Face ID", symbol: "lock.doc.fill", color: .gray) { navigation.showsDocumentVault = true }
                }
                accountSection
            }
            .padding(16)
            .padding(.bottom, 20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Mais")
    }

    private var accountHeader: some View {
        HStack(spacing: 14) {
            Image(systemName: "person.crop.circle.fill").font(.system(size: 44)).foregroundStyle(.indigo)
            VStack(alignment: .leading, spacing: 3) {
                Text(authentication.authenticatedName ?? "Viajante").font(.headline)
                Text(authentication.authenticatedEmail ?? "").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func featureSection<Content: View>(_ title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title3.bold())
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: columns, spacing: 12) { content() }
        }
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Conta").font(.title3.bold())
            VStack(spacing: 0) {
                Button { navigation.showsChangePassword = true } label: {
                    AccountRow(title: "Alterar senha", symbol: "key.fill", color: .indigo)
                }
                Divider().padding(.leading, 52)
                Button(role: .destructive) {
                    Task {
                        await locationSharing.setSharing(false, authentication: authentication)
                        authentication.signOut()
                    }
                } label: {
                    AccountRow(title: "Terminar sessão", symbol: "rectangle.portrait.and.arrow.right", color: .red)
                }
            }
            .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

private struct FeatureTile: View {
    let title: String
    let subtitle: String
    let symbol: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbol).font(.title2).foregroundStyle(color)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 94, alignment: .topLeading)
            .padding(14)
            .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct AccountRow: View {
    let title: String
    let symbol: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).frame(width: 28).foregroundStyle(color)
            Text(title).foregroundStyle(color)
            Spacer()
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
        }
        .padding(14)
        .contentShape(Rectangle())
    }
}
