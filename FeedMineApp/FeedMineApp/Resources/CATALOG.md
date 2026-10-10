# Catálogo empacotado

Snapshot read-only do catálogo V1: 77.443 fontes, 6.450 nós e 77.443 placements. 117.940.224 bytes.

SHA-256: `c2ae483a7525fd2b6797855149eb6fb312abbed788549a90a7754121eb5c8629`.
Metadata schema_version=2; catalog_version=1789618085179441; SQLite user_version=0.

Origem da cópia em 2026-10-09: `feedmine/Resources/FeedEngine/catalog.sqlite` do checkout local V1 em `712a6ba9`, com modificações locais preexistentes preservadas. O checksum identifica os bytes copiados; não se afirma que o arquivo corresponde integralmente ao commit V1.

O recurso não é versionado no Git nem no LFS (a cota LFS da conta foi excedida). Ele é o asset `catalog.sqlite` da release `catalog-v1` deste repositório. Depois de clonar, executar `scripts/fetch-catalog.sh`: o script baixa, confere tamanho e SHA-256 e só então instala em `Resources/`. Sem o arquivo, o build falha em Copy Bundle Resources (falha explícita, sem fallback). O teste iOS verifica SHA-256 por streaming e consulta a contagem real.

Inicialização registra somente quatro fontes encontradas por key no catálogo: BBC News, BBC Science, NPR News e Guardian World. A seleção não usa a ordem alfabética global nem considera podcasts com quality_score alto como notícias. O catálogo completo permanece disponível para seleção posterior. Identidades UUID são derivadas por LegacyCatalogImport; request_url permanece separado da key.

Debug permite fallback para as duas BBC de desenvolvimento. Release apresenta falha explícita se o catálogo ou o starter set estiver ausente/inválido. O debug `FEEDMINE_USE_DEVELOPMENT_FEEDS=1` mantém os testes de RSS real independentes do starter set; não usa connector simulado.

O catálogo é aberto read-only e nunca migrado pelo RuntimeDatabase. Substituições futuras devem registrar novo checksum/versão e conservar a identidade por key.

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
