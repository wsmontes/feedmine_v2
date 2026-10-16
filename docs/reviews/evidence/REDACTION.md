# Redação de identificadores pessoais na ponta do repositório público

Este documento é a regra e o registro da redação aplicada à ponta do repositório
público (`github.com/feedmine_v2`), decidida pelo dono em 2026-10-16: **limpar a ponta,
sem reescrever histórico**, e adotar a regra abaixo como mecanismo.

## 1. A regra

1. **Log bruto de aparelho, de teste ou de assinatura nunca é publicado sem redação.**
   Saída crua de `xcodebuild`, `codesign`, `xctrace`, `simctl` e afins carrega caminho de
   home, conta local, UDID de aparelho, UUID de perfil de provisionamento, impressão
   digital de certificado e o endereço no sujeito do certificado. Publicar a saída crua
   publica tudo isso.
2. Quando um log bruto já publicado precisa ficar legível e verificável, a redação é
   aplicada **na ponta**, com os placeholders da §2, e os **bytes originais continuam
   recuperáveis no histórico** (`git show <commit>:<path>`). Nada é reescrito.
3. Nenhum artefato novo — relatório, script, mensagem de commit — repete o valor
   redigido. A verificação é `scripts/check_public_redaction.sh` (§6), que roda contra a
   própria ponta e falha se qualquer um dos valores voltar.
4. Identificador funcional que o código consome **não** é redigido: bundle id, chave de
   fixture, id de contêiner de teste. Ver §3.

## 2. Classes e placeholders

| Classe | Placeholder | Onde aparecia |
|---|---|---|
| Conta local anterior (caminho de home `/Users/<conta>` e o nome solto) | `/Users/<user>` e `<user>` | caminhos de worktree, `HOME`, scripts, tabelas de repositório |
| UDID de aparelho físico (forma Apple, 8+16 hexadecimais) | `<physical-device-udid>` | `xcodebuild -destination`, listas `xctrace`, tabelas de aparelho |
| UUID de perfil de provisionamento | `<profile-uuid>` | `Provisioning Profiles/<uuid>.mobileprovision`, `EXPANDED_PROVISIONING_PROFILE` |
| Impressão digital do certificado de assinatura | `<cert-fingerprint>` | `codesign --sign <sha1>` |
| Endereço no sujeito do certificado | `<redacted-email>` | `Signing Identity: "Apple Development: <endereço> …"` |

Cada placeholder é **neutro**: não diz o valor nem o esconde atrás de outro
identificador. As frases que explicavam a presença do valor continuam legíveis — por
exemplo, uma linha que dizia de onde um caminho vinha continua dizendo de onde ele vinha,
agora com `/Users/<user>`.

## 3. O que foi deixado de fora, e por quê

| Deixado como está | Por quê |
|---|---|
| Apple team ID (`955573A4YH`) | Público por construção: ele é gravado no próprio binário assinado e em qualquer `.mobileprovision`, e aparecia em 15 arquivos, muitos deles instruções de build/assinatura que um leitor precisa reproduzir. O dono decidiu mantê-lo. |
| Terminação de Common Name emitida pela Apple (`BU5227WFYX`) | Mesma razão do team ID: a Apple a emite no certificado e ela viaja no binário assinado; não é escolha nem segredo do dono. |
| Bundle ids funcionais (`com.feedmine.*`) | O código, os testes e o `ExportOptions.plist` dependem deles; redigir seria mentir sobre o que roda. |
| Handle público do repositório (`wsmontes`) e o nome de exibição do dono em rótulos de aparelho e de testador | Não estão na lista de classes acima. O dono é a identidade pública do projeto: o nome dele é o autor de todo commit e o handle está na URL do repositório. Remover um token desses do meio de um relatório não anonimiza nada e destrói o sentido da frase. |
| UDID de simulador, UUID de contêiner de teste, `runtime.sqlite` de fixture | Identificadores funcionais de artefato de teste, não de aparelho pessoal; o código e os vereditos citam-nos. |
| `/Users/USER` | Já vem anonimizado na origem: é o que o próprio `sample` do macOS grava. A verificação o aceita explicitamente. |
| IP privado da estação anterior na LAN | Necessário para reconhecer a estação e retomar as evidências (ver `docs/reviews/2026-10-16-estacao-anterior-disponibilidade.md`). É endereço de rede privada, não identificador pessoal. |

## 4. Cadeia de evidência: o que a redação preserva

A redação **não** apaga evidência; ela troca o valor por um placeholder e mantém a
verificabilidade:

- os bytes publicados originais continuam no histórico, byte a byte, no commit que os
  publicou pela primeira vez (tabela da §5);
- o sha256 dos **bytes publicados originais** de cada arquivo está na §5 — é o número que
  confere contra `git show <commit>:<path> | shasum -a 256`, e não contra a ponta atual;
- o sha256 dos bytes da ponta atual redigida é o que `shasum -a 256 <path>` devolve hoje.

Ou seja: uma cópia futura de um log, vinda de outra máquina, confere contra os bytes
originais (o hash da §5) depois de refazer a mesma redação — ou confere direto contra o
original recuperado do histórico.

## 5. Arquivos tocados

`original sha256` = sha256 dos bytes **publicados** (revisão anterior a esta redação,
`dd109e9eaa39c6a6c22968b435476d3b67a6e06f`), medido com
`git show <commit>:<path> | shasum -a 256` **antes** de qualquer edição. `publicado em` =
commit que introduziu o arquivo.

| Arquivo | Tipo | Classe(s) redigida(s) | original sha256 | publicado em |
|---|---|---|---|---|
| `coordination/KIRO.md` | prosa | conta local anterior | `7ff17ac91bde8fb5b815e322e2335dbc73e6df13ff163f7142a58a46d4fe83ab` | `ae8508611e30` |
| `docs/reviews/2026-10-11-round5-inventory-and-commit-restriction.md` | prosa | conta local anterior | `3a138d018b4fc6396ea25f24e6975ccbd78a1af8b7b2c6d29045a3707642039b` | `ba0866da00d8` |
| `docs/reviews/2026-10-12-codex-position-completion.md` | prosa | conta local anterior | `1fa15008af52032be6a2988b9843925374feef49b4bd2616b401367df3c6fbeb` | `f4bfabc23253` |
| `docs/reviews/2026-10-12-f06-gesture-regression.md` | prosa | conta local anterior | `87d819084f47273ea6d3d8dd9db8b23b1c591d3132667e878d15037edb1764c6` | `90c04e54f274` |
| `docs/reviews/2026-10-12-offline-proof-runbook.md` | prosa | conta local anterior | `c09e7ef97a850db712acabbf973c5acf70f557ff8fd1de3e48cdd24e3f2f1954` | `c5ddec22556a` |
| `docs/reviews/2026-10-14-gates-e-integracao-de-branches.md` | prosa | conta local anterior, UDID de aparelho físico | `39ea673e20215efd846006ca814f0829119dde7253d2009c7436a733393d24a4` | `d964a41fce94` |
| `docs/reviews/2026-10-15-aplicacao-dos-relatorios-de-pesquisa.md` | prosa | — (só citação de hash de arquivo redigido) | `41cd34172d295bead1cd9115f0c8c754eb6e962d55d2fdf5482e339d1511cc1f` | `9da7c6c85f44` |
| `docs/reviews/2026-10-15-build-46-testflight.md` | prosa | conta local anterior | `5a71da8605ae2c1ef50e19228c8cd3716ab4f8e0e29805ed75a33a4e19f0536f` | `7b20b0d53fc3` |
| `docs/reviews/2026-10-15-build-47-e-jornadas-no-aparelho.md` | prosa | conta local anterior | `e8bf8c8d7217f842dd03d77ced2fe417fcacdfa1b1c7f8ae2d6c108ae97034c9` | `48c0101065c2` |
| `docs/reviews/2026-10-15-jornadas-de-usuario-v1-vs-v2.md` | prosa | conta local anterior | `2c02c3c7212dba5c1f41cc6e671091ec298d5a1c463f420aaf6049c7d1bc8f03` | `4e405995fabd` |
| `docs/reviews/2026-10-15-medicoes-obvias-e-constantes-magicas.md` | prosa | conta local anterior | `1aab6fb573acbb5cb07fb47f65e6024d3c89494a322e6d94f67088a16efd7e08` | `087997cbf15f` |
| `docs/reviews/2026-10-15-pd10-p0a-p0b-e-build-45.md` | prosa | conta local anterior | `2c93a75839d33255078810013d5adc57280e44621231bdcb1ac56bb6b9346596` | `0be556e715e8` |
| `docs/reviews/2026-10-16-b06-registro-de-ambiente.md` | prosa | UDID de aparelho físico | `96cb6e302d2b78bf73a6b35d99c22155a2824d72af02fb5faafad9bb4af32608` | `d605a335afb8` |
| `docs/reviews/2026-10-16-build-48-aparelho-e-publicacao.md` | prosa | UDID de aparelho físico | `baefba4d7490857709a013e60be932e4250157e3228d27ee99d4f80e71b97eb3` | `1bebf3bf95ae` |
| `docs/reviews/2026-10-16-build-48-validacao.md` | prosa | UDID de aparelho físico | `0e6f063e003acb05af1a3f0dde2913a3a7b81c7e108db7c2ed5c386f20163389` | `cb23632a8676` |
| `docs/reviews/2026-10-16-jornada-de-fluidez-medida.md` | prosa | UDID de aparelho físico | `edaf42ae316e8cd1184f37b96672e15311166bc5ba3fe176151350df7bfc66a3` | `b7c013eaebab` |
| `docs/reviews/2026-10-16-jornada-medida-no-aparelho.md` | prosa | conta local anterior | `deeef47068ddf213c1580511b399cca0d02acd2c0a3070de286cf684b3f61cb6` | `299c0729d6a3` |
| `docs/reviews/2026-10-16-retomar-no-imac.md` | prosa | UDID de aparelho físico | `2f3fb8ecec2f292d6d5033dba64bd9f60feb194bd4ebe800849e2057980f73e1` | `8ac99e477a7d` |
| `docs/reviews/2026-10-16-rodada-entrega-48.md` | prosa | UDID de aparelho físico | `b2780d8b8dda387da3d6ce3d25399e83a5d405e2aceaffaac087d2dafabce198` | `d605a335afb8` |
| `docs/reviews/R1_EDITORIAL_DIAGNOSIS.md` | prosa | conta local anterior | `8657545db13623608f7ec125e044d00117c7528a9332881f73e711cb3b76eea0` | `7e35e0b158f9` |
| `docs/reviews/V1_UI_REFERENCE.md` | prosa | conta local anterior | `dbbd25d830c5129aca7171f95f78cf3bccaae6c4e346ae5b96c0df7bedfadc99` | `35331510673d` |
| `docs/reviews/V1_V2_FRONTEND_TRANSFER_EVIDENCE.md` | prosa | conta local anterior | `570d231f12fc785f4e2fa4331ce4e41d2ab079375834e9467a0ff466a181625f` | `41ed1a599490` |
| `docs/reviews/evidence/2026-10-11-codex-runway/app-composition.log` | log bruto | conta local anterior | `e917a1f172a553eca261fac6e4fd33152ec1510446f05b3e8487d4f944bc0736` | `ba0866da00d8` |
| `docs/reviews/evidence/2026-10-11-codex-runway/app-final.log` | log bruto | conta local anterior | `ba60742ccee94d5eadad8c26950d582b4ccaa22f154e29337b1e3a0499ab3c27` | `ba0866da00d8` |
| `docs/reviews/evidence/2026-10-11-codex-runway/budget-scope-red.log` | log bruto | conta local anterior | `0444c7c2d6d9868a00148e869b3e25aeb3d93299304fa8946bf13850afea7fa7` | `ba0866da00d8` |
| `docs/reviews/evidence/2026-10-11-codex-runway/reconstruction-diagnostic.log` | log bruto | conta local anterior | `5b606b5af9332ac0bd4f11cbec341806a5ed0955026423e54fc221bd1be506b5` | `ba0866da00d8` |
| `docs/reviews/evidence/2026-10-11-codex-runway/transport-red.log` | log bruto | conta local anterior | `6ea5d85528a53bc387959312f72d5929e18c396c72adaf25170d5800baa88128` | `ba0866da00d8` |
| `docs/reviews/evidence/2026-10-12-codex-scroll/verification.log` | log bruto | conta local anterior | `9d813ad1cf74a40b8a880262fb874d2cb2de6b9b7ed380eb5c93b4c369d6dd20` | `ee2e0ee2824f` |
| `docs/reviews/evidence/2026-10-13-production/catalog-verification.log` | log bruto | conta local anterior | `8bc54b727fd6b6d74cae5dbb0abc899c9bb108d9377aa4789b1a2efbbc220989` | `2b1c4b4e6a10` |
| `docs/reviews/evidence/2026-10-13-production/layout-replay/B01-B.log` | log bruto | conta local anterior | `970f19d85f1c962edf53a59b922831e3a32b91118209a1c5579583df5d1372da` | `ae0ade7992e4` |
| `docs/reviews/evidence/2026-10-13-production/layout-replay/B01.verdict.json` | log bruto | conta local anterior | `de0eaf66904e70a006796140e27b90013a3170e047ff6b2e5307395c90343249` | `ae0ade7992e4` |
| `docs/reviews/evidence/2026-10-13-production/layout-replay/feedmine-exposure-green.log` | log bruto | conta local anterior | `fde7d5482f01142d24538450b3ee1e19a3b27525b906c955fd3fad6dab7d55c9` | `3444d5ae8323` |
| `docs/reviews/evidence/2026-10-13-production/layout-replay/feedmine-exposure-red.log` | log bruto | conta local anterior | `87976c3b3e05a2d6a661da8fbfa7e1cab712441874062b14a4752b03a739d79b` | `3444d5ae8323` |
| `docs/reviews/evidence/2026-10-13-production/layout-replay/swift-full.log` | log bruto | conta local anterior | `7f33201f9c7c46a7c2d5fa159f4663e191b6138494e077a732ada873b06dd803` | `3444d5ae8323` |
| `docs/reviews/evidence/2026-10-13-production/layout-replay/viewport-regressions.log` | log bruto | conta local anterior | `f4fb65f3f56499d9a5c68f74bfb28f4b6d7e3020abe74ebd9583e6f7f7636613` | `ae0ade7992e4` |
| `docs/reviews/evidence/2026-10-13-production/profile-b-hang/ui-test.log` | log bruto | conta local anterior | `5f3d5f331a983df7c09fb1ec0cff8b998ae291c9b06fea830cfe0c50bd66618e` | `ae0ade7992e4` |
| `docs/reviews/evidence/2026-10-13-production/swift-test.log` | log bruto | conta local anterior | `7cb3ccbe467b41ee21c5bf2fbe72904aea5fe9f85301fb492b2c35632d4f6d2b` | `2b1c4b4e6a10` |
| `docs/reviews/evidence/2026-10-14-b01-pass/B01.json` | log bruto | conta local anterior | `607074a60546a18f8e621148bdf8264f63f2a561c0a80f1540ec7e09d655c5d7` | `2e6cda672e55` |
| `docs/reviews/evidence/2026-10-14-b01-pass/report.md` | log bruto | conta local anterior | `b93e83410b067896fee8cb1f4dac56a790a934c0620a0e7c808bc5824eba9121` | `2e6cda672e55` |
| `docs/reviews/evidence/2026-10-14-b04-incomplete/B04.json` | log bruto | conta local anterior | `cd078a2257f2ec51067b92dc2bfeb7c25c692f2b58338bade05f37c2f1994e8f` | `f4af4eef665e` |
| `docs/reviews/evidence/2026-10-15-aplicacao-dos-relatorios/app-target-build-precondition-peer.log` | log bruto | conta local anterior | `797f2aac5d330022353633f4205524a96e77aa6de7902170aa6271372dbf49de` | `7a60595ede66` |
| `docs/reviews/evidence/2026-10-15-aplicacao-dos-relatorios/integrated-tree-app-tests.log` | log bruto | conta local anterior | `d8ff17c554b132c1136a458e3f200db1a46ed6d6b4f24b3f4f68da108c19138b` | `7a60595ede66` |
| `docs/reviews/evidence/2026-10-15-aplicacao-dos-relatorios/nn07-base-control.log` | log bruto | conta local anterior | `fb51d0d7ed9ddb567dad169d3e207ab8f9923932057739029a2eb7d21f76e517` | `7a60595ede66` |
| `docs/reviews/evidence/2026-10-15-aplicacao-dos-relatorios/nn08-composition-and-onboarding-journey.log` | log bruto | conta local anterior | `af9fe2f4253009d2a346d8eb479f51b37396e7d6c69d37063d4ef0e2fea17159` | `7a60595ede66` |
| `docs/reviews/evidence/2026-10-16-rodada-48/int48-physical-authorized.log` | log bruto | conta local anterior, UDID de aparelho físico, UUID de perfil de provisionamento, impressão digital do certificado, endereço no sujeito do certificado | `03fd1799f7d269ba9ac441812fa94bc0c4f58e276c47c313c8531b0c2bac37be` | `ef519465c99d` |
| `docs/reviews/evidence/2026-10-16-rodada-48/sharecheck-ORCH-repro.log` | log bruto | conta local anterior | `d23b63268c7b78cfcaf0d90e7c2719b8b6855f15a8f334c3a8015d7e2ff6d23d` | `ef519465c99d` |
| `docs/superpowers/plans/2026-10-09-transferencia-frontend-v1-v2.md` | prosa | conta local anterior | `9d88e3d8f8bb2b46118063cf0f4a80604b3512904cd549fd73dc33036fd22908` | `35331510673d` |
| `docs/superpowers/specs/2026-10-09-reader-filters-and-context-identity.md` | prosa | conta local anterior | `8f4171188c1fb0809ae8519fe35f07614a21e694f4de8fcc8b62dc6d9b44178b` | `8dc7fe856438` |
| `docs/superpowers/specs/2026-10-10-t7-catalog-metadata-queries.md` | prosa | conta local anterior | `d74ab8e3813cba9e6e8bc4448856526518d5c6956b1861cd2f7bc3c9f6a99f87` | `50eec1bc49ca` |
| `docs/v1-study/PORT_LOG.md` | prosa | UDID de aparelho físico, endereço no sujeito do certificado | `893d030b327460bf61c6f2e598de50b366afe7b19c41bf106b2ef40542d46469` | `64b5bf456518` |
| `docs/v1-study/UI_TRANSFER_MATRIX.md` | prosa | conta local anterior | `4035a49e466d24bfdf3a1b5d72ca1b579757e9dd97f9431be60c815de505be24` | `35331510673d` |

`docs/reviews/2026-10-15-aplicacao-dos-relatorios-de-pesquisa.md` não carregava valor
algum: ele **citava** o sha256 de quatro logs que esta redação alterou, e por isso entrou
na revisão que corrige as citações (§7).

Dois arquivos são **novos** nesta redação e não têm `original sha256`:
`docs/reviews/evidence/REDACTION.md` (este documento) e
`scripts/check_public_redaction.sh`. Ambos são escritos sem repetir nenhum valor.

## 6. Como reconferir

A ponta, uma linha (sai `0` e imprime a linha de limpeza quando não há ofensor; sai `1` e
lista `classe: arquivo:linha:texto` quando há):

```sh
sh scripts/check_public_redaction.sh
```

Saída esperada hoje:

```
check_public_redaction: limpo — revisão <árvore de trabalho>, 0 ofensores nas 5 classes
```

Para reconferir uma revisão publicada, ou a revisão anterior a esta redação (que **deve**
falhar, é o controle positivo):

```sh
sh scripts/check_public_redaction.sh main            # a ponta
sh scripts/check_public_redaction.sh dd109e9eaa39c6a6c22968b435476d3b67a6e06f
```

O agente que voltar aqui depois pode reconferir o essencial sem o script, pela forma
genérica das classes que não depende de conhecer o valor (a forma Apple de UDID não tem
outra expressão possível):

```sh
git grep -I -n -E '[0-9A-F]{8}-[0-9A-F]{16}' main    # deve sair vazio
git grep -I -n -E '/Users/[A-Za-z0-9._-]+' main      # só a forma já anonimizada /Users/USER
```

As demais classes são conferidas por agulha exata, e as agulhas vivem no próprio
verificador (`scripts/check_public_redaction.sh`, § cabeçalho), montadas a partir de
fragmentos justamente para não repetir os valores neste repositório.

## 7. Citações de hash que a redação tornaria falsas

O commit `ef519465` publicou os logs crus da rodada 48 **e registrou o sha256 deles em
prosa**. A redação altera esses bytes, então o número citado deixaria de conferir contra a
ponta. As citações não foram apagadas: cada uma passou a dizer **de quais bytes** o hash é.

| Local | O que foi ajustado |
|---|---|
| `docs/reviews/2026-10-16-rodada-entrega-48.md` §6 (duas linhas da tabela) | o sha256 dos dois logs versionados passou a estar marcado como "dos bytes publicados antes da redação"; o parágrafo que os declarava conferidos diz que a conferência foi na cópia versionada **antes** da redação e aponta para este documento |
| `docs/reviews/2026-10-16-rodada-entrega-48.md` §6 (linha do registro do B06) | a linha dizia "cópia versionada, byte a byte"; agora diz que era byte a byte **até** a redação, que altera bytes |
| `docs/reviews/2026-10-16-build-48-aparelho-e-publicacao.md` §2 | o sha256 do log do aparelho ficou marcado como dos bytes publicados antes da redação |
| `docs/reviews/2026-10-15-aplicacao-dos-relatorios-de-pesquisa.md` (tabela de normalização) | nota explícita de que as colunas `bytes` e `SHA-256 (normalizado)` descrevem os bytes publicados **antes** da redação, que quatro dos cinco arquivos normalizados também foram redigidos, e que a medição da normalização continua válida |

Nenhuma citação de hash de arquivo redigido ficou sem dizer a quais bytes se refere. O
registro por arquivo, com o sha256 original completo, é a §5.
