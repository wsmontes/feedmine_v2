# F18 — Portabilidade: fontes, biblioteca pessoal e saída sem aprisionamento

**Status:** especificação de produto/UX candidata, 2026-10-10. Não é implementação, prova executada ou autorização para substituir B01–B06.  
**Referências comuns:** [norte](PRODUCT_NORTH_STAR.md), [decisões](PRODUCT_DECISIONS_2026-10-09.md), [invariantes](../architecture/PRODUCT_INVARIANTS.md), [benchmark vigente](DISCOVERY_ACCEPTANCE_BENCHMARK.md), [mapa de impactos](PRODUCT_SPEC_DEPENDENCIES_F11_F20.md), [matriz V1→V2](../v1-study/UI_TRANSFER_MATRIX.md).

## 1. Promessa e o que é produto pronto

O usuário pode trazer fontes de outros leitores, acrescentar uma URL quando quiser e levar seus próprios dados para fora do FeedMine. **Portabilidade de assinaturas** não é **backup completo**: o produto precisa nomear ambas corretamente e jamais vender um arquivo parcial como restauração integral.

**Pronto significa:** Interoperabilidade recebe **PASS UX18-A/B/D/E** somente por roundtrip em app real. **UX18-C torna-se obrigatório se a interface prometer 'backup'**: inventário de entidades restauradas em instalação limpa, zero perda silenciosa. Se backup completo não for produto desta release, retirar o rótulo e registrar UX18-C como não ofertado/deferido, nunca como PASS.

## 2. Evidência V1/V2 e gargalo

A V1 tinha `AddFeedView` com campo de URL, clipboard e prévia, mais parser OPML/exportação. Na V2 a importação/exportação OPML e formatos vários existem em diferentes graus; não há prova completa da jornada colar URL→importar. **Constatação de código:** `ReaderExportFormat.json` chama-se «Backup JSON», mas `ReaderImportExportCoordinator.json(entries:)` grava apenas uma lista `sources`; exportar uma `bookmarkBox` converte links dos artigos salvos em **fontes inferidas pelo host**, não em itens salvos. Isso não é backup de bookmarks.

## 3. Contrato de experiência

- **R1 — Importação voluntária sem pré-requisito.** Começar a explorar não exige importar nada; quem possui URL/site/feed/OPML pode acrescentar, pré-visualizar e confirmar explicitamente. URL inválida e link de site sem feed identificado recebem explicação clara.

- **R2 — Interoperabilidade de fontes.** Oferecer exportação padrão de fontes selecionadas/importadas com nomes/URLs apropriados e importação de OPML externo. Duplicatas, sources já existentes, falhas parciais e pertença a coleção têm contagens e resultados verdadeiros. Caminho não depende de conta FeedMine.

- **R3 — Backup pessoal é outro escopo.** Se a UI anuncia «Backup» ou «Restaurar meus dados», o arquivo recupera, em instalação limpa e sem login: Sources pessoais/importadas, seleção e coleções com membership, caixas e **identidades/referências individuais** dos artigos salvos, Smart Feeds/presets e definições, idiomas/lugares, regras duráveis de exclusão, escolhas explícitas, leitura/progresso e outros dados pessoais que o app disser incluir. Qualquer item deliberadamente excluído aparece no inventário **antes** do download.

- **R4 — Material recuperável.** Metadados e relações do usuário sobrevivem sem depender da atualização do catálogo público. Conteúdo externo pode exigir acesso de rede para reabrir; exportação não promete copiar a totalidade dos artigos/mídia de terceiros ou garantir URL futura.

- **R5 — Arquivo compreensível e independente.** A pessoa recebe um arquivo real, consultável/transferível, com data/versão/escopo, sem serviço próprio obrigatório; a importação informa compatibilidade e não apaga dados existentes silenciosamente.

- **R6 — Preservação e integridade.** Cancelar prévia, rejeitar arquivo inválido ou encontrar entradas incorretas não muda estado sem consentimento. Operação parcial relata exatamente o que entrou, foi rejeitado ou já existia; backups exportados continuam íntegros.

- **R7 — Nomenclatura responsável.** OPML, CSV/HTML/texto e JSON de **Sources** são «Exportar fontes/lista»; só se chama «Backup pessoal» se o contrato completo de R3 for efetivamente suportado e restaurável. Um botão presente sem função é FAIL.

## 4. Benchmark UX18 (provas black-box)

| Caso | Cenário e gesto reais | Oráculo de aprovação |
| --- | --- | --- |
| **UX18-A — URL/clipboard** | Colar link de site e URL de feed com dados conhecidos, pré-visualizar e confirmar numa coleção. | Fonte certa adicionada na coleção escolhida, duplicata reconhecida, cancelamento anterior sem efeito. |
| **UX18-B — OPML** | Importar arquivo externo com fontes válidas, repetidas e inválidas; exportar novamente e abrir em leitor de terceiros. | Fontes transportáveis e contagem verdadeira; falhas de entrada não geram sucesso fictício. |
| **UX18-C — Backup pessoal (se anunciado)** | Criar duas coleções, duas caixas com artigos específicos, Smart Feed, filtros, preferências e estados de leitura; exportar, instalar limpo e importar offline. | Cada entidade/associação declarada é restaurada e conferida item por item; conteúdo remoto fica sinalizado conforme disponibilidade. |
| **UX18-D — Interrupção e erro** | Tentar arquivo incorreto, cancelamento, importação parcial e backup de versão diferente. | Estado anterior preservado, falhas claras, nenhuma eliminação silenciosa. |
| **UX18-E — Sem serviço central** | Exportar arquivo sem conta e transferi-lo para outra instalação/dispositivo compatível. | Arquivo abre e restaura escopos prometidos sem autenticação/servidor FeedMine. |

Executar com dados/versão/dispositivo identificados, evidências de gestos reais, capturas e identidades de entrada/saída. Cada caso recebe **PASS / FAIL / NOT_RUN / BLOCKED** e motivo. Os gates B01–B06 não são substituídos nem reduzidos; percentuais e durações do benchmark vigente não são convertidos em cotas de produção.

## 5. Documentos conectados e limites

[F01 catálogo](PRODUCT_AUDIT_10_FRONTS.md); [F08 biblioteca](PRODUCT_AUDIT_10_FRONTS.md); [F09 offline/durabilidade](PRODUCT_AUDIT_10_FRONTS.md); [F10 prontidão](PRODUCT_AUDIT_10_FRONTS.md); [PD-10: catálogo público separado do usuário](PRODUCT_DECISIONS_2026-10-09.md); [F16 biblioteca pessoal](F16_PERSONAL_LIBRARY_SMART_FEEDS_UX_PRD.md); [ReaderExport atual](https://github.com/wsmontes/feedmine_v2/blob/main/Sources/FeedMineRuntime/ReaderExport.swift); [coordenador atual](https://github.com/wsmontes/feedmine_v2/blob/main/Sources/FeedMineComposition/ReaderImportExportCoordinator.swift).

**Fronteira:** F01 cobre descoberta pública automática; F18 cobre **entrada e saída voluntárias de dados**. F09 é autoridade de preservação e offline. Esta especificação define comportamento/cobertura, não formato interno, banco ou implementação de backup.

**Não-objetivos:** copiar automaticamente a V1, exigir conta/servidor próprio, criar UI com ações mortas, quebrar o prefixo publicado ou definir soluções técnicas nesta etapa.

## 6. Estado e conflitos em aberto

**Jornada UX18 integral: NOT_RUN.** O que existe nos componentes/testes do repositório é evidência de capacidade, não certificação desta promessa. Diferenças deliberadas da V1 devem ser aceitas ou revertidas **por decisão de produto explícita** e não por presunção de paridade.
