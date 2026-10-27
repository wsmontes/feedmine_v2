# Auditoria das pendências de aceitação — 2026-10-27

Árvore inspecionada: `c37146bb`, branch `product/nf04-tail-truth`. A rodada anterior foi progresso:
fix de fila de mídia com RED causal, 1742 testes/1 skip/0 falhas e revisão independente.
Esta rodada reconcilia lacunas atuais, sem implementar feature, rodar gate ou certificar release.

## Ordem de retomada

| Frente | Evidência atual | O que falta |
|---|---|---|
| B03 | FAIL da corrida `20261026T143646Z`; detector corrigido, negativo 17/17 MISS | calibração positiva com transporte fiel, consumo efetivo e anti-tap, depois replay completo; §7 de `2026-10-26-b03-pacing-calibration.md` |
| B06 | **iPhone 14 Plus pareado, disponível e acessível nesta rodada** | instalar candidata identificada de benchmark e executar B03 com recursos no aparelho; não há bundle `com.feedmine.development.benchmark` instalado |
| Reserva P1 | teto `targetDepth + 16` e testes de concessão limitados | nenhuma prova de desbloqueio geral se os 16 extras forem incompatíveis; não ampliar teto silenciosamente |
| F13 | editor de palavras/modelos e switch já existem e estão ligados aos Ajustes | completar contrato de exclusão por fonte e provas UX13-A–D; não reconstruir editor existente |
| Release | testes do pacote verdes não são gates de aceitação | identidade de candidata + gates, UI e recursos; sem autorização de distribuição nova |

## B06: o bloqueio de aparelho mudou

`xcrun devicectl list devices` retornou iPhone 14 Plus `available (paired)`.
`device info lockState` adquiriu túnel e usage assertion: `passcodeRequired: false`,
`unlockedSinceBoot: true`. Consulta exata por `--bundle-id com.feedmine.development.benchmark` terminou
com sucesso e lista de apps vazia. Não é correto continuar dizendo apenas "aparelho ausente/travado".

Consultas somente de leitura: nenhum app iniciado, instalado, removido ou alterado no aparelho.
Sem benchmark no device e sem ensaio de recursos: B06 **NOT_RUN nesta rodada**, não PASS.
A consulta inicial `device info details` feita no sandbox terminou em timeout do CoreDeviceService;
a consulta de lockState executada com acesso aprovado foi a medição válida subsequente.

## F13: separar implementação existente de aceitação ausente

O §2 do PRD F13 descreve a ausência de editor como estado conhecido de 10/out. Na árvore atual:

- `ReaderContentFilterView` tem switch, modelos, adição por vírgula/newline/ponto-e-vírgula e remoção;
  `ReaderSettingsView` abre a tela, e `FeedMineApp.swift` fornece o backend real.
- `ReaderContentFilterAdapter` grava `ReaderSettings.contentFilterRules`, templates e switch;
  `ReaderContentFilterPolicy` combina palavras/modelos, e `ReaderFilterEligibility` aplica as regras
  a **título ou resumo**. Correspondência por substring, sem distinguir maiúsculas/minúsculas;
  a copy da tela declara título/resumo e o mesmo escopo. Não há regex ou inferência de body nesse caminho.
- Fechar a superfície chama `reapplyReaderFilters` no host. Os testes de app em `ContentFilterTests`
  exercem filtro global + filtro de contexto, switch e templates, mas não foram rodados nesta auditoria.
- A regra de expiração separa o contexto temporário das exclusões (`ReaderFilterExpiry`).
- Não foi identificado owner de exclusão durável por fonte: os settings/exclusions aqui são palavras
  e templates; `excludedTopicNodeKeys` é descoberta por assunto, não uma lista de fontes bloqueadas.
  Um toggle de seleção de fontes não deve ser tratado como essa exclusão (ver revisão S1).

| Requisito F13 | Cobertura identificada | Limite |
|---|---|---|
| R1 significados distintos | filtro contextual, exclusões de palavras e preferências de descoberta possuem owners | exclusão durável por fonte não encontrada; UX13-C não comprovada nesta rodada |
| R2 regras visíveis | editor ligado aos Ajustes | leitura de código, sem jornada UI nova |
| R3 coincidência previsível | copy título/resumo + matcher por substring | sem observação de falsos positivos na UI |
| R4 histórico/salvos | contrato de contexto e testes de app existentes | teste de filtro que esvazia antes do launch não prova preservação de uma sequência já publicada |
| R5 durabilidade/expiração | settings persistidos e expiry separada | relaunch/A→B→A de UX13-D não executado aqui |
| R6 vazio recuperável | política consegue produzir zero candidatos | não há prova nesta rodada de copy específica/ação correta na superfície vazia |

`swift test --scratch-path .build/index-build --disable-index-store --jobs 2 --filter
ReaderContentFilterPolicyTests`: **8 testes, 0 falhas**, 0,005 s. Log em
`evidence/2026-10-27-acceptance-audit/f13-policy.log`. É prova da política pura, não PASS UX13.
`SourcesAndFilterJourneyUITests` cobre outros gestos de fonte/lente; não substitui UX13-A–D.

## Capacidade e limites

`df -h .`: **682 MiB** livres no início. `/Volumes` só lista o volume do sistema e o instalador
ChatGPT; não foi identificado volume de trabalho alternativo. `simctl list devices booted` retorna
nenhum simulador ativo. A guarda de 3 GiB do ensaio permanece não satisfeita. Não houve limpeza de
cache, simuladores, bancos ou evidências. Caches próprios encontrados não foram apagados nem somados
como se fossem espaço já disponível.

Para retomar B03/B06 com build e evidência novos é necessário espaço suficiente, medido imediatamente
antes do trabalho. A disponibilidade atual do iPhone deve ser revalidada nesse momento.
Nenhuma autoridade de produto, régua ou relatório histórico foi editado para converter pendência em PASS.

Consulta repetida incluindo `--include-default-apps`: **0 resultados**. Payload filtrado preservado em
`evidence/2026-10-27-acceptance-audit/benchmark-app-query.json`. Disco no encerramento: **723 MiB**.
