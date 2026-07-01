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

O roteiro é protegido por Supabase Auth e por uma lista fechada de utilizadores. As senhas são validadas exclusivamente no servidor e não existem no código do app. A sessão é guardada no Keychain com proteção exclusiva do dispositivo. Face ID ou Touch ID ficam disponíveis apenas depois do primeiro acesso válido e renovam a sessão no Supabase. O app volta a bloquear quando é colocado em segundo plano e o menu permite terminar a sessão por completo.

## Modo offline

O roteiro, voos, hotéis, reservas, checklist, clima esperado e guias de mobilidade são incluídos no app. O menu Modo Offline permite guardar mapas de referência das quatro cidades, atualizar a última previsão meteorológica e consultar contactos de hotéis e emergências. Uma sessão anteriormente validada pode ser reaberta offline com biometria. Rotas e transportes em tempo real continuam dependentes de rede; para navegação completa, o utilizador deve descarregar as cidades no Apple Maps.

## Notificações inteligentes

O app agenda localmente resumos da agenda, lembretes 40 minutos antes de compromissos importantes, saídas para o aeroporto, avisos de check-out e lembretes especiais como DisneySea. A última previsão guardada também pode gerar um aviso matinal de chuva. Os tipos de aviso podem ser ativados individualmente e continuam a funcionar sem rede depois de agendados.

## Cofre de documentos

O cofre importa PDFs, imagens, passaportes, seguros, bilhetes, reservas e QR Codes. Cada ficheiro e o índice de documentos são cifrados individualmente com AES-256-GCM. A chave é guardada no Keychain com `biometryCurrentSet`, apenas para este dispositivo, e o cofre volta a bloquear quando o app passa para segundo plano. Os ficheiros não entram no backup e as cópias temporárias criadas para Quick Look são eliminadas ao fechar.

## Localização do grupo

Cada participante pode ativar ou desligar voluntariamente a partilha de localização aproximada. O app usa permissão `When In Use`, atualiza apenas enquanto está aberto e remove o ponto do Supabase quando a partilha é desligada. O mapa mostra o nome e a hora da última atualização. Antes de usar, execute `supabase/location_sharing.sql` no SQL Editor do projeto para criar a tabela e as políticas RLS restritas aos seis e-mails.

As despesas e fotografias também podem ser partilhadas entre os participantes, mantendo cópias locais para funcionamento offline. Execute `supabase/trip_sharing.sql` no SQL Editor do Supabase para criar as tabelas, o bucket privado de fotografias e as respetivas políticas RLS. As fotos só podem ser alteradas ou eliminadas pelo participante que as publicou.

## Despesas

O módulo de despesas regista valores em BRL, AED e JPY, converte automaticamente com taxas Frankfurter guardadas para uso offline, acompanha o orçamento diário do grupo e divide cada lançamento entre participantes selecionados. Os saldos indicam quanto cada pessoa deve ou tem a receber. Os lançamentos ficam protegidos localmente pelo sistema de proteção de ficheiros do iOS.

## Compras

O menu Compras fotografa produtos e etiquetas, usa Vision OCR local e assume sempre que os valores reconhecidos estão em ienes japoneses. O valor pode ser corrigido antes de guardar e é convertido imediatamente para real, euro e dólar. Existe uma estimativa opcional de tax-free japonês e o botão Comprei cria diretamente um lançamento no módulo Despesas.

## Privacidade

Localizadores de voos e referências de hotéis não foram gravados diretamente no código. Consulte o PDF original quando necessário. O estado do checklist fica apenas no aparelho, em `UserDefaults`. A autenticação é local e nenhum dado é enviado para um servidor.

## Dados que precisam de confirmação

- Data do voo de retorno: 24 ou 25 de julho.
- Estadia em Kyoto/Osaka: o resumo e o roteiro diário divergem.
- Unidade do teamLab: Planets ou Borderless.
- Ordem de Shitennoji e transferência Kyoto → Osaka em 22 de julho.
