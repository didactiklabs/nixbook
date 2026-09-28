#!/usr/bin/env bash
# Snapshot of KDE Connect state as one JSON line, for services/KdeConnect.qml.
# Reads the daemon over D-Bus with busctl (one process per call, no polling of
# its own — the service runs this on D-Bus signals and when the panel opens).
#
# {"available":bool,"selfName":str,"devices":[{"id","name","type","icon",
#   "reachable","paired","pairRequested","verificationKey","plugins":[...],
#   "battery":int(-1),"charging":bool,"network":str,"signal":int(-1)}]}
set -u

svc=org.kde.kdeconnect
base=/modules/kdeconnect

if ! busctl --user status "$svc" >/dev/null 2>&1; then
  echo '{"available":false,"selfName":"","devices":[]}'
  exit 0
fi

prop() { # path iface name -> JSON value or null
  busctl --user --json=short get-property "$svc" "$1" "$2" "$3" 2>/dev/null | jq -c '.data' 2>/dev/null || echo null
}

self_name=$(busctl --user --json=short call "$svc" "$base" org.kde.kdeconnect.daemon announcedName 2>/dev/null | jq -c '.data[0]' 2>/dev/null)
[ -n "$self_name" ] || self_name='""'

ids=$(busctl --user --json=short call "$svc" "$base" org.kde.kdeconnect.daemon devices bb false false 2>/dev/null | jq -r '.data[0][]' 2>/dev/null)

devices=()
for id in $ids; do
  p="$base/devices/$id"
  d=org.kde.kdeconnect.device
  plugins=$(prop "$p" "$d" supportedPlugins)
  has() { jq -e --arg n "kdeconnect_$1" 'index($n) != null' <<<"$plugins" >/dev/null 2>&1; }
  battery=-1 charging=false network='""' signal=-1
  if has battery; then
    battery=$(prop "$p/battery" "$d.battery" charge)
    charging=$(prop "$p/battery" "$d.battery" isCharging)
  fi
  if has connectivity_report; then
    network=$(prop "$p/connectivity_report" "$d.connectivity_report" cellularNetworkType)
    signal=$(prop "$p/connectivity_report" "$d.connectivity_report" cellularNetworkStrength)
  fi
  devices+=("$(jq -nc \
    --arg id "$id" \
    --argjson name "$(prop "$p" "$d" name)" \
    --argjson type "$(prop "$p" "$d" type)" \
    --argjson icon "$(prop "$p" "$d" statusIconName)" \
    --argjson reachable "$(prop "$p" "$d" isReachable)" \
    --argjson paired "$(prop "$p" "$d" isPaired)" \
    --argjson pairRequested "$(prop "$p" "$d" isPairRequestedByPeer)" \
    --argjson verificationKey "$(prop "$p" "$d" verificationKey)" \
    --argjson plugins "${plugins:-null}" \
    --argjson battery "${battery:-null}" \
    --argjson charging "${charging:-null}" \
    --argjson network "${network:-null}" \
    --argjson signal "${signal:-null}" \
    '{id: $id, name: ($name // $id), type: ($type // "phone"), icon: ($icon // ""),
      reachable: ($reachable // false), paired: ($paired // false),
      pairRequested: ($pairRequested // false), verificationKey: ($verificationKey // ""),
      plugins: (($plugins // []) | map(sub("^kdeconnect_"; ""))),
      battery: ($battery // -1), charging: ($charging // false),
      network: ($network // ""), signal: ($signal // -1)}')")
done

printf '%s\n' "${devices[@]}" | jq -sc --argjson selfName "$self_name" \
  '{available: true, selfName: $selfName, devices: map(select(. != null))}'
