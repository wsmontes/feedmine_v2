# Catálogo empacotado

Snapshot read-only derivado da **revisão pública 5** de `wawasoft/feed-repository`: 77.443 fontes, 6.450 nós e
77.443 placements. 117.993.472 bytes.

SHA-256: `1825fdae1d68fc5f6c22f1c1574d9930b8e6e88947f841519c12a9d1554d01b8`.
Metadata schema_version=2; catalog_version=1792868795281916; SQLite user_version=0.

> **Builds 46–48** embarcaram o mesmo snapshot com outro par de bytes — SHA-256
> `42e602341d18f47290b06615eb9d49a25a693e36f3e9a4c327bbecd83e923b66` e
> `catalog_version=1792122546765159`. As **builds ≤ 45** embarcaram um par ainda mais antigo — SHA-256
> `72f066227958b482f365c88dd58320e75bc9ade9268b4e2ddaac9173908ecf71` e
> `catalog_version=1791736083355950`. O **build 55** (IPA de release já distribuído) embarcou
> `e6da170eb9bd139ee9acd95f09940b9c999e3870ce5b70b8f1cace2be076e54c` com
> `catalog_version=1792180662394189`; o par descrito no topo é o do **build 56**, compilado depois e
> o único que casa com o descritor commitado. Todas as versões têm o mesmo tamanho, o mesmo inventário
> (118 OPML, 77.443 fontes, 6.450 nós) e a mesma revisão pública 5: o compilador V1 não é
> reprodutível byte a byte, e o `catalog_version` é um relógio de parede. Os relatórios anteriores
> de `docs/reviews/` mantêm, corretamente, os números das builds que mediram.

## Rastreabilidade (PD-10)

`catalog.manifest.json`, ao lado, é o descritor que este build embarca e que `CatalogInstallation` verifica antes
de abrir o catálogo. Ele declara a revisão pública (`revision: 5`, a mesma do `manifest.json` de
`wawasoft/feed-repository`) e o inventário que este build carrega — as 118 entradas de OPML **mais** a entrada do
artefato compilado, com tamanho e SHA-256 acima. As 118 comprovam os **insumos**; a entrada adicional comprova o
**artefato derivado**, e é por isso que o descritor local não é cópia do manifesto público: `fileCount` é 119, não
118. O bloco `derivedFrom` registra a URL do manifesto publicado, o SHA-256 dele e a revisão de origem.

`schemaVersion` é a versão do **manifesto** (formato publicado = 1), não a do SQLite: o esquema do banco é
declarado pelo próprio catálogo em `catalog_metadata.schema_version` (=2) e é o valor que o verificador compara
com `LegacyCatalogReader.supportedCatalogSchemaVersion`. Toda substituição futura do asset exige atualizar este
descritor (novo par revisão/checksum); substituições devem conservar a identidade por key.

## Preparação e verificação

O recurso **não é versionado no Git nem no LFS**, e **não é mais baixado de um asset de release**. Ele é produzido
por `scripts/bootstrap_catalog.py`, que fixa a revisão pública, busca os OPMLs do canal, confere **cada um** por
tamanho e SHA-256, recusa se o inventário divergir, compila com o builder legado, recusa se o relatório de build
não concordar com o manifesto, e só então empacota o par (catálogo + descritor) — antes da assinatura. O script é
idempotente: revisão igual não provoca substituição.

`scripts/fetch-catalog.sh` está **obsoleto**: ele baixa o asset `catalog-v1` com checksum fixo, e um asset de
release não estabelece correspondência com revisão pública alguma. O caminho atual é o pipeline acima.

Sem o par no lugar, o build falha em Copy Bundle Resources (falha explícita, sem fallback). O teste iOS verifica
SHA-256 por streaming e consulta a contagem real; `CatalogInstallation` faz a mesma verificação em execução, e um
descritor que não corresponda aos bytes rejeita a instalação em vez de ativar.

## O que mudou em 2026-10-11, e por quê

O asset anterior era uma cópia do catálogo V1 (`catalog-v1`, `c2ae483a…`, 117.940.224 bytes), com origem declarada
no checkout local V1. A afirmação de que ele correspondia à revisão pública 5 **não se sustentou quando medida**:
comparando a árvore de OPMLs local contra o manifesto publicado, **1 de 118** batia e 117 divergiam por tamanho.
Correspondência de número não é correspondência de derivação — a contagem de 77.443 fontes coincidia e o conteúdo
não. O catálogo atual é construído **dos** OPMLs publicados, e a proveniência é consequência do processo, não uma
declaração sobre um arquivo antigo.

Inicialização registra somente quatro fontes encontradas por key no catálogo: BBC News, BBC Science, NPR News e
Guardian World. A seleção não usa a ordem alfabética global nem considera podcasts com quality_score alto como
notícias. O catálogo completo permanece disponível para seleção posterior. Identidades UUID são derivadas por
LegacyCatalogImport; `request_url` permanece separado da key.

Debug permite fallback para as duas BBC de desenvolvimento. Release apresenta falha explícita se o catálogo ou o
starter set estiver ausente/inválido. O debug `FEEDMINE_USE_DEVELOPMENT_FEEDS=1` mantém os testes de RSS real
independentes do starter set; não usa connector simulado.

O catálogo é aberto read-only e nunca migrado pelo RuntimeDatabase. Substituições futuras devem registrar novo
checksum/versão e conservar a identidade por key.

## Autoridade do catálogo e obrigação de release (PD-10, 2026-10-10)

**Estado descrito acima = implementação atual, não comportamento aprovado de release.** A cópia de 2026-10-09 veio do checkout local da V1 e é distribuída pela release `catalog-v1` do próprio repositório V2. A coincidência de **77.443 fontes** com o manifesto público não demonstra que esse snapshot tenha origem, revisão ou conteúdo idênticos ao catálogo da Wawasoft.

**Fonte da verdade:** [`wawasoft/feed-repository`](https://github.com/wawasoft/feed-repository), especialmente [`manifest.json`](https://github.com/wawasoft/feed-repository/blob/main/manifest.json) e a árvore `Feeds/`. A revisão pública observada em 2026-10-10 é `revision: 5` (`sourceCount: 77443`); esses números são apenas a referência histórica da revisão consultada, nunca limite/cota do app. A origem deve ser rastreada por revisão e integridade, não inferida apenas da contagem.

**Contrato ainda pendente na V2:**
1. Cada release deve incorporar um snapshot compilado da **última revisão pública validada disponível no build**, com procedência/revisão/hash documentados; disponibilizá-lo localmente na primeira abertura, inclusive offline.
2. Ao iniciar/voltar ao foreground e em oportunidades legítimas durante o uso, quando a última consulta bem-sucedida tiver aproximadamente 24 horas, verificar o manifesto da Wawasoft **em background**, sem bloquear feed, runway ou restauração. Se o iOS ou a rede não permitir, tentar na próxima oportunidade, não em loop.
3. Se a revisão for mais recente, baixar e validar inventário, formato, tamanho e SHA-256 de cada OPML, compilar/stagear a cópia completa e ativar atomicamente; falha ou interrupção preserva o catálogo ativo. Revisão idêntica não exige baixar/compilar tudo novamente.
4. Alterações de fontes, URLs, metadados, países, temas, idiomas e remoções alteram **exploração/aquisição futuras**; nenhuma atualização altera cards publicados nem apaga fontes importadas pelo usuário, salvos, histórico, coleções ou dados em `runtime.sqlite`. Identidades estáveis e trocas de canonical key requerem tratamento explícito.
5. A ausência do repositório público não impede uso do snapshot embarcado/último válido; o GitHub é canal de **metadados de fontes**, não backend de conteúdo.

**Gate:** não declarar a sincronização do catálogo nem o release concluídos sem implementação e evidência de ponta a ponta. Ver [PD-10](../../../docs/product/PRODUCT_DECISIONS_2026-10-09.md), [INV-18](../../../docs/architecture/PRODUCT_INVARIANTS.md) e [arquitetura](../../../docs/architecture/ARCHITECTURE.md). A política da V1 de desabilitar atualização remota em release **não é uma autorização para repetir isso na V2**.

## PD10-P0C — proveniência exigida em novas builds (2026-10-15)

O valor histórico `revision: 5` neste documento não é uma constante do bootstrap. O script
`scripts/bootstrap_catalog.py` agora consulta o manifesto público no momento da preparação;
`--revision` apenas fixa uma expectativa explícita. Exige um compilador V1 fornecido pelo
operador, hash esperado de `build_catalog.py` e hash esperado de `catalog_identity.py` adjacente.
Registra também o commit Git do checkout do compilador (quando resolvível), a versão Python,
o comando executado, o SHA do manifesto original e todo o inventário validado.

Somente instale em Resources o par gerado e verificado no mesmo staging, e faça commit dele
antes de rodar `scripts/release-testflight.sh`. O release se recusa a reconstituir, baixar ou
substituir conteúdo após fixar o SHA da build. O preflight e o archive usam a mesma revisão
pública fresca e confirmam o SHA-256 dos bytes realmente distribuíveis; sem acesso à
autoridade, não se declara uma revisão antiga como atual. Nada disso ocorre no primeiro paint.
O antigo `fetch-catalog.sh` agora recusa explicitamente instalar `catalog-v1`.

## Reparo do par local (2026-10-26)

**Sintoma medido:** este checkout trazia o descritor commitado (`sha256 4cc9cba6…`, o mesmo de
`55c097ab`, que declara o catálogo `1825fdae…`) ao lado de um `catalog.sqlite` gitignored
`e6da170e…` — o par do **build 55**, anterior ao descritor. `CatalogInstallation` recusava o par em
execução, e seis testes de catálogo da suíte de app falhavam por isso.

**Varredura (a parte que a primeira tentativa errou):** procurar só em `~/Documents`, `/tmp` e
DerivedData não encontra os bytes do build 56, que estão em worktrees de outras sessões. A varredura
correta cobriu `~/.codex/worktrees`, `~/Documents`, `/tmp`, `~/Desktop`, `~/Downloads` e
`~/Library/Developer/Xcode/Archives`: **55** arquivos chamados `catalog.sqlite`; **33** com o tamanho
esperado (117.993.472 B) foram hasheados; **11** são `1825fdae…` — `feedmine-bisect`,
`-bisect-base`, `-bisect-pre`, `-bisect-reader`, `-churn`, `-reserve2`, e, em `-reader-position` e
`-reserve`, tanto `Resources` quanto o staging e o `.xcarchive`. Os outros 22 desse tamanho são
`e6da170e…` (build 55). Nenhum arquivo de outro tamanho foi contado como candidato.

**Staging válido encontrado e usado:**
`~/.codex/worktrees/feedmine-reserve/feedmine_v2/build/catalog-bootstrap` — `state.json` registra
`catalog.sqlite 1825fdae…` (117.993.472 B), descritor `4cc9cba6…`, `build-report.json cf885af7…`,
`builtAt 2026-10-24T19:06:40Z`, compilador `build_catalog.py e3c9fcf2…` +
`catalog_identity.py 2a83b833…` (Python 3.11.1), árvore de entrada
`846b17206806ee02dd3f0556e4aa3b9cf514374d591502879246361c36139550` e manifesto público
`2a4f754f…`, revisão 5. É o par do build 56, produzido pelo pipeline.

**O que foi feito:** copiar o `.sqlite` e o descritor daquele staging para `Resources` (o descritor é
byte-idêntico ao commitado, então nada de rastreado mudou por isso) e rodar
`scripts/bootstrap_catalog.py` com os hashes pinados neste checkout. O gate de idempotência
confirmou entradas inalteradas — *“reused: catalog.sqlite compiled at 2026-10-24T19:06:40Z”* — e
reescreveu `state.json`/`provenance.json` com os caminhos deste workspace, sem recompilar e sem
trocar checksum. O `catalog.sqlite` continua gitignored.

**Verificação:** `scripts/verify_catalog_release.py preflight --head <SHA>` →
`P0C preflight verified: revision 5 / manifest 2a4f754f… / sqlite 1825fdae…` (exit 0); metadata do
banco `schema_version=2`, `catalog_version=1792868795281916`, 77.443 fontes, 6.450 nós, 77.443
placements; e os testes de catálogo da suíte de app passam com estes bytes.

**Correção de uma conclusão errada desta mesma rodada:** a primeira tentativa afirmou que “nenhum
byte com `1825fdae` existia na máquina” e instalou o par antigo (`e6da17`), reescrevendo este
documento. A afirmação era falsa porque a varredura não cobria `~/.codex/worktrees`; o commit foi
revertido e esta seção o substitui. A origem do número antigo é legítima — o IPA do build 55 —
mas ele não é o par do descritor commitado, que é o do build 56.
