# Roteiro — prova offline no iPhone (o que só o usuário pode acionar)

O PO pediu: abrir conteúdo armazenado com o **iPhone efetivamente desconectado**. O arquiteto confirmou que a
contagem de requisições (zero) prova a independência do leitor em relação à aquisição, mas **não substitui** essa
execução. Este é o roteiro mínimo para produzi-la.

## Por que depende do usuário

Nem o XCUITest nem o `devicectl` desligam a conectividade de um iPhone físico: não existe API pública para isso, e a
tela do aparelho não é dirigida daqui. O teste está escrito e compilado; falta só o corte da rede.

## Roteiro (2 minutos)

1. **Antes de desconectar**, abra o FeedMine uma vez e deixe o feed carregar — o conteúdo precisa estar
   **armazenado**. O namespace usado pelo teste (`3E1B4C1A-…`) já tem 173 cartões guardados; se preferir usar outro,
   basta que ele tenha carregado uma vez com rede.
2. **Modo Avião ligado** e **Wi-Fi desligado** (o Modo Avião já desliga o Wi-Fi; confira que ele não voltou).
3. Rode o teste abaixo. Ele **se recusa a passar** se a rede estiver ativa — a primeira coisa que faz é uma
   requisição real e, se ela chegar, falha com "o aparelho está online… Ligue o Modo Avião e rode de novo".
4. O que ele afirma quando passa:
   - parte 1: a edição do namespace real é apresentada **com nenhuma conectividade** — só pode ter vindo do store;
   - parte 2: o artigo guardado abre no **leitor local** com o **texto inteiro** (> 3.000 caracteres), com o rótulo
     de origem correto.

```bash
cd /Users/wagnermontes/Documents/GitHub/feedmine_v2
xcodebuild test -project FeedMineApp/FeedMineApp.xcodeproj -scheme FeedMine \
  -destination "platform=iOS,id=BBA4F656-A5EA-5D81-934E-E484ED71B8E2" \
  -derivedDataPath /tmp/fm-product-derived \
  -only-testing:FeedMineUITests/ReadingSurfaceUITests/testStoredContentIsReadableWithTheDeviceActuallyOffline
```

Se a rodada passar, o resultado é a prova; se falhar na primeira asserção, é o aviso de que a rede continua ativa —
não um defeito.

## Limitação registrada (arquiteto: "registre a limitação do XCUITest")

- O teste **não** prova desconexão global do sistema (Safari incluído) — prova que o leitor local lê conteúdo
  armazenado sem rede. É a mesma distinção que o PO registrou no parecer dele.
- No **Simulador** isso não é executável: ele compartilha a rede do Mac e não há como cortá-la sem privilégio de
  administrador. Rodado no Simulador, o autocheck reprova corretamente e diz por quê — foi o que aconteceu em
  2026-10-12.
