#!/usr/bin/env bash
# Sentinel v0.1 — Aegis L6 deployment/network posture auditor.
# Read-only docker inspect + bounded active probes. NEVER mutates. Safe to run against a live node.
# Design: deploy/sentinel/SENTINEL-DESIGN.md. Dims 1-4 (egress · attack surface · guard/seal · straddler).
#
#   deploy/sentinel/sentinel.sh                         # sweep every network, infer profile per node
#   deploy/sentinel/sentinel.sh --network archon_default --profile private
#   deploy/sentinel/sentinel.sh --json                  # (stub in v0.1: verdict line only)
#
# Profiles: private (must not egress) · dmz (must not egress) · sphere (egress expected, info) · control.
# --profile is authoritative; unspecified single-node audit defaults to STRICTEST (private) and cross-checks
# inference (WARN on mismatch). Inference never RELAXES a check. Signet is always a HARD loopback-only rule.
set -uo pipefail

# ---------- presentation ----------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  R=$'\033[31m'; G=$'\033[32m'; Y=$'\033[33m'; B=$'\033[1m'; D=$'\033[2m'; X=$'\033[0m'
else R=; G=; Y=; B=; D=; X=; fi
nPASS=0; nWARN=0; nFAIL=0; worst=0   # worst severity seen among non-PASS: 1 med 2 high 3 crit

sev_rank(){ case "$1" in info)echo 0;; medium)echo 1;; high)echo 2;; critical)echo 3;; *)echo 0;; esac; }
# finding <PASS|WARN|FAIL> <sev> <msg> [evidence] [fix]
finding(){
  local v="$1" sev="$2" msg="$3" ev="${4:-}" fix="${5:-}" mark col
  case "$v" in
    PASS) mark="✓"; col="$G"; nPASS=$((nPASS+1));;
    WARN) mark="⚠"; col="$Y"; nWARN=$((nWARN+1));;
    FAIL) mark="✗"; col="$R"; nFAIL=$((nFAIL+1));;
  esac
  if [ "$v" != PASS ]; then local r; r=$(sev_rank "$sev"); [ "$r" -gt "$worst" ] && worst=$r; fi
  printf "  %s%s %-4s%s %s[%s]%s %s\n" "$col" "$mark" "$v" "$X" "$D" "$sev" "$X" "$msg"
  [ -n "$ev" ]  && printf "        %s· %s%s\n" "$D" "$ev" "$X"
  [ -n "$fix" ] && printf "        %s→ %s%s\n" "$D" "$fix" "$X"
}
dim(){ printf "\n%s── %s ──%s\n" "$B" "$1" "$X"; }

# ---------- docker helpers (read-only) ----------
net_internal(){ docker network inspect "$1" --format '{{.Internal}}' 2>/dev/null; }
containers_on_net(){ docker network inspect "$1" --format '{{range $k,$v := .Containers}}{{$v.Name}} {{end}}' 2>/dev/null; }
container_nets(){ docker inspect "$1" --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' 2>/dev/null; }
has_node(){ docker exec "$1" sh -c 'command -v node' >/dev/null 2>&1; }
# published host bindings for a container: lines like "127.0.0.1:4310" or "0.0.0.0:4324"
pub_binds(){ docker inspect "$1" --format '{{range $p,$b := .NetworkSettings.Ports}}{{range $b}}{{.HostIp}}:{{.HostPort}} {{end}}{{end}}' 2>/dev/null; }
is_loopback(){ case "$1" in 127.0.0.1:*|::1:*) return 0;; *) return 1;; esac; }
hostport(){ echo "${1##*:}"; }   # 0.0.0.0:4324 -> 4324
code(){ curl -s -o /dev/null -w '%{http_code}' --max-time 6 "$@" 2>/dev/null; }

# egress probe from a network: try a node-capable member, then a throwaway alpine on that net.
egress_probe(){
  local net="$1" c
  for c in $(containers_on_net "$net"); do
    if has_node "$c"; then
      docker exec "$c" node -e 'const s=require("net").connect({host:"1.1.1.1",port:443,timeout:4000});s.on("connect",()=>{console.log("REACHED");process.exit()});s.on("timeout",()=>{console.log("TIMEOUT");s.destroy();process.exit()});s.on("error",e=>{console.log("ISOLATED "+e.code);process.exit()})' 2>/dev/null && return
    fi
  done
  docker run --rm --network "$net" alpine:3.20 sh -c 'nc -w3 -z 1.1.1.1 443 2>/dev/null && echo REACHED || echo "ISOLATED nc"' 2>/dev/null || echo "UNKNOWN"
}

infer_profile(){
  local net="$1"; [ "$(net_internal "$net")" = true ] && { echo private; return; }
  for c in $(containers_on_net "$net"); do case "$c" in *mediator*) echo sphere; return;; esac; done
  echo open
}

# ---------- the audit ----------
audit_network(){
  local net="$1" prof="$2" inferred="$3"
  local intl; intl=$(net_internal "$net")
  printf "\n%s══════════════════════════════════════════════════════════════%s\n" "$B" "$X"
  printf "%s NODE%s  network=%s%s%s  profile=%s%s%s%s\n" "$B" "$X" "$B" "$net" "$X" "$B" "$prof" "$X" \
    "$([ "$inferred" = 1 ] && echo " ${D}(inferred)${X}")"
  local members; members=$(containers_on_net "$net")
  printf "  %smembers: %s%s\n" "$D" "$(echo $members | sed 's/ /, /g')" "$X"

  # cross-check inference vs declared
  if [ "$inferred" = 0 ]; then
    local inf; inf=$(infer_profile "$net")
    [ "$inf" != "$prof" ] && finding WARN medium "declared profile '$prof' but topology infers '$inf'" \
      "internal=$intl$( for c in $members; do case $c in *mediator*) echo -n ' +mediator';; esac; done)" \
      "confirm --profile matches intent; inference never relaxes checks"
  fi

  # ---- DIM 1 · Egress isolation ----
  dim "DIM 1 · Egress isolation"
  case "$prof" in
    private|dmz)
      if [ "$intl" = true ]; then finding PASS info "network is internal:true"
      else finding FAIL high "network is NOT internal (egress-capable) but profile=$prof requires isolation" \
        "docker network inspect $net .Internal=$intl" "add 'internal: true' to the network (docker-compose.override.yml)"; fi
      local e; e=$(egress_probe "$net")
      case "$e" in
        ISOLATED*) finding PASS critical "no egress reached the internet ($e)" ;;
        REACHED)   finding FAIL critical "a container REACHED the internet — ISOLATION BREACH" \
                     "probe TCP 1.1.1.1:443 from a member succeeded" "the network is leaking egress; do NOT relax to pass — find the leak" ;;
        TIMEOUT)   finding WARN medium "egress probe timed out (no hard-fail, no reach)" "soft-fail; treat as inconclusive" ;;
        *)         finding WARN info "egress probe inconclusive ($e)" ;;
      esac ;;
    sphere)
      finding PASS info "SPHERE node — egress is expected (hyperswarm DHT); internal=$intl"
      [ "$intl" = true ] && finding WARN medium "sphere node on an internal network — the mediator can't reach the DHT" ;;
    *)
      finding WARN medium "egress-capable network, profile=$prof — confirm this is intended (bridge / measurement / DMZ)" \
        "internal=$intl" ;;
  esac

  # ---- DIM 4 · Straddler audit ----
  dim "DIM 4 · Straddler audit (internal + open legs)"
  local found_straddle=0
  for c in $members; do
    local nets open_legs=""; nets=$(container_nets "$c")
    local hasInt=0 hasOpen=0
    for n in $nets; do [ "$(net_internal "$n")" = true ] && hasInt=1 || { hasOpen=1; open_legs="$open_legs $n"; }; done
    if [ "$hasInt" = 1 ] && [ "$hasOpen" = 1 ]; then
      found_straddle=1
      local binds; binds=$(pub_binds "$c"); local nonlb=""
      for bnd in $binds; do is_loopback "$bnd" || nonlb="$nonlb $bnd"; done
      if [ -n "$nonlb" ]; then
        finding FAIL critical "straddler $c bridges internal+open AND publishes non-loopback:$nonlb" \
          "open legs:$open_legs" "a straddler may only publish loopback ports; move the publish to 127.0.0.1 or drop the open leg"
      else
        finding WARN medium "justified straddler $c (open leg$open_legs) — publishes loopback only:${binds:- none}" \
          "" "expected for tcp-forward bridges; no non-loopback surface"
      fi
    fi
  done
  [ "$found_straddle" = 0 ] && finding PASS info "no container straddles internal + open networks"

  # ---- DIM 2 · Attack surface (exploitability) + DIM 3 · Guard/seal ----
  dim "DIM 2 · Attack surface  ·  DIM 3 · Guard / seal (active)"
  local any_pub=0
  for c in $members; do
    local binds; binds=$(pub_binds "$c"); [ -z "$binds" ] && continue
    for bnd in $binds; do
      any_pub=1; local port; port=$(hostport "$bnd") ; local url="http://127.0.0.1:$port"
      # classify by container role
      case "$c" in
        *signet*)   # HARD loopback-only, no exceptions
          if is_loopback "$bnd"; then finding PASS info "Signet published loopback-only ($bnd)"
          else finding FAIL critical "Signet published beyond loopback ($bnd) — signing authority MUST stay loopback" \
            "" "bind the Signet bridge to 127.0.0.1 only; no guard substitutes for this"; fi ;;
        *warden*console*|*warden*control*|*control*)   # control plane — probe the L3 guard if exposed
          if is_loopback "$bnd"; then finding PASS info "control plane published loopback-only ($bnd)"
          else
            local ch co; ch=$(code -H 'Host: evil.example' "$url/api/status"); co=$(code -H 'Origin: https://evil.example' "$url/api/snapshot")
            if [ "$ch" = 403 ] && { [ "$co" = 403 ] || [ "$co" = 401 ]; }; then
              finding WARN high "control plane published beyond loopback ($bnd) but GUARD PROVEN (rebound-Host 403, cross-origin/scoped ${co})" \
                "" "acceptable only if the guard is intended to face this interface; prefer loopback"
            else
              finding FAIL critical "control plane published ($bnd) with guard ABSENT (Host-rebind=$ch cross-origin=$co)" \
                "" "bind to loopback, or ensure the hardened control server (anti-rebind/CSRF/require-session) is on"
            fi
          fi ;;
        *gatekeeper*|*guard*)   # DIM 3 — the seal probe
          local rv en im; rv=$(code "$url/api/v1/did/did:cid:bagaaieraaa"); en=$(code -X POST -H 'content-type: application/json' -d '{}' "$url/api/v1/dids/"); im=$(code -X POST -H 'content-type: application/json' -d '[]' "$url/api/v1/batch/import")
          if [ "$en" = 403 ] && [ "$im" = 403 ]; then
            finding PASS high "gatekeeper $bnd SEALED (resolve=$rv enumerate=403 import=403)"
          elif is_loopback "$bnd"; then
            finding WARN medium "raw (unsealed) gatekeeper on loopback ($bnd) — admin/enumerate reachable host-locally only (resolve=$rv enum=$en import=$im)" \
              "" "fine if intended (e.g. the DMZ import path); seal it if it must not answer admin even on-box"
          else
            finding FAIL critical "gatekeeper $bnd OPEN + non-loopback (resolve=$rv enumerate=$en import=$im) — writes/enumerate reachable off-box" \
              "" "put it behind gatekeeper-guard.mjs (docker-compose.sealed.yml) or unpublish it"
          fi ;;
        *)   # unclassified publish
          if is_loopback "$bnd"; then finding PASS info "$c published loopback-only ($bnd)"
          else finding WARN medium "$c publishes non-loopback ($bnd) — unclassified surface" \
            "" "confirm this port is meant to face LAN/tailnet; if not, bind 127.0.0.1"; fi ;;
      esac
    done
  done
  [ "$any_pub" = 0 ] && finding PASS info "no published ports on this node's containers"
}

# ---------- main ----------
NETWORK=""; PROFILE=""; JSON=0
while [ $# -gt 0 ]; do case "$1" in
  --network) NETWORK="$2"; shift 2;;
  --profile) PROFILE="$2"; shift 2;;
  --json) JSON=1; shift;;
  -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
  *) echo "unknown arg: $1" >&2; exit 2;;
esac; done

printf "%s════════════════════════════════════════════════════════════════%s\n" "$B" "$X"
printf "%s SENTINEL v0.1 — Aegis L6 posture audit%s   %s%s%s\n" "$B" "$X" "$D" "$(hostname)" "$X"
printf "%s════════════════════════════════════════════════════════════════%s\n" "$B" "$X"

if [ -n "$NETWORK" ]; then
  prof="${PROFILE:-private}"; inferred=0; [ -z "$PROFILE" ] && inferred=0
  audit_network "$NETWORK" "$prof" "$([ -z "$PROFILE" ] && echo 1 || echo 0)"
else
  # sweep every non-builtin network, infer profile per node
  for net in $(docker network ls --format '{{.Name}}' | grep -vE '^(bridge|host|none)$'); do
    [ -z "$(containers_on_net "$net")" ] && continue   # skip empty networks
    prof="${PROFILE:-$(infer_profile "$net")}"
    audit_network "$net" "$prof" "$([ -z "$PROFILE" ] && echo 1 || echo 0)"
  done
fi

# ---------- verdict ----------
printf "\n%s════ VERDICT ════%s\n" "$B" "$X"
verdict="OK"; vc="$G"
[ "$nWARN" -gt 0 ] && { verdict="REVIEW"; vc="$Y"; }
[ "$worst" -ge 2 ] && { verdict="AT RISK"; vc="$R"; }   # a high/critical non-PASS
[ "$nFAIL" -gt 0 ] && [ "$worst" -ge 3 ] && { verdict="CRITICAL"; vc="$R"; }
printf "  %d PASS · %d WARN · %d FAIL   →  POSTURE: %s%s%s\n" "$nPASS" "$nWARN" "$nFAIL" "$vc" "$verdict" "$X"
[ "$JSON" = 1 ] && printf '{"pass":%d,"warn":%d,"fail":%d,"verdict":"%s"}\n' "$nPASS" "$nWARN" "$nFAIL" "$verdict"
[ "$nFAIL" = 0 ]
