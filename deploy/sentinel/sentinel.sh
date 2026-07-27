#!/usr/bin/env bash
# Sentinel v0.3 — Aegis L6 deployment/network posture auditor.
# Read-only docker inspect + bounded active probes. NEVER mutates. Safe to run against a live node.
# Design: deploy/sentinel/SENTINEL-DESIGN.md. Dims 1-6 (egress · attack surface · guard/seal · straddler ·
# registry/topic · secrets/endpoints). Terminal report, or --json / --attest for records & CI.
#
#   deploy/sentinel/sentinel.sh                         # sweep every network, infer profile per node
#   deploy/sentinel/sentinel.sh --network archon_default --profile private
#   deploy/sentinel/sentinel.sh --json                  # full structured findings (for the timer / audit table)
#   SENTINEL_ATTEST_KEY=<key> deploy/sentinel/sentinel.sh --attest   # signed, timestamped posture attestation
#
# Profiles: private (must not egress) · dmz (must not egress) · sphere (egress expected, info) · control.
# --profile is authoritative; unspecified single-node audit defaults to STRICTEST (private) and cross-checks
# inference (WARN on mismatch). Inference never RELAXES a check. Signet is always a HARD loopback-only rule.
set -uo pipefail

# ---------- presentation ----------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  R=$'\033[31m'; G=$'\033[32m'; Y=$'\033[33m'; B=$'\033[1m'; D=$'\033[2m'; X=$'\033[0m'
else R=; G=; Y=; B=; D=; X=; fi
nPASS=0; nWARN=0; nFAIL=0; worst=0    # worst severity among non-PASS: 1 med 2 high 3 crit
cCRIT=0; cHIGH=0; cMED=0; cLOW=0      # severity counts (for JSON)
SCOREDED=0                           # score deduction — FAILs weigh heavily, WARNs lightly
JSON=0; ATTEST=0                      # output modes (set in arg parse; declared for `set -u`)
CUR_NODE=""; CUR_DIM=""; declare -a FINDINGS=()
sha256(){ if command -v sha256sum >/dev/null 2>&1; then sha256sum|cut -d' ' -f1; elif command -v shasum >/dev/null 2>&1; then shasum -a 256|cut -d' ' -f1; else openssl dgst -sha256|sed 's/.*= //'; fi; }
json_escape(){ printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

sev_rank(){ case "$1" in info)echo 0;; medium)echo 1;; high)echo 2;; critical)echo 3;; *)echo 0;; esac; }
# finding <PASS|WARN|FAIL> <sev> <msg> [evidence] [fix]
finding(){
  local v="$1" sev="$2" msg="$3" ev="${4:-}" fix="${5:-}" mark col
  case "$v" in
    PASS) mark="✓"; col="$G"; nPASS=$((nPASS+1));;
    WARN) mark="⚠"; col="$Y"; nWARN=$((nWARN+1));;
    FAIL) mark="✗"; col="$R"; nFAIL=$((nFAIL+1));;
  esac
  if [ "$v" != PASS ]; then
    local r; r=$(sev_rank "$sev"); [ "$r" -gt "$worst" ] && worst=$r
    case "$sev" in critical) cCRIT=$((cCRIT+1));; high) cHIGH=$((cHIGH+1));; medium) cMED=$((cMED+1));; *) cLOW=$((cLOW+1));; esac
    if [ "$v" = FAIL ]; then
      case "$sev" in critical) SCOREDED=$((SCOREDED+40));; high) SCOREDED=$((SCOREDED+20));; medium) SCOREDED=$((SCOREDED+10));; *) SCOREDED=$((SCOREDED+5));; esac
    else  # WARN — a thing to confirm, not a proven exposure: shave lightly
      case "$sev" in high) SCOREDED=$((SCOREDED+4));; medium) SCOREDED=$((SCOREDED+1));; *) SCOREDED=$((SCOREDED+0));; esac
    fi
  fi
  FINDINGS+=("$CUR_NODE"$'\037'"$CUR_DIM"$'\037'"$v"$'\037'"$sev"$'\037'"$msg")
  { [ "$JSON" = 1 ] || [ "$ATTEST" = 1 ]; } && return
  printf "  %s%s %-4s%s %s[%s]%s %s\n" "$col" "$mark" "$v" "$X" "$D" "$sev" "$X" "$msg"
  [ -n "$ev" ]  && printf "        %s· %s%s\n" "$D" "$ev" "$X"
  [ -n "$fix" ] && printf "        %s→ %s%s\n" "$D" "$fix" "$X"
}
dim(){ CUR_DIM="$1"; { [ "$JSON" = 1 ] || [ "$ATTEST" = 1 ]; } && return; printf "\n%s── %s ──%s\n" "$B" "$1" "$X"; }

# ---------- docker helpers (read-only) ----------
net_internal(){ docker network inspect "$1" --format '{{.Internal}}' 2>/dev/null; }
containers_on_net(){ docker network inspect "$1" --format '{{range $k,$v := .Containers}}{{$v.Name}} {{end}}' 2>/dev/null; }
container_nets(){ docker inspect "$1" --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' 2>/dev/null; }
has_node(){ docker exec "$1" sh -c 'command -v node' >/dev/null 2>&1; }
# published host bindings for a container: lines like "127.0.0.1:4310" or "0.0.0.0:4324"
pub_binds(){ docker inspect "$1" --format '{{range $p,$b := .NetworkSettings.Ports}}{{range $b}}{{.HostIp}}:{{.HostPort}} {{end}}{{end}}' 2>/dev/null; }
is_loopback(){ case "$1" in 127.0.0.1:*|::1:*) return 0;; *) return 1;; esac; }
pub_nonloopback(){ local b; for b in $(pub_binds "$1"); do is_loopback "$b" || { echo yes; return; }; done; echo no; }
hostport(){ echo "${1##*:}"; }   # 0.0.0.0:4324 -> 4324
code(){ curl -s -o /dev/null -w '%{http_code}' --max-time 6 "$@" 2>/dev/null; }
cenv(){ docker inspect "$1" --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | grep "^$2=" | head -1 | cut -d= -f2-; }
cimg(){ docker inspect "$1" --format '{{.Config.Image}}' 2>/dev/null; }
# member_like <net> <glob> [exclude-glob] — first running member of net matching glob (skipping exclude)
member_like(){ local net="$1" pat="$2" exc="${3:-__none__}" c; for c in $(containers_on_net "$net"); do
  case "$c" in $exc) continue;; esac; case "$c" in $pat) echo "$c"; return 0;; esac; done; return 1; }

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
  CUR_NODE="$net"
  local intl members; intl=$(net_internal "$net"); members=$(containers_on_net "$net")
  if [ "$JSON" = 0 ] && [ "$ATTEST" = 0 ]; then
    printf "\n%s══════════════════════════════════════════════════════════════%s\n" "$B" "$X"
    printf "%s NODE%s  network=%s%s%s  profile=%s%s%s%s\n" "$B" "$X" "$B" "$net" "$X" "$B" "$prof" "$X" \
      "$([ "$inferred" = 1 ] && echo " ${D}(inferred)${X}")"
    printf "  %smembers: %s%s\n" "$D" "$(echo $members | sed 's/ /, /g')" "$X"
  fi

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

  # ---- DIM 5 · Registry & topic (REGISTRY-FIRST — Hearthold refinement #1) ----
  dim "DIM 5 · Registry & topic"
  local gk; gk=$(member_like "$net" '*gatekeeper*' '*guard*') || gk=""
  if [ -z "$gk" ]; then
    finding PASS info "no gatekeeper on this node — n/a"
  else
    local regs; regs=$(cenv "$gk" ARCHON_GATEKEEPER_REGISTRIES)
    if [ "$regs" = "local" ] || [ -z "$regs" ]; then
      finding PASS high "registry is local-only ($gk: '${regs:-local}') — cannot gossip; topic is moot"
    else
      finding WARN medium "gatekeeper exposes a gossip registry ('$regs') — topic privacy now matters" "$gk"
      local med; med=$(member_like "$net" '*mediator*') || med=""
      if [ -z "$med" ]; then
        finding WARN medium "gossip registry configured but no mediator running — gossip inactive (drift risk if one starts)"
      else
        local topic img tpriv=0; topic=$(cenv "$med" ARCHON_PROTOCOL); img=$(cimg "$med")
        case "$topic" in
          */ARCHON/v0.8-beta) finding FAIL critical "on the PUBLIC default topic /ARCHON/v0.8-beta — private DIDs would propagate publicly" "$med" "set ARCHON_PROTOCOL to a private random topic (setup-node.sh)";;
          ""|*REPLACE*|*'<'*) finding FAIL high "placeholder/empty topic ('$topic') — never gossip on an un-minted topic" "$med" "mint /aegis-private/\$(openssl rand -hex 32)";;
          /aegis-private/*|/aegis-sphere/*) tpriv=1; finding PASS high "private topic ($topic, len ${#topic})";;
          *) finding WARN medium "non-default topic '$topic' — confirm it's private-random, not shared/guessable";;
        esac
        case "$img" in
          *secure-mediator*)     finding PASS high "secure mediator ($img) — peer-auth + scoped gossip";;
          *hyperswarm-mediator*)
            if [ "$tpriv" = 1 ]; then finding WARN medium "STOCK mediator on a private topic — exposure bounded to topic-knowers, but no peer-auth/scoping (a non-member who learns the topic can join/inject)" "$img" "swap to aegis-secure-mediator"
            else finding WARN high "STOCK mediator on a non-private topic — bulk-gossips the DID set with no auth" "$img" "swap to aegis-secure-mediator"; fi;;
          *) finding WARN info "mediator image '$img' unrecognized — confirm gossip scope/auth";;
        esac
      fi
    fi
  fi

  # ---- DIM 6 · Secrets & endpoints ----
  dim "DIM 6 · Secrets & endpoints"
  local sec; sec=$(member_like "$net" '*gatekeeper*' '*guard*') || sec=$(member_like "$net" '*keymaster*') || sec=""
  if [ -z "$sec" ]; then
    finding PASS info "no gatekeeper/keymaster on this node — n/a"
  else
    local key; key=$(cenv "$sec" ARCHON_ADMIN_API_KEY)
    case "$key" in
      "") if [ "$(pub_nonloopback "$sec")" = yes ]; then
            finding FAIL critical "admin API key BLANK on a LAN-published gatekeeper ($sec) — admin routes open to the network" "" "set ARCHON_ADMIN_API_KEY=\$(openssl rand -hex 32)"
          else
            finding WARN high "admin API key BLANK ($sec) — admin routes unprotected (loopback/in-network only; defense-in-depth gap)" "" "set ARCHON_ADMIN_API_KEY even for internal/ephemeral nodes"
          fi;;
      measure-key|changeme|admin|test|password|secret|sample|key) finding WARN high "admin key is a weak/sample value ('$key')" "$sec" "regenerate a unique key";;
      *) if [ "${#key}" -lt 32 ]; then finding WARN medium "admin key is short (${#key} chars) — prefer 64-hex"; else finding PASS medium "admin key set (${#key} chars)"; fi;;
    esac
    local km pp; km=$(member_like "$net" '*keymaster*') || km="$sec"
    pp=$(cenv "$km" ARCHON_ENCRYPTED_PASSPHRASE)
    [ -z "$pp" ] && { local wd; wd=$(member_like "$net" '*warden*' '*bridge*') && pp=$(cenv "$wd" HEARTHOLD_PASSPHRASE); }
    case "$pp" in
      "") finding WARN medium "wallet passphrase not found in env here (may be set elsewhere) — confirm it's not blank";;
      measure-pp|changeme|password|sample) finding WARN medium "wallet passphrase is a sample value ('$pp')";;
      *) finding PASS medium "wallet passphrase set";;
    esac
  fi
  local db; db=$(member_like "$net" '*drawbridge*') || db=""
  if [ -n "$db" ]; then
    local host; host=$(cenv "$db" ARCHON_DRAWBRIDGE_PUBLIC_HOST)
    case "$host" in
      "") finding PASS info "no advertised external DIDComm host (in-network default)";;
      http://drawbridge*|http://*:4222*) finding PASS info "in-network DIDComm host ($host)";;
      *.local*|*.internal*|*sandbox*) finding WARN medium "advertises a non-resolving host ($host) — DIDComm delivery can 502 unless HEARTHOLD_DIDCOMM_ENDPOINT overrides in-network" "$db";;
      http://*|https://*) finding WARN medium "advertises an external host ($host) — on an isolated node confirm this isn't a leak/misconfig" "$db";;
      *) finding WARN info "DIDComm host '$host' — unrecognized form";;
    esac
  fi
}

# ---------- output modes ----------
emit_json(){
  local ts; ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  printf '{"sentinel":"v0.3","host":"%s","timestamp":"%s","summary":{"pass":%d,"warn":%d,"fail":%d},"score":%d,"verdict":"%s","findings":[' \
    "$(hostname)" "$ts" "$nPASS" "$nWARN" "$nFAIL" "$score" "$verdict"
  local i=0 f node d v s m
  for f in "${FINDINGS[@]:-}"; do
    [ -z "$f" ] && continue
    IFS=$'\037' read -r node d v s m <<<"$f"
    [ "$i" -gt 0 ] && printf ','
    printf '{"node":"%s","dim":"%s","verdict":"%s","severity":"%s","message":"%s"}' \
      "$(json_escape "$node")" "$(json_escape "$d")" "$v" "$s" "$(json_escape "$m")"
    i=$((i+1))
  done
  printf ']}\n'
}
# a signed, timestamped posture attestation — a tamper-evident record that the clean state was verified.
emit_attestation(){
  local ts digest att sig key
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  digest=$(printf '%s\n' "${FINDINGS[@]:-}" | sha256)
  att=$(printf '{"host":"%s","timestamp":"%s","sentinel":"v0.3","verdict":"%s","score":%d,"summary":{"pass":%d,"warn":%d,"fail":%d},"findings_digest":"sha256:%s"}' \
    "$(hostname)" "$ts" "$verdict" "$score" "$nPASS" "$nWARN" "$nFAIL" "$digest")
  key="${SENTINEL_ATTEST_KEY:-}"
  if [ -n "$key" ]; then
    sig=$(printf '%s' "$att" | openssl dgst -sha256 -hmac "$key" 2>/dev/null | awk '{print $NF}')
    printf '{"attestation":%s,"signature":{"alg":"HMAC-SHA256","value":"%s"}}\n' "$att" "$sig"
  else
    printf '{"attestation":%s,"signature":null,"note":"set SENTINEL_ATTEST_KEY for a tamper-evident HMAC signature"}\n' "$att"
  fi
}
print_handoff(){
  printf "\n%s── HANDOFF · what Sentinel (L6) does NOT cover ──%s\n" "$B" "$X"
  printf "  %sA full posture = these L6 checks + Hearthold's L1–L5 review:%s\n" "$D" "$X"
  printf "  %s· L1–L2 app/session — require-session, per-member scoping, step-up reveal, key custody (keys stay in the Signet)\n" "$D"
  printf "  · L3 control — anti-DNS-rebinding, anti-CSRF, CORS allow-list on the control server\n"
  printf "  · L4 read-gating — the unauth GET /did/:did residual (Archon's universal resolver, by design)\n"
  printf "  · L5 config defaults — registry=local, control-host loopback%s\n" "$X"
}

# ---------- main ----------
NETWORK=""; PROFILE=""
while [ $# -gt 0 ]; do case "$1" in
  --network) NETWORK="$2"; shift 2;;
  --profile) PROFILE="$2"; shift 2;;
  --json)    JSON=1; shift;;
  --attest)  ATTEST=1; shift;;
  -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
  *) echo "unknown arg: $1" >&2; exit 2;;
esac; done

if [ "$JSON" = 0 ] && [ "$ATTEST" = 0 ]; then
  printf "%s════════════════════════════════════════════════════════════════%s\n" "$B" "$X"
  printf "%s SENTINEL v0.3 — Aegis L6 posture audit%s   %s%s%s\n" "$B" "$X" "$D" "$(hostname)" "$X"
  printf "%s════════════════════════════════════════════════════════════════%s\n" "$B" "$X"
fi

if [ -n "$NETWORK" ]; then
  audit_network "$NETWORK" "${PROFILE:-private}" "$([ -z "$PROFILE" ] && echo 1 || echo 0)"
else
  for net in $(docker network ls --format '{{.Name}}' | grep -vE '^(bridge|host|none)$'); do
    [ -z "$(containers_on_net "$net")" ] && continue
    audit_network "$net" "${PROFILE:-$(infer_profile "$net")}" "$([ -z "$PROFILE" ] && echo 1 || echo 0)"
  done
fi

# ---------- verdict + score ----------
verdict="OK"; vc="$G"
[ "$nWARN" -gt 0 ] && { verdict="REVIEW"; vc="$Y"; }
[ "$worst" -ge 2 ] && { verdict="AT RISK"; vc="$R"; }
[ "$nFAIL" -gt 0 ] && [ "$worst" -ge 3 ] && { verdict="CRITICAL"; vc="$R"; }
score=$((100 - SCOREDED)); [ "$score" -lt 0 ] && score=0

if   [ "$JSON" = 1 ];   then emit_json
elif [ "$ATTEST" = 1 ]; then emit_attestation
else
  printf "\n%s════ VERDICT ════%s\n" "$B" "$X"
  printf "  %d PASS · %d WARN · %d FAIL   ·  score %s%d/100%s   →  POSTURE: %s%s%s\n" \
    "$nPASS" "$nWARN" "$nFAIL" "$B" "$score" "$X" "$vc" "$verdict" "$X"
  print_handoff
fi
[ "$nFAIL" = 0 ]
