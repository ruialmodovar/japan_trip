# Japão 2026

App iOS offline em SwiftUI para acompanhar o roteiro Dubai–Japão da família Coelho & Mateus.

## Abrir e executar

1. Abra `JapanTrip.xcodeproj` no Xcode.
2. Escolha um simulador de iPhone.
3. Pressione **Run** (`⌘R`).

O app exige iOS 17 ou superior. Não há dependências externas nem backend.

## Testes

O target `JapanTripTests` cobre roteiro, atividades, checklist, reservas, voos, clima, autenticação, navegação e persistência do diário fotográfico. Execute no Xcode com **Product → Test** (`⌘U`).

## Clima

A área Clima apresenta condições atuais e previsão de cinco dias para Dubai, Tóquio, Kyoto e Osaka. Os dados vêm da Open-Meteo, sem chave de API, e a última atualização fica armazenada no aparelho para consulta offline.

Cada dia do roteiro também apresenta uma expectativa sazonal de temperatura e condições típicas de julho. Esses valores são médias climáticas para planejamento e não devem ser confundidos com uma previsão real; quando a data entrar na janela de cinco dias, a tela Clima mostrará a previsão atualizada.

## Mobilidade

O menu superior dá acesso à tela inicial e à central de Mobilidade. Nela é possível planejar rotas de metrô/trem no Apple Maps, abrir uma corrida no Uber, acessar o Careem em Dubai e consultar orientações para cada cidade. O cartão do Shinkansen reúne horário, carro, assentos e instruções de embarque do NOZOMI 53.

## Voos

O menu superior também abre a central de Voos, com os trechos EK262, EK312, EK317 e EK261, horários locais, duração, conexão e lembretes de bagagem. A data do EK317 permanece sinalizada para confirmação porque o PDF apresenta informações divergentes entre 24 e 25 de julho.

## Diário fotográfico

O menu superior contém um diário privado para tirar fotografias diretamente com a câmera ou importar imagens da biblioteca, organizá-las cronologicamente e adicionar legendas. As imagens são copiadas para a área privada do aplicativo e não são enviadas para servidores. A área Clima também passou da barra inferior para o menu superior.

## Autenticação

O roteiro é protegido por uma senha partilhada pelo grupo. Face ID, Touch ID ou código do iPhone continuam disponíveis como atalho opcional. O app volta a bloquear quando é colocado em segundo plano. A senha não é armazenada em texto simples no projeto.

## Privacidade

Localizadores de voos e referências de hotéis não foram gravados diretamente no código. Consulte o PDF original quando necessário. O estado do checklist fica apenas no aparelho, em `UserDefaults`. A autenticação é local e nenhum dado é enviado para um servidor.

## Dados que precisam de confirmação

- Data do voo de retorno: 24 ou 25 de julho.
- Estadia em Kyoto/Osaka: o resumo e o roteiro diário divergem.
- Unidade do teamLab: Planets ou Borderless.
- Ordem de Shitennoji e transferência Kyoto → Osaka em 22 de julho.
