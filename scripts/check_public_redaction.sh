#!/bin/sh
# check_public_redaction.sh — a ponta do repositório público não volta a publicar
# identificadores pessoais.
#
# Uso:
#   sh scripts/check_public_redaction.sh            # revisão de trabalho (a ponta)
#   sh scripts/check_public_redaction.sh main       # uma revisão, p.ex. main ou um SHA
#
# Sai 0 e imprime uma linha quando a revisão está limpa; sai 1 e lista
# `<classe>: arquivo:linha:texto` por ofensor. Só depende de git, grep, sed e mktemp.
#
# Por que as agulhas são montadas a partir de fragmentos: um verificador que
# soletrasse os valores completos no próprio arquivo voltaria a publicá-los e
# falharia contra a revisão em que ele mesmo estreia. Nenhum valor das classes 1
# a 5 aparece contíguo no texto deste script; só as variáveis montadas abaixo os
# contêm. As formas genéricas (a forma Apple de UDID, o caminho `/Users/<nome>`,
# o UUID atrás de `Provisioning … Profiles/`, o `--sign <40 hex>` e qualquer
# `Apple Development: <endereço>`) não precisam de fragmentos: elas descrevem a
# classe inteira, não um valor.
#
# Classes cobertas, todas com agulha específica e, quando existe forma estável,
# com forma genérica adicional:
#   1. nome de conta local anterior (caminho do home anterior e o nome solto);
#   2. UDID de aparelho físico (três aparelhos registrados na estação anterior);
#   3. UUID de perfil de provisionamento;
#   4. impressão digital do certificado de assinatura;
#   5. endereço no sujeito do certificado.
#
# Fora de escopo por decisão do dono (ver docs/reviews/evidence/REDACTION.md):
# o Apple team ID, a terminação de Common Name que a Apple emite no próprio
# certificado, os bundle ids funcionais `com.feedmine.*`, o handle público do
# repositório e o nome de exibição do dono.

set -u

REV=${1:-}
REF=${REV:-<árvore de trabalho>}

cd "$(git rev-parse --show-toplevel)" || exit 2

TMP=$(mktemp) || exit 2
trap 'rm -f "$TMP"' EXIT

# --- agulhas específicas, cada valor partido em fragmentos -------------------
LOCAL_A='wagner'; LOCAL_B='montes'
LOCAL_USER="${LOCAL_A}${LOCAL_B}"

DEV1_A='00008110'; DEV1_B='-00067D861486201E'
DEV2_A='00008120'; DEV2_B='-000260903ED1A01E'
DEV3_A='00008006'; DEV3_B='-0010749A3E00C02E'
DEV1="${DEV1_A}${DEV1_B}"
DEV2="${DEV2_A}${DEV2_B}"
DEV3="${DEV3_A}${DEV3_B}"

PROFILE_A='2abf3e99'; PROFILE_B='-ffec-47fa-9696-'; PROFILE_C='a67bcbd9c7f6'
PROFILE_UUID="${PROFILE_A}${PROFILE_B}${PROFILE_C}"

CERT_FP_A='D4D057537849FAB4'; CERT_FP_B='B1A2AA99B962C9DCE07600ED'
CERT_FP="${CERT_FP_A}${CERT_FP_B}"

CERT_MAIL_A='wmontes'; CERT_MAIL_B='@gmail.com'
CERT_MAIL="${CERT_MAIL_A}${CERT_MAIL_B}"

# --- coletores ---------------------------------------------------------------
# Literal (-F): agulha específica, sem risco de a agulha virar expressão.
needle() {
  git grep -I -n -F -e "$1" $REV -- . 2>/dev/null
}
# Expressão (-E): forma genérica de uma classe.
shape() {
  git grep -I -n -E -e "$1" $REV -- . 2>/dev/null
}
label() { # $1 = classe; o resto vem do stdin
  sed "s|^|$1: |" >> "$TMP"
}

L1='conta local anterior'
L2='UDID de aparelho físico'
L3='UUID de perfil de provisionamento'
L4='impressão digital do certificado'
L5='endereço do sujeito do certificado'

needle "$LOCAL_USER"                                   | label "$L1"
# A forma genérica do caminho pega qualquer conta que não seja a já neutralizada
# no texto; a única forma permitida é a que o próprio `sample` do macOS grava,
# porque ela já vem anonimizada da origem.
shape '/Users/[A-Za-z0-9._-]+' | grep -v -F -e '/Users/USER' | label "$L1"
needle "$DEV1" | label "$L2"
needle "$DEV2" | label "$L2"
needle "$DEV3" | label "$L2"
shape '[0-9A-F]{8}-[0-9A-F]{16}' | label "$L2"
needle "$PROFILE_UUID" | label "$L3"
shape '[Pp]rovisioning.{0,2}Profiles/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | label "$L3"
needle "$CERT_FP" | label "$L4"
shape '--sign [0-9A-F]{40}' | label "$L4"
needle "$CERT_MAIL" | label "$L5"
shape 'Apple Development: [^ )]+@' | label "$L5"

if [ -s "$TMP" ]; then
  printf 'check_public_redaction: %s ofensor(es) na revisão %s\n' "$(wc -l < "$TMP" | tr -d ' ')" "$REF"
  sed 's|^|  |' "$TMP"
  exit 1
fi

printf 'check_public_redaction: limpo — revisão %s, 0 ofensores nas 5 classes\n' "$REF"
exit 0
