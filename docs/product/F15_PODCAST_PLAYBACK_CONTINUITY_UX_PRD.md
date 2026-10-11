# F15 — Podcasts: tocar, escutar, navegar e retomar

**Status:** especificação de produto/UX candidata, 2026-10-10. Não é plano técnico nem evidência de execução.  
**Autoridades:** [North Star](PRODUCT_NORTH_STAR.md), [decisões PD](PRODUCT_DECISIONS_2026-10-09.md), [invariantes](../architecture/PRODUCT_INVARIANTS.md), [B01–B06](DISCOVERY_ACCEPTANCE_BENCHMARK.md), [mapa de dependências F11–F20](PRODUCT_SPEC_DEPENDENCIES_F11_F20.md) e [inventário V1→V2](../v1-study/UI_TRANSFER_MATRIX.md).  

## 1. Promessa

Um episódio deve ser experiência de áudio durável enquanto o feed segue navegável. O leitor sabe o que está tocando, controla reprodução e consegue retomar após distração, interrupção ou relançamento.

**Produto pronto:** Provas A–D com episódio efetivo, interrupção e relançamento; same item/position e sem salto de feed. Cobrar B04/B05 e físico B06 quando aplicáveis; casos faltantes ficam NOT_RUN.

## 2. Evidência e gargalo V1→V2

V1: `AudioPlayerManager` + mini/full player, seek ±15, persistência de posição e informações do episódio. V2: mini/full player e adapter AVFoundation estão presentes e possuem alguns testes de UI; **salvar/restaurar posição real** e transições de lifecycle ainda não têm prova suficiente na matriz. A prova parcial de componentes não equivale a aprovação da experiência completa.

## 3. Requisitos de comportamento (não de arquitetura)

- **R1 — Ação explícita:** tocar card/controle de áudio inicia o episódio correto, com título, origem, duração/progresso quando conhecidos. Renderização do feed não inicia áudio nem rede.

- **R2 — Controles utilizáveis:** play/pause, seek e close têm resultados previsíveis; o estado da versão compacta é coerente com o player expandido.

- **R3 — Continuidade entre telas:** scrolling, abrir artigo, ir a uma coleção, trocar de contexto ou voltar ao card não reiniciam o episódio ou reordenam cards.

- **R4 — Retomada:** episódio e posição são recuperados após fechamento/relançamento segundo regra apresentada ao usuário; se a URL não puder mais tocar, informar claramente o motivo e manter referência ao item.

- **R5 — Interrupções reais:** chamadas, áudio de outro app, conectividade indisponível, background e condições permitidas pelo iOS têm transição compreensível; não prometer reprodução offline de episódio não baixado.

- **R6 — Mídia e geometria:** artwork ausente ou tardia não muda tamanho/posição do card publicado; não bloquear runway exigindo download do arquivo de áudio para todo card.

## 4. Benchmark UX15 — oráculo externo

| Caso | Jornada observável com dados reais rotulados | Aceite verificável |
| --- | --- | --- |
| **UX15-A** | Escolher episódio P, tocar, pausar, avançar e retornar do player grande ao compacto. | Mesmo episódio/tempo e mesmos controles reais, não apenas labels. |
| **UX15-B** | Com P reproduzindo, rolar feed e abrir outra história/coleção. | Áudio continua segundo escolha; posição de scroll não muda por eventos do player. |
| **UX15-C** | Progredir P, suspender, relançar; retomar P. | Reabre episódio correto e posição salva conforme contrato, sem voltar arbitrariamente ao início. |
| **UX15-D** | Interromper áudio por sistema/rede e tentar retomar offline. | Estado é honesto; não declara download/offline inexistente; UI continua navegável. |

Registre vídeo/captura, identidade do conteúdo, estado anterior e posterior, versão do app/dispositivo, e **PASS / FAIL / NOT_RUN / BLOCKED** por caso. Os gates [B01–B06](DISCOVERY_ACCEPTANCE_BENCHMARK.md) não são reduzidos nem substituídos. O benchmark não pressupõe quantidade fixa de páginas, tempos de retry ou algoritmo especial.

## 5. Dependências documentais e escopo

[F03](F03_ACQUISITION_FRESHNESS_STORY_INTEGRITY_PRD.md); [F06](F06_SACRED_FEED_CARD_READINESS_PRD.md); [F08 e F09](PRODUCT_AUDIT_10_FRONTS.md); [F10 dispositivo físico](PRODUCT_AUDIT_10_FRONTS.md); [F14 leitor web](F14_READER_LINK_NAVIGATION_UX_PRD.md); [F20 retorno](F20_RETURN_FRESHNESS_LIFECYCLE_PRD.md).

**Fronteira:** F06 garante prontidão do cartão; F15 avalia consumo **depois do play explícito**, não cria download remoto no renderer. Não incluir vídeo por dedução de um contrato de áudio.

**Não-objetivos:** copiar controles da V1 sem necessidade, promover componente existente a prova de UX, ou reescrever história já publicada.

## 6. Estado de aceitação

**NOT_RUN** como jornada UX15 integral. Relatórios de código/testes da matriz V1→V2 são evidência preliminar, não um PASS de produto. Toda divergência de escopo deve ser registrada explicitamente antes de ofertar o controle ao usuário.

---

## Referências técnicas externas — F15

Estas referências complementam o PRD e não alteram seus critérios de aceitação, nem comprovam funcionalidade já implementada.

**Aplicação:** Player com posição durável e retomada após interrupção.

- [AVPlayer](https://developer.apple.com/documentation/avfoundation/avplayer) — Streaming, seek e playback.
- [Monitoring playback progress](https://developer.apple.com/documentation/avfoundation/monitoring-playback-progress-in-your-app) — Persistir posição de reprodução.
- [Handling audio interruptions](https://developer.apple.com/documentation/avfaudio/handling-audio-interruptions) — Retomar após interrupção.
- [MPRemoteCommandCenter](https://developer.apple.com/documentation/mediaplayer/mpremotecommandcenter) — Comandos remotos.

**Índice integral:** [Pesquisa F01–F20](../research/FeedMine_V2_referencias_F01-F20_2026-10-10.md). Usar os responsáveis/pipelines já existentes; não criar um mecanismo concorrente por causa de uma API ou padrão de interface.
