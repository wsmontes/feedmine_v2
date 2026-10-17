# Leitor — suficiência do texto local e linguagem de disponibilidade

Data: 2026-10-17 (America/Vancouver). Revisão estática autorizada pelo dono para commit. Somente documentação; sem build, testes executados ou alteração do app nesta sessão.

## Decisão existente: preservar, não reinventar

Ler `docs/reviews/2026-10-11-reading-decision.md`, `2026-10-11-reading-implementation-evidence.md`, `2026-10-11-reading-po-verdict.md` e F14. A decisão aprova leitor sobre texto já guardado, acesso explícito ao site, identificação honesta de conteúdo parcial e nenhuma aquisição iniciada pela renderização. Extração integral está fora do escopo; não criar segundo cache ou arquitetura de conteúdo.

Existem evidências históricas de leitura local, ausência de requisições pelo leitor e retorno ao mesmo card com delta 0,0 pt. Elas não certificam automaticamente o HEAD atual, mas impedem apresentar essa entrega como inexistente.

## 1. Suficiência é tratada de modo assimétrico

`Sources/FeedMineUI/Reader/FeedReadingDecision.swift`, `target`:

- qualquer `body` não vazio após trim abre `.local`;
- `summary` só abre localmente quando tem pelo menos `substantialSummaryCharacters = 3000`;
- caso contrário, retorna `.site` se houver endereço, ou nil.

Consequência direta: corpo de uma frase abre tela própria, enquanto resumo legível menor que o limite segue para o site. A diferença de campo não prova diferença de suficiência ou completude. Isto identifica a regra executável; não reproduziu defeito de UI nem determina um novo limiar.

Encaminhamento: reconciliar a regra com o critério aprovado de texto substancial, distinguindo procedência, utilidade para leitura e completude. Não substituir 3000 por outro número arbitrário, não chamar extensão do texto de prova de artigo integral e não mudar política apenas para obter teste verde.

## 2. Texto local curto não tem destino local neste caminho

A mesma regra descarta o acesso local ao resumo abaixo do limite na decisão primária: com URL abre site; sem URL não produz destino. `AppComposition.readingTarget` passa corpo da revisão, resumo da revisão ou texto publicado e o endereço ao decisor; `read` simplesmente retorna se não houver alvo.

Uma abertura primária direta ao site para teaser foi aprovada. Portanto, **não registrar toda abertura ao site como regressão**. A lacuna a resolver é distinguir "não deve ser a leitura principal por ser teaser" de "texto disponível não pode ser consultado localmente", especialmente para salvos/offline e ausência/falha do endereço. Preservar gesto simples sem tela intermediária inútil e a especificação de salvos offline já registrada.

Definir uma saída honesta para texto local existente sem destino web utilizável; não prometer artigo completo, extração automática ou sucesso de Safari offline. Conferir alcançabilidade de cada caso antes de afirmar que existe botão morto reproduzido.

## 3. Mensagem afirma disponibilidade externa não comprovada

`FeedReadingDecision.target` cria `FeedReadingContent` com `isPartial` padrão true. `Sources/FeedMineUI/Reader/FeedReadingSurface.swift`, `origin`, mostra "Conteúdo parcial: o artigo completo está no site." quando esse flag está ativo.

A política conservadora de não afirmar completude local é correta. Contudo, não comprovar completude local não prova que o texto é truncado nem que há artigo completo acessível no site. O destino pode ser ausente, indisponível ou exigir assinatura; um feed pode ter fornecido texto integral sem evidência suficiente para certificá-lo.

Direção de linguagem: dizer o que o app sabe — texto fornecido pela fonte, cuja integralidade não foi confirmada — e oferecer consulta ao site quando houver endereço válido, sem garantir acesso ou completude externa. Exemplo de sentido, não copy final aprovada: "Texto fornecido pela fonte. A versão no site pode conter mais conteúdo." Não buscar a página só para justificar uma frase da interface.

## 4. Referência V1 e cuidados com achados antigos

V1 `feedmine/Views/ArticleReaderView.swift`: `ArticleReaderView` abre `ArticleWebView`; `makeUIView` faz `webView.load(URLRequest(url: url))`; há progresso por `estimatedProgress`, comando Safari e `MiniPlayerBar`. Esse caminho não escolhe uma superfície de corpo local armazenado. A V2 possui um avanço real de leitura local e deve preservá-lo.

Da V1, avaliar feedback de navegação web e continuidade de playback, conforme requisitos vigentes, sem copiar WKWebView automaticamente. A troca para SFSafariViewController foi aceita; `FeedMineApp/InAppBrowser.swift` delega navegação ao sistema.

O defeito histórico de truncamento do botão em acessibilidade não deve ser reaberto como se não houvesse correção: o código atual do cabeçalho usa rótulo curto "Site" com identificação acessível "Abrir no site". Isso é observação de código, não nova certificação visual.

## Provas esperadas após definição/correção

- Corpo curto, corpo substancial, resumo curto, resumo substancial e ausência de texto; não confundir origem do campo com completude.
- Texto local com URL, sem URL e com site indisponível; o usuário entende o que pode ler e consegue sair.
- Salvo reaberto offline mantém acesso ao conteúdo local prometido, sem depender do navegador remoto.
- A renderização não inicia aquisição; abrir site é ação explícita quando apropriado.
- Fonte/título/data e procedência corretos; linguagem não promete integralidade ou disponibilidade desconhecida.
- Abrir/fechar e site→texto→feed preservam contexto, card e posição durante trabalho concorrente; Dynamic Type e playback conforme contratos vigentes.

Não alterar benchmarks congelados. Não interpretar as evidências de 11/out como testes executados nesta sessão. Este commit documenta a diferença entre contrato aprovado, regra atual e pontos a reconciliar; não implementa ou certifica solução.
