# F13 — Controle negativo: filtros de conteúdo e preferências de exclusão

**Status:** especificação candidata de produto/UX, 2026-10-10; nenhuma validação integral alegada. **Não contém desenho de implementação.**  
**Autoridade transversal:** [North Star](PRODUCT_NORTH_STAR.md), [decisões PD](PRODUCT_DECISIONS_2026-10-09.md), [invariantes](../architecture/PRODUCT_INVARIANTS.md), [B01–B06](DISCOVERY_ACCEPTANCE_BENCHMARK.md), [mapa de impacto](PRODUCT_SPEC_DEPENDENCIES_F11_F20.md), [inventário V1→V2](../v1-study/UI_TRANSFER_MATRIX.md).  

## 1. Promessa e definição de pronto

A pessoa precisa dizer 'não quero ver isso' de forma compreensível, reversível e sem ter de conhecer o algoritmo. O produto distingue preferências editoriais suaves de exclusões explícitas.

**Definição de produto pronto:** **PASS UX13** exige testes A–D com comparação da sequência publicada antes/depois de cada intenção; nenhum item histórico removido silenciosamente, nenhuma preferência suave convertida em exclusão forte, e retomada consistente. Cruzar B02/B04/B05.

## 2. Evidência da V1, estado conhecido na V2 e gargalo

A V1 possuía `ContentFilterView` com modelos prontos, palavras-chave customizadas e remoção de regras. A V2 possui lógica de elegibilidade de exclusões e um switch mestre nas preferências, mas a matriz indica **ausência de editor de regras na UI**. F02 prevê 'menos disso' como preferência negativa que não é bloqueio irrevogável. Estas evidências orientam a especificação, **não certificam** paridade de experiência.

## 3. Contrato observável da experiência

- **R1 — Três significados separados.** 'Menos deste assunto' no feed inicial = preferência editorial ajustável; filtro contextual = intenção ativa naquele contexto; exclusão durável de termo/fonte = regra explícita forte. Não transformar um gesto em outro sem consentimento.

- **R2 — Regras visíveis.** A pessoa vê o que está bloqueado, em que escopo, se está ativo, e como editar/remover. Uma opção de switch sem acesso ao conteúdo da configuração é incompleta.

- **R3 — Previsibilidade.** Regras de palavra-chave são aplicadas ao conteúdo definido na interface; a pessoa sabe o que conta como coincidência, e pode perceber falsos positivos.

- **R4 — Reversão sem efeitos retroativos.** A inclusão ou remoção de regra afeta apenas seleção/publicação futuras ou contexto explicitamente substituído. Não reescreve card nem remove salvos anteriores.

- **R5 — Durabilidade e expiração.** Filtros de sessão podem expirar segundo regras visíveis; exclusões duráveis permanecem até o usuário desativar/remover. Reiniciar não mistura ambos.

- **R6 — Estado vazio recuperável.** Se filtros eliminarem todas as opções, a interface explica a restrição e oferece alterar/remover o critério correto; não mascara como falha de rede.

## 4. Benchmark adicional (black-box)

**Não modifica a baseline B01–B06.** Usar corpus independente com entradas conhecidas, app real e gestos de usuário; registrar estado inicial, identidade de cada item/destino, versão e observações.

| Caso | Jornada real | Oráculo de aprovação |
| --- | --- | --- |
| **UX13-A — Exclusão forte** | Corpus tem título/summary com termo X e história Y não relacionada; criar regra X. | Novas publicações elegíveis excluem X e preservam Y; feedback da regra mostra que está ativa. |
| **UX13-B — Editar e desfazer** | Remover X, criar variante X2, desligar switch e reativar. | O efeito futuro acompanha somente o estado escolhido; sem apagamento de histórico/salvos. |
| **UX13-C — Preferência fraca** | Selecionar 'menos tema Z' no feed, sem exclusão formal. | Exploração futura muda de preferência, mas Z não se torna banido; ignorar convite não cria regra. |
| **UX13-D — Restore/sem resultado** | Reiniciar app, alternar A→B→A e aplicar regra que zera candidatos. | Estado durável volta, estados temporários não se tornam permanentes e o vazio explica recuperação. |

Resultado por caso: **PASS / FAIL / NOT_RUN / BLOCKED** com evidência. Uma tela desenhada ou unit test isolado não substitui a jornada.

## 5. Ganchos documentais e limites

Documentos relacionados: [F02 votos no próprio feed](F02_DISCOVERY_FEED_ONBOARDING_PRD.md); [F04 curadoria](PRODUCT_AUDIT_10_FRONTS.md); [F07 filtros/identidade](PRODUCT_AUDIT_10_FRONTS.md); [F09 durabilidade](PRODUCT_AUDIT_10_FRONTS.md); [decisões/invariantes](PRODUCT_DECISIONS_2026-10-09.md); [spec de filtros](../superpowers/specs/2026-10-09-reader-filters-and-context-identity.md).

**Limite de responsabilidade:** F02 define votos editoriais; F07 define elegibilidade e identidade de contexto; F13 define **controles negativos que pessoas conseguem compreender e reverter**. Não prescreve uma segunda camada de filtros.

**Não-objetivos:** reimplementar mecanismos da V1, mover trabalho remoto para renderização, alterar regras de publicação já decididas, ou criar cotas/timers artificiais para o benchmark.

## 6. Pendências de escopo e evidências

A especificação fixa comportamento verificável, mas **não afirma que a UI V2 já o entrega**. A execução deve registrar implementação efetiva, lacunas, falhas e risco residual sem alterar a régua. Se uma diferença aceita na antiga transferência V1→V2 não atende a promessa atual, registrar a decisão de produto de forma explícita, em vez de presumir paridade.

---

## Referências técnicas externas — F13

Estas referências complementam o PRD e não alteram seus critérios de aceitação, nem comprovam funcionalidade já implementada.

**Aplicação:** Controle negativo durável, reversível e explicável.

- [HIG Search fields](https://developer.apple.com/design/human-interface-guidelines/search-fields) — Tokens e escopos de restrição.
- [HIG Undo and redo](https://developer.apple.com/design/human-interface-guidelines/undo-and-redo) — Desfazer exclusões.
- [HIG Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback) — Explicar efeitos e estados vazios.

**Índice integral:** [Pesquisa F01–F20](../research/FeedMine_V2_referencias_F01-F20_2026-10-10.md). Usar os responsáveis/pipelines já existentes; não criar um mecanismo concorrente por causa de uma API ou padrão de interface.

## Pesquisa Apple transversal — F13 (2026-10-10)

Cenários complementares iOS sobre estabilidade, background, offline, integrações e recursos: [F22](F22_NETWORK_OFFLINE_CONSTRAINED_UX_PRD.md) · [F24](F24_IOS_STORAGE_PROTECTION_RECOVERY_PRD.md). Referência direta: [Apple — Accessing cached data](https://developer.apple.com/documentation/foundation/accessing-cached-data). Visão geral: [Frentes Apple F21–F27](PRODUCT_AUDIT_APPLE_FRONTS_21_27.md) e [índice Apple](../research/APPLE_IOS_UI_UX_RELIABILITY_2026-10-10.md).

**Precedência:** esta pesquisa não substitui o PRD, decisões de produto, owners existentes ou B01–B06; referências de APIs não comprovam implementação ou teste.
