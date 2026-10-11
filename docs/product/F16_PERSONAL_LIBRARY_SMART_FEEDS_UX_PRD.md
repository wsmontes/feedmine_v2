# F16 — Biblioteca: caixas de salvos, coleções e feeds inteligentes

**Status:** especificação de produto/UX candidata, 2026-10-10. Não é plano técnico nem evidência de execução.  
**Autoridades:** [North Star](PRODUCT_NORTH_STAR.md), [decisões PD](PRODUCT_DECISIONS_2026-10-09.md), [invariantes](../architecture/PRODUCT_INVARIANTS.md), [B01–B06](DISCOVERY_ACCEPTANCE_BENCHMARK.md), [mapa de dependências F11–F20](PRODUCT_SPEC_DEPENDENCIES_F11_F20.md) e [inventário V1→V2](../v1-study/UI_TRANSFER_MATRIX.md).  

## 1. Promessa

O FeedMine não só descobre: guarda escolhas e as transforma em destinos que a pessoa entende e consegue revisitar. Uma caixa é grupo de **artigos salvos**; uma coleção agrupa **fontes**; um Smart Feed é um **contexto reutilizável de leitura**. Não confundir os três.

**Produto pronto:** Provas A–D no app real, incluindo itens retornando como leitura, não apenas registros persistidos. Zero perda cruzada de membership, zero troca de identidade de contexto e restauração B05 demonstrada.

## 2. Evidência e gargalo V1→V2

V1: BookmarkBoxPicker, BookmarkBoxesView, CollectionManagementView, presets e smart bookmarks. V2: entidades e testes de lists/collections/presets existem, mas picker a partir do card, caixa como superfície de leitura e comportamento de atualização de Smart Feeds não possuem prova completa. O código V2 de exportação da caixa atualmente **exporta fontes inferidas dos artigos**, não os próprios artigos: isto não serve como backup da caixa. A prova parcial de componentes não equivale a aprovação da experiência completa.

## 3. Requisitos de comportamento (não de arquitetura)

- **R1 — Entidades distintas:** salvar artigo preserva sua identidade/referência de leitura; agrupar fontes não equivale a agrupar artigos; filtro salvo não equivale a captura estática de resultados.

- **R2 — Organização visível:** criar/renomear/reordenar/deletar caixas e coleções, adicionar/remover item/source e escolher destinos são ações localizáveis; cada ação mostra confirmação ou erro compreensível.

- **R3 — Leitura de agrupamentos:** abrir caixa exibe os itens salvos; abrir coleção exibe conteúdo das Sources daquela coleção; abrir Smart Feed reativa as regras declaradas e continua com a política editorial correspondente.

- **R4 — Independência de membership:** o mesmo card pode estar em várias caixas; excluir uma caixa ou coleção não apaga o card, a Source nem outra lista. Default/saved possui função clara.

- **R5 — Retorno e edição:** alternar principal→coleção→principal conserva posições/contextos ainda válidos; alterar preset afeta futuro, não histórico já publicado.

- **R6 — Durabilidade/portabilidade:** nomes, membros, tipos e regras salvas persistem e podem fazer parte de backup pessoal quando esse nome for oferecido; exportar somente Sources deve ser descrito como exportar Sources.

## 4. Benchmark UX16 — oráculo externo

| Caso | Jornada observável com dados reais rotulados | Aceite verificável |
| --- | --- | --- |
| **UX16-A** | Salvar card X em caixas A e B; tirar X de A; reiniciar. | B ainda apresenta X acionável; A não apresenta X; restauração não destrói outro estado. |
| **UX16-B** | Criar coleção com Sources S1 e S2, abrir sua leitura, voltar ao principal. | Collection contém apenas conteúdo elegível dessas fontes, posição de ambos contextos recuperada. |
| **UX16-C** | Salvar Smart Feed do filtro/search A; alterar filtro depois; reiniciar e reabrir Smart Feed. | O contexto ativado corresponde às regras salvas e à revisão escolhida; identidade não troca por acaso. |
| **UX16-D** | Excluir uma coleção/caixa e abrir outra; exportar suas listas. | Só o agrupamento escolhido some; estado alheio não é eliminado; relatório de exportação tem escopo correto. |

Registre vídeo/captura, identidade do conteúdo, estado anterior e posterior, versão do app/dispositivo, e **PASS / FAIL / NOT_RUN / BLOCKED** por caso. Os gates [B01–B06](DISCOVERY_ACCEPTANCE_BENCHMARK.md) não são reduzidos nem substituídos. O benchmark não pressupõe quantidade fixa de páginas, tempos de retry ou algoritmo especial.

## 5. Dependências documentais e escopo

[F07 contextos/filtros](PRODUCT_AUDIT_10_FRONTS.md); [F08 ações e biblioteca](PRODUCT_AUDIT_10_FRONTS.md); [F09 persistência/offline](PRODUCT_AUDIT_10_FRONTS.md); [F18 portabilidade](F18_ADD_FEED_CLIPBOARD_OPML_PORTABILITY_PRD.md); [spec reader-contexts](../superpowers/specs/2026-10-09-reader-contexts.md); [spec reader-filters](../superpowers/specs/2026-10-09-reader-filters-and-context-identity.md).

**Fronteira:** F08 é o contrato geral de ação; F16 define o **modelo mental, a navegação e as consequências de organização pessoal**. F18 define exportação/restauração, não F16.

**Não-objetivos:** copiar controles da V1 sem necessidade, promover componente existente a prova de UX, ou reescrever história já publicada.

## 6. Estado de aceitação

**NOT_RUN** como jornada UX16 integral. Relatórios de código/testes da matriz V1→V2 são evidência preliminar, não um PASS de produto. Toda divergência de escopo deve ser registrada explicitamente antes de ofertar o controle ao usuário.
