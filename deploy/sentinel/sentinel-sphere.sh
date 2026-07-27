#!/usr/bin/env bash
# Collate Sentinel across a sphere's hosts. Per-host verdict + a SPHERE verdict = the WORST per-host
# verdict (one AT RISK/CRITICAL host, or an unreachable one, sets the sphere). Per-host report stays
# primary; this is a thin roll-up (per Hearthold review). Needs `node` on the collating host (JSON parse).
#
#   deploy/sentinel/sentinel-sphere.sh local gamerflax
#   SENTINEL_REMOTE_DIR=~/isolation/aegis deploy/sentinel/sentinel-sphere.sh local megaflax
#
# 'local' audits THIS host. A hostname is reached over ssh; the repo is expected at $SENTINEL_REMOTE_DIR
# (default ~/research/aegis) with docker access for that user.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
REMOTE="${SENTINEL_REMOTE_DIR:-\$HOME/research/aegis}"
hosts=("$@"); [ "${#hosts[@]}" -eq 0 ] && hosts=(local)

rank(){ case "$1" in CRITICAL) echo 3;; "AT RISK") echo 2;; REVIEW) echo 1;; OK) echo 0;; *) echo 2;; esac; }
worstv=0; worstlabel="OK"
bump(){ local r; r=$(rank "$1"); [ "$r" -gt "$worstv" ] && { worstv=$r; worstlabel="$2"; }; }

printf "══ SENTINEL SPHERE — %d host(s) ══\n" "${#hosts[@]}"
for h in "${hosts[@]}"; do
  if [ "$h" = local ]; then j=$("$DIR/sentinel.sh" --json 2>/dev/null)
  else j=$(ssh -o ConnectTimeout=8 "$h" "cd $REMOTE && deploy/sentinel/sentinel.sh --json" 2>/dev/null); fi
  if [ -z "$j" ]; then printf "  %-16s UNREACHABLE / no output\n" "$h"; bump "AT RISK" "AT RISK ($h unreachable)"; continue; fi
  if ! read -r pass warn fail score verdict < <(printf '%s' "$j" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const j=JSON.parse(s);console.log(j.summary.pass,j.summary.warn,j.summary.fail,j.score,j.verdict)}catch(e){process.exit(1)}})'); then
    printf "  %-16s BAD OUTPUT (not JSON)\n" "$h"; bump "AT RISK" "AT RISK ($h bad output)"; continue; fi
  printf "  %-16s %-9s  %s PASS · %s WARN · %s FAIL · score %s/100\n" "$h" "$verdict" "$pass" "$warn" "$fail" "$score"
  bump "$verdict" "$verdict"
done

echo "──"
echo "SPHERE VERDICT: $worstlabel  (worst of ${#hosts[@]} host(s))"
[ "$worstv" -ge 2 ] && exit 1 || exit 0
