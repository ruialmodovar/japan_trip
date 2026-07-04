import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var navigation: AppNavigationState
    @EnvironmentObject private var authentication: AuthenticationManager
    @State private var previewDate = Date()

    private var today: TripDay? {
        TripData.days.first { TripDate.calendar.isDate($0.date, inSameDayAs: previewDate) }
    }

    private var countdown: Int {
        let start = TripDate.calendar.startOfDay(for: TripData.days[0].date)
        let current = TripDate.calendar.startOfDay(for: Date())
        return max(0, TripDate.calendar.dateComponents([.day], from: current, to: start).day ?? 0)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                TripCountdownCard()
                if let name = authentication.authenticatedName {
                    WelcomeCard(name: name)
                }
                NowModeCard()
                if let today {
                    TripHeader(city: today.city, eyebrow: today.date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "pt_BR"))), title: today.title, subtitle: "\(today.activities.count) momentos no roteiro")

                    PreviewDatePicker(selection: $previewDate)

                    FlightDayBanner(date: today.date)

                    WeatherMiniCard(city: today.city)

                    ExpectedClimateCard(day: today)

                    if let note = today.note {
                        Label(note, systemImage: "info.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
                    }

                    VStack(spacing: 0) {
                        ForEach(Array(today.activities.enumerated()), id: \.element.id) { index, activity in
                            ActivityRow(activity: activity, city: today.city, color: today.city.color, isLast: index == today.activities.count - 1)
                        }
                    }
                    .padding(.horizontal)
                    .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: .black.opacity(0.06), radius: 12, y: 5)
                } else {
                    TripHeader(city: .travel, eyebrow: "Dubai · Japão", title: countdown > 0 ? "Faltam \(countdown) dias" : "Viagem 2026", subtitle: "8 a 26 de julho · 6 viajantes")
                    PreviewDatePicker(selection: $previewDate)
                    EmptyStateCard(icon: "suitcase.rolling.fill", title: "A aventura está chegando", message: "Cada detalhe preparado agora vira uma memória inesquecível depois. Use a prévia abaixo para explorar a viagem.")
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: navigation.homeRequestID) { _, _ in
            previewDate = Date()
        }
        .onChange(of: navigation.selectedTab) { _, selectedTab in
            if selectedTab == .today {
                previewDate = Date()
            }
        }
    }
}

private struct NowModeCard: View {
    @EnvironmentObject private var weather: WeatherStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            momentContent(NowModePlanner.moment(at: context.date))
        }
    }

    @ViewBuilder
    private func momentContent(_ moment: LiveTripMoment) -> some View {
        if let entry = moment.entry {
                let destination = ExpectedClimate.forDay(entry.day)?.city ?? entry.day.city
                let outfit = OutfitRecommendation.forActivity(entry.activity, city: entry.day.city)
                VStack(alignment: .leading, spacing: 15) {
                    HStack {
                        Label(phaseTitle(moment.phase), systemImage: phaseSymbol(moment.phase))
                            .font(.caption.bold()).tracking(0.9)
                        Spacer()
                        if let countdown = moment.countdown {
                            Text(countdownText(countdown))
                                .font(.caption.bold().monospacedDigit())
                        } else if moment.phase == .happening {
                            Text("AGORA")
                                .font(.caption2.weight(.black))
                                .padding(.horizontal, 9).padding(.vertical, 5)
                                .background(.white.opacity(0.18), in: Capsule())
                        }
                    }
                    .foregroundStyle(.white.opacity(0.9))

                    VStack(alignment: .leading, spacing: 5) {
                        Text(entry.activity.title)
                            .font(.title2.bold())
                        Text("\(entry.day.title) · \(entry.activity.time)")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.82))
                    }
                    .foregroundStyle(.white)

                    HStack(spacing: 8) {
                        infoPill(symbol: "calendar", text: entry.date.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(Locale(identifier: "pt_BR"))))
                        if let snapshot = weather.snapshots[destination] {
                            infoPill(symbol: WeatherCondition.from(code: snapshot.current.weatherCode).symbol, text: String(format: "%.0f°", snapshot.current.temperature))
                        } else if let climate = ExpectedClimate.forDay(entry.day) {
                            infoPill(symbol: "thermometer.medium", text: "\(climate.minimum)°–\(climate.maximum)°")
                        }
                    }

                    Label(outfit.shared.prefix(2).joined(separator: " · "), systemImage: "tshirt.fill")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.86))

                    HStack(spacing: 10) {
                        NavigationLink {
                            ActivityDetailView(activity: entry.activity, city: entry.day.city)
                        } label: {
                            Label("Abrir atividade", systemImage: "arrow.right.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.white)
                        .foregroundStyle(.indigo)

                        if let query = entry.activity.locationQuery,
                           let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                           let url = URL(string: "https://maps.apple.com/?q=\(encoded)") {
                            Link(destination: url) {
                                Image(systemName: "map.fill")
                                    .frame(width: 42, height: 34)
                            }
                            .buttonStyle(.bordered)
                            .tint(.white)
                            .accessibilityLabel("Abrir rota")
                        }
                    }
                }
                .padding(20)
                .background(
                    LinearGradient(
                        colors: [.indigo, destination.color.opacity(0.9), .purple.opacity(0.86)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 27)
                )
                .shadow(color: .indigo.opacity(0.22), radius: 16, y: 8)
                .task {
                    if let location = WeatherLocation.location(for: destination) {
                        await weather.refresh(location)
                    }
                }
        }
    }

    private func infoPill(symbol: String, text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.white.opacity(0.14), in: Capsule())
    }

    private func phaseTitle(_ phase: LiveTripMoment.Phase) -> String {
        switch phase {
        case .beforeTrip: "MODO AGORA · PRIMEIRO PASSO"
        case .happening: "MODO AGORA · EM CURSO"
        case .upcoming: "MODO AGORA · PRÓXIMO PASSO"
        case .completed: "MODO AGORA · VIAGEM CONCLUÍDA"
        }
    }

    private func phaseSymbol(_ phase: LiveTripMoment.Phase) -> String {
        switch phase {
        case .beforeTrip: "airplane.departure"
        case .happening: "location.fill"
        case .upcoming: "clock.fill"
        case .completed: "checkmark.circle.fill"
        }
    }

    private func countdownText(_ interval: TimeInterval) -> String {
        let minutes = max(0, Int(interval) / 60)
        let days = minutes / 1_440
        let hours = (minutes % 1_440) / 60
        if days > 0 { return "FALTAM \(days)d \(hours)h" }
        if hours > 0 { return "FALTAM \(hours)h \(minutes % 60)min" }
        return "FALTAM \(minutes)min"
    }
}

private struct WelcomeCard: View {
    let name: String

    private var firstName: String {
        name.split(separator: " ").first.map(String.init) ?? name
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.22))
                    .frame(width: 48, height: 48)
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("BEM-VINDO(A)")
                    .font(.caption2.weight(.black))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.75))
                Text(firstName)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Text("A nossa aventura está cada vez mais perto.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.82))
            }
            Spacer()
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(.yellow)
        }
        .padding(18)
        .background(
            LinearGradient(colors: [.indigo, .purple.opacity(0.82), .pink.opacity(0.82)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .shadow(color: .indigo.opacity(0.18), radius: 14, y: 7)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Bem-vindo, \(name). A nossa aventura está cada vez mais perto.")
    }
}

private struct TripCountdownCard: View {
    private let departure: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        return calendar.date(from: DateComponents(year: 2026, month: 7, day: 8, hour: 1, minute: 5))!
    }()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if context.date < departure {
                countdownContent(remaining: departure.timeIntervalSince(context.date))
            }
        }
    }

    private func countdownContent(remaining: TimeInterval) -> some View {
        let days = Int(remaining) / 86_400
        let hours = (Int(remaining) % 86_400) / 3_600
        let minutes = (Int(remaining) % 3_600) / 60
        let seconds = Int(remaining) % 60

        return VStack(spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("A CONTAGEM REGRESSIVA COMEÇOU")
                            .font(.caption.weight(.black))
                            .tracking(1.1)
                            .foregroundStyle(.white.opacity(0.82))
                        Text(countdownMessage(days: days))
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    Image(systemName: "airplane.departure")
                        .font(.system(size: 31))
                        .foregroundStyle(.white)
                        .symbolEffect(.pulse, options: .repeating.speed(0.35))
                }

                HStack(spacing: 8) {
                    CountdownUnit(value: days, label: "DIAS")
                    separator
                    CountdownUnit(value: hours, label: "HORAS")
                    separator
                    CountdownUnit(value: minutes, label: "MIN")
                    separator
                    CountdownUnit(value: seconds, label: "SEG")
                }

                HStack(spacing: 7) {
                    Image(systemName: "location.fill")
                    Text("Próxima parada: Dubai")
                    Spacer()
                    Text("EK262 · 01:05")
                        .monospacedDigit()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.82))
            }
            .padding(20)
            .background(
                ZStack {
                    LinearGradient(
                        colors: [Color(red: 0.89, green: 0.29, blue: 0.40), Color(red: 0.95, green: 0.48, blue: 0.38), .purple.opacity(0.82)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Circle()
                        .fill(.white.opacity(0.08))
                        .frame(width: 170, height: 170)
                        .offset(x: 145, y: -80)
                    Circle()
                        .stroke(.white.opacity(0.10), lineWidth: 18)
                        .frame(width: 130, height: 130)
                        .offset(x: -165, y: 95)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: .pink.opacity(0.28), radius: 20, y: 10)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Faltam \(days) dias, \(hours) horas, \(minutes) minutos e \(seconds) segundos para a viagem")
    }

    private var separator: some View {
        Text(":")
            .font(.title2.bold())
            .foregroundStyle(.white.opacity(0.55))
            .offset(y: -8)
    }

    private func countdownMessage(days: Int) -> String {
        switch days {
        case 0: "É hoje! Malas prontas?"
        case 1: "Amanhã começa a nossa história"
        case 2...7: "Já dá para sentir a viagem"
        case 8...30: "Está quase na hora de partir"
        default: "Um sonho cada vez mais perto"
        }
    }
}

private struct CountdownUnit: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(spacing: 5) {
            Text(String(format: "%02d", value))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 9, weight: .black))
                .tracking(0.7)
                .foregroundStyle(.white.opacity(0.68))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.white.opacity(0.13), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct PreviewDatePicker: View {
    @Binding var selection: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PRÉVIA DA VIAGEM")
                .font(.caption.weight(.bold))
                .tracking(1)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 9) {
                    ForEach(TripData.days) { day in
                        Button {
                            selection = day.date
                        } label: {
                            VStack(spacing: 3) {
                                Text(day.date.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "pt_BR"))))
                                    .font(.caption2.weight(.semibold))
                                Text(day.date.formatted(.dateTime.day()))
                                    .font(.title3.bold())
                            }
                            .frame(width: 48, height: 58)
                            .foregroundStyle(TripDate.calendar.isDate(day.date, inSameDayAs: selection) ? .white : .primary)
                            .background(TripDate.calendar.isDate(day.date, inSameDayAs: selection) ? day.city.color : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.top, 8)
    }
}

struct ActivityRow: View {
    @EnvironmentObject private var ratings: ActivityRatingStore
    let activity: TripActivity
    let city: City
    let color: Color
    let isLast: Bool

    var body: some View {
        NavigationLink {
            ActivityDetailView(activity: activity, city: city)
        } label: {
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 0) {
                    ZStack {
                        Circle().fill(color.opacity(0.14)).frame(width: 38, height: 38)
                        Image(systemName: activity.kind.symbol).font(.callout.weight(.semibold)).foregroundStyle(color)
                    }
                    if !isLast {
                        Rectangle().fill(color.opacity(0.18)).frame(width: 2, height: 62)
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(activity.time).font(.caption.monospacedDigit().weight(.bold)).foregroundStyle(color)
                        if activity.isCritical {
                            Text("IMPORTANTE").font(.caption2.weight(.black)).foregroundStyle(.orange)
                        }
                    }
                    Text(activity.title).font(.headline).foregroundStyle(.primary)
                    Text(activity.details).font(.subheadline).foregroundStyle(.secondary)
                    if let summary = ratings.summary(for: activity.id) {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                            Text(summary.average.formatted(.number.precision(.fractionLength(1))))
                            Text("· \(summary.count)")
                        }
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                    }
                    Label("Ver detalhes", systemImage: "chevron.right.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(color)
                        .padding(.top, 3)
                }
                .padding(.bottom, isLast ? 16 : 10)
                .padding(.top, 2)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct ActivityGuide {
    let about: String
    let highlights: [String]
    let recommendations: [String]
    let officialURL: URL?
    let officialLabel: String
    let imageURL: URL?

    static func guide(for activity: TripActivity, city: City) -> ActivityGuide {
        let title = activity.title.lowercased()
        let dubaiImage = URL(string: "https://images.unsplash.com/photo-1512453979798-5ea266f8880c?auto=format&fit=crop&w=1200&q=80")
        let tokyoImage = URL(string: "https://images.unsplash.com/photo-1540959733332-eab4deabeeaf?auto=format&fit=crop&w=1200&q=80")
        let fujiImage = URL(string: "https://images.unsplash.com/photo-1570459027562-4a916cc6113f?auto=format&fit=crop&w=1200&q=80")
        let kyotoImage = URL(string: "https://images.unsplash.com/photo-1493976040374-85c8e12f0c0e?auto=format&fit=crop&w=1200&q=80")
        let osakaImage = URL(string: "https://images.unsplash.com/photo-1590559899731-a382839e5549?auto=format&fit=crop&w=1200&q=80")

        let cityImage: URL? = switch city {
        case .dubai: dubaiImage
        case .tokyo: tokyoImage
        case .kyoto: kyotoImage
        case .osaka: osakaImage
        case .travel:
            title.contains("kyoto") || title.contains("shinkansen") ? kyotoImage : (title.contains("tokyo") || title.contains("haneda") ? tokyoImage : dubaiImage)
        }

        if title.contains("burj khalifa") {
            return .init(about: "O edifício mais alto do mundo domina Downtown Dubai. A experiência At the Top SKY inclui o nível 148, a 555 metros, além dos observatórios inferiores.", highlights: ["Vista panorâmica sobre Dubai", "Pôr do sol e luzes da cidade", "Dubai Fountain junto à saída"], recommendations: ["Chegar 30–40 minutos antes do horário do bilhete.", "Reservar tempo para filas de segurança e elevadores.", "Fotografar antes e depois do pôr do sol."], officialURL: URL(string: "https://www.burjkhalifa.ae/"), officialLabel: "Burj Khalifa oficial", imageURL: dubaiImage)
        }
        if title.contains("disneysea") || title.contains("fantasy springs") {
            return .init(about: "Tokyo DisneySea é um parque único, construído em torno de portos temáticos. Fantasy Springs reúne áreas inspiradas em Frozen, Rapunzel e Peter Pan.", highlights: ["Fantasy Springs", "Journey to the Center of the Earth", "Believe! Sea of Dreams"], recommendations: ["Cadastrar os seis ingressos no app antes da visita.", "A área Fantasy Springs está atualmente com entrada livre; Premier Access é opcional para atrações elegíveis.", "Consultar disponibilidade e horários no app oficial no próprio dia."], officialURL: URL(string: "https://www.tokyodisneyresort.jp/en/tds/"), officialLabel: "Tokyo DisneySea oficial", imageURL: tokyoImage)
        }
        if title.contains("teamlab") {
            return .init(about: "Uma experiência de arte digital imersiva em que luz, som e movimento respondem ao espaço e aos visitantes.", highlights: ["Instalações em grande escala", "Ambientes espelhados", "Experiência sensorial e fotográfica"], recommendations: ["Confirmar no ingresso se é Planets ou Borderless.", "No Planets há áreas com água; levar meias extras.", "Sair com margem confortável para Tokyo Station."], officialURL: URL(string: "https://www.teamlab.art/e/planets/"), officialLabel: "teamLab oficial", imageURL: tokyoImage)
        }
        if title.contains("fuji") || title.contains("hakone") || title.contains("lago ashi") {
            return .init(about: "A região de Hakone combina vistas do Monte Fuji, paisagens vulcânicas, lago, teleférico e tradição de águas termais.", highlights: ["Monte Fuji quando o céu está limpo", "Lago Ashi", "Paisagens de Hakone"], recommendations: ["A visibilidade do Fuji é incerta e costuma ser melhor cedo.", "Levar casaco leve, mesmo no verão.", "Ter dinheiro para pequenos estabelecimentos."], officialURL: URL(string: "https://www.hakonenavi.jp/international/en/"), officialLabel: "Guia oficial de Hakone", imageURL: fujiImage)
        }
        if title.contains("asakusa") || title.contains("senso-ji") {
            return .init(about: "Senso-ji é o templo budista mais antigo de Tóquio. O percurso tradicional passa por Kaminarimon e pela rua comercial Nakamise.", highlights: ["Portão Kaminarimon", "Nakamise Street", "Salão principal e pagode"], recommendations: ["Chegar antes do horário do tour.", "Manter dinheiro para pequenas lojas e oferendas.", "Respeitar as áreas onde fotografia não é permitida."], officialURL: URL(string: "https://www.senso-ji.jp/english/"), officialLabel: "Senso-ji oficial", imageURL: tokyoImage)
        }
        if title.contains("arashiyama") {
            return .init(about: "Arashiyama é conhecida pelo corredor de bambu, templos, jardins e paisagem junto ao Rio Katsura.", highlights: ["Bamboo Grove", "Ponte Togetsukyo", "Templos e jardins próximos"], recommendations: ["Chegar cedo para evitar as maiores multidões.", "O corredor é curto; combinar com templos próximos.", "Levar água e proteção solar."], officialURL: URL(string: "https://kyoto.travel/en/areas/arashiyama.html"), officialLabel: "Kyoto Travel oficial", imageURL: kyotoImage)
        }
        if title.contains("kinkaku") {
            return .init(about: "Kinkaku-ji, o Pavilhão Dourado, é um templo zen revestido de folhas de ouro e refletido no lago Kyokochi.", highlights: ["Reflexo do pavilhão no lago", "Jardim de passeio", "Arquitetura zen"], recommendations: ["Seguir o circuito de visita em sentido único.", "A melhor fotografia costuma ser logo no primeiro mirante.", "Ter dinheiro para a entrada."], officialURL: URL(string: "https://www.shokoku-ji.jp/en/kinkakuji/"), officialLabel: "Kinkaku-ji oficial", imageURL: kyotoImage)
        }
        if title.contains("kiyomizu") {
            return .init(about: "Kiyomizu-dera é um complexo budista histórico na encosta leste de Kyoto, conhecido pelo grande terraço de madeira.", highlights: ["Terraço panorâmico", "Otowa Waterfall", "Ninenzaka e Sannenzaka"], recommendations: ["Usar calçado confortável para subidas e escadas.", "Evitar o meio do dia por causa do calor.", "Reservar tempo para as ruas históricas na descida."], officialURL: URL(string: "https://www.kiyomizudera.or.jp/en/"), officialLabel: "Kiyomizu-dera oficial", imageURL: kyotoImage)
        }
        if title.contains("fushimi inari") {
            return .init(about: "Fushimi Inari Taisha é o principal santuário dedicado a Inari, famoso pelos milhares de portões torii que sobem o Monte Inari.", highlights: ["Corredores Senbon Torii", "Santuários na montanha", "Vista sobre Kyoto"], recommendations: ["Vinte a trinta minutos de subida já rendem ótimas vistas.", "Ir ao fim da tarde reduz calor e multidões.", "Levar água; a trilha completa é longa."], officialURL: URL(string: "https://inari.jp/en/"), officialLabel: "Fushimi Inari oficial", imageURL: kyotoImage)
        }
        if title.contains("nara park") || title.contains("cervos") {
            return .init(about: "Nara Park reúne templos históricos e cervos considerados mensageiros sagrados na tradição local.", highlights: ["Cervos livres pelo parque", "Caminho até Todai-ji", "Paisagem arborizada"], recommendations: ["Mostrar as mãos vazias depois de terminar os biscoitos.", "Guardar mapas e papéis; os cervos podem mordê-los.", "Chegar cedo antes do calor forte."], officialURL: URL(string: "https://www.visitnara.jp/venues/A00489/"), officialLabel: "Visit Nara oficial", imageURL: kyotoImage)
        }
        if title.contains("todai-ji") || title.contains("grande buda") {
            return .init(about: "Todai-ji abriga o monumental Grande Buda de bronze dentro de um dos maiores edifícios históricos de madeira do Japão.", highlights: ["Grande Buda", "Daibutsuden", "Portão Nandaimon"], recommendations: ["Manter silêncio nas áreas de culto.", "Ter dinheiro para entrada e oferendas.", "Observar os guardiões de madeira no portão principal."], officialURL: URL(string: "https://www.todaiji.or.jp/en/"), officialLabel: "Todai-ji oficial", imageURL: kyotoImage)
        }
        if title.contains("osaka castle") {
            return .init(about: "O castelo atual abriga um museu dedicado a Toyotomi Hideyoshi e à história de Osaka, com observatório no piso superior.", highlights: ["Museu histórico", "Vista panorâmica", "Muralhas e parque do castelo"], recommendations: ["Comprar ingresso antecipado quando disponível.", "Levar água para a caminhada pelo parque.", "Começar pelo museu antes de explorar os jardins."], officialURL: URL(string: "https://www.osakacastle.net/english/"), officialLabel: "Osaka Castle oficial", imageURL: osakaImage)
        }
        if title.contains("dotonbori") || title.contains("glico") {
            return .init(about: "Dotonbori é o coração luminoso e gastronômico de Osaka, concentrado junto ao canal e à ponte Ebisubashi.", highlights: ["Glico Sign", "Canal de Dotonbori", "Takoyaki, okonomiyaki e izakayas"], recommendations: ["Ir depois do anoitecer para ver os letreiros.", "Definir um ponto de encontro porque a área fica lotada.", "Experimentar porções pequenas em vários lugares."], officialURL: URL(string: "https://osaka-info.jp/en/spot/dotonbori/"), officialLabel: "Osaka Info oficial", imageURL: osakaImage)
        }
        if title.contains("umeda sky") {
            return .init(about: "O Umeda Sky Building liga duas torres por uma plataforma elevada e pelo Kuchu Teien Observatory.", highlights: ["Observatório panorâmico", "Escadas rolantes suspensas", "Vista urbana de Osaka"], recommendations: ["Confirmar o horário do ingresso.", "A área externa pode fechar com vento forte.", "Reservar tempo para caminhar desde Osaka Station."], officialURL: URL(string: "https://www.skybldg.co.jp/en/"), officialLabel: "Umeda Sky Building oficial", imageURL: osakaImage)
        }

        let genericRecommendations: [String] = switch activity.kind {
        case .flight: ["Confirmar terminal e portão no dia.", "Chegar com três horas de antecedência.", "Documentos e baterias na bagagem de mão."]
        case .hotel: ["Confirmar check-in, endereço e nome da reserva.", "Guardar o endereço no idioma local.", "Pedir ajuda ao concierge com malas e transporte."]
        case .food: ["Confirmar reserva e número de pessoas.", "Informar alergias antes do pedido.", "Levar dinheiro para estabelecimentos menores."]
        case .attraction: ["Confirmar horário e ingresso no dia anterior.", "Levar água e proteção solar.", "Respeitar regras locais de fotografia."]
        case .transport: ["Chegar com margem para encontrar a plataforma.", "Manter bilhetes e cartões IC acessíveis.", "Evitar horário de pico com malas."]
        case .shopping: ["Levar passaporte para tax-free.", "Conferir regras de bagagem e garantia.", "Guardar recibos em envelope separado."]
        case .tour: ["Confirmar meeting point na véspera.", "Chegar 15 minutos antes.", "Guardar o contato do operador offline."]
        case .luggage: ["Fotografar etiqueta e comprovante.", "Confirmar nome e endereço do hotel seguinte.", "Manter uma muda de roupa na mala de mão."]
        case .rest: ["Usar o tempo para hidratar e recuperar energia.", "Rever o plano do dia seguinte.", "Evitar excesso de atividades no calor."]
        }

        return .init(about: activity.details, highlights: [activity.title, city.rawValue, activity.time], recommendations: genericRecommendations, officialURL: nil, officialLabel: "Site oficial", imageURL: cityImage)
    }
}

private struct ActivityDetailView: View {
    @EnvironmentObject private var ratings: ActivityRatingStore
    @EnvironmentObject private var authentication: AuthenticationManager
    let activity: TripActivity
    let city: City
    private var guide: ActivityGuide { .guide(for: activity, city: city) }
    private var outfit: OutfitRecommendation { .forActivity(activity, city: city) }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                hero
                ratingCard
                outfitCard
                card(title: "O QUE ESPERAR", symbol: "sparkles", text: guide.about)
                listCard(title: "DESTAQUES", symbol: "star.fill", items: guide.highlights)
                listCard(title: "RECOMENDAÇÕES", symbol: "lightbulb.fill", items: guide.recommendations)
                actions
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(activity.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await ratings.sync(authentication: authentication) }
        .alert("Avaliação", isPresented: Binding(
            get: { ratings.errorMessage != nil },
            set: { if !$0 { ratings.errorMessage = nil } }
        )) {
            Button("OK") { ratings.errorMessage = nil }
        } message: {
            Text(ratings.errorMessage ?? "")
        }
    }

    private var ratingCard: some View {
        let ownRating = ratings.rating(for: activity.id, email: authentication.authenticatedEmail)
        let summary = ratings.summary(for: activity.id)
        return VStack(spacing: 13) {
            VStack(spacing: 4) {
                Text("A TUA AVALIAÇÃO")
                    .font(.caption.bold()).tracking(0.8).foregroundStyle(.secondary)
                Text(ownRating == nil ? "Gostaste desta atividade?" : "Avaliação guardada")
                    .font(.headline)
            }
            HStack(spacing: 10) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        Task { await ratings.rate(activity: activity, stars: star, authentication: authentication) }
                    } label: {
                        Image(systemName: star <= (ownRating ?? 0) ? "star.fill" : "star")
                            .font(.title2)
                            .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(star) \(star == 1 ? "estrela" : "estrelas")")
                }
            }
            if let summary {
                Text("Média do grupo: \(summary.average.formatted(.number.precision(.fractionLength(1)))) · \(summary.count) \(summary.count == 1 ? "avaliação" : "avaliações")")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Sê a primeira pessoa a avaliar.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
    }

    private var outfitCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            Label("VESTUÁRIO RECOMENDADO", systemImage: "tshirt.fill")
                .font(.caption.bold()).tracking(0.8).foregroundStyle(city.color)

            Label(outfit.climateSummary, systemImage: "thermometer.medium")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()
            outfitGroup(title: "Meninos", symbol: "person.fill", color: .blue, items: outfit.boys)
            Divider()
            outfitGroup(title: "Meninas", symbol: "person.fill", color: .pink, items: outfit.girls)
            Divider()
            outfitGroup(title: "Para todos", symbol: "backpack.fill", color: .orange, items: outfit.shared)

            Text("Sugestão baseada na média climática esperada e no tipo de atividade. Confirme o clima real no próprio dia.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
    }

    private func outfitGroup(title: String, symbol: String, color: Color, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.subheadline.bold())
                .foregroundStyle(color)
            ForEach(items, id: \.self) { item in
                Label(item, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let imageURL = guide.imageURL {
                AsyncImage(url: imageURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Rectangle().fill(city.color.opacity(0.12)).overlay { ProgressView() }
                    }
                }
                .frame(height: 210)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 22))
                Text("Imagem ilustrativa · Unsplash")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Label(activity.time, systemImage: activity.kind.symbol)
                    .font(.headline)
                Spacer()
                Label(city.rawValue, systemImage: city.symbol)
                    .font(.caption.bold())
                    .foregroundStyle(city.color)
            }
            Text(activity.details).font(.subheadline).foregroundStyle(.secondary)
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 24))
    }

    private func card(title: String, symbol: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(.caption.bold()).tracking(0.8).foregroundStyle(.secondary)
            Text(text).font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
    }

    private func listCard(title: String, symbol: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Label(title, systemImage: symbol).font(.caption.bold()).tracking(0.8).foregroundStyle(.secondary)
            ForEach(items, id: \.self) { item in
                Label(item, systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
    }

    private var actions: some View {
        VStack(spacing: 10) {
            if let url = guide.officialURL {
                Link(destination: url) {
                    Label(guide.officialLabel, systemImage: "safari.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(city.color)
            }
            if let query = activity.locationQuery,
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
