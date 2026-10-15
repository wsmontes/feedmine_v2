# Catálogo empacotado

Snapshot read-only derivado da **revisão pública 5** de `wawasoft/feed-repository`: 77.443 fontes, 6.450 nós e
77.443 placements. 117.993.472 bytes.

SHA-256: `72f066227958b482f365c88dd58320e75bc9ade9268b4e2ddaac9173908ecf71`.
Metadata schema_version=2; catalog_version=1791736083355950; SQLite user_version=0.

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
