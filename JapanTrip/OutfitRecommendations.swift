import Foundation

struct OutfitRecommendation: Hashable {
    let climateSummary: String
    let boys: [String]
    let girls: [String]
    let shared: [String]

    static func forActivity(_ activity: TripActivity, city: City) -> OutfitRecommendation {
        let day = TripData.days.first { day in day.activities.contains { $0.id == activity.id } }
        let climate = day.flatMap(ExpectedClimate.forDay)
        let maximum = climate?.maximum ?? 30
        let title = activity.title.lowercased()

        var boys = maximum >= 32
            ? ["Camiseta leve e respirável", "Bermuda ou calça leve de secagem rápida"]
            : ["Camiseta confortável", "Calça leve ou bermuda"]
        var girls = maximum >= 32
            ? ["Blusa ou camiseta leve e respirável", "Shorts, calça leve ou vestido fresco"]
            : ["Blusa ou camiseta confortável", "Calça leve, shorts ou vestido"]
        var shared = ["Calçado confortável para caminhar"]

        switch activity.kind {
        case .flight:
            boys = ["Camiseta macia com calça confortável", "Casaco leve para a cabine"]
            girls = ["Blusa ou camiseta macia com calça confortável", "Cardigã ou casaco leve para a cabine"]
            shared = ["Meias confortáveis ou de compressão", "Calçado fácil de retirar", "Uma muda leve na bagagem de mão"]
        case .hotel, .rest:
            boys = ["Roupa casual, leve e confortável"]
            girls = ["Roupa casual, leve e confortável"]
            shared = ["Chinelos ou calçado leve", "Casaco fino para ambientes climatizados"]
        case .food:
            boys = ["Polo ou camiseta cuidada", "Calça leve ou bermuda alinhada"]
            girls = ["Blusa, vestido leve ou camiseta cuidada", "Calça ou saia confortável"]
            shared = ["Casaco fino para o ar-condicionado", "Confirmar se o restaurante exige smart casual"]
        case .shopping:
            shared.append(contentsOf: ["Casaco fino para centros comerciais climatizados", "Mochila leve ou bolsa transversal"])
        case .transport, .luggage:
            shared.append(contentsOf: ["Calçado fechado e estável", "Evitar peças longas ou soltas ao transportar malas"])
        case .tour, .attraction:
            shared.append("Roupa que permita caminhar e subir escadas com conforto")
        }

        if title.contains("desert") || title.contains("deserto") || title.contains("safari") {
            boys = ["Camiseta UV ou camisa leve de manga comprida", "Calça leve ou bermuda abaixo do joelho"]
            girls = ["Blusa leve cobrindo os ombros", "Calça ampla ou vestido/saia abaixo do joelho"]
            shared = ["Tênis fechado para a areia", "Chapuéu, óculos de sol e lenço leve", "Casaco fino para o anoitecer"]
        } else if title.contains("fuji") || title.contains("hakone") || title.contains("lago ashi") {
            boys.append("Camada leve de manga comprida")
            girls.append("Cardigã ou camada leve de manga comprida")
            shared.append(contentsOf: ["Casaco corta-vento", "Capa de chuva compacta", "Tênis com boa aderência"])
        } else if title.contains("disney") || title.contains("fantasy springs") || title.contains("journey to") {
            boys = ["Camiseta de secagem rápida", "Bermuda ou calça leve"]
            girls = ["Camiseta de secagem rápida", "Shorts ou calça leve"]
            shared = ["Tênis já amaciado", "Boné ou chapéu", "Capa de chuva leve", "Camiseta e meias extra"]
        } else if title.contains("teamlab") {
            boys = ["Camiseta leve", "Shorts ou calça que possa ser dobrada"]
            girls = ["Camiseta leve", "Shorts ou calça; evitar saia por causa dos pisos espelhados"]
            shared = ["Meias extra", "Calçado fácil de retirar", "Evitar roupas com tecido muito transparente"]
        }

        let culturalVisit = ["templo", "shrine", "senso-ji", "kinkaku", "kiyomizu", "fushimi", "todai-ji", "kasuga", "zojo-ji", "shitennoji", "souks", "al fahidi"]
            .contains { title.contains($0) }
        if culturalVisit {
            boys.append("Para o local cultural: ombros cobertos e peça até perto do joelho")
            girls.append("Para o local cultural: ombros cobertos e peça até perto do joelho")
            shared.append("Usar meias limpas: pode ser necessário retirar o calçado")
        }

        if maximum >= 38 {
            shared.append(contentsOf: ["Chapuéu de aba ou boné", "Proteção UV e garrafa de água"])
        } else if maximum >= 30 {
            shared.append(contentsOf: ["Bonéu ou chapéu", "Protetor solar e garrafa de água"])
        }
        if climate?.rainChanceText.lowercased().contains("possíve") == true {
            shared.append("Guarda-chuva compacto ou capa leve")
        }

        return .init(
            climateSummary: climate.map { "\($0.minimum)°–\($0.maximum)° · \($0.summary)" }
                ?? "Condições variáveis; confirmar a previsão no próprio dia.",
            boys: unique(boys),
            girls: unique(girls),
            shared: unique(shared)
        )
    }

    private static func unique(_ values: [String]) -> [String] {
        values.reduce(into: []) { result, value in
            if !result.contains(value) { result.append(value) }
        }
    }
}
