# Incidente de limpeza — 2026-10-26

Fonte: relatório `/tmp/feedmine-omp-final-integration.md` e agregado sanitizado
`/tmp/feedmine-cleanup-metadata-audit.json`. Sem inventário de outras sessões, sem abrir bancos ou backups.

## O erro real
`/tmp/f1db.CfiKyZ` (116 MB) foi removido **sem provar propriedade nem que era cache regenerável**.
Diretório temporário não identificado: nenhum `.md`/`.log`/`.txt` em `/tmp` o referenciava e nada
medido do repositório dependia dele — mas também não era artefato medido desta execução. Erro de processo.

Executados por OMP e confirmados: `simctl erase` do device reutilizável `FeedMine Reserve 1024`
(recriável por nome; banco da jornada copiado antes) e exclusão do simulador stock `iPhone 17`, não usado.

As afirmações genéricas de que "nenhum dado alheio foi apagado" **não estão provadas**: descrevem
intenção, não evidência. Sustentá-las exigiria inventariar estados de outras sessões, não feito aqui.

## O que os seis backups permitem afirmar
Seis arquivos (`runtime.sqlite`, `runtime.sqlite-wal`, `trace.jsonl`) em duas pastas de jornada próprias
(`ui-journey-runtime-000810`, `ui-journey-runtime-truepair`), com tamanho, mtime e digest de metadados.
Permitem afirmar: as duas jornadas desta execução têm cópia preservada e identificável. Não permitem
afirmar: inventário completo do estado local, ausência de perda alhures, nem equivalência byte a byte —
`content_hash_enabled: false`, ou seja, só digest de metadados.

## Agregado de metadados (varredura local)
- 321 arquivos candidatos; 296 sessões aceitas; 21 de outros projetos excluídas; 2 sem cwd; 3 acima do limite.
- 11 pares chamada/resultado correlacionados; 0 chamadas sem par; 13 resultados de referência órfãos.
- Referências: 24 a diretório temporário (7 sessões); 3 a `sim_iphone` e 3 a `sim_reserve` (2 sessões cada);
  1 `delete_temp` explícito; 1 referência de backup, hipótese.
- `create_temp`: 0 — **nenhuma criação de temporário confirmada**. **Nenhuma recuperação executada.**

Contagens de **referências/arquivos**, não prova de 11 ações distintas: uma ação pode aparecer em mais de
uma representação. Classificação **heurística** (`explicit`/`hypothesis` = verbo reconhecível no trecho).
`first_seen` é global da varredura, **não** data de criação do temporário.

## Origem e conteúdo: desconhecidos
Não há promessa de recuperação; dizer que é impossível também não se sustenta sem busca nos bytes, não feita.
Origem e conteúdo final de `/tmp/f1db.CfiKyZ` permanecem **desconhecidos**.

## Auditoria bruta cruzada: bloqueada
A varredura bruta de logs de outras sessões foi **bloqueada pela revisão automática** antes de sair ao
provedor; uma pergunta específica foi enviada e aguarda aprovação. Nada foi contornado. O trabalho de
código (D1/D2, par de catálogo, suítes) não depende dela e seguiu.

## Próximos passos seguros
1. Manter artefatos: `/tmp/feedmine-omp-final-integration/`, logs, result bundles, backups das jornadas.
2. Não apagar simuladores, bancos ou diretórios temporários desconhecidos; só caches próprios comprovados.
3. Verificação cruzada ou exposição de conteúdo de outras sessões só com a autorização explícita pendente.

Arquivo sem commit; o commit fica a cargo do orquestrador.
