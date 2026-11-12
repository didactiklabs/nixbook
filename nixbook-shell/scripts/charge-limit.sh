# shellcheck shell=bash
# The level the battery stops charging at, for the bar's battery panel
# (services/Battery.qml):
#   nixbook-charge-limit status   what it is and whether it can be changed
#   nixbook-charge-limit set N    stop charging at N % (20 to 100)
# Both answer one JSON line: {"limit": N, "canSet": bool, "error": "…"}
# (limit 0: this battery has no such limit), and `set` exits 1 when it failed.
#
# The limit is the kernel's charge_control_end_threshold. Where that file is
# writable it is written directly; otherwise through the system unit
# battery-charge-limit@N.service (nixbook's laptopProfile, which also puts it
# back at each boot), started without a password where polkit allows it.
set -u

dir=${NIXBOOK_POWER_SUPPLY_DIR:-/sys/class/power_supply}
unit=${NIXBOOK_CHARGE_LIMIT_UNIT:-battery-charge-limit@}

file=
for candidate in "$dir"/*/charge_control_end_threshold; do
  if [ -r "$candidate" ]; then
    file=$candidate
    break
  fi
done

has_unit() { systemctl cat "$unit.service" >/dev/null 2>&1; }

answer() {
  local limit=0 can=false error=${1:-}
  if [ -n "$file" ]; then
    limit=$(cat "$file" 2>/dev/null || true)
    case "$limit" in "" | *[!0-9]*) limit=0 ;; esac
    if [ "$limit" -gt 0 ] && { [ -w "$file" ] || has_unit; }; then can=true; fi
  fi
  # One line, no quotes or backslashes: valid JSON without a JSON tool.
  error=${error//[$'\n\r\t']/ }
  error=${error//[\"\\]/}
  printf '{"limit": %d, "canSet": %s, "error": "%s"}\n' "$limit" "$can" "$error"
}

case "${1:-status}" in
status)
  answer
  ;;
set)
  want=${2:-}
  case "$want" in
  "" | *[!0-9]* | ????*)
    answer "not a percentage: $want"
    exit 1
    ;;
  esac
  want=$((10#$want))
  if [ "$want" -lt 20 ] || [ "$want" -gt 100 ]; then
    answer "a charge limit is between 20 and 100"
    exit 1
  fi
  if [ -z "$file" ]; then
    answer "this battery has no charge limit"
    exit 1
  fi
  if [ -w "$file" ]; then
    if ! out=$({ echo "$want" >"$file"; } 2>&1); then
      answer "${out:-the limit could not be written}"
      exit 1
    fi
  elif has_unit; then
    if ! out=$(systemctl start "$unit$want.service" 2>&1); then
      answer "${out:-the limit could not be set}"
      exit 1
    fi
  else
    answer "changing the limit needs administrator rights here"
    exit 1
  fi
  answer
  ;;
*)
  echo "usage: nixbook-charge-limit status | set PERCENT" >&2
  exit 2
  ;;
esac
