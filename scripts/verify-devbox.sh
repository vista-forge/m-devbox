#!/usr/bin/env bash
# Acceptance gates for the m-devbox image — all engine execution through the
# driver seam (`m vista exec` / `m test`), never a raw exec.
#
#   verify-devbox.sh [image]        (default m-devbox:0.1.0-local)
#
# Gates:
#   G1  registry-driven env gate — every package declared in m-stdlib's
#       dist/callout-symbols.json is wired as image ENV (ydb_xc_<pkg>), plus
#       STDLIB_LIB. This is what makes the Dockerfile's hand-written ENV list
#       safe: registry drift reds here.
#   G2  known-answer callout call through the driver seam, NON-login shell —
#       $$sha256^STDCRYPTO("abc") must return the FIPS 180-4 vector. Proves
#       the .so set is present, loadable, and correct (not the stale-hmac
#       failure mode), and that PR-5's env claim is closed by execution.
#   G3  availability probes — $$available^STDCRYPTO() is itself a KAT.
#   G4  negative arm (informational): an EMPTIED ydb_xc_* — measured
#       2026-07-22: the engine HANGS on the first $& (an in-engine hang no
#       module $etrap can catch). Recorded, not gated: the image never ships
#       this state (env baked non-empty; G1 asserts it).
#   G5  negative arm (informational): a WIRED .xc whose .so is missing
#       (STDLIB_LIB pointed nowhere) — measured 2026-07-22: also a hang.
#       This is the state the in-build HANG-GUARD exists to prevent.
#   G6  size + artifact report.
#   G7  PR-6 — the devcontainer-uid acceptance. A green `m test` on a real MSL
#       suite as (a) root, (b) an ARBITRARY uid that is neither root nor
#       pre-baked, (c) the baked `devbox` user. Arm (b) is the one the whole
#       row exists for: the unfixed image refused every verb with
#       RUNLOCK_FAILED (measured 2026-07-22).
#   G8  PR-6 negative arm — `--user <uid>:<non-zero-gid>` is out of contract and
#       must REFUSE LOUDLY (exit 78, naming the fix), not fall through into an
#       opaque RUNLOCK_FAILED three layers down. Gated, not informational: a
#       refusal that rots into a silent pass is the failure mode
#       [[degrade-loud-or-refuse]] names.
set -uo pipefail

IMG="${1:-m-devbox:0.1.0-local}"
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FORGE="${FORGE:-$(cd -- "$HERE/../.." && pwd)}"
REG="$FORGE/m-stdlib/dist/callout-symbols.json"
KAT_ABC=ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
# The PR-6 acceptance suite: a real MSL suite with real assertions, so a
# green arm cannot be a vacuous 0/0 (which m-cli scores RED anyway — PR-18).
ACC_SUITE=/opt/msl/tests/STDSTRTST.m
ACC_EXPECT=63
rc=0
fail() { echo "FAIL: $*" >&2; rc=1; }
run() { timeout 90 docker run --rm "$@"; }

[ -f "$REG" ] || { echo "FATAL: no callout registry at $REG (is FORGE=$FORGE right?)" >&2; exit 2; }
docker image inspect "$IMG" >/dev/null 2>&1 || {
  echo "FATAL: image '$IMG' is not present." >&2
  echo "       build it   : make build      (sync-time; network)" >&2
  echo "       or load it : make load       (offline, from the engine-image archive)" >&2
  exit 2
}
echo "image: $IMG ($(docker image inspect --format '{{.Id}}' "$IMG"))"

echo "== G1: registry-driven env gate =="
mapfile -t PKGS < <(python3 - "$REG" <<'PY'
import json, sys
for lib in json.load(open(sys.argv[1]))["libraries"]:
    stem = lib["xc"].removesuffix(".xc")
    print("".join(c for c in stem if c.isalnum()))
PY
)
ENVDUMP="$(run "$IMG" env)"
for p in "${PKGS[@]}"; do
  grep -q "^ydb_xc_${p}=" <<<"$ENVDUMP" || fail "ydb_xc_${p} missing from image ENV (registry drift?)"
done
grep -q '^STDLIB_LIB=' <<<"$ENVDUMP" || fail "STDLIB_LIB missing from image ENV"
echo "declared packages: ${PKGS[*]}"

echo "== G2: known-answer digest through the driver seam (non-login shell) =="
OUT="$(run "$IMG" m vista exec --engine ydb --transport local 'write $$sha256^STDCRYPTO("abc")' 2>&1)"
if grep -q "$KAT_ABC" <<<"$OUT"; then
  echo "KAT ok: sha256('abc') = $KAT_ABC"
else
  fail "KAT mismatch or error:"$'\n'"$OUT"
fi

echo "== G3: availability probes =="
OUT="$(run "$IMG" m vista exec --engine ydb --transport local 'write $$available^STDCRYPTO(),":",$$available^STDCOMPRESS(),":",$$available^STDHTTP(),":",$$available^STDFS(),":",$$useCallout^STDCSPRNG()' 2>&1)"
# Expected "1::1:1:1": STDCOMPRESS's available() returns "" on SUCCESS
# (missing-library list; empty = both libz and libzstd loaded).
if grep -q '1::1:1:1' <<<"$OUT"; then
  echo "all five callout families available"
else
  fail "availability probe:"$'\n'"$OUT"
fi

echo "== G4 (informational): emptied ydb_xc_* =="
OUT="$(timeout 30 docker run --rm -e ydb_xc_stdcrypto= "$IMG" \
  m vista exec --engine ydb --transport local 'write $$sha256^STDCRYPTO("abc")' 2>&1)"
g4=$?
if [ $g4 -eq 124 ]; then
  echo "HANG confirmed (timeout after 30s) — empty ydb_xc_* hangs the engine on first \$&; the image never ships this state (G1)"
elif grep -q "$KAT_ABC" <<<"$OUT"; then
  fail "env override ineffective — digest still returned with ydb_xc_stdcrypto emptied"
else
  echo "no hang (rc=$g4): $(tail -2 <<<"$OUT" | head -1)"
fi

echo "== G5 (informational): wired .xc, missing .so =="
OUT="$(timeout 30 docker run --rm -e STDLIB_LIB=/nonexistent "$IMG" \
  m vista exec --engine ydb --transport local 'write $$sha256^STDCRYPTO("abc")' 2>&1)"
g5=$?
if [ $g5 -eq 124 ]; then
  echo "HANG confirmed (timeout after 30s) — this is the state the in-build HANG-GUARD refuses"
else
  echo "no hang (rc=$g5): $(tail -2 <<<"$OUT" | head -1)"
fi

echo "== G6: sizes =="
docker image ls --format '{{.Repository}}:{{.Tag}}  {{.Size}}' "$IMG"
run "$IMG" sh -c 'ls -la /opt/stdlib/lib /opt/stdlib/xc; du -sh /opt/stdlib'

echo "== G7: PR-6 — a green m test as root, an arbitrary uid, and the baked user =="
# Arm labels and their docker --user argv. "" = the image default (root).

# Read `passed failed` out of an `m test` envelope on stdin. Prints "NOTOK …"
# when the envelope itself is red and "ERR ERR" when it is not parseable — both
# fail the comparison below, so a mangled envelope can never read as green.
acc_score() {
  python3 -c '
import json, sys
try:
    d = json.loads(sys.stdin.read())
except Exception:
    print("ERR ERR"); raise SystemExit
g = d.get("data") or {}
ok = d.get("ok") is True
print(g.get("passed", "ERR") if ok else "NOTOK", g.get("failed", "ERR"))'
}

acc_arm() { # $1 = label, $2 = --user value ("" for none)
  local label="$1" u="$2" out score passed failed
  if [ -n "$u" ]; then
    out="$(timeout 240 docker run --rm --user "$u" "$IMG" m test --engine ydb "$ACC_SUITE" 2>&1)"
  else
    out="$(timeout 240 docker run --rm "$IMG" m test --engine ydb "$ACC_SUITE" 2>&1)"
  fi
  score="$(printf '%s' "$out" | acc_score)"
  passed="${score%% *}"; failed="${score##* }"
  if [ "$passed" = "$ACC_EXPECT" ] && [ "$failed" = 0 ]; then
    echo "  ✓ $label: m test green — $passed passed, $failed failed"
  else
    fail "$label: expected $ACC_EXPECT passed / 0 failed, got passed=$passed failed=$failed"$'\n'"$(printf '%s' "$out" | tail -20)"
  fi
}
acc_arm "root (image default)"                 ""
acc_arm "arbitrary uid 4242:0 (not pre-baked)" "4242:0"
acc_arm "baked devbox user"                    "devbox"

echo "== G8: PR-6 negative — a non-zero gid must refuse LOUDLY, not silently =="
OUT="$(timeout 120 docker run --rm --user 4242:4242 "$IMG" \
        m test --engine ydb "$ACC_SUITE" 2>&1)"
g8=$?
if [ $g8 -eq 78 ] && grep -q 'no /etc/passwd entry' <<<"$OUT"; then
  echo "  ✓ refused with exit 78 and an actionable message"
else
  fail "expected a loud refusal (exit 78 + 'no /etc/passwd entry'), got rc=$g8:"$'\n'"$(tail -10 <<<"$OUT")"
fi

if [ $rc -eq 0 ]; then echo; echo "verify-devbox: OK — all gates green ($IMG)"; fi
exit $rc
