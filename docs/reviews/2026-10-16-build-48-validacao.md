# Build 48 — validação da candidata interna

Data: 2026-10-16. **Candidata interna de observabilidade; não é entrega completa nem certificação de fluidez.**
Fluidez **NOT_CERTIFIED**, B06 **NOT_RUN**, reabertura sem loading **não incluída**. Release externa **BLOCKED**
pelo contrato de aceitação ainda não satisfeito. A missão do dono permanece aberta.

## Identidade e escopo

Base `origin/main`: `78a374288d38e5c965b9ecc9fe587ac8fe4dbd43`.
Worktree exclusiva: `/tmp/fm-int48-verify`; branch `release/1.0-build.48`.
Código validado: `ec9016aa8048d6e5c4a752abcc2be674b75acb72` (antes destas correções documentais).
Versão `1.0`, `CFBundleVersion=48`; a Apple não tinha build 48 na consulta read-only desta rodada.
Nenhum merge/push de `main` foi executado.

Incluído:
- `32f4ff34` → `5bbad81b`: remoção de oito scaffolds sem declarações.
- `9698346b` → `f017eca2`: jornada de imagem desenhada, geometria e retorno, com controle sem imagem.
- `9749237b` → `fca792c7`: instrumento do aparelho e console DEBUG opcional, no callback existente.
- `3845f228` → `3d54cf1a`: rolagem com série bruta, sem teto artificial; orçamento do display coerente no registro;
  histórico somente DEBUG; primeiro callback inicia a janela de amostragem.
- `ec9016aa`: numeração 48, sem reutilizar números das publicações anteriores.

A colisão de IDs do Xcode foi resolvida preservando ambas as classes: imagem usa fileRef `…10F`/buildFile `…110`;
rolagem usa `…111`/`…112`. As duas pertencem ao target **FeedMineUITests**, não FeedMineAppTests.

Fora: reabertura `3e6c54b6` e seu diff posterior (revisão detectou perda do seed de aquisição e risco de metadados
A→B), PD8-R1/R6-E, honest-surfaces, deduplicação, splits e o novo instrumento `journey.py` ainda em revisão.

Verdict explícito do arquiteto: GO interno condicionado à validação combinada, NO-GO externo, sem reduzir a régua.
[Conversa e decisão](https://chatgpt.com/g/g-p-6a584059c8f0819180f2f1d07b1ccbbe-feedmine/c/6ad16b59-5a88-83e8-9235-71ceb8048e95).

## Ambiente e insumos

Mac arm64, macOS 26.3.1, Xcode 26.6. Simulador iOS 26.5, iPhone 17 Pro, UDID
`26AAAE22-70DD-4768-B63C-5058E0737C75`, criado e removido para esta verificação.
Corpus UI: duas fontes locais, 95 itens/fonte; PNG magenta 16:9 pela cadeia normal de mídia e controle sem mídia.
Isso não prova download de fotos da internet nem diversidade do catálogo.

Catálogo público empacotado: revisão 5, 77.443 fontes, SQLite de 117.993.472 bytes,
SHA-256 `42e602341d18f47290b06615eb9d49a25a693e36f3e9a4c327bbecd83e923b66`.
Preflight do catálogo no checkout canônico: `verify_product_catalogue.sh` e `verify_catalog_release.py preflight`
ambos exit 0; o script de release repetirá as verificações contra a árvore final antes e depois do archive.

## Validação final serial

```sh
xcodebuild test -project FeedMineApp/FeedMineApp.xcodeproj -scheme FeedMine \
  -destination 'id=26AAAE22-70DD-4768-B63C-5058E0737C75' -derivedDataPath /tmp/fm-int48-dd \
  -only-testing:FeedMineUITests/CardImageJourneyUITests \
  -only-testing:FeedMineUITests/FluidityJourneyUITests \
  -only-testing:FeedMineAppTests/FeedFrameBudgetTests
swift build
swift test
git diff --check
shasum -a 256 -c bench/EVALUATOR.sha256
```

Saída bruta resumida, sem substituir os logs:

```
FeedFrameBudgetTests: Executed 3 tests, with 0 failures
CardImageJourneyUITests: Executed 2 tests, with 0 failures (38.893 s)
FluidityJourneyUITests: Executed 1 test, with 0 failures (29.623 s)
** TEST SUCCEEDED **
Build complete! (52.00s)
Executed 1399 tests, with 1 test skipped and 0 failures (0 unexpected) in 64.600 (64.785) seconds
git diff --check: exit 0
EVALUATOR.sha256: seis arquivos OK
```

A rodada anterior da mesma integração, antes do ajuste do início da amostragem, também executou CompositionTests
64/0 e os três testes de orçamento de quadro, além das três jornadas UI. Não confundir essas duas revisões.

| Log bruto | SHA-256 |
|---|---|
| `/tmp/int48-final-ui.log` | `766a5a9931d56daf9195dad0a3ab039112c2cfe8510ad2250828b1dc970261a0` |
| `/tmp/int48-final-build.log` | `4a7a7be6ed0846f2c6282df4b70d67ddeb589cd9ac4c8730594900ebe2022d33` |
| `/tmp/int48-final-package.log` | `739def547c4ae34209f7f0c3c31bfd7fa8485c4c849fab8b92e748e0a9363061` |
| `/tmp/int48-physical-journeys.log` | `d08b538f1b72acc025ebb2aad2d6393a4d5913cf799102eba096a5e41b07cc35` |

Resultado XCTest: `/tmp/fm-int48-dd/Logs/Test/Test-FeedMine-2026.10.16_07-23-50--0700.xcresult`.
Capturas/série exportadas em `/tmp/int48-visual-evidence/`, com manifest de associação por teste.
A imagem `43DF4326-4E4F-4F7A-99D8-3DDF575AE345.png` foi inspecionada: bitmap magenta desenhado nos slots, texto e
geometria visíveis. A série `6FD5ADCB-35A5-4366-9D38-4F6B99C03DC8.txt` registra troca real de carta e intervalos
ruins durante a carga; eles não foram transformados em aprovação de desempenho.

## Tentativa física e erros que NÃO contam como prova

iPhone 14 Plus, iOS 18.6.2, UDID `<physical-device-udid>`: build e instalação do runner ocorreram, mas a
ativação de automação expirou. Jornadas UI físicas **NOT_RUN** nesta tentativa. A ferramenta relatou Developer Mode
ativo, pareamento por cabo e `passcodeRequired=false`. Nenhuma permissão foi alterada. Isso não demonstra que
screenshots pelo XCTest sejam impossíveis; demonstra este bloqueio de inicialização.

Duas execuções anteriores foram descartadas: uma filtrou o target errado e executou zero testes; outra sofreu troca
de branch no checkout compartilhado por um subagente. Nem `TEST SUCCEEDED` com zero casos nem o build de outra árvore
foram usados como validação. O subagente reconheceu a troca; a integração foi preservada e passou a usar worktree própria.

Três agentes foram interrompidos por ENOSPC. Esses resultados não foram atribuídos ao produto. Preservados código
pendente e logs; removidos somente caches reproduzíveis e simuladores descartáveis desta frente. Após a recuperação,
builds/testes foram serializados. A permissão pedida pela outra sessão OMP não foi substituída por decisão do ORCH;
o diálogo poluído foi cancelado e a instrução de autorização entre sessões foi explicitamente retirada.

## Publicação

Neste checkpoint, archive/upload e confirmação de processamento pela Apple **ainda não executados**. O relatório
posterior de publicação deverá citar o SHA completo efetivamente carimbado no archive, versão, catálogo, estado
Apple e tag. O arquivo Release deve ser inspecionado para confirmar ausência da instrumentação DEBUG.
