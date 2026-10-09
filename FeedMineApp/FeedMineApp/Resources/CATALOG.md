# Catálogo empacotado

Snapshot read-only do catálogo V1: 77.443 fontes, 6.450 nós e 77.443 placements. 117.940.224 bytes.

SHA-256: `c2ae483a7525fd2b6797855149eb6fb312abbed788549a90a7754121eb5c8629`.
Metadata schema_version=2; catalog_version=1789618085179441; SQLite user_version=0.

Origem da cópia em 2026-10-09: `feedmine/Resources/FeedEngine/catalog.sqlite` do checkout local V1 em `712a6ba9`, com modificações locais preexistentes preservadas. O checksum identifica os bytes copiados; não se afirma que o arquivo corresponde integralmente ao commit V1.

Git LFS armazena o recurso. Depois de clonar, executar `git lfs pull`; antes de distribuir, verificar que o bundle contém o SQLite completo, não o pointer. O teste iOS verifica SHA-256 por streaming e consulta a contagem real.

Inicialização registra somente quatro fontes encontradas por key no catálogo: BBC News, BBC Science, NPR News e Guardian World. A seleção não usa a ordem alfabética global nem considera podcasts com quality_score alto como notícias. O catálogo completo permanece disponível para seleção posterior. Identidades UUID são derivadas por LegacyCatalogImport; request_url permanece separado da key.

Debug permite fallback para as duas BBC de desenvolvimento. Release apresenta falha explícita se o catálogo ou o starter set estiver ausente/inválido. O debug `FEEDMINE_USE_DEVELOPMENT_FEEDS=1` mantém os testes de RSS real independentes do starter set; não usa connector simulado.

O catálogo é aberto read-only e nunca migrado pelo RuntimeDatabase. Substituições futuras devem registrar novo checksum/versão e conservar a identidade por key.
