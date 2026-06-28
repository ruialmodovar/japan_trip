import Foundation

enum TripData {
    private static func activity(_ day: Int, _ index: Int, _ time: String, _ title: String, _ details: String, _ kind: ActivityKind, location: String? = nil, critical: Bool = false) -> TripActivity {
        TripActivity(id: "2026-07-\(day)-\(index)", time: time, title: title, details: details, kind: kind, locationQuery: location, isCritical: critical)
    }

    static let days: [TripDay] = [
        TripDay(id: "2026-07-08", date: TripDate.make(8), city: .travel, title: "São Paulo → Dubai", note: "Chegada tarde; hotel avisado sobre o late arrival.", activities: [
            activity(8, 1, "01:05", "Voo EK262", "GRU → DXB · duração prevista de 14h55", .flight, critical: true),
            activity(8, 2, "23:00", "Chegada a Dubai", "Imigração, bagagem e transfer privado para o Taj Dubai.", .transport, location: "Dubai International Airport"),
            activity(8, 3, "00:30", "Check-in e descanso", "Room service leve e uma boa noite de sono.", .hotel, location: "Taj Dubai")
        ]),
        TripDay(id: "2026-07-09", date: TripDate.make(9), city: .dubai, title: "Desert Safari", note: "Calor intenso: hidratação constante.", activities: [
            activity(9, 1, "Manhã", "Manhã livre", "Descanso, piscina e recuperação do voo.", .rest),
            activity(9, 2, "12:00", "Almoço", "Hotel ou Din Tai Fung no Dubai Mall.", .food, location: "Din Tai Fung Dubai Mall"),
            activity(9, 3, "14:30", "Pickup do Desert Safari", "Dune bashing, sandboard, camelo, falcoaria e acampamento beduíno.", .tour, location: "Taj Dubai", critical: true),
            activity(9, 4, "20:00", "Jantar no deserto", "Buffet árabe incluído no passeio.", .food),
            activity(9, 5, "21:30", "Retorno ao hotel", "Chegada estimada entre 21:30 e 22:00.", .hotel, location: "Taj Dubai")
        ]),
        TripDay(id: "2026-07-10", date: TripDate.make(10), city: .dubai, title: "Souks e Burj Khalifa", note: "Atividades externas apenas cedo ou depois das 18h.", activities: [
            activity(10, 1, "08:50", "Saída do hotel", "Deslocamento até Dubai Creek.", .transport),
            activity(10, 2, "09:25", "Tour pelos Souks", "Gold Souk, Spice Souk e Al Fahidi District.", .tour, location: "Dubai Gold Souk"),
            activity(10, 3, "12:30", "Almoço em Al Fahidi", "Al Fanar ou Arabian Tea House.", .food, location: "Arabian Tea House Al Fahidi"),
            activity(10, 4, "14:30", "Dubai Mall", "Tarde indoor; escolher duas ou três zonas.", .shopping, location: "Dubai Mall"),
            activity(10, 5, "18:00", "Burj Khalifa", "At the Top SKY; chegar 30–40 minutos antes.", .attraction, location: "Burj Khalifa", critical: true),
            activity(10, 6, "20:00", "Jantar em Downtown", "CE LA VI, Armani ou Social House.", .food, location: "Downtown Dubai")
        ]),
        TripDay(id: "2026-07-11", date: TripDate.make(11), city: .dubai, title: "Dia livre e preparação", note: "Dormir cedo: despertar às 04:00.", activities: [
            activity(11, 1, "Manhã", "Manhã livre", "Hotel, piscina ou compras de última hora.", .rest),
            activity(11, 2, "18:00", "Jantar cedo", "Separar documentos, baterias e pesar malas.", .food),
            activity(11, 3, "21:00", "Dormir", "Alarmes ligados e transfer confirmado.", .rest, critical: true)
        ]),
        TripDay(id: "2026-07-12", date: TripDate.make(12), city: .travel, title: "Dubai → Tóquio", note: "Guardar roupa do primeiro dia na mala de mão.", activities: [
            activity(12, 1, "04:00", "Check-out", "Café rápido e saída para DXB às 04:40.", .hotel, critical: true),
            activity(12, 2, "07:40", "Voo EK312", "DXB → HND · duração prevista de 9h40.", .flight, critical: true),
            activity(12, 3, "22:20", "Chegada a Haneda", "Imigração, bagagem e transporte para Shinbashi.", .transport, location: "Haneda Airport"),
            activity(12, 4, "00:00", "Check-in The Blossom Hibiya", "Lanche rápido no konbini.", .hotel, location: "The Blossom Hibiya")
        ]),
        TripDay(id: "2026-07-13", date: TripDate.make(13), city: .tokyo, title: "Shinjuku", note: "Primeiro dia leve para adaptação ao fuso.", activities: [
            activity(13, 1, "11:00", "Metro para Shinjuku", "Seguir a sinalização para East Exit.", .transport),
            activity(13, 2, "11:30", "Alpen, Bic Camera e Don Quijote", "Compras com passaporte para tax-free.", .shopping, location: "Bic Camera Shinjuku East Exit"),
            activity(13, 3, "12:30", "Almoço no Sushiro", "Alternativa: Ichiran Ramen.", .food, location: "Sushiro Shinjuku"),
            activity(13, 4, "15:00", "Tokyo Metropolitan Government", "Mirante panorâmico gratuito.", .attraction, location: "Tokyo Metropolitan Government Building"),
            activity(13, 5, "17:30", "Omoide Yokocho", "Yakitori e atmosfera do antigo Shinjuku.", .attraction, location: "Omoide Yokocho"),
            activity(13, 6, "20:00", "Wazen Izakaya", "Reserva necessária.", .food, location: "Wazen Shinjuku", critical: true)
        ]),
        TripDay(id: "2026-07-14", date: TripDate.make(14), city: .tokyo, title: "Asakusa e Kappabashi", note: nil, activities: [
            activity(14, 1, "10:00", "Tour de Asakusa", "Senso-ji, Kaminarimon e Nakamise; passeio reservado para seis.", .tour, location: "Senso-ji", critical: true),
            activity(14, 2, "12:00", "Almoço wagyu", "Almoço na região de Asakusa.", .food),
            activity(14, 3, "14:00", "Kappabashi", "Facas, louças e utensílios de cozinha.", .shopping, location: "Kappabashi Dougu Street"),
            activity(14, 4, "17:00", "Akihabara opcional", "Eletrônicos, anime e jogos retrô.", .shopping, location: "Akihabara"),
            activity(14, 5, "19:30", "Itamae Sushi Ginza", "Omakase ou à la carte.", .food, location: "Itamae Sushi Ginza")
        ]),
        TripDay(id: "2026-07-15", date: TripDate.make(15), city: .tokyo, title: "Monte Fuji e Hakone", note: "Levar dinheiro, água, chapéu e casaco leve.", activities: [
            activity(15, 1, "08:30", "Pickup no hotel", "Tour GetYourGuide reservado para seis pessoas.", .tour, location: "The Blossom Hibiya", critical: true),
            activity(15, 2, "Dia todo", "Fuji, Lago Ashi e Hakone", "Roteiro definido pelo operador e condições do tempo.", .attraction, location: "Lake Ashi"),
            activity(15, 3, "Noite", "Regresso e jantar leve", "Hotel ou konbini.", .food)
        ]),
        TripDay(id: "2026-07-16", date: TripDate.make(16), city: .tokyo, title: "Tokyo DisneySea", note: "Cadastrar os seis ingressos no app antes da visita.", activities: [
            activity(16, 1, "07:00", "Saída do hotel", "Ir até Maihama e seguir para o parque.", .transport, critical: true),
            activity(16, 2, "Abertura", "Fantasy Springs", "Comprar Premier Access assim que entrar.", .attraction, location: "Tokyo DisneySea Fantasy Springs", critical: true),
            activity(16, 3, "10:30", "Journey to the Center of the Earth", "Uma das atrações mais emblemáticas do parque.", .attraction),
            activity(16, 4, "12:30", "Almoço", "Magellan's ou Casbah Food Court.", .food),
            activity(16, 5, "20:00", "Believe! Sea of Dreams", "Chegar 30 minutos antes.", .attraction),
            activity(16, 6, "21:30", "Retorno ao hotel", "Maihama → Shinbashi.", .transport)
        ]),
        TripDay(id: "2026-07-17", date: TripDate.make(17), city: .tokyo, title: "Omotesando, Ginza e Zojo-ji", note: "Enviar hoje as malas grandes para Kyoto.", activities: [
            activity(17, 1, "09:00", "Yamato para Kyoto", "Entregar malas no lobby e confirmar recepção no DoubleTree.", .luggage, critical: true),
            activity(17, 2, "10:30", "Harajuku e Omotesando", "Arquitetura, lojas e Takeshita Street.", .shopping, location: "Omotesando Tokyo"),
            activity(17, 3, "14:00", "Ginza", "Itoya, Muji e Uniqlo.", .shopping, location: "Ginza Itoya"),
            activity(17, 4, "16:30", "Templo Zojo-ji", "Templo Tokugawa com a Tokyo Tower ao fundo.", .attraction, location: "Zojo-ji Temple"),
            activity(17, 5, "19:30", "Jantar Imahan", "Sukiyaki wagyu; reservar antecipadamente.", .food, location: "Imahan Tokyo", critical: true)
        ]),
        TripDay(id: "2026-07-18", date: TripDate.make(18), city: .travel, title: "Tóquio → Kyoto", note: "Confirmar se os ingressos são para Planets ou Borderless.", activities: [
            activity(18, 1, "10:00", "Check-out", "Malas grandes já enviadas pelo Yamato.", .hotel),
            activity(18, 2, "10:30", "teamLab", "Arte digital imersiva; local exato precisa de confirmação.", .attraction, critical: true),
            activity(18, 3, "13:00", "Almoço e ekiben", "Comprar o bento antes do embarque.", .food, location: "Tokyo Station"),
            activity(18, 4, "16:30", "Embarque na Tokyo Station", "NOZOMI 53 · Green Car 8.", .transport, location: "Tokyo Station", critical: true),
            activity(18, 5, "17:12", "Shinkansen NOZOMI 53", "Assentos 7-C, 7-D, 8-A, 8-B, 8-C e 8-D.", .transport, critical: true),
            activity(18, 6, "19:23", "Chegada a Kyoto", "Táxi para o DoubleTree Higashiyama.", .hotel, location: "DoubleTree by Hilton Kyoto Higashiyama")
        ]),
        TripDay(id: "2026-07-19", date: TripDate.make(19), city: .kyoto, title: "Tour privado de Kyoto", note: "Levar dinheiro para entradas dos templos.", activities: [
            activity(19, 1, "08:00", "Início do tour", "Confirmar meeting point com o operador.", .tour, critical: true),
            activity(19, 2, "08:30", "Arashiyama", "Bamboo Forest cedo, antes das multidões.", .attraction, location: "Arashiyama Bamboo Forest"),
            activity(19, 3, "10:00", "Kinkaku-ji", "Pavilhão Dourado.", .attraction, location: "Kinkaku-ji"),
            activity(19, 4, "11:30", "Gion", "Bairro histórico e casas machiya.", .attraction, location: "Gion Kyoto"),
            activity(19, 5, "14:00", "Kiyomizu-dera", "Ninenzaka e Sannenzaka aos pés do templo.", .attraction, location: "Kiyomizu-dera"),
            activity(19, 6, "16:00", "Fushimi Inari", "Subir 20–30 minutos para os melhores corredores de torii.", .attraction, location: "Fushimi Inari Taisha")
        ]),
        TripDay(id: "2026-07-20", date: TripDate.make(20), city: .kyoto, title: "Bate-volta a Nara", note: "Trem das 07:30; calor e cervos mais ativos cedo.", activities: [
            activity(20, 1, "07:30", "Kintetsu para Nara", "Comprar os bilhetes com antecedência.", .transport, critical: true),
            activity(20, 2, "08:30", "Nara Park", "Mais de 1.200 cervos livres pelo parque.", .attraction, location: "Nara Park"),
            activity(20, 3, "09:30", "Todai-ji", "Grande Buda de bronze.", .attraction, location: "Todai-ji"),
            activity(20, 4, "11:30", "Kasuga Taisha", "Santuário com milhares de lanternas.", .attraction, location: "Kasuga Taisha"),
            activity(20, 5, "13:00", "Almoço em Nara", "Kamameshi ou outra opção local.", .food),
            activity(20, 6, "17:00", "Regresso a Kyoto", "Kintetsu Express.", .transport)
        ]),
        TripDay(id: "2026-07-21", date: TripDate.make(21), city: .kyoto, title: "Higashiyama e Pontocho", note: "Dia mais calmo, sem pressa.", activities: [
            activity(21, 1, "09:00", "Yasaka Shrine", "Santuário no coração de Gion.", .attraction, location: "Yasaka Shrine"),
            activity(21, 2, "10:30", "Higashiyama", "Cerâmica, leques, incensos e yukata.", .shopping, location: "Ninenzaka Kyoto"),
            activity(21, 3, "14:30", "Kyukyodo", "Papelaria tradicional fundada em 1663.", .shopping, location: "Kyukyodo Kyoto"),
            activity(21, 4, "16:00", "Pontocho Alley", "Passeio junto ao Kamogawa ao anoitecer.", .attraction, location: "Pontocho Alley"),
            activity(21, 5, "19:30", "Pontocho Idumoya", "Pedir mesa com varanda sobre o rio.", .food, location: "Pontocho Idumoya", critical: true)
        ]),
        TripDay(id: "2026-07-22", date: TripDate.make(22), city: .travel, title: "Kyoto → Osaka", note: "O PDF contém conflito: Shitennoji às 10h, mas também orienta ir a Osaka só após as 14h.", activities: [
            activity(22, 1, "09:00", "Yamato para Osaka", "Enviar malas para o Osaka Station Hotel.", .luggage, critical: true),
            activity(22, 2, "10:00", "Shitennoji — confirmar ordem", "Esta atividade já fica em Osaka.", .attraction, location: "Shitennoji"),
            activity(22, 3, "14:00", "Check-in em Osaka", "JR ou Hankyu até Umeda.", .hotel, location: "Osaka Station Hotel"),
            activity(22, 4, "16:00", "Shinsaibashi ou Denden Town", "Compras, eletrônicos e cultura pop.", .shopping),
            activity(22, 5, "18:00", "Dotonbori", "Glico Sign, canal e takoyaki.", .attraction, location: "Dotonbori"),
            activity(22, 6, "20:00", "Jantar em Dotonbori", "Tempura Sakugetsu ou izakaya local.", .food, critical: true)
        ]),
        TripDay(id: "2026-07-23", date: TripDate.make(23), city: .osaka, title: "Osaka Castle e Namba", note: nil, activities: [
            activity(23, 1, "10:00", "Osaka Castle", "Visita guiada com ingresso; reserva pendente.", .attraction, location: "Osaka Castle", critical: true),
            activity(23, 2, "13:00", "Almoço", "Kushikatsu ou okonomiyaki.", .food),
            activity(23, 3, "15:00", "Shitennoji opcional", "Apenas se não tiver sido visitado no dia anterior.", .attraction, location: "Shitennoji"),
            activity(23, 4, "17:00", "Dotonbori e Namba", "Namba Parks, Hozenji Yokocho e Don Quijote.", .attraction, location: "Namba Osaka"),
            activity(23, 5, "19:30", "Jantar em Dotonbori", "Kani Doraku, Harukoma Sushi ou izakaya.", .food)
        ]),
        TripDay(id: "2026-07-24", date: TripDate.make(24), city: .osaka, title: "Umeda e possível partida", note: "Atenção: o PDF alterna entre partida em 24 e 25 de julho. Confirmar no bilhete.", activities: [
            activity(24, 1, "09:30", "Compras finais em Umeda", "Yodobashi, Grand Front e Pokémon Center.", .shopping, location: "Yodobashi Camera Umeda"),
            activity(24, 2, "11:30", "Umeda Sky Building", "Observatório com vista de 360°.", .attraction, location: "Umeda Sky Building", critical: true),
            activity(24, 3, "13:00", "Almoço final", "Wagyu, ramen ou 551 Horai.", .food),
            activity(24, 4, "15:00", "Organizar malas", "Recibos tax-free e baterias na mala de mão.", .luggage),
            activity(24, 5, "18:00", "Transfer para KIX — confirmar data", "Chegar ao aeroporto até 21:00.", .transport, location: "Kansai International Airport", critical: true),
            activity(24, 6, "23:45", "Voo EK317 — confirmar data", "KIX → DXB → GRU.", .flight, critical: true)
        ]),
        TripDay(id: "2026-07-25", date: TripDate.make(25), city: .travel, title: "Data sob confirmação", note: "O resumo do PDF indica retorno em 25/07, em conflito com a programação detalhada de 24/07.", activities: [
            activity(25, 1, "—", "Confirmar bilhete Emirates", "Atualizar o app assim que a data correta do EK317 for confirmada.", .flight, critical: true)
        ])
    ]

    static let reservations: [Reservation] = [
        Reservation(id: "flights", title: "Voos Emirates", subtitle: "EK262 · EK312 · EK317 · EK261", dateText: "8–26 jul", status: .confirmed, symbol: "airplane", sensitiveNote: "Localizador disponível no PDF original"),
        Reservation(id: "hotels", title: "Hotéis", subtitle: "Taj · Blossom · DoubleTree · Osaka Station", dateText: "8–25 jul", status: .confirmed, symbol: "bed.double.fill", sensitiveNote: "Referências disponíveis no PDF original"),
        Reservation(id: "safari", title: "Desert Safari", subtitle: "Pickup no Taj Dubai às 14:30", dateText: "9 jul", status: .booked, symbol: "sun.max.fill", sensitiveNote: nil),
        Reservation(id: "burj", title: "Burj Khalifa", subtitle: "At the Top SKY", dateText: "10 jul", status: .confirmed, symbol: "building.fill", sensitiveNote: nil),
        Reservation(id: "asakusa", title: "Tour Asakusa", subtitle: "GetYourGuide · 6 pessoas", dateText: "14 jul", status: .booked, symbol: "figure.walk", sensitiveNote: nil),
        Reservation(id: "fuji", title: "Fuji e Hakone", subtitle: "Pickup no hotel às 08:30", dateText: "15 jul", status: .booked, symbol: "mountain.2.fill", sensitiveNote: nil),
        Reservation(id: "disney", title: "Tokyo DisneySea", subtitle: "Ingressos comprados", dateText: "16 jul", status: .confirmed, symbol: "sparkles", sensitiveNote: nil),
        Reservation(id: "teamlab", title: "teamLab", subtitle: "Confirmar Planets ou Borderless", dateText: "18 jul", status: .confirmed, symbol: "circle.hexagongrid.fill", sensitiveNote: nil),
        Reservation(id: "shinkansen", title: "NOZOMI 53", subtitle: "Green Car 8 · 6 assentos", dateText: "18 jul", status: .booked, symbol: "tram.fill", sensitiveNote: nil),
        Reservation(id: "kyototour", title: "Tour privado Kyoto", subtitle: "GetYourGuide", dateText: "19 jul", status: .booked, symbol: "building.columns.fill", sensitiveNote: nil),
        Reservation(id: "nara", title: "Kintetsu para Nara", subtitle: "Bilhetes ainda necessários", dateText: "20 jul", status: .pending, symbol: "ticket.fill", sensitiveNote: nil),
        Reservation(id: "castle", title: "Osaka Castle", subtitle: "Visita guiada por reservar", dateText: "23 jul", status: .pending, symbol: "building.columns.fill", sensitiveNote: nil)
    ]

    static let checklist: [ChecklistItem] = [
        .init(id: "kintetsu", title: "Comprar bilhetes Kintetsu para Nara", section: .urgent),
        .init(id: "wazen", title: "Reservar Wazen Izakaya", section: .urgent),
        .init(id: "castle", title: "Reservar visita guiada ao Osaka Castle", section: .urgent),
        .init(id: "umeda", title: "Confirmar ingresso Umeda Sky Building", section: .urgent),
        .init(id: "sakugetsu", title: "Reservar Tempura Sakugetsu", section: .urgent),
        .init(id: "idumoya", title: "Reservar Pontocho Idumoya", section: .urgent),
        .init(id: "imahan", title: "Reservar Imahan Tokyo", section: .urgent),
        .init(id: "maps", title: "Baixar mapas offline das quatro cidades", section: .before),
        .init(id: "apps", title: "Instalar Careem, LINE e Tokyo Disney Resort", section: .before),
        .init(id: "tours", title: "Confirmar meeting points dos três tours", section: .before),
        .init(id: "esim", title: "Comprar eSIM para Dubai e Japão", section: .before),
        .init(id: "money", title: "Separar cartões, AED e JPY", section: .before),
        .init(id: "dates", title: "Confirmar data correta do voo de regresso", section: .before),
        .init(id: "teamlabPlace", title: "Confirmar qual unidade do teamLab", section: .before),
        .init(id: "passport", title: "Levar passaporte para tax-free", section: .during),
        .init(id: "receipts", title: "Guardar recibos tax-free separados", section: .during),
        .init(id: "batteries", title: "Baterias e power banks na mala de mão", section: .during),
        .init(id: "yamato", title: "Solicitar Yamato com 1–2 dias", section: .during),
        .init(id: "weight", title: "Pesar malas periodicamente", section: .during),
        .init(id: "bookedDisney", title: "Ingressos DisneySea", section: .booked),
        .init(id: "bookedBurj", title: "Burj Khalifa", section: .booked),
        .init(id: "bookedSafari", title: "Desert Safari", section: .booked),
        .init(id: "bookedTeamlab", title: "teamLab", section: .booked),
        .init(id: "bookedTours", title: "Tours Asakusa, Fuji e Kyoto", section: .booked),
        .init(id: "bookedTrain", title: "Shinkansen NOZOMI 53", section: .booked)
    ]
}
