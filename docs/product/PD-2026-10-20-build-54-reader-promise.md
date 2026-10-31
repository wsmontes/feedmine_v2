# PD-2026-10-20 — Build 54: a promessa do leitor antes de qualquer nova superfície

**Papel:** gerente de produto. **Autoridade:** decisão de escopo e de aceite; o "como" pertence ao team lead e ao arquiteto.
**Base:** build 53 (`568098db`, tag `ios/1.0-build.53-568098db`), TestFlight interno. Evidência de 2026-10-20: gates B01–B05 no simulador dedicado, corrida física `bench/run/20261020T152325Z`, e inspeção de código na árvore do produto.
**Revisão do dono:** 2026-10-20, consulta em voz de dono. Aprova a direção com três mudanças: vídeo mantém identidade própria, `og:image` sem meta artificial e sem bloquear o feed, e perda da biblioteca V1 é inaceitável. As decisões abaixo já incorporam essa revisão.

Este documento não substitui o benchmark B01–B06. Ele decide **o que falta para a build 54 poder ser chamada de beta do produto**, e não apenas de beta da infraestrutura.

## 1. O que está entregue, medido

| Fato | Evidência |
|---|---|
| B01–B05 PASS no simulador dedicado, pelo entrypoint correto | `proc gates3` (2026-10-20 09:52–10:46Z); B01 475 alvos / 94 fontes contribuintes; B02 200/200 relevantes, 79 fontes, 4,5% máximo; B03 3.157 avanços, 2.256 cartas distintas, 0 stalls, 0 repetições; B04/B05 PASS |
| Captura B06 consultada sem medição válida | `proc b06full2` refere-se à tentativa `20261020T111032Z`: nenhum PID e recursos `NOT_MEASURED`. Não representa todas as capturas posteriores; a corrida `20261020T152325Z` possui dados parciais, sem fechar B06. |
| B03 físico não aplicou a cadência exigida | driver a ~0,55 gesto/s; 1.398 cartas distintas expostas; oráculo conta eventos `advance`, não consumo distinto. Isso não decide a capacidade do produto na cadência congelada. |
| Série de quadros do app registra degradação | 138 segundos com quadro ≥100 ms, pior 225,6 ms, numa corrida textual. Não houve isolamento causal entre produto, driver e instrumentação. |
| Podcast: a carta oferece "Tocar" e o host responde um aviso | `AppComposition.swift:2287` — `.media` sempre mostra "Mídia indisponível nesta compilação"; adapter e `ReaderMediaCoordinator` existem; o único caminho que toca algo é o episódio simulado de `#if DEBUG` (`:1498-1503`) |
| Vídeo: não existe superfície visual | zero `AVKit`/`VideoPlayer`/`AVPlayerLayer` no app; item `.video` vira card rotulado "Podcast" |
| Imagem: só quando o feed a declara | `SyndicationTranslator` lê 5 superfícies do feed, sem fallback `og:image`; corrida física: 0 candidatos de mídia, 1.652 cards `textOnly` |
| Primeira tela: entra com 1 card | `FeedScreen.swift:66` monta o leitor quando `renderedItems` não é vazio; admissão tem teto (8/16) e nenhum piso de cobertura |
| "Falha ao atualizar o feed" cobre erros que não são do feed | `reportFailure` mapeia todo erro não-URL para `.failed`, inclusive clipboard, escrita de salvos, pressão de memória e background (`AppComposition.swift:4064-4092` e call sites) |
| Atualizar da V1 deixa a biblioteca anterior inacessível na V2 | arquivos V1 preservados; importador sem call site. Mesmo ligado, não cobre artigos salvos, mídia e posições. Não é evidência de destruição dos arquivos. |
| Salvo offline: imagem sim, áudio não | bytes de imagem em Application Support com teste de relançamento; candidatos `playback` nunca são baixados |
| Jornada de mídia no catálogo publicado, fixtures desligadas | `MEDIA_JOURNEY` (simulador, 20/out): 4 cartas, **1 imagem real desenhada**, áudio com identidade correta e relógio **2→3 s**, pausa **3→3 s** em 5 s, retomada **4 s**. Prova o caminho de imagem declarada e o player, não cobertura nem aparelho. |
| Cobertura de imagem medida no catálogo real | Amostra do team lead (20/out): 8.542 itens, **5.444 declaram imagem (63,7%)**; das 435 cartas publicadas, **64 com imagem renderizada (14,7%)** e 371 texto. Identidade: 53 áudio, 1 vídeo, 381 nenhuma. Candidatos de playback: 1.917 áudio, 25 vídeo. O gargalo está entre declaração e publicação, não na oferta. |

### Marco de implementação — 20/out, 18:10Z
Relato do team lead: `1f786344` admite texto+áudio no pool; `b248d76c` liga a ação de mídia ao canal existente; `a0bfe812` implementa D7-A, com 18 testes de unidade relatados verdes. **Não aceitos ainda como experiência comprovada:** não há prova física de áudio nem ensaio concluído de upgrade V1→V2. A identidade visual de vídeo (D2) continua aberta; mudar o pool não a resolve.

Evidência inspecionada pelo gerente: `docs/reviews/evidence/2026-10-20-first-screen/first-presented-screen.json` na árvore do produto registra primeiro conteúdo com **141 pt** para viewport de **730 pt**, `cards=1` e `render_ready_cards=1`. É reprovação de D4 em transporte de fixture; não prova o primeiro uso no catálogo real. O team lead está corrigindo o produto e executando o ensaio de upgrade. Nenhuma dessas entregas constitui aceite da build 54 ou da 1.0.

## 2. Decisões

### D1 — Áudio é obrigatório na build 54
O produto promete "ouvir". A build 53 oferece o botão e responde com um aviso: isso é uma promessa quebrada, não um adiamento. A fiação já existe; o host precisa executar o card, não recusá-lo.

**Aceite observável:** numa carta de podcast do catálogo publicado, tocar abre o player, o relógio avança, pausar/retomar funciona, a posição sobrevive a relançar e o mini-player convive com a leitura. Uma passagem no simulador (jornada de mídia) **e** uma no aparelho físico.

### D2 — Vídeo mantém identidade própria e não é prometido como player nativo
Não há superfície de vídeo; player nativo fica fora da build 54 interna, sem renúncia à visão futura do produto. Um item de vídeo não pode ser classificado como podcast nem oferecer um "Tocar" que só reproduz áudio.

**Aceite observável (decisão B do dono, 2026-10-20):** a carta se identifica como vídeo; o toque abre **o conteúdo correspondente na origem**, não uma página genérica; no iPhone real, o vídeo fica visível e reproduz **no Safari**; voltar ao FeedMine preserva exatamente a posição de leitura. Não há promessa de reprodução nativa nem controles internos. Player nativo fica para decisão posterior, não para esta rodada. Uma URL apenas aberta não satisfaz o critério.

### D3 — Imagem real do feed na 54; og:image no backlog (revisado pelo dono)
O feed só declara imagem quando a fonte a declara, e nenhum código do app busca `og:image`. Medição de 20/out no catálogo publicado, fixtures desligadas: 4 cartas, 1 imagem real desenhada, 0 textOnly.

**Decisão (dono, 2026-10-20):** a build 54 **não** exige `og:image`. Ela exige:
- imagem real renderizada **no iPhone**, sem fixtures e sem DEBUG;
- PD-5/PD-9 preservados: candidato dependente de imagem aguarda fora da fila publicável, outros prontos avançam; carta publicada é imutável;
- **cobertura de imagens no catálogo real registrada separadamente** — 4 cartas não demonstram cobertura satisfatória;
- `og:image` fica no backlog, com avaliação própria de custo, latência e impacto editorial.

Retirar `og:image` do escopo não resolve a apresentação visual: ela continua sendo preocupação de produto e será medida antes de qualquer conclusão sobre a 1.0.

### D4 — A primeira tela nasce preenchida
**Aceite observável:** primeiro quadro com prefixo editorial válido, render-ready e suficiente para preencher a área útil do viewport real, sem espera artificial nem piora de rolagem. Não existe piso universal de duas cartas; contagem não substitui utilidade, diversidade e geometria observável. Antes de haver conteúdo pronto suficiente, a preparação deve ser honesta. Uma mídia pendente não bloqueia os demais candidatos prontos.

### D5 — Falha honesta e recuperável
**Aceite observável:** "Falha ao atualizar o feed" só pode ser produzida por operações de atualização do feed; falha de rede mostra mensagem própria com ação de tentar de novo; erro de salvar/copiar não se apresenta como falha do feed. O conteúdo já lido nunca desaparece por causa de uma falha.

### D6 — B06 precisa medir o que diz medir
O FAIL físico atual não é absolvição nem condenação: é instrumento quebrado. O driver não sustenta a trilha congelada e o oráculo conta eventos, não cartas.

**Decisão:** até existir driver capaz de 1 card/s com rajadas de 3/s, B06 é **BLOCKED**, não FAIL nem INCOMPLETE. O oráculo deve contar cartas distintas e avanços `forward`. A série de quadros do app entra no relatório. Energia pode ficar `NOT_MEASURED` com a limitação do Xcode 26.6 registrada; CPU, RSS, memória, hitches e tempo de scroll não.

### D7 — Integridade da biblioteca: importar o que existe, dizer o que não veio (D7-A, decidido pelo dono)
Áudio offline fica fora da 1.0: o rótulo "Disponível offline" só aparece para o que o app guarda de fato.

**Fatos medidos:** a V1 existe aqui apenas em fonte (`~/Documents/GitHub/_legacy_feedmine_v1`), sem binário e sem usuário público conhecido. A V2 Release usa o **mesmo bundle id** (`com.feedmine.app`), então instala no mesmo contêiner. Os bancos não colidem (`Feedmine/user.sqlite` × `FeedMine/runtime.sqlite`), a V2 não escreve nem apaga dados da V1, e o único leitor abre somente-leitura. O importador existe sem call site e, mesmo ligado, descarta artigos salvos, mídia e posições. Hoje o efeito é **arquivos preservados, biblioteca invisível** — não destruição.

**Decisão (dono, 2026-10-20): D7-A na build 54.** Ligar o importador para fontes, caixas e coleções, com operação **idempotente**; preservar integralmente os arquivos V1 (nenhuma escrita ou exclusão); informar claramente **o que foi importado e o que ficou inacessível**. Provar que uma execução repetida não duplica nem corrompe dados. Reportar a **taxa de importação** (quantos itens existiam e quantos entraram, por categoria). O ensaio de upgrade é feito **em aparelho real ou simulador limpo**, com a mesma instalação — não em simulador sujo de outra corrida.

**Limite aceito:** artigos salvos da V1 podem ficar temporariamente inacessíveis na build interna — mas não são "perdidos", e a migração não é declarada concluída. Para a 1.0 pública, essa limitação exige nova decisão explícita; se houver usuários com biblioteca V1, o acesso aos artigos salvos precisa ser resolvido.

**Aceite de D7-A (20/out, rodada 5 em `67d49c86`):** caminho original `Application Support/Feedmine`; importação `completed` com fontes 3, caixas 1, coleções 1, membros 2; skip de artigos salvos reportado; arquivos V1 byte-idênticos; aviso visível aos 3 s e ainda presente aos 13 s, sem toque; `notice_presented` vira 1 somente no clique em "Entendi"; segunda abertura sem aviso e sem duplicação. Limites: simulador case-insensitive, banco V1 sintético, sem assinatura nem upgrade da App Store. Não é migração completa.

### D12 — Imagem pronta não pode envelhecer fora da publicação
A coorte mediu 3.836 preparações indisponíveis, das quais **3.663 por `over-ceiling`**, e **1.512 revisões com imagem pronta contra 3 publicadas**. Os dois mecanismos são independentes e ambos são falha de produto, não proteção.

**Decisão:**
- O orçamento dinâmico de bytes não pode rejeitar a imagem típica do slot. Tetos de segurança (12 MB, 12k px de lado, 50 MP) e o deadline continuam valendo; o orçamento derivado deve cobrir o caso típico e o efeito precisa ser medido na cobertura publicada.
- Candidato com imagem pronta precisa voltar à seleção enquanto elegível. Preparar e não oferecer à publicação é desperdício e produz um feed textual sem justificativa editorial.
- Sem quota de imagens e sem regra de mistura artificial antes do efeito medido. A meta é a variedade visual disponível chegar à experiência sem violar PD-5/PD-9.

**Interpretação aprovada pelo dono (20/out):** o mecanismo teto-de-segurança + deadline pode medir cobertura na 54, com condições: escolher a variante adequada ao tamanho de exibição quando existir (não baixar imagem enorme para exibir pequena); 12 MB é proteção, não orçamento operacional; deadline não descarta — candidato não publicado continua elegível e imagem pronta volta à seleção; exceção documentada quando a origem só oferece imagem superdimensionada; medir cobertura publicada, recusas por motivo, prontas não publicadas, latência e impacto na rolagem no iPhone real; sem remendar cartas publicadas nem bloquear prontas. **PD-6.1 não é declarada integralmente cumprida**; deadline e downsample são mecanismos, não evidência de experiência satisfatória.

### D13 — Restaurar a edição durável, não reconstruir o feed (decisão A do dono)
**Fato discriminado:** B05 passa antes de D10 e falha a partir de D10 (pool texto+áudio). Na reabertura a edição é reconstruída com o pool atual, a âncora salva não é encontrada e o leitor cai no topo; `b05-reopen-preserves-anchor=false`. D4 está inocentado (falha sem ele).

**Decisão do dono (20/out): A.** Manter D10 e corrigir a restauração. Condições:
- restaurar a **edição publicada e durável**, não reconstruir o feed na reabertura;
- preservar âncora, posição relativa e estado salvo, inclusive offline;
- teste discriminante com pool misto texto+áudio comprovando que a **mesma edição** é restaurada;
- **B05 verde** e B01–B04 sem regressão, sem alterar oráculos;
- a build 54 espera o B05 passar; rollback preventivo de D10 não é autorizado.

**Hierarquia:** continuidade da leitura acima de calendário e acima da expansão da oferta. Se surgir impedimento estrutural comprovado, a evidência volta ao dono — não se decide rollback por conta própria.

### D8 — Portão da build 54 e autorização do dono
**Decisão do dono (20/out): opção B.** A build 54 vai ao **TestFlight interno** como build de validação, mesmo sem sessão física automatizada (iPhone indisponível para o `devicectl`). Condições:
- rodar **regressão B01–B05** no simulador antes do envio; não presumir que o PASS da build 53 vale para a 54;
- entregar o roteiro objetivo de cinco testes físicos (áudio, vídeo/Safari, imagem, primeira tela, rolagem/retorno);
- identificar claramente o que foi comprovado e o que segue sem evidência;
- manter **B06 BLOCKED**, sem inventar PASS;
- preservar os dados existentes na instalação;
- o dono valida no próprio iPhone e devolve os resultados.

A **1.0 continua decisão separada** e exige o fluxo completo num iPhone real, com B06 válido e parecer do arquiteto. A build 53 permanece a beta atual; ninguém a descreve como multimídia.

### D10 — Descoberta automática admite texto + áudio (decidido pelo dono)
**Fato medido:** o pool de descoberta só admite texto — `ReaderDiscoveryPool.swift:129` (`mediaKinds` default `["text"]`), sem override em `AppComposition.swift:1998`. O catálogo embarcado tem 71.234 fontes habilitadas: 17.798 texto, 23.446 áudio, 29.983 vídeo. O "feed só de texto" observado pelo dono tem causa estrutural: a descoberta nunca inclui podcast nem vídeo.

**Decisão (dono, 2026-10-20):** a descoberta automática passa a admitir **texto + áudio**, sem preferência artificial por texto.
- A identidade de mídia da carta vem do **item/enclosure**, nunca do `media_kind` da fonte. Fonte de vídeo pode carregar item de áudio e vice-versa.
- Fontes de vídeo já seguidas continuam acessíveis, com itens corretamente identificados.
- Vídeo **não** entra no pool automático nesta rodada (B fica para uma rodada específica de descoberta multimídia). Isso não exclui vídeo do produto: controla a entrada automática.
- Provar no aparelho: podcast real aparecendo e tocando, além de distribuição texto/áudio, diversidade de fontes, latência e estabilidade da rolagem.

### D11 — A evidência de mídia é real, não fixture
O modo DEBUG tem feeds de desenvolvimento que podem declarar PNGs gerados (`FEEDMINE_FIXTURE_MEDIA=image`). Isso é testemunha de teste, não imagem de fonte real. A prova de D1/D3 exige execução com as variáveis de fixture **desligadas**, contra o catálogo publicado e rede de verdade. Imagem gerada por fixture não conta. O mesmo vale para D4: a primeira tela também precisa ser medida contra o catálogo publicado, não apenas com transporte de fixture; fixture prova mecânica, não a experiência do leitor real.

### D9 — Cortes e exigências do dono
**Cortado da 54:** player nativo de vídeo, áudio offline e qualquer expansão de mídia além do necessário para cumprir D1–D3.
**Exigido além:** teste discriminante para cada correção, ausência de regressão B01–B05, teste físico de áudio, e prova de que a abertura inicial preenchida não introduziu bloqueio nem jank na rolagem. PASS no benchmark não substitui qualidade de produto.

### Revisão pelo embaixador e decisão posterior do dono
Consulta concluída em 2026-10-20 nas conversas `6ad7a705-83d4-83e8-8617-55328ac6407e` (embaixador documental) e `6ad7a15c-c5f0-83e8-8d12-cb41e6566adb` (voz do dono). O embaixador fundamentou o parecer em PD-3, PD-5, PD-9, INV-17 e F15; o dono confirmou explicitamente que essa interpretação **substitui a orientação anterior** sobre imagem tardia e quota de cartas. Exige regressões discriminantes para publicação imutável, falha transitória de imagem e avanço independente dos candidatos prontos. Gates intactos; nenhuma mudança de oráculo para acomodar implementação. A consulta passa a seguir embaixador → gerente de produto → dono, antes de novas decisões de produto.


## 3. Ordem de trabalho

1. **D7 integridade da biblioteca** — primeiro, porque é requisito de confiança e condição do envio interno.
2. **D10 + D1 áudio real** — o pool de descoberta precisa admitir áudio (texto + áudio) antes de a fiação da carta provar qualquer coisa; a fiação existe e a jornada de mídia já é o instrumento; nada de stub.
3. **D4 primeira tela** e **D5 falha honesta** — o que o dono viu no aparelho.
4. **D2 identidade de mídia** — vídeo deixa de se disfarçar de podcast e de oferecer ação morta.
5. **D3 imagem real** — `og:image` sem bloquear a publicação; medir descoberta, obtenção e renderização separadamente.
6. **D6 medição física** — em paralelo, sem bloquear 1–5.

## 4. O que não fazer agora

- Não portar oportunidades da V1 (carrossel, estatísticas, card exportável) por conveniência.
- Não transformar a jornada de mídia em aceitação de áudio: quadro visível de vídeo não é relógio avançando.
- Não recalibrar B01–B06 para fechar a build.
- Não anunciar "multimídia" enquanto D1–D3 não tiverem prova no aparelho.

## 5. Como atualizar esta decisão

Cada entrega registra a jornada do leitor afetada: antes/depois, estado atual, evidência observável e pendência seguinte. Contagem de testes acompanha a entrega; não a substitui. Este documento é atualizado em marcos funcionais, não a cada rodada.

## 6. Roteiro de aceitação no aparelho (para o dono, não para o time)

Cinco testes objetivos, sem fixture, com o app instalado e a rede normal. Cada falha é reprovação:

1. **Áudio.** Tocar um card de podcast: abre o player, o relógio conta, pausa congela, retomar continua. Sair do app e voltar mantém o episódio e a posição.
2. **Vídeo/Safari.** Abrir um card de vídeo: ele se identifica como vídeo, abre **o conteúdo correspondente** na origem, o vídeo fica visível e reproduz no Safari. Voltar ao FeedMine mantém exatamente a posição de leitura.
3. **Imagem.** Rolar as primeiras cartas e contar quantas mostram foto desenhada. Registrar o número; uma imagem isolada não prova cobertura.
4. **Primeira tela.** Abrir o app: o feed aparece já preenchido até o fim da área útil, sem um card sozinho e o resto chegando depois.
5. **Rolagem/retorno.** Rolar por cerca de dois minutos sem travar; abrir uma carta, voltar e conferir a mesma posição; alternar A→B→A e voltar.

Se o aparelho tiver dados da V1: na primeira abertura, o app diz o que trouxe e o que ficou inacessível — e não chama isso de migração concluída.

## 7. Texto de envio ao TestFlight interno (rascunho)

Usar na descrição "What to Test" da build 54, sem prometer 1.0:

> **Build de validação — não aprovada para release.**
> Esta build testa: descoberta com texto e áudio; reprodução real de podcast; primeira tela preenchida; imagem real quando a fonte oferece; vídeo identificado como vídeo, aberto na origem; mensagens de erro por operação.
>
> **Cinco testes, por favor:**
> 1. **Áudio** — toque um podcast; o relógio conta, pausa congela, retomar continua; saia e volte ao app e confira a posição.
> 2. **Vídeo/Safari** — abra um card de vídeo: ele se identifica como vídeo, abre o conteúdo certo na origem e reproduz no Safari; voltar ao FeedMine mantém a posição.
> 3. **Imagem** — role as primeiras cartas e conte quantas mostram foto desenhada.
> 4. **Primeira tela** — abra o app: o feed aparece preenchido até o fim da área útil, sem um card sozinho.
> 5. **Rolagem/retorno** — role por ~2 minutos sem travar; abra uma carta, volte e confira a mesma posição; alterne A→B→A.
>
> Limitações conhecidas: B06 (medição física) BLOCKED por instrumento; áudio fora do modo offline; a biblioteca V1 é importada para fontes, caixas e coleções, mas artigos salvos continuam acessíveis apenas no arquivo da V1.
> O que **não** observar como aprovado: 1.0, paridade V1 completa, reprodução nativa de vídeo.

O envio não deve afirmar "multimídia completa", "migração concluída" nem "release aprovada".

## 8. Avaliação exploratória da 1.0 (aprovada pelo dono, 20/out)

Complementar aos gates B01–B06, sem substituí-los, sem pontuação composta e sem metas percentuais. Objetivo: saber se o FeedMine desperta vontade de continuar lendo sem ninguém explicar por quê.

- **Cinco participantes que nunca tiveram contato com o FeedMine** (não misturar conhecidos do produto).
- Catálogo real, uso livre, **sem explicar funcionalidades** nem induzir comportamento.
- **Dois encontros em dias diferentes**: o retorno revela continuidade, não apenas curiosidade inicial.
- Registrar comportamento e respostas **sem tratá-los como votos** de qualidade editorial (F02 §5).
- Separar **usabilidade**, **relevância editorial** e **confiança no conteúdo**.
- Inspecionar imagens, títulos e destinos como problemas concretos de apresentação.
- Perguntas espontâneas ao final: algo inesperado? o que ficou? pareceu repetitivo, arbitrário ou pouco confiável? voltaria e por quê?

**Racional (embaixador):** proxies de novidade, coerência e retorno servem como tela de reprovação (detectam monotonia, repetição, falta de novidade), **não** como critério de sucesso. Coerência não é propriedade objetiva a pontuar: uma mudança inesperada de assunto pode ser a melhor parte. A experiência relatada e observada tem precedência sobre qualquer indicador automático.

Este estudo é da 1.0; não bloqueia a build 54 interna.

## 9. Política de verificação (decidida em 20/out)

- **Gate por candidata, não por mudança:** B01–B05 rodam no congelamento da candidata (antes de upload/release); B06 físico só na final. Não se roda a matriz a cada alteração.
- **Por mudança:** apenas o alvo afetado + testes de risco. Pacote completo no congelamento; UI completa só pré-release. Exceção: mudança em restauração, mídia, primeira tela ou publicação roda na hora a jornada discriminante correspondente.
- **Suíte vermelha não é dívida aceita na candidata:** os 10 FAILs de `ReaderDiscoveryPoolTests` bloqueiam a build 54 até serem corrigidos ou provados idênticos no commit-base anterior a D10, com a regressão registrada.
- **Gate de produto:** B01–B06, os cinco testes físicos, ensaio D7, cobertura de mídia e imutabilidade da publicação.
- **Higiene de engenharia (pode reduzir):** tempo de unidade/integração, testes que leem código-fonte, UI completa, duplicados. Os 11 testes que leem fonte podem sair (SwiftPM garante imports); os smoke tests de fronteira arquitetural ficam.
- **Níveis:** L0 unidade <10 s; L1 integração <60 s; L2 pacote <3 min; L3 UI smoke <5 min **incluindo as jornadas do leitor** (primeira tela, áudio); L4 gates na candidata.
- **Instrumentos:** stub com `stopLoading` vazio é defeito do instrumento, não do produto; o teste de 60 s deve ser corrigido, não acomodado. Processo de teste pendurado é morto, não esperado.

## 10. Riscos abertos registrados

- **Cancelamento de download durante os headers não cancela a tarefa de rede.** `URLSession.bytes(for:)` é aguardado antes de o handle da task existir; cancelar nesse intervalo não interrompe a `URLSession` task. O timeout de 1 s no teste é mitigação do instrumento, não conserto de produto. O conserto correto é data task gerenciada com cancelamento no header. Risco: trabalho de rede continua após mudança de contexto/consumo; prioridade para a 1.0, não bloqueia a 54 interna.
- **Cobertura de imagem publicada** ainda precisa ser medida depois das correções de orçamento e reoferta; 14,7% é a linha de base, não o resultado.
- **B06 físico** segue BLOCKED por instrumento; não há PASS inventado.
