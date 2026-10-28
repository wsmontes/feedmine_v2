# F13: exclusão durável de fontes sem reescrever o histórico

Estado: desenho de execução autônoma, não implementação nem PASS UX13.
Base inspecionada: `382edf73`. Autoridade: `docs/product/F13_CONTENT_CONTROL_EXCLUSIONS_UX_PRD.md`
R1–R6/UX13-A–D, PD-1/PD-4/PD-5 e INV-17. A instrução do usuário é prosseguir autonomamente;
as escolhas abaixo são do executor, não decisões anteriormente atribuídas ao usuário.

## Intenção

Permitir que a pessoa diga explicitamente que não quer novas histórias de uma fonte, veja essa regra
nos filtros de conteúdo e a remova. Desmarcar uma seleção, votar num assunto e excluir uma fonte
continuam sendo três atos diferentes. Não reconstruir o editor de palavras já existente.

Entrega completa inclui domínio, persistência, elegibilidade, fiação no app, controles acessíveis e
provas UX13; entregar apenas um campo em settings não encerra a frente.

## Semântica escolhida

- Regra global e durável: afeta publicação futura em principal, fonte, coleção, curadoria e busca.
  Não apaga aquisição canônica, memberships, histórico, checkpoint, mídia de ocorrência ou salvos.
- O switch mestre existente de filtros de conteúdo mascara também as regras por fonte, sem apagá-las.
  Filtros de sessão continuam com sua expiração; essas regras não expiram.
- Uma fonte é a identidade editorial já existente, não o nome ou uma URL. A regra persiste o
  `SourceID` conhecido e um nome para apresentação. O nome não participa de matching.
  O nome congelado permite entender/remover a regra mesmo se a fonte sair do catálogo.
- Aliases verificados são expandidos por `SourceIdentityIndex.sourceIDs(in:for:)`. Não criar
  heurística de alias. Fonte importada e fonte de catálogo usam suas identidades existentes.
- Uma história com memberships A bloqueada e B permitida pode publicar por B, se B pertence ao
  escopo corrente. A não pode ser atribuída nem contribuir para diversidade dessa seleção.
  No contexto explícito de A bloqueada, B não transforma essa história numa publicação do contexto A.
- Bloqueio não revoga autoridade de aquisição e não promete bloquear tráfego: a copy promete
  impedir novas publicações. Abrir explicitamente a fonte não remove a regra nem a seleção.
- Nova regra não remove cartas já publicadas, vistas ou não. Trocar uma regra de fonte não cria nova Edition
  nem muda ContextKey. Remover a regra ou desligar o switch permite reconsiderar supply já passada,
  usando as lanes de produção existentes e os guards de exposição, sem duplicar material publicado.

## Modelo e owners

### Domain e settings

Criar `ReaderSourceExclusion: Hashable, Codable, Sendable` com `sourceID: SourceID` e
`displayName: String`. Identidade de regra é sourceID. Normalização remove duplicatas por identidade;
não normalizar displayName como chave. Lista em ordem canônica por UUID para comparação estável.

`ReaderSettings.contentSourceExclusions: [ReaderSourceExclusion]`, default `[]`, decodeIfPresent para
bancos antigos. Encoding da ausência deve manter compatibilidade com documentos e fixtures existentes.
Não modificar migrações históricas: os settings já são JSON. A lista não entra na assinatura de ContextKey.

`ReaderSourceExclusionSnapshot(settings:)` descreve a política efetiva por `sourceIDs: Set<SourceID>`,
vazio quando o switch está off. Não inclui nomes de apresentação nem regras mascaradas pelo switch.
Igualdade não muda quando apenas o nome muda ou uma regra desligada é editada. A resolução de aliases
é uma projeção da autoridade existente, feita por Composition; a lista persistida é a expectativa
que o writer compara. Falha de leitura da política não deve virar "nenhuma exclusão".

### Elegibilidade e publicação

O provider usa um snapshot único por oportunidade: restringir memberships ao escopo corrente, subtrair
as identidades excluídas e omitir a candidata que tinha memberships e não conserva nenhuma permitida.
Os demais campos e o cursor/contagem de exame da janela permanecem fatos do mesmo walk. Não filtrar
cartas renderizadas. Uma candidata sem membership conhecida não adquire fonte inventada; a presença
de regra não é prova de que ela pertence à fonte excluída.

A seleção e a preparação usam apenas as memberships sobreviventes. Reoffers de mídia, cold bootstrap,
head reconsideration e produção normal devem usar a mesma política; um caminho sem a regra é defeito.
Não alterar o alinhamento inputs × cardIDs nem atribuição congelada de cartas antigas.

**Corrida obrigatória:** leitura da regra → preparação → commit não é atomicamente uma operação.
Transportar a expectativa `ReaderSourceExclusionSnapshot` com o trabalho. `PublicationStore` compara
essa expectativa com o estado atual dos settings **dentro da mesma transação** que cria a primeira
Edition/segmento ou faz append. Se divergiu, nada é publicado e o resultado é stale, sem avançar o
cursor de produção. A oportunidade seguinte relê a política. Não reaproveitar erro de falha de rede.

O guard é específico dessa política, não um lock novo global, scheduler ou segundo banco. Publicação
sem guard só pode continuar nos chamadores existentes que não representam esse fluxo do app; a
fiação de produção deve provar que first Edition e append carregam a expectativa. Salvos existentes
não são re-publicados nem filtrados por esse writer.

### Continuidade e reconsideração

Mudança efetiva de política é um fato de supply local, sem reinstalar o leitor. O owner de runway deve
invalidar trabalho ainda não commitado e reabrir uma caminhada desde a cabeça para a nova política,
reutilizando episode/headReconsideration, preservando Edition/âncora/ordem e sem zerar high-water.
Uma atualização velha de progress não pode sobrescrever a caminhada nova. O guard transacional impede
commit stale mesmo se a preparação anterior sobreviver ao cancelamento.

Persistir/reler a política no relaunch e aplicá-la à produção futura antes de qualquer cold/append.
Restaurar as cartas publicadas sem aplicar retroativamente a regra. Não confundir ausência de novas
candidatas com ausência de histórico.

### UI e Composition

Reusar `ReaderContentFilterView`/Store/Backend/Adapter. Mostrar seção “Fontes excluídas”, status do
switch e ação explícita de remover cada regra. Nome congelado é fallback se a fonte não resolve mais.

Adicionar ação explícita “Não publicar mais desta fonte” na superfície de fonte já existente,
com confirmação descritiva curta: vale para novas histórias; publicado e salvos permanecem.
A seleção da fonte não muda. Para reverter, usar o editor existente. Nunca pedir digitação de UUID.
Composition recebe o SourceID e nome reais da fonte apresentada; a UI recebe valores/closures e não DB.

Uma superfície sem supply nova por regra deve identificar a restrição e oferecer abrir Filtros de
conteúdo. Não dizer "sem conexão" ou revogar seleção. Se já existe histórico, preservar sua apresentação;
a explicação deve acompanhar a ausência de novas histórias sem cobrir as cartas.

Copy nova em pt/en no String Catalog existente, identificadores AX estáveis para ação, lista,
remoção, estado do switch e ação de recuperação. Dynamic Type e VoiceOver não dependem só de cor.

## Provas obrigatórias antes de encerrar

1. Settings antigos decodificam sem regra; roundtrip mantém regra, nome e switch; sourceID duplicado
   normaliza; nomes iguais com IDs diferentes continuam duas fontes.
2. Fonte importada e catálogo; alias verificado antigo/novo; regra de fonte removida continua removível.
3. A bloqueada/B permitida em origem canônica comum: principal atribui B, contexto A não publica B.
   Nenhum published sourceID/diversity fact novo contém identidade bloqueada.
4. Snapshot capturado e regra alterada antes de createInitialEdition/append: commit stale não cria
   linhas, não avança cursor e nova oportunidade aplica regra atual. Nome apenas não invalida trabalho.
5. Regra aplicada com cartas já publicadas: CardRecord inteiro, segmentos, âncora e salvos idênticos;
   nova publicação exclui A e continua publicando B. Retomar app e A→B→A mantém ambos os contratos.
6. Remover regra/desligar switch reabre supply local anteriormente passada, sem republicar material
   já publicado; religar switch bloqueia novas publicações novamente, mantendo lista.
7. Regra não aparece após desmarcar fonte ou voto de assunto; a implementação não usa revoke para isso.
8. Fonte explicitamente aberta e excluída: estado recuperável com ação correta, sem habilitação silenciosa.
9. UI real: UX13-A–D com corpus independente e sequência publicada antes/depois, screenshots/AX,
   idioma pt/en, texto grande; B02/B04/B05 devem ser cruzados conforme o PRD.
10. Pacote completo, target do app e journeys executados. Limites ambientais ficam BLOCKED/NOT_RUN;
    unit tests não certificam UX13, e uma captura de UI não prova o guard de commit.

## Recursos e não objetivos

Swift/SwiftUI/SQLite/GRDB já presentes, sem dependência ou runtime novo. Manter o teto da reserva,
contrato de mídia, ordem histórica e versões já congeladas. Não alterar bench/corpus/driver/oráculo
para obter PASS. Não distribuir build sem autorização.

No início deste desenho havia 711 MiB livres, abaixo da guarda de ensaio de 3 GiB. Implementação
não dispensa validação iOS: reservar capacidade antes de compilar/rodar o app, preservando evidências.
Não apagar simulador, banco, trace, backup ou produto de teste para financiar a feature.

## Limite de escopo que não pode virar fechamento de F13

Este incremento acrescenta fontes; não certifica sozinho todo F13. O host atual dobra exclusões de
palavras globais em `applied(ContextKey)` e `reapplyReaderFilters` pode substituir associação quando
essa identidade muda. Logo o switch mestre com regras de palavras também exige prova de histórico:
a continuidade garantida aqui para alteração de fonte não deve ser generalizada à troca de palavras.

A suite final deve medir as variantes com palavras existentes e registrar qualquer falha R4 como
pendência de produto, sem trocar a comparação de histórico por uma asserção menor. A origem de cada
regra (contextual versus global) deve permanecer distinguível; não retirar palavras de uma Edition
antiga supondo que eram globais. Não declarar UX13-B/D PASS só porque o novo caso de fonte passou.


## Ajuste de representação após prova de cauda — 2026-10-28

Decisão do implementador sob a autorização de continuidade autônoma: com histórico, a recuperação
fica no menu Mais existente, com indicador eye.slash e valor AX Fontes excluídas no botão de tamanho
constante. Abrir o menu oferece Rever fontes excluídas e o mesmo editor direto. Sem cartas, a
explicação e o atalho direto permanecem na superfície de ausência. Estado idle/unavailable/deferred/
endOfContent segue sendo só lembrete de regras efetivas, sem atribuir causalidade da ausência.

Motivo medido: retirar o footer na cauda recuou o offset máximo e moveu a última carta admitida
117 pt, mantendo os mesmos IDs. Não criar espaço invisível nem navegação/correção de offset.
O custo da escolha é um toque extra no menu para quem tem histórico; não há novo espaço no chrome
nem mudança de filtros/contexto, captura, scheduler ou PD-4. A prova deve comparar a mesma janela
e carta em cinco observações após retornar do editor; não alega histórico integral nem supply A/B.


## Evidência posterior de palavras — 2026-10-28

A lacuna R4 foi confirmada por integração do fechamento do host: incluir/reativar a regra global muda
a identidade aplicada e deixa apresentação/posição ativa ausentes; desligar/remover restaura o reader
anterior. A intenção lógica não mudou. CardRecords/segmentos/salvo/checkpoint histórico continuam
preservados. Não é apagamento de dados. Oito sintomas conhecidos seguem em expectativas de falha
estritas, sem correção do produto nem PASS UX13. Ver `docs/reviews/2026-10-28-f13-word-history-r4.md`.
A exigência de distinguir origem global/contextual e preservar chaves históricas permanece integral.
