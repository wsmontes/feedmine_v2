# FeedMine V2 — Monitor externo de código, arquitetura e produto

> **Canal consultivo**: este arquivo é atualizado pelo monitor do ChatGPT na branch `monitor/architecture`. Não substitui as decisões do PO, a hierarquia documental, a validação no Mac ou os benchmarks congelados.

## Estado inicial — 2026-10-17 (America/Vancouver)

**Situação:** canal criado e sincronização inicial estabelecida; **primeira revisão técnica recorrente ainda não executada**. Não há achados novos certificados nesta configuração.

- Repositório: [wsmontes/feedmine_v2](https://github.com/wsmontes/feedmine_v2).
- Base verificada para criar esta branch: `main@37633bb3e4b6342ae89a9f58d78b90f3182ab14a`.
- Commit da base: *Release build 49: version bump and catalogue provenance*.
- Escopo recorrente: diferenças em branches ativas, integração, commits, documentos vigentes, regressões, invariantes de produto e riscos de publicação.
- Cadência solicitada: duas horas; publicar uma nova versão deste documento quando houver evidência ou recomendação nova relevante.

### Como os agentes devem consumir

1. Antes de planejar uma nova rodada, buscar atualizações remotas, sem mudar de branch nem tocar na árvore de trabalho:
   ```sh
   git fetch origin monitor/architecture
   git show origin/monitor/architecture:docs/reviews/ARCHITECTURE_MONITOR.md
   ```
2. Tratar cada recomendação como **entrada de revisão**, não como uma ordem nem como autorização automática para mudar código.
3. Verificar SHAs/linhas contra a própria branch de trabalho antes de implementar; identificar recomendações já resolvidas e trabalho concorrente.
4. Aplicar sempre primeiro os documentos normativos da `main`: `docs/product/PRODUCT_NORTH_STAR.md`, `PRODUCT_DECISIONS_2026-10-09.md`, `docs/architecture/PRODUCT_INVARIANTS.md`, benchmark B01–B06 e diretivas de execução vigentes.
5. Não baixar a régua de testes nem alterar `bench/` por recomendação do monitor. Resultado não executado no Mac permanece **NOT_RUN / NÃO VERIFICADO**.

### Modelo das próximas revisões

- **Proveniência:** timestamp, SHAs e branches/PRs verificados; qual intervalo foi comparado.
- **Mudanças relevantes:** implicações para produto, arquitetura e release, não apenas resumo do diff.
- **Achados:** prioridade P0/P1/P2, fato vs hipótese vs opinião, referência `arquivo:linha` + link.
- **Recomendação concreta:** owner proposto, intervenção mínima, verificação no Mac e risco de regressão.
- **Evolução:** novo / ainda aberto / resolvido / invalidado; sem reabrir defeitos já corrigidos.
- **Sem novidades:** registrar sinteticamente a verificação; evitar commits idênticos e relatórios repetidos.

## Regras do monitor

- Apenas atualizar este documento na branch `monitor/architecture`; não modificar código, testes, benchmarks ou configurações operacionais.
- Não criar PR, issue, outras branches ou commits na `main`.
- Priorizar comportamento observável (feed contínuo, apresentação local fluida, reserva adaptativa, preservação de posição, offline e dados do leitor) acima de métricas cosméticas.
- Se o GitHub não puder ser acessado ou atualizado numa execução, registrar a falha no relatório entregue no ChatGPT; nunca afirmar que um commit foi publicado sem verificar.
