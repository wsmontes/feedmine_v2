# T5 — Sucessão da cauda

Publication é o owner da substituição. A história vista mantém IDs, valores e posição; a cauda não vista pode receber IDs novos somente com autorização durável de tela oculta. A autorização é revogada antes de foreground ou de novo viewport. O high-water por Edition só avança, inclusive quando o cursor volta para trás.

Persistence acrescenta edition_reading_state(edition_id, high_water_card_id, visible, generation) e arquivos retired_published_cards/retired_feed_segments que preservam os valores substituídos. A migração inicializa o high-water conservadoramente pelo checkpoint disponível. Não é possível inferir leitura anterior não registrada na base antiga; essa limitação fica documentada.

PublicationStore.hiddenTail(editionID:) retorna Lease(editionID, generation, highWaterCardID, expectedTailCardID); setVisibility(editionID:visible:) revoga a autorização. succeedTail(lease:segmentID:cards:createdAt:) retorna applied/stale/ineligible. A transação valida autorização, cauda e identidades; arquiva a cauda anterior, mantém o prefixo visto, trunca apenas o sufixo não visto e insere um novo segmento. Erro faz rollback integral. Uma autorização só pode ser aplicada uma vez. Nenhuma seleção alternativa é instalada em caso de stale.

PublicationCoordinator recebe selection/drafts/IDs e traduz para records. Runtime consulta diretamente os IDs da cauda limitada para obter as revisões canônicas mais recentes, mesmo quando há supply mais novo no head, e substituir a cauda durante background, depois da preparação de mídia. A seleção usa exposição do prefixo visto e vizinho de fronteira para PD-4. Se o conjunto elegível não cobre toda a cauda anterior dentro do limite, a substituição é recusada, evitando perder histórias futuras por um scan parcial. Foreground invalida a autorização antes de reprojetar o cursor. Bookmarks futuros também impedirão truncamento em T6.

Provas: E1→E2→E3 deixa só E3 no futuro ativo; backward não reduz high-water; stale foreground/tail não aplica; falha de inserção reverte arquivo e prefixo; reopen recupera cursor e novo sufixo; valores antigos permanecem arquivados.
