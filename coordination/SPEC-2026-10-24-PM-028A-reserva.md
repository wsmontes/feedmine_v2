# SPEC — PM-028A: reserva de apresentações preparadas

Base: `6474984b` (v6 editorial já commitado). Branch `product/reserve-20261024`, worktree
`/Users/wagnersilvamontes/.codex/worktrees/feedmine-reserve/feedmine_v2`.

Esta spec foi aprovada pelo PM (ChatGPT) com três ajustes, transcritos na seção 4. Siga-a ao pé da letra;
quando algo não estiver dito, escolha a opção mais conservadora e registre a escolha no relatório.

## 1. Escopo exato

**Escreve (só estes caminhos):**
- `Sources/FeedMineRuntime/PreparedReserve.swift` (novo)
- `Tests/FeedMineRuntimeTests/PreparedReserveTests.swift` (novo)
- `Tests/FeedMineRuntimeTests/PreparedReserveIntegrationTests.swift` (novo)
- `Sources/FeedMineRuntime/MediaPrefetcher.swift` — só se precisar expor o resultado de uma conclusão
  tardia; não mude a semântica de prazo nem a concorrência.
- `FeedMineApp/FeedMineApp/AppComposition.swift` — apenas: `examinedCandidateCapacity` 32 → **128**,
  construção da reserva, ligação `onReadinessChanged`/publicação, e um evento de traço por ciclo.
- `FeedMineApp/FeedMineAppTests/CompositionTests.swift` — só se uma expectativa existente passar a
  falhar por causa da profundidade 128.

**Não toca:** `Sources/FeedMineEditorial/**`, `Sources/FeedMinePersistence/**`, `bench/**`,
`docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md`, `bench/oracle.py`, `bench/EVALUATOR.sha256`,
`coordination/**`.

**Não roda `xcodebuild`** (o simulador pertence a outra sessão nesta rodada). Verificação por `swift test`
e, se precisar do alvo nativo, diga no relatório em vez de rodar.
**Não muda o tamanho da rajada de publicação** (`forwardWindowCards` fica 16; nenhuma fatia passa a
publicar mais por causa da reserva).

## 2. `PreparedReserve` — contrato

Ator em `FeedMineRuntime`. Não duplica o dado binário: a apresentação pronta continua em `MediaReadiness`;
a reserva é o índice de **estado + política + orçamento**.

```swift
public actor PreparedReserve {
    public enum Phase: Hashable, Sendable {
        case pending                    // nunca tentado, ou liberado por orçamento
        case preparing(attempt: Int)    // trabalho em voo
        case ready(hasImage: Bool)      // preparado, ainda não publicado
        case published                  // saiu na edição; não volta a competir
        case deferred(retryAt: Double)  // condição estrutural (orçamento/condições); não gasta tentativa
        case exhausted(Reason)          // não será tentado de novo
    }
    public enum Reason: Hashable, Sendable { case attemptsSpent, mediaInvalid, superseded }

    public init(targetDepth: Int = 96, lowWaterMark: Int = 64, maxAttempts: Int = 3,
                persistedByteBudget: Int = 96 << 20, retryDelays: [Double] = [1, 4, 16],
                now: @escaping @Sendable () -> Double = { ProcessInfo.processInfo.systemUptime })

    // Planejamento: quais revisões merecem trabalho agora, na ordem recebida, parando ao atingir
    // targetDepth de prontas. Só devolve `.pending` e `.deferred` vencidas. Nunca devolve `.published`,
    // `.ready`, `.preparing` nem `.exhausted`.
    public func plan(offer: [OriginRevisionID]) -> [OriginRevisionID]

    public func markPreparing(_ revision: OriginRevisionID, attempt: Int)
    // Idempotente. Conclusão tardia (depois do prazo da fatia) é aceita e entra como `.ready`.
    // `.published` e `.exhausted` ignoram qualquer settle posterior (nunca republica, nunca duplica).
    public func settle(_ revision: OriginRevisionID, outcome: SettleOutcome, persistedBytes: Int = 0)
    public func markPublished(_ revision: OriginRevisionID)
    public func markPublished(_ revisions: [OriginRevisionID])

    public func snapshot() -> Snapshot
}
```

`SettleOutcome`:
```swift
public enum SettleOutcome: Hashable, Sendable {
    case prepared(hasImage: Bool)   // inclui texto legitimamente sem imagem (hasImage == false)
    case transientFailure           // rede/5xx: gasta tentativa, agenda retry pelo backoff
    case definitiveFailure          // mídia inválida/removida: esgota JÁ, sem gastar tentativas
    case conditionsUnavailable      // offline/térmico/sem orçamento: `.deferred`, não gasta tentativa
}
```

Regras de contagem (testáveis):
1. `transientFailure` com `attempts + 1 < maxAttempts` → `.deferred(retryAt = now + retryDelays[attempts])`.
   Com `attempts + 1 >= maxAttempts` → `.exhausted(.attemptsSpent)`.
2. `definitiveFailure` → `.exhausted(.mediaInvalid)` na primeira vez.
3. `conditionsUnavailable` → `.deferred(retryAt = now + retryDelays[0])`, `attempts` inalterado.
4. `settle` em `.published`/`.exhausted` é no-op e devolve `false` (o chamador pode registrar o descarte).
5. `settle` em `.pending` sem `markPreparing` é aceito (o prefetch pode concluir antes do registro) e
   entra como `.ready` — não invente estado `.preparing` obrigatório.
6. `markPublished` numa revisão `.ready` → `.published`; em `.pending`/`.deferred` → `.exhausted(.superseded)`
   (publicada por outro caminho não deve voltar a competir).

`Snapshot`: `ready`, `preparing`, `pending`, `deferred`, `exhausted`, `published`, `persistedBytes`,
`lateCompletions` (contagem de settles `.prepared` que chegaram para revisão já não-`.preparing`).
Sem contadores de memória decodificada: não há cache de imagens decodificadas nesta entrega.

Orçamento: `persistedBytes` é somado no `settle(.prepared)`; quando excede `persistedByteBudget`,
`plan` para de emitir novas revisões (devolve o que já cabe; estado `.pending` permanece). Não despeça
nada já pronto nesta versão — despejar exigiria re-materialização, que é fase 2. Registre essa escolha.

## 3. Ligação no app (`AppComposition.swift`)

- `examinedCandidateCapacity: 32 → 128` com comentário citando PM-028A e o fato medido (2.488 declaram
  imagem, 66 prontas).
- Uma instância `PreparedReserve()` por associação, ao lado de `MediaReadiness`.
- `MediaPrefetcher(onReadinessChanged:)` → `reserve.settle(revision, outcome: .prepared(hasImage: readiness.prepared(revision) != nil))`.
- No fechamento de cada fatia publicada, `reserve.markPublished(revisions das cartas publicadas)`.
- Um evento de traço por ciclo: `reserve_depth`, `late_completions`, `persisted_bytes` (use o `RunwayTrace`
  que já existe; não crie um segundo mecanismo de traço).

## 4. Ajustes do PM (obrigatórios)

1. Estado explícito por revisão, tentativas idempotentes, conclusão tardia entregue à reserva **sem
   duplicar carta nem republicar revisão superada**. Diferenciar falha de rede, adiamento por orçamento e
   mídia definitivamente inválida. Carta esgotada não perde identidade nem entra em ciclo infinito.
2. 96 MB é **ativo persistido** retido pela reserva — não 96 MB de imagens decodificadas em memória;
   distinguir persistido, memória e downloads em voo. LRU não pode destruir ativo persistido nem gerar
   re-download infinito; cartas publicadas mantêm as regras de retenção existentes.
3. 128/96 são parâmetros iniciais, não garantias. O critério é **demonstrar que a reserva recebe imagens
   concluídas depois do prazo da fatia e que elas passam a competir por publicação**.

## 5. Testes obrigatórios (os três discriminantes do PM)

Em `PreparedReserveIntegrationTests`, com `MediaPrefetcher` real e um `fetch` stub controlado por
continuação (nada de `sleep`):
1. **Imagem rápida**: fetch conclui antes do prazo → `prefetch` retorna com a revisão pronta; `plan` não
   a devolve de novo; uma seleção imediata a inclui.
2. **Imagem lenta**: fetch conclui **depois** do prazo (`prefetch` já retornou). A revisão entra na
   reserva (`snapshot().ready == 1`, `lateCompletions >= 1`) e a fatia seguinte a publica.
3. **Imagem indisponível**: `definitiveFailure` → `.exhausted(.mediaInvalid)` na primeira tentativa, sem
   bloquear as outras revisões da mesma oferta, e a carta publicada não carrega imagem declarada
   (comportamento existente preservado).

Mais casos unitários: idempotência de `settle`; `published` ignora settle; `markPublished` supersede
`deferred`; orçamento persistido bloqueia `plan` sem apagar o que já está pronto; `plan` respeita
`targetDepth` e a histerese.

## 6. Aceitação

- `swift test --filter 'PreparedReserve|MediaPrefetcher'` verde.
- `swift test` do pacote: mesmos 1.672/1 skip e **zero** falhas (o teste de aquisição já foi corrigido
  no commit `37547456`).
- Relatório: tabela de testes executados, contagem, e as escolhas conservadoras feitas.
- Commits pequenos, mensagens no formato do repo, e o SHA final no relatório.
