import SwiftUI

struct ReservationsView: View {
    var body: some View {
        List {
            Section {
                HStack {
                    SummaryMetric(value: "\(TripData.reservations.filter { $0.status != .pending }.count)", label: "confirmadas", color: .green)
                    Divider()
                    SummaryMetric(value: "\(TripData.reservations.filter { $0.status == .pending }.count)", label: "pendentes", color: .orange)
                }
                .frame(height: 72)
            }

            ForEach(ReservationStatus.allCasesCompat, id: \.rawValue) { status in
                let reservations = TripData.reservations.filter { $0.status == status }
                if !reservations.isEmpty {
                    Section(status.rawValue) {
                        ForEach(reservations) { reservation in
                            NavigationLink {
                                ReservationDetailView(reservation: reservation)
                            } label: {
                                HStack(spacing: 13) {
                                    Image(systemName: reservation.symbol)
                                        .frame(width: 38, height: 38)
                                        .foregroundStyle(status.color)
                                        .background(status.color.opacity(0.12), in: Circle())
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(reservation.title).font(.headline)
                                        Text(reservation.subtitle).font(.subheadline).foregroundStyle(.secondary)
                                        if let note = reservation.sensitiveNote {
                                            Label(note, systemImage: "lock.fill").font(.caption2).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Text(reservation.dateText).font(.caption.weight(.semibold)).foregroundStyle(status.color)
                                }
                                .padding(.vertical, 5)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Reservas")
        .listStyle(.insetGrouped)
    }
}

private struct ReservationGuide {
    let overview: String
    let details: [String]
    let recommendations: [String]
    let officialURL: URL?
    let officialLabel: String
    let mapQuery: String?
    let imageURL: URL?

    static func guide(for reservation: Reservation) -> ReservationGuide {
        let dubaiImage = URL(string: "https://images.unsplash.com/photo-1512453979798-5ea266f8880c?auto=format&fit=crop&w=1200&q=80")
        let tokyoImage = URL(string: "https://images.unsplash.com/photo-1540959733332-eab4deabeeaf?auto=format&fit=crop&w=1200&q=80")
        let fujiImage = URL(string: "https://images.unsplash.com/photo-1570459027562-4a916cc6113f?auto=format&fit=crop&w=1200&q=80")
        let kyotoImage = URL(string: "https://images.unsplash.com/photo-1493976040374-85c8e12f0c0e?auto=format&fit=crop&w=1200&q=80")
        let osakaImage = URL(string: "https://images.unsplash.com/photo-1590559899731-a382839e5549?auto=format&fit=crop&w=1200&q=80")

        switch reservation.id {
        case "flights":
            return .init(overview: "Quatro trechos Emirates ligam São Paulo, Dubai, Tóquio e Osaka.", details: ["EK262 · GRU → DXB · 08/07 às 01:05", "EK312 · DXB → HND · 12/07 às 07:40", "EK317 · KIX → DXB · 25/07 às 23:45 — confirmar data", "EK261 · DXB → GRU · chegada prevista em 26/07 às 17:15"], recommendations: ["Chegar com pelo menos três horas de antecedência.", "Power banks e baterias sempre na bagagem de mão.", "Confirmar no bilhete a data do EK317, pois o PDF contém divergência."], officialURL: URL(string: "https://www.emirates.com/br/portuguese/manage-booking/"), officialLabel: "Gerenciar na Emirates", mapQuery: nil, imageURL: dubaiImage)
        case "hotels":
            return .init(overview: "Quatro hotéis confirmados ao longo da viagem, escolhidos pela localização e facilidade logística.", details: ["Taj Dubai · Downtown · 08–12/07", "The Blossom Hibiya · Shinbashi · 12–18/07", "DoubleTree Kyoto Higashiyama · 18–22/07", "Osaka Station Hotel · Umeda · 22–25/07"], recommendations: ["Confirmar late arrival no Taj Dubai.", "Pedir ao Blossom Hibiya o envio Yamato para Kyoto em 17/07.", "Confirmar recepção das malas em Kyoto e Osaka antes do envio.", "Guardar referências de Booking apenas no comprovante privado."], officialURL: URL(string: "https://www.booking.com/"), officialLabel: "Abrir Booking.com", mapQuery: "Taj Dubai", imageURL: kyotoImage)
        case "safari":
            return .init(overview: "Safari premium no deserto com pickup confirmado no Taj Dubai às 14:30.", details: ["Dune bashing em veículo 4x4", "Sandboard, camelo e falcoaria", "Jantar em acampamento beduíno", "Retorno previsto entre 21:30 e 22:00"], recommendations: ["Comer leve antes do dune bashing.", "Levar água, óculos de sol e roupa fresca que cubra do sol.", "Proteger câmera e telemóvel da areia."], officialURL: nil, officialLabel: "Operador no comprovante", mapQuery: "Taj Dubai", imageURL: dubaiImage)
        case "burj":
            return .init(overview: "At the Top SKY leva ao lounge e observatório do nível 148, a 555 metros de altura.", details: ["Visita planeada para 10/07 às 18:00", "Chegar 30–40 minutos antes", "Acesso pelo Dubai Mall", "Janela escolhida para pôr do sol e fontes"], recommendations: ["Não marcar jantar apertado logo após a visita.", "Verificar o horário exato no bilhete.", "A luz muda rapidamente: fotografar antes e depois do pôr do sol."], officialURL: URL(string: "https://www.burjkhalifa.ae/"), officialLabel: "Site oficial Burj Khalifa", mapQuery: "At The Top Burj Khalifa", imageURL: dubaiImage)
        case "asakusa":
            return .init(overview: "Tour guiado de duas horas por Senso-ji, Kaminarimon e Nakamise para seis pessoas.", details: ["14/07 às 10:00", "Meeting point ainda deve ser confirmado", "Duração aproximada de duas horas", "Reserva GetYourGuide"], recommendations: ["Chegar 15 minutos antes.", "Levar água e chapéu; julho é quente e úmido.", "Guardar tempo após o tour para almoço e Kappabashi."], officialURL: URL(string: "https://www.getyourguide.com/"), officialLabel: "Abrir GetYourGuide", mapQuery: "Senso-ji Tokyo", imageURL: tokyoImage)
        case "fuji":
            return .init(overview: "Passeio de dia inteiro ao Monte Fuji e Hakone com pickup no hotel.", details: ["15/07 às 08:30", "Pickup no The Blossom Hibiya", "Lago Ashi e Hakone conforme condições", "Reserva para seis pessoas"], recommendations: ["A visibilidade do Fuji depende muito das nuvens.", "Levar dinheiro, casaco leve, água e protetor solar.", "Confirmar na véspera o roteiro e o ponto exato de encontro."], officialURL: URL(string: "https://www.getyourguide.com/"), officialLabel: "Abrir GetYourGuide", mapQuery: "Lake Ashi Hakone", imageURL: fujiImage)
        case "disney":
            return .init(overview: "Dia completo no Tokyo DisneySea, com prioridade para Fantasy Springs.", details: ["16/07 · saída do hotel às 07:00", "Ingressos já comprados para seis pessoas", "Fantasy Springs atualmente não exige passe para entrar na área", "Premier Access pode ser comprado para atrações elegíveis, conforme disponibilidade"], recommendations: ["Cadastrar todos os ingressos no app oficial antes da visita.", "Consultar horários e Premier Access no próprio dia.", "Fazer pausas frequentes no calor e usar lockers para compras."], officialURL: URL(string: "https://www.tokyodisneyresort.jp/en/tds/"), officialLabel: "Tokyo Disney Resort oficial", mapQuery: "Tokyo DisneySea", imageURL: tokyoImage)
        case "teamlab":
            return .init(overview: "Experiência de arte digital imersiva marcada antes do Shinkansen para Kyoto.", details: ["18/07 às 10:30", "O PDF alterna entre Planets e Borderless", "Confirmar a unidade no ingresso", "Reservar duas horas e margem para Tokyo Station"], recommendations: ["Se for Planets, há áreas com água e superfícies espelhadas.", "Usar roupa adequada e levar meias extras.", "Guardar malas grandes no Yamato no dia anterior."], officialURL: URL(string: "https://www.teamlab.art/e/planets/"), officialLabel: "teamLab Planets oficial", mapQuery: "teamLab Planets Tokyo", imageURL: tokyoImage)
        case "shinkansen":
            return .init(overview: "NOZOMI 53 em Green Car, de Tokyo Station para Kyoto Station.", details: ["18/07 · 17:12 → 19:23", "Carro 8", "Assentos 7-C, 7-D, 8-A, 8-B, 8-C e 8-D", "Seis lugares reservados"], recommendations: ["Chegar à plataforma 30–40 minutos antes.", "Embarcar com QR Ticket, cartão IC atribuído ou bilhete físico.", "Comprar ekiben antes de entrar no trem."], officialURL: URL(string: "https://smart-ex.jp/en/entraining/"), officialLabel: "Guia oficial SmartEX", mapQuery: "Tokyo Station Yaesu", imageURL: kyotoImage)
        case "kyototour":
            return .init(overview: "Tour privado pelos principais monumentos de Kyoto.", details: ["19/07 às 08:00", "Arashiyama, Kinkaku-ji, Gion, Kiyomizu-dera e Fushimi Inari", "Meeting point por confirmar", "Reserva GetYourGuide"], recommendations: ["Começar cedo para evitar calor e multidões.", "Levar dinheiro para entradas dos templos.", "Seguir a ordem do guia, que pode mudar conforme trânsito."], officialURL: URL(string: "https://www.getyourguide.com/"), officialLabel: "Abrir GetYourGuide", mapQuery: "Arashiyama Bamboo Forest", imageURL: kyotoImage)
        case "nara":
            return .init(overview: "Bate-volta de Kyoto a Nara pela Kintetsu Limited Express.", details: ["20/07 · trem planejado para 07:30", "Bilhetes ainda pendentes", "Nara Park, Todai-ji e Kasuga Taisha", "Regresso previsto às 17:00"], recommendations: ["Comprar lugares antecipadamente.", "Não mostrar papéis ou comida aos cervos.", "Sair cedo: os cervos ficam menos ativos com o calor."], officialURL: URL(string: "https://www.kintetsu.co.jp/foreign/english/"), officialLabel: "Kintetsu oficial", mapQuery: "Kintetsu Nara Station", imageURL: kyotoImage)
        case "castle":
            return .init(overview: "Visita ao Osaka Castle Museum, ainda pendente de reserva guiada.", details: ["23/07 às 10:00", "Museu distribuído pelo interior do castelo", "Mirante panorâmico no topo", "Visita guiada e ingresso ainda por confirmar"], recommendations: ["Reservar o primeiro horário confortável.", "Chegar cedo e levar água para atravessar o parque.", "Consultar exposições e funcionamento no site oficial."], officialURL: URL(string: "https://www.osakacastle.net/english/"), officialLabel: "Osaka Castle oficial", mapQuery: "Osaka Castle Museum", imageURL: osakaImage)
        default:
            return .init(overview: reservation.subtitle, details: [reservation.dateText], recommendations: ["Confirmar horário e condições no comprovante oficial."], officialURL: nil, officialLabel: "Informação oficial", mapQuery: reservation.title, imageURL: nil)
        }
    }
}

private struct ReservationDetailView: View {
    let reservation: Reservation
    private var guide: ReservationGuide { .guide(for: reservation) }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                hero
                detailSection("DETALHES DA RESERVA", symbol: "doc.text.fill", items: guide.details)
                detailSection("RECOMENDAÇÕES", symbol: "lightbulb.fill", items: guide.recommendations)
                actionSection
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(reservation.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let imageURL = guide.imageURL {
                AsyncImage(url: imageURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Rectangle().fill(reservation.status.color.opacity(0.12)).overlay { ProgressView() }
                    }
                }
                .frame(height: 190)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 20))
                Text("Imagem ilustrativa · Unsplash")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Label(reservation.dateText, systemImage: "calendar")
                Spacer()
                Text(reservation.status.rawValue.uppercased())
                    .font(.caption2.bold())
                    .foregroundStyle(reservation.status.color)
            }
            .font(.subheadline)
            Text(guide.overview).font(.title3.bold())
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 22))
    }

    private func detailSection(_ title: String, symbol: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol).font(.caption.bold()).tracking(0.8).foregroundStyle(.secondary)
            ForEach(items, id: \.self) { item in
                Label(item, systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 22))
    }

    private var actionSection: some View {
        VStack(spacing: 10) {
            if let url = guide.officialURL {
                Link(destination: url) {
                    Label(guide.officialLabel, systemImage: "safari.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            if let query = guide.mapQuery,
               let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
               let url = URL(string: "https://maps.apple.com/?q=\(encoded)") {
                Link(destination: url) {
                    Label("Abrir no Apple Maps", systemImage: "map.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

private extension ReservationStatus {
    static let allCasesCompat: [ReservationStatus] = [.pending, .booked, .confirmed]
}

private struct SummaryMetric: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 3) {
            Text(value).font(.title.bold()).foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
