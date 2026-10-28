# Limpeza autorizada de caches — 2026-10-27

O usuário autorizou liberar espaço e confirmou a continuação. O manifesto ao lado registra os caminhos
removidos, tamanhos alocados e espaço disponível. A medição inicial era 907.350.016 bytes livres;
após a limpeza e a restauração dos repositórios, a segunda rodada chegou a 2.676.047.872 bytes
(aproximadamente 2,49 GiB). Compilações posteriores regeneram parte dos caches.

Removidos: intermediários e índice de um DerivedData antigo do FeedMine, caches globais de módulos/SDK
do Xcode, módulo/índice do scratch Swift, downloads do Homebrew e caches de VS Code, Discord e Chrome
sem processos ativos. Nenhum produto de teste, banco, simulador, xcresult, log ou backup foi removido.
A instalação em andamento do atualizador do Codex foi preservada.

## Correção durante a limpeza

A seleção inicial incluiu quatro diretórios de repositórios bare SwiftPM. Isso foi um erro: os checkouts
preservados dependiam deles por `objects/info/alternates`. Os quatro foram restaurados por clones APFS
de cópias locais preservadas. O cache antigo do FeedKit não possuía todos os objetos mais recentes;
um fetch público do origin repôs os objetos, sem alterar a revisão de nenhum checkout.
`git fsck --no-dangling` passou nos seis checkouts dependentes. Portanto, os repositórios listados na
primeira remoção do manifesto foram **restaurados**, e não representam espaço recuperado final.

Os SHA-256 dos 23 arquivos de evidência F13 foram preservados. Os seis hashes do avaliador congelado
continuam válidos. `capacity-ready.json` permanece intocado.

## Limitação restante

A limpeza não atingiu a margem de 3 GiB prevista para iniciar a validação iOS. Esse gate permanece
NOT_RUN; parse do app e testes macOS do pacote não o substituem. T5 pode avançar no pacote, mas T4/T6
não devem ser declaradas concluídas por essa limpeza.

Manifesto: `docs/reviews/evidence/2026-10-27-authorized-cleanup/manifest.json`.


Avaliação adicional de compressão: `ditto --hfsCompression` foi aplicado somente a uma cópia temporária
em /tmp de um DWARF antigo. A cópia não passou na comparação de bytes e foi descartada; o original
não foi modificado. Portanto, nenhuma evidência/produto foi substituído por esse método. O resultado
está em `evidence/2026-10-27-authorized-cleanup/compression-probe.json`. O cache grande do atualizador
foi revalidado: o processo Updater continua ativo e o diretório foi preservado.


## 2026-10-28 — preservar evidências e concluir a regressão de cauda

Manifestos em `evidence/2026-10-27-source-exclusions/`: cache de download Ollama e Homebrew sem
handles foram liberados, sem modelos/instalações. Intermediários próprios inativos foram regenerados
quando necessário. O updater Codex permaneceu ativo e seu cache não foi removido.

`t6-interrupted-result-archive.json`: resultado próprio já incompleto (`Info.plist` ausente) em
tar.gz restaurável, todos os arquivos conferidos por SHA-256; economia de 253605760 bytes.
`t6-historical-incomplete-log-compression.json` e `t6-chrome-capacity-preservation.json`: somente
logs fechados em resultados históricos já incompletos, gzip descomprimido conferido por SHA-256,
modos/mtimes e caminhos originais registrados. Nenhum conteúdo foi descartado. A restauração dos
bytes usa gunzip; modos/mtimes originais constam dos manifestos se necessários.

A sondagem de dois resultados falhos completos não produziu economia útil: os tar.gz temporários
foram retirados e as pastas originais mantidas (`t6-failed-results-archive.json`). Resultados completos
aprovados, produtos, bancos, simuladores e sessões de outros chats permaneceram intactos.


## 2026-10-28 — medição R4

Cópias de exports em /private/tmp foram liberadas após comprovar presença dos xcresults completos
originais (`r4-unit-probe-duplicate-export-cleanup.json`). SDK ModuleCache regenerável foi removido
após builds terminais. O resultado próprio incompleto da coleta R4, já sem Info.plist, foi arquivado
sem perda: todos os hashes conferidos e comando de restauração em `r4-interrupted-result-archive.json`.
Resultados oficiais posteriores concluíram sem sysdiagnose volumoso, mantendo status/asserções/fatos.
Bancos históricos, simuladores, produtos e resultados completos não foram removidos.
