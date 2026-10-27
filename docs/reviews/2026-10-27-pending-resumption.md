# Retomada do trabalho pendente — 2026-10-27

Base inspecionada: `ef5d7999`, branch `product/nf04-tail-truth`. Único arquivo inicialmente
untracked: `capacity-ready.json`, de 23/out; preservado e não usado como medição atual.

## Estado reconciliado

- **PD-5:** correção já implementada, com testes de pacote e regressão do owner de ciclo de vida
  registrados em `2026-10-26-pd5-published-tail.md`. Não foi reimplementada nem medida de novo aqui.
  A ausência de red do app contra o mecanismo antigo continua limite declarado.
- **F12/S1 e UX12-A/D:** revisão e jornadas já executadas, conforme `2026-10-26-s1-review-and-ui.md`.
- **B03:** permanece FAIL da corrida `20261026T143646Z`. Próximo passo técnico é §7 de
  `2026-10-26-b03-pacing-calibration.md`: bed com transporte fiel, varredura de velocidade contínua,
  anti-tap e composição curta antes de qualquer replay de 30 minutos.
- A lista de 25/out é histórica: sua referência a `HiddenTailMaintenance` como causa atual de volume
  foi superada pela remoção de 26/out. Volume/primeira tela precisam de nova medição na árvore atual;
  números anteriores não provam o comportamento após PD-5.
- B06 em aparelho, armazenamento/retencão e build 57 continuam sem fechamento comprovado pelos relatórios
  lidos. Não há autorização de distribuição nova nesta retomada.

## Avanço realizado: contagem do instrumento

O contrato do próprio `pacing_probe.py` diz que `stationary` nunca conta consumo. Porém `measure`
contava todas as âncoras distintas, inclusive as vistas apenas em evento estacionário.

Regressão RED: sequência stationary(a), forward(b), forward(a), stationary(c) devolvia **3**, esperado
**2**. Corrigido apenas o conjunto usado na contagem de consumo. Diagnósticos brutos permanecem intactos.
O evento forward na mesma âncora de um stationary anterior ainda conta; por isso a filtragem percorre a
janela inteira, não a lista previamente colapsada por âncora.

Verificação desta rodada:

- `python3 -B -m unittest discover -s tools/b03-pacing -p 'test_*.py'`: **3 testes PASS**.
- Controle negativo contra o trace original, com as fases preservadas do piloto: **17/17 MISS**;
  há 78 eventos stationary nessas janelas. Inputs e resultados corrigidos em
  `evidence/2026-10-27-b03-pacing/`. O alinhamento temporal das fases é herdado do piloto anterior;
  não foi recalibrado nesta rodada.
- `shasum -a 256 -c tools/b03-pacing/SHA256SUMS`: 4/4 OK, identidade do instrumento atualizada.
- `shasum -a 256 -c bench/EVALUATOR.sha256`: 6/6 OK. Régua congelada intocada.
- `git diff --check`: sem erros.

Reprodução do controle negativo, a partir da raiz:

```sh
python3 -B tools/b03-pacing/pacing_probe.py \
  --trace 'bench/run/20261026T143646Z/container/Library/Application Support/FeedMine/6D600274-B8CA-4CEA-BEE1-8A1CA03DC16A/trace.jsonl' \
  --phases docs/reviews/evidence/2026-10-27-b03-pacing/frozen-phases.jsonl --json
```

## Limite ambiental e próximo passo

`df -h .` mediu **530 MiB livres**. A guarda de ensaio registrada é 3 GiB; não foi satisfeita.
Consulta `simctl list devices booted`, com acesso fora do sandbox, retornou **nenhum device ativo**.
Não foi iniciado simulador, build, servidor ou ensaio novo. Nenhum arquivo de evidência/cache/banco foi
apagado para abrir espaço. A suíte Swift não foi rodada, pois nenhum produto Swift foi alterado.

Retomar a varredura de §7 após capacidade suficiente, confirmada por medição nova. Servir o corpus com
log separado fora de `bench/`, usar namespace novo e preservar o original. Revalidar geometria da janela
antes dos gestos; as coordenadas de ontem não são evidência da posição atual. O app instalado pode ser
anterior à remoção PD-5: verificar identidade antes de atribuir resultados à árvore atual.

A calibração positiva continua pendente; testes do detector não provam 1 carta/s ou 3 cartas/s no app.
Nenhum gate foi reclassificado, nenhum build foi distribuído, nenhum push/merge foi feito.

## Continuação autônoma: integridade das fases

Segunda causa confirmada no instrumento: `phase.get("gestures") or 1` transformava **zero gestos em um**
e inventava o mesmo valor quando faltava o campo. Duração zero/negativa/não finita não era validada.
Regressões RED reproduziram 9 falhas e 1 erro nesses casos. Corrigido para exigir timestamps finitos,
duração positiva finita e contagem inteira explícita não negativa; zero preservado e julgado MISS.

Verificação: **8 testes PASS**, incluindo controles positivos sintéticos de 1/s e 3/s (prova do detector,
não da UI). Controle negativo real **17/17 MISS**, resultado JSON idêntico ao da medição corrigida anterior.
Disco reconsultado: **1,0 GiB** livres, ainda abaixo da guarda de 3 GiB. Sem limpeza ou build.
O residual P1 de desbloqueio da reserva permanece sob análise; o teto explícito de `targetDepth + 16`
não foi ampliado nem removido.

## Continuação autônoma: fix no produto e suíte atual

A auditoria da reserva executou **24 testes PASS** e levou a uma corrida causal no prefetcher:
a oportunidade suspensa em autorização de retry podia baixar novamente uma revisão que outra
já concluíra. RED com **3 fetches em vez de 2**; revalidação após `await` corrigida.
**37 testes de mídia/reserva PASS**, revisão independente sem defeitos acionáveis e suíte completa
**1741 testes, 1 pulado, 0 falhas** (104,666 s). Detalhes e logs duráveis em
`2026-10-27-media-retry-reentrancy.md`. O registro anterior de ausência de execução Swift descreve
somente a primeira etapa desta retomada; agora existe esta medição nova.

Nenhum simulador, ensaio B03 ou distribuição novo. Não houve limpeza. Disco final 686 MiB.

## Continuação: revisão aceita mas ainda enfileirada

Outro intervalo stale foi reproduzido no início de itens da fila: enquanto uma revisão aguardava
atrás de outra lenta, uma oportunidade paralela já podia decidi-la ou colocá-la em backoff.
A fila antiga repetia o fetch nos dois casos. Guardas de readiness/backoff adicionadas no início de
`prepare`, preservando o caminho dos salvos. RED: 2 falhas; GREEN: **38 testes mídia/reserva**;
suíte completa **1742 testes, 1 pulado, 0 falhas** (108,543 s). Revisão independente sem defeitos
acionáveis. Relatório: `2026-10-27-media-queue-revalidation.md`. B03 e residual P1 permanecem abertos.

## Auditoria de aceitação: bloqueio B06 atualizado

Em `c37146bb`, o iPhone 14 Plus agora aparece pareado/disponível, túnel acessível e
`passcodeRequired: false`. A consulta exata do bundle de benchmark devolveu 0 resultados; o CoreDevice reporta
`defaultAppsIncluded: false` mesmo com a flag contrária, então ausência absoluta não está provada. Portanto, aparelho ausente/travado deixou de ser
a descrição atual do bloqueio; faltam instalação identificada, ensaio e recursos. B06 segue NOT_RUN.

F13 já possui editor ligado aos Ajustes, contrariando a descrição histórica de ausência no §2 do PRD.
A política existente passou em **8 testes** nesta auditoria. Restam exclusão durável por fonte e provas
UX13-A–D; não reimplementar editor nem tomar política pura como jornada UI. Evidência e matriz por
requisito: `2026-10-27-acceptance-pending-audit.md`.

Disco ao encerrar esta auditoria: **723 MiB**, ainda abaixo da guarda do ensaio. Nenhuma limpeza,
instalação, execução de app ou distribuição.

## Próximo incremento F13: desenho e plano concretos

Desenho: `docs/superpowers/specs/2026-10-27-source-exclusions-design.md`.
Plano nativo em seis tarefas: `docs/superpowers/plans/2026-10-27-source-exclusions.md`.
Builder check independente do desenho: nenhuma dúvida impeditiva. Auto-revisão do plano cobriu
interfaces, comandos, atribuição multissource, CAS de política no commit e reconsideração sem
reescrever histórico. Nenhuma tarefa de implementação iniciada nesta etapa.

Escolhas do executor: identidade SourceID + nome de apresentação; máscara pelo switch mestre;
retirar apenas memberships excluídas no escopo correto; snapshot efetivo comparado dentro de
create/append; preservar Edition/âncora; reutilizar lanes existentes para reexaminar supply na reversão.
Não usar revoke nem toggle de seleção como regra de exclusão.

Caveat identificado no host: palavras globais ainda entram em `applied(ContextKey)` e o switch pode
substituir associação. O plano exige medir esse caso e manter F13 aberto se o histórico não se
preservar; entregar a nova regra de fonte não certifica todo UX13. Espaço no fim: 707 MiB.
