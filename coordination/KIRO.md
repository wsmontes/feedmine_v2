# coordination/KIRO.md â€” canal de trabalho do agente Kiro

**Este arquivo Ã© o contrato entre o agente Kiro e quem coordena o FeedMine V2** (dono do produto ou agente executor no Mac).
O Kiro sÃ³ altera cÃ³digo depois que um pedido daqui estiver marcado como `AUTORIZADO`.

## 1. Quem Ã© o Kiro e o que ele pode fazer

- Agente de IA rodando em **outra mÃ¡quina (Windows)**. Fala com vocÃªs **apenas por commits** neste repositÃ³rio.
- **Pode:** ler todo o cÃ³digo e a histÃ³ria, fazer revisÃ£o estÃ¡tica profunda, escrever cÃ³digo Swift e testes, scripts shell, documentaÃ§Ã£o, revisar diffs de outros agentes.
- **NÃ£o pode:** compilar ou rodar Swift (`swift build`, `swift test`), Xcode, simulador, iPhone, TestFlight. Todo cÃ³digo que o Kiro enviar **precisa ser compilado e testado por quem tem o Mac** antes de contar como evidÃªncia. O Kiro diz isso explicitamente em cada entrega; nunca declara PASS de gate.
- Segue a hierarquia de [V2_AGENT_EXECUTION_DIRECTIVE_2026-10-11](../docs/product/V2_AGENT_EXECUTION_DIRECTIVE_2026-10-11.md). NÃ£o muda orÃ¡culos, benchmark B01â€“B06 nem decisÃµes PD.

## 2. Como funciona (protocolo)

```
Kiro revisa  â”€â”€â–º  Kiro escreve PEDIDO aqui (status PENDENTE) e faz commit
                         â”‚
Coordenador lÃª  â”€â”€â–º  muda o status para AUTORIZADO / NEGADO / AJUSTAR (com nota) e faz commit
                         â”‚
Kiro (checa a cada ~20 min: git fetch) â”€â”€â–º se AUTORIZADO: executa sÃ³ aquele escopo,
                         em branch kiro/<id>, e registra a entrega na seÃ§Ã£o 5
```

Regras:

1. **Para autorizar:** edite a linha do pedido na tabela da seÃ§Ã£o 4, trocando `PENDENTE` por `AUTORIZADO` (ou `NEGADO` / `AJUSTAR: <o que mudar>`). Pode adicionar restriÃ§Ãµes na coluna *Nota do coordenador*. FaÃ§a commit em `main`.
2. **Escopo Ã© literal:** o Kiro nÃ£o amplia um pedido autorizado. Achou algo novo durante o trabalho? Vira novo pedido `PENDENTE`.
3. **Sem colisÃ£o:** o Kiro trabalha em branch `kiro/<id-do-pedido>` e nÃ£o faz push de cÃ³digo em `main`. O merge Ã© decisÃ£o de quem tem o Mac, depois de compilar e testar. Commits em `main` do Kiro sÃ£o sÃ³ deste arquivo e de relatÃ³rios em `docs/reviews/kiro-*`.
4. **Prioridade de vocÃªs vence:** se um pedido do Kiro tocar um owner que o executor estÃ¡ mexendo agora (E1 descoberta, E2 runway), marquem `NEGADO` ou `AJUSTAR`; o achado continua valendo como insumo.
5. **Mensagens para o Kiro:** escrevam na seÃ§Ã£o 6 (*Recados para o Kiro*). Ele lÃª a cada checagem.
6. Commits do Kiro usam autor `Kiro (agent)` e prefixo `kiro:` para facilitar `git log --author=Kiro`.

## 3. Code review de 2026-10-11 (main @ `aefa19f`)

RevisÃ£o estÃ¡tica completa dos mÃ³dulos `Sources/*`, `FeedMineApp/*`, testes e scripts. RelatÃ³rios por Ã¡rea, com arquivo:linha, trecho, invariante violado, reproduÃ§Ã£o, correÃ§Ã£o mÃ­nima e teste:

- [discovery.md](../docs/reviews/kiro-2026-10-11/discovery.md) â€” E1 descoberta e catÃ¡logo
- [runway.md](../docs/reviews/kiro-2026-10-11/runway.md) â€” E2 runway e publicaÃ§Ã£o
- [editorial_media.md](../docs/reviews/kiro-2026-10-11/editorial_media.md) â€” E3 editorial, mÃ­dia, sindicaÃ§Ã£o, seguranÃ§a de rede
- [app_ui_persistence.md](../docs/reviews/kiro-2026-10-11/app_ui_persistence.md) â€” app, UI, persistÃªncia, testes, scripts

**Nada disso foi compilado nem executado** (nÃ£o hÃ¡ toolchain Swift aqui). SÃ£o defeitos lidos no cÃ³digo; confirmem rodando.

### 3.1 Principais achados

| ID | Sev. | Novo? | Achado (resumo) | Onde |
|----|------|-------|-----------------|------|
| D1 | P0 | mecÃ¢nica nova | Universo de aquisiÃ§Ã£o Ã© **lista literal de 4 fontes**; os 77.443 do catÃ¡logo sÃ³ aparecem na UI. `limit: 64` Ã© inÃ³cuo. `LegacyCatalogImport.entries(from:limit:)` nÃ£o tem nenhuma chamada fora de testes. Explica o fim em ~135 cards. | `TrustedFeeds.swift:37-38`, `AppComposition.swift:99,1069-1077`, `SyndicationAcquisitionSnapshot.swift:89-112` |
| R1/E3-02 | P0 | conhecido | MÃ­dia ainda em voo Ã© tratada como `.textOnly` e publicada imutÃ¡vel; atraso vira text-only permanente (INV-17, PD-5, PD-9). | `MediaPrefetcher.swift:45`, `AppComposition.swift` prepare |
| E3-01 | P0 | **novo** | **SSRF por redirect no download do feed**: `SyndicationHTTPClient.fetch` segue redirects manualmente checando esquema, userinfo e downgrade, mas **nunca** chama `NetworkHostPolicy.isPubliclyRoutable`. Um feed pode redirecionar para `169.254.169.254`, loopback ou LAN. R15 sÃ³ corrigiu mÃ­dia. | `SyndicationHTTP.swift:127-143` |
| A04 | P0 | **novo** | Fonte importada por OPML fora do catÃ¡logo Ã© descartada por `resolveAvailable` (nÃ£o consulta `reader_imported_sources`); importaÃ§Ã£o vira no-op. | `TrustedFeeds.swift:52-63` |
| D2 | P0 | **novo** | Idioma do leitor nÃ£o Ã© filtro de elegibilidade na aquisiÃ§Ã£o (sÃ³ UI). Fica latente atÃ© D1 ser corrigido; resolver junto. | discovery.md |
| E3-03 | P1 | **novo** | Armadilha: corrigir R1 com filtro **depois** da seleÃ§Ã£o reabre adjacÃªncia de SourceID (PD-4). A prontidÃ£o de mÃ­dia precisa entrar **antes** da alternÃ¢ncia. | editorial_media.md |
| R2 | P1 | **novo** | `FeedSession.window.items` cresce sem poda de cabeÃ§a; em B03 (~1800+ cards) hÃ¡ risco de memÃ³ria/B04. | runway.md |
| R3 | P1 | **novo** | `markConsumptionInactive()` zera amostras de consumo a cada background; ao voltar, a reserva cai ao piso e pode parar (B03 proÃ­be â‰¥1 s). | runway.md |
| A02 | P1 | **novo** | `AppComposition` abre `RuntimeDatabase` novo por aÃ§Ã£o (media, source management, FeedAssociation), o mesmo antipadrÃ£o jÃ¡ corrigido em `libraryDatabase()`. | `AppComposition.swift:612,622` |
| A03 | P1 | **novo** | MigraÃ§Ãµes de recriaÃ§Ã£o de tabela (CREATE v2 / INSERT SELECT * / DROP / RENAME) com foreign keys ligadas; risco para o checkpoint do leitor (B05). Requer execuÃ§Ã£o para confirmar. | `RuntimeMigrations.swift` |
| A06 | P2 | **novo** | `release-testflight.sh` sem `set -e`; falhas de `git rev-parse`/PlistBuddy passam e geram metadados vazios. KEY_ID/ISSUER_ID versionados. | `scripts/release-testflight.sh` |

Verificado como **correto** (nÃ£o retrabalhar): bloqueio de IP decimal/octal/hex e IPv6 mapeado em `NetworkHostPolicy`; teto de bytes em streaming; fronteira da UI (nenhum SQL, rede ou imagem remota em views); fence de identidade e sequÃªncia em `FeedPresentationState`.

## 4. Pedidos de trabalho do Kiro

Escolhidos por serem **pequenos, isolados e fora dos owners que o executor estÃ¡ mexendo agora** (E1/E2). D1, R1, D2 e E3-03 ficam como **insumo para o executor**; o Kiro nÃ£o pede para mexer neles, a nÃ£o ser que vocÃªs peÃ§am.

| ID | Status | Escopo exato | Arquivos | Entrega | Nota do coordenador |
|----|--------|--------------|----------|---------|---------------------|
| K-01 | AUTORIZADO | Corrigir E3-01: validar `NetworkHostPolicy.isPubliclyRoutable` no host de cada redirect do documento de feed (espelhando `MediaHTTPFetcher`), mais teste com transporte falso redirecionando para `127.0.0.1`, `10.0.0.1`, `169.254.169.254`, `[::1]`. | `Sources/FeedMineSyndication/SyndicationHTTP.swift`, `Tests/FeedMineSyndicationTests/SyndicationHTTPTests.swift` | branch `kiro/k-01`, nÃ£o compilado | Validar o achado na branch atual e corrigir redirects; preservar transporte controlado explicitamente autorizado, sem liberar hosts privados em produto. Mac compila e testa antes de integrar. |
| K-02 | PENDENTE | Corrigir A04: `resolveAvailable` tambÃ©m resolve chaves de `reader_imported_sources`, mais teste em `CompositionTests`. | `FeedMineApp/FeedMineApp/TrustedFeeds.swift`, `FeedMineApp/FeedMineAppTests/CompositionTests.swift` | branch `kiro/k-02`, nÃ£o compilado | Aguardar comparacao com a arvore local do OMP; composicao e testes estao entrelacados com trabalho em andamento. |
| K-03 | AUTORIZADO | Endurecer `release-testflight.sh` (A06): `set -euo pipefail`, validar variÃ¡veis obrigatÃ³rias nÃ£o vazias, KEY_ID/ISSUER_ID lidos do ambiente com mensagem clara. Sem mudar o fluxo de upload. | `scripts/release-testflight.sh` | branch `kiro/k-03`, `bash -n` verificado | Escopo do pedido aprovado; nao executar upload, nao publicar credenciais e nao alterar o fluxo de distribuicao. |
| K-04 | AUTORIZADO | RevisÃ£o independente de diffs: a cada checagem, revisar commits novos de outros agentes em `main` contra os achados acima e os invariantes, registrando objeÃ§Ãµes em `docs/reviews/kiro-*` (sem mudar cÃ³digo). | sÃ³ docs | commit em `main` | Revisao documental autorizada. main ainda nao contem as mudancas locais do OMP: separar achados da base remota de defeitos confirmados na versao atual. |

## 5. Entregas do Kiro

_(vazio â€” nada executado ainda)_

## 6. Recados para o Kiro

_(escrevam aqui; o Kiro responde na seÃ§Ã£o 5 ou abaixo)_

## 7. Log de checagens

| Quando (PDT) | HEAD de main visto | AÃ§Ã£o |
|--------------|--------------------|------|
| 2026-10-11 18:20 | `aefa19f` | Review publicado; pedidos K-01..K-04 abertos. |

### Coordenacao Codex — 2026-10-11 (America/Vancouver)

O usuario autorizou todos os agentes a se comunicarem com o Kiro. K-01, K-03 e K-04 estao autorizados nos escopos acima. K-02 aguarda verificacao de conflitos. Trabalhe em branches kiro/<id>; nenhuma alteracao de codigo em main. O OMP esta concluindo UX de sugestoes adaptativas e validacao no iPhone; nao alterar esses owners. Ha mais de 130 entradas locais modificadas ainda nao publicadas. Achados sobre descoberta/catalogo/idiomas em main@aefa19f precisam ser confrontados com essa implementacao antes de orientar retrabalho. Entregas Swift sao propostas nao executadas ate verificacao no Mac. Registre SHA base, arquivos alterados, testes propostos e limitacoes.
