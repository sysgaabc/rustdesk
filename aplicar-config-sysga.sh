#!/usr/bin/env bash
# Aplica a configuracao SYSGA no fonte do cliente RustDesk.
# Rodar DENTRO do clone do fork (git bash no Windows ou bash no Linux):
#     bash aplicar-config-sysga.sh
#
# Clone obrigatoriamente com submodulos:
#     git clone --recurse-submodules https://github.com/<SUA-CONTA>/rustdesk.git
#
# Cada troca exige que a ancora apareca EXATAMENTE uma vez; aborta se nao.
set -euo pipefail

# Valores vindos do ambiente (Secrets do GitHub) — assim o repositorio pode ser
# PUBLICO sem conter nenhum dado da SYSGA. Se nao vierem, o script aborta.
HOST="${SYSGA_RD_HOST:-}"
KEY="${SYSGA_RD_KEY:-}"
PORT_ID="${SYSGA_RD_PORT_ID:-}"
PORT_RELAY="${SYSGA_RD_PORT_RELAY:-}"
API="${SYSGA_RD_API:-}"

faltando=""
for v in SYSGA_RD_HOST SYSGA_RD_KEY SYSGA_RD_PORT_ID SYSGA_RD_PORT_RELAY SYSGA_RD_API; do
  [ -z "${!v:-}" ] && faltando="$faltando $v"
done
if [ -n "$faltando" ]; then
  echo "ABORTADO: variaveis ausentes:$faltando"
  echo
  echo "No CI, defina os Secrets do repositorio e passe-os no passo do workflow."
  echo "Localmente, exporte antes de rodar, por exemplo:"
  echo "  export SYSGA_RD_HOST=remoto.sysga.com.br"
  echo "  export SYSGA_RD_PORT_ID=31116"
  echo "  export SYSGA_RD_PORT_RELAY=31117"
  echo "  export SYSGA_RD_API=https://remoto.sysga.com.br"
  echo "  export SYSGA_RD_KEY=<chave publica do servidor>"
  exit 2
fi

echo "=== configuracao recebida ==="
echo "  host       : $HOST"
echo "  portas     : $PORT_ID / $PORT_RELAY"
echo "  api        : $API"
echo "  chave      : ${KEY:0:8}... (${#KEY} chars)"

CFG="libs/hbb_common/src/config.rs"
COMMON="src/common.rs"

[ -f "$CFG" ]    || { echo "ERRO: $CFG nao existe. O submodulo foi clonado? (--recurse-submodules)"; exit 1; }
[ -f "$COMMON" ] || { echo "ERRO: $COMMON nao existe. Voce esta na raiz do clone?"; exit 1; }

trocar() {  # arquivo, velho, novo, rotulo
  local f="$1" velho="$2" novo="$3" rot="$4"
  local n
  n=$(grep -cF "$velho" "$f" || true)
  if [ "$n" != "1" ]; then
    echo "ABORTADO [$rot]: ancora aparece $n vez(es) em $f"
    echo "  procurado: $velho"
    exit 1
  fi
  python3 - "$f" "$velho" "$novo" <<'PY'
import sys
f,velho,novo=sys.argv[1],sys.argv[2],sys.argv[3]
s=open(f,encoding="utf-8").read()
open(f,"w",encoding="utf-8").write(s.replace(velho,novo,1))
PY
  echo "  ok  $rot"
}

echo "=== libs/hbb_common/src/config.rs ==="
trocar "$CFG" \
  'pub const RENDEZVOUS_SERVERS: &[&str] = &["rs-ny.rustdesk.com"];' \
  "pub const RENDEZVOUS_SERVERS: &[&str] = &[\"$HOST\"];" \
  "servidor de rendezvous"

trocar "$CFG" \
  'pub const RS_PUB_KEY: &str = "OeVuKk5nlHiXp+APNn0Y3pC1Iwpwn44JGqrQCsWqmBw=";' \
  "pub const RS_PUB_KEY: &str = \"$KEY\";" \
  "chave publica do servidor"

trocar "$CFG" \
  'pub const RENDEZVOUS_PORT: i32 = 21116;' \
  "pub const RENDEZVOUS_PORT: i32 = $PORT_ID;" \
  "porta do hbbs"

trocar "$CFG" \
  'pub const RELAY_PORT: i32 = 21117;' \
  "pub const RELAY_PORT: i32 = $PORT_RELAY;" \
  "porta do hbbr"

echo "=== src/common.rs ==="
trocar "$COMMON" \
  '    "https://admin.rustdesk.com".to_owned()' \
  "    \"$API\".to_owned()" \
  "api-server padrao"

echo
echo "=== conferencia final ==="
grep -nE "RENDEZVOUS_SERVERS|RS_PUB_KEY|RENDEZVOUS_PORT:|RELAY_PORT:" "$CFG" | sed 's/^/  /'
grep -n "to_owned()" "$COMMON" | grep -i "sysga\|rustdesk.com" | sed 's/^/  /'
echo
echo "=== sobrou referencia ao servidor publico do RustDesk? ==="
grep -nE 'rs-(ny|sg|cn)\.rustdesk\.com|admin\.rustdesk\.com' "$CFG" "$COMMON" | sed 's/^/  /' || echo "  nenhuma"
echo
echo "PRONTO. Revise com:  git diff  (e  git -C libs/hbb_common diff)"
