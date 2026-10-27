# FeedMine — TestFlight 1.0 (58)

Disponível para o grupo interno **WawaTesters**. A Apple confirmou `VALID`, `IN_BETA_TESTING`,
participação no grupo e notas de teste em português. ID: `bf591289-d5d0-4f4a-a1ee-b63ae83aafe0`.

Binário: commit `fb2e499de47b8a388897c4c49401ec7128f261f1`, tag local
`ios/1.0-build.58-fb2e499d`. O archive foi conferido contra o commit e o catálogo de produção.
O registro de upload informa conclusão sem erros nem avisos. Não houve publicação na App Store.

## O que mudou e por quê

- **Primeira abertura e filtros:** tela de preparação com manchetes e imagens reais, enquanto o app
  prepara imagens, variedade e conteúdo de reserva. A leitura aguarda esses critérios dentro de um
  limite de espera; fontes sem imagem ou falhas continuam tendo um estado honesto. O teste real
  revelou capas de podcasts ignoradas: agora a imagem declarada pelo programa complementa episódios
  sem arte própria, como na V1, sem substituir a imagem do episódio nem aplicar logotipos a notícias.
- **Leitura:** conteúdo local e página da fonte abrem numa aba nativa deslizável. A rolagem normal
  mantém a leitura; ao voltar ao topo e puxar para baixo, a aba fecha e preserva a posição no feed.
  O controle de fechar e os recursos de acessibilidade continuam disponíveis.
- **Podcast:** capa e programa no mini player, player completo com arte, posição, duração medida,
  busca ao soltar o controle, saltos de 15 segundos e ações reais do episódio. A troca de episódio
  evita herdar a capa anterior. A imagem do Now Playing pode ser requisitada fora da fila principal
  sem provocar a falha de isolamento detectada durante a validação.

## Evidências

- Pacote: **1.805 testes, um ignorado, nenhuma falha**.
- App: **33 testes unitários e seis jornadas de interface**, sem falhas, na rodada 11.
- Aceitação final: **quatro jornadas**, sem falhas, na rodada 13: fonte atrasada oito segundos,
  catálogo público e dois fluxos de podcast. Os nove novos testes de capas também passaram.
- Catálogo real, dois namespaces novos: **9 e 7 imagens entre os primeiros 12 itens**, **5 e 3 fontes**,
  **12 itens à frente** nos dois casos. Ambos liberaram por atingir os critérios (`reason=initial`),
  com 12,354 s e 13,956 s de preparo, sem atingir o limite de espera.
- O resultado anterior de apenas duas imagens e saída pelo limite foi rejeitado como prova de qualidade.
  Os resultados novos foram medidos após a correção, sem alterar os limiares ou reordenar cartas publicadas.
- Catálogo e descriptor mantiveram os hashes originais; os seis arquivos congelados do avaliador passaram
  na verificação. O checkout principal e seu `capacity-ready.json` foram preservados.

Os resultados do catálogo real medem duas execuções; a oferta pública varia. Fontes genuinamente sem
imagem não recebem capas inventadas. Publicações históricas não são reescritas, e retomadas de leitura
preservam a edição existente. A ação de adicionar fonte à coleção continua oculta no player quando o host
não oferece executor. **B03 mantém o FAIL anterior; B06 em aparelho físico permanece NOT_RUN.**
Esta entrega é uma beta interna de avaliação.

## Artefatos preservados

- Evidência da Apple e notas: `.build/keep/ios-1.0-build.58-fb2e499d/asc-proof/`.
- Archive APFS copiado e verificado: `.build/keep/ios-1.0-build.58-fb2e499d/FeedMine.xcarchive`.
- Logs e manifesto de arquivos do archive: no mesmo diretório de preservação.
- Aceitação final: `/tmp/fm58-root-release-acceptance-13.xcresult`.
- Medições e capturas reais: `/tmp/fm58-real-catalogue-12-visuals/` e
  `/tmp/fm58-real-catalogue-13-visuals/`.
- Histórico de implementação e incidentes: `2026-10-27-next-experience-loading.md` e
  `2026-10-27-build58-execution-incident.md`, neste diretório.
