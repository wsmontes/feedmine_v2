# F24 — Durabilidade local, proteção de arquivos e recuperação

**Tipo:** investigação de UX/plataforma Apple, sem modificação de runtime. **Prioridade:** P0. **Versão:** 2026-10-10. **Resultado atual:** NOT_RUN (não foi executado benchmark ou teste iOS nesta pesquisa).

**Autoridade:** [North Star](PRODUCT_NORTH_STAR.md), [PD-1–PD-10](PRODUCT_DECISIONS_2026-10-09.md), [invariantes](../architecture/PRODUCT_INVARIANTS.md), [benchmark B01–B06](DISCOVERY_ACCEPTANCE_BENCHMARK.md). Essas autoridades prevalecem sobre exemplos externos de Apple API.

**Relação com frentes existentes:** F01, F08, F09, F10, F18. **Owner já existente:** Persistence/GRDB/PublicationHistory/AssetStore já existentes; separar catálogo substituível, publicação protegida e dados do usuário.

## Promessa de experiência
Bookmarked stories, bibliotecas pessoais, histórico publicado protegido, filtros e cursor sobrevivem a reboot, interrupção de energia, app kill, falta de rede e remoção de arquivos reconstruíveis. O usuário não descobre que sua biblioteca era um cache.

## Contrato Apple → FeedMine
- **Directories:** dados duráveis invisíveis ao Files app pertencem tipicamente a `Application Support`; arquivo explicitamente gerenciado pelo usuário pode pertencer a `Documents`. `Caches` e `tmp` são purgáveis; nenhum invariant depende de sua sobrevivência.
- **Backup:** Apple inclui Application Support no backup padrão; excluir arquivos reconstruíveis (catálogo baixado, media speculativa quando apropriado) do backup quando possível; não excluir dados pessoais não reconstruíveis.
- **File Protection:** checar atributos reais dos arquivos e comportamento com aparelho bloqueado. `complete` impede leitura/gravação enquanto bloqueado; `completeUntilFirstUserAuthentication` permite depois do primeiro unlock. Seleção depende do requisito de acesso, não de desligar proteção indiscriminadamente. SQLite principal e sidecars `-wal`/`-shm` precisam de estratégia coerente.
- **Transações:** não confundir substituição atômica do arquivo de catálogo com atualização em múltiplos bancos. Validar manifesto/hash/schema, fazer staging e ativar a revisão gerenciada somente após verificação; preservar último snapshot bom. CatalogSource ≠ user-owned imported Source.
- **Imutabilidade:** exclusão de OriginRecord/revision/bytes que podem ser reconstruídos não elimina PublishedCardPayload, checkpoint compatível ou Bookmark. Asset publicado sem bytes usa placeholder determinístico permitido; não solicita download no render.

## UX24 — cenários verificáveis
1. **UX24-A:** remover itens purgáveis do Caches enquanto app está fechado; restaurar história e salvos sem corrupção.
2. **UX24-B:** trocar catálogo gerenciado com arquivo inválido/hash falho/schema errado; manter versão anterior e bibliotecas pessoais.
3. **UX24-C:** interromper admission/publication/catálogo nas bordas transacionais; retomar sem checkpoint adiantado, segmento pela metade ou perda de bookmark.
4. **UX24-D:** reboot, dispositivo bloqueado/primeiro unlock, background refresh permitido/negado; verificar file protection sem perder consistência.
5. **UX24-E:** disco quase cheio e eviction de assets: cards publicados e âncora permanecem legíveis, sem download involuntário.

## Não-objetivos e prova
Não criar novo banco de durabilidade, backup próprio oculto, sincronização em nuvem, cascades destrutivos ou duplicação total de dados para evitar decidir roots. Exigir mapeamento real de diretórios e atributos no dispositivo, crash tests e prova de recuperação offline. **Estado: NOT_RUN**.

## Documentação oficial Apple pesquisada
- [Using the file system effectively](https://developer.apple.com/documentation/foundation/using-the-file-system-effectively) — Documents/Application Support vs Caches/tmp, backups, exclusão de backup.
- [File System overview](https://developer.apple.com/documentation/foundation/file-system) — Acesso confiável, coordenação e I/O.
- [FileProtectionType.complete](https://developer.apple.com/documentation/foundation/fileprotectiontype/complete) — Proteção total: arquivos indisponíveis quando device bloqueado.
- [FileProtectionType.completeUntilFirstUserAuthentication](https://developer.apple.com/documentation/foundation/fileprotectiontype/completeuntilfirstuserauthentication) — Leitura após primeiro unlock até novo boot.
- [URLCache](https://developer.apple.com/documentation/foundation/urlcache) — Cache HTTP no disco é purgável e não pode ser authority.
- [Reducing terminations in your app](https://developer.apple.com/documentation/xcode/reduce-terminations-in-your-app) — Crash/termination e restore resiliente.

**Referências transversais:** [Índice Apple UI/UX e robustez](../research/APPLE_IOS_UI_UX_RELIABILITY_2026-10-10.md) · [Mapa F21–F27](PRODUCT_AUDIT_APPLE_FRONTS_21_27.md). Links são documentação de mecanismos possíveis, não prova de que estejam em uso no FeedMine; confirmar deployment target e disponibilidade antes de codificar.
