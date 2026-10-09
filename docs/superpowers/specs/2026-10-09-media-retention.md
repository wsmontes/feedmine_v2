# T6 — Retenção por uso

Persistence guarda uso por card e bookmarks duráveis. PublicationStore.markSeen(at:) registra o avanço e a última visita à âncora; prefixo percorrido recebe prova de leitura, backward atualiza uso sem diminuir high-water. PublicationStore.toggleBookmark(cardID:at:) preserva mídia compartilhada: qualquer bookmark que use uma key protege o asset inteiro. UI emite somente o ID do card, via menu Salvar/Remover dos salvos.

MediaTidy recebe fatos mecânicos de uso pela composição e converte para MediaRetentionClass. Bytes sem uso publicado são farFutureUnseen; uso anterior a sete dias é seenLongAgo, posterior é seenRecently; janela materializada é protegida; bookmark nunca é removido. Data de instalação não é prova de leitura. Falha na consulta cancela eviction, mantendo bytes. Livrar espaço não altera geometria/card e ausência usa placeholder congelado. Sucessão recusa um sufixo que contenha bookmark ou uso visto além do high-water.

Uma migração não pode reconstruir leituras históricas ausentes: preserva o checkpoint e trata outros assets sem prova como não vistos. Relatório declara essa limitação.
