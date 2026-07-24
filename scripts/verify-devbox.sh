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
#   ── P2 (the bake) ──────────────────────────────────────────────────────────
#   G9  DURABLE library install — `m lib list` records m-stdlib AND f-stdlib,
#       and `m lib verify` re-derives each from the ENGINE and matches the
#       ledger. This is what §5.1(c) bought over a plain COPY: the install is
#       inspectable and reversible on the running image.
#   G10 FileMan RESIDENT — a FileMan API call through the seam ($$GET1^DIQ)
#       returns the file name, proving the §5.2(a) build-time install landed.
#   G11 FSL resident + working ON FileMan — the full f-stdlib suite runs green
#       in the image (the FSL suites exercise FileMan, so this is also a
#       second, behavioural FileMan proof).
#   G12 examples/hello — the MD-D2 acceptance seed: `m test` on the starter
#       project is green, and it calls BOTH an STD* and an FSL* routine, so a
#       green run is the falsifiable form of "the environment is real".
#   ── P3 (attach) ────────────────────────────────────────────────────────────
#   G13 PR-11 — the engine SELECTOR is baked and load-bearing. Every gate above
#       passes `--engine ydb`, which sidesteps engine selection; a real
#       devcontainer user runs a BARE `m test`. Positive: with M_ENGINE=ydb
#       baked, a bare `m test` (no --engine, cwd = the project) is green —
#       engine-selection-on-attach ADR §5. Negative control: with M_ENGINE
#       UNSET the tool REFUSES (exit 4 ENGINE_UNRESOLVED), never guesses — so
#       the selector cannot silently vanish and leave the 60 s-to-green claim
#       resting on an ambient default [[degrade-loud-or-refuse]].
#   G14 §3.1 — the devcontainer mount rules, ASSERTED not just documented.
#       Static: parse .devcontainer/devcontainer.json and require $ydb_dir
#       (/data) to be a NAMED VOLUME, nothing to bind-mount /data (YDB region
#       locking corrupts over virtiofs/9p), and PR-6's remoteUser=devbox +
#       updateRemoteUserUID. Functional: run the image under that exact mount
#       topology — a FRESH named volume at /data, seeded from the baked DB — and
#       prove a bare `m test` is green, so the config's promise is executed, not
#       asserted on paper.
#   G15 MD-D5 — the baked m-vscode .vsix matches its source (no drift). The
#       image bakes the extension .vsix for install-from-file at attach; this
#       drift-gates the baked bytes against the SINGLE SOURCE (the m-vscode
#       repo's committed .vsix), so an image built off a stale staged copy, or
#       an m-vscode release the image has not re-baked, goes RED
#       [[data-shipping-pin-is-a-stale-grammar]].
#   G16 PR-12 — baked routines link + run under a READ-ONLY rootfs, no host
#       writes. The strictest form of the requirement: `--read-only`, so the
#       ONLY writable surface is ephemeral tmpfs (the passwd-derived run-lock
#       home + /tmp) and the $ydb_dir NAMED VOLUME (the DB) — no host bind mount,
#       no writable rootfs. Library + example routines are object-precompiled
#       (step 5), so nothing ZLINKs to the now-read-only source dirs. Run as the
#       devbox uid (1000:0), the real devcontainer identity.
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

# ── P2 gates ─────────────────────────────────────────────────────────────────

# Parse an `m test` envelope on stdin → "PASSED FAILED", or "NOTOK …"/"ERR ERR"
# when the envelope is red or unparseable (both fail every comparison below).
mtest_score() {
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

# Run `m test` on a suite/dir in the image and assert failed=0 with passed>=min.
suite_green() { # $1 = label, $2 = path, $3 = min passed
  local label="$1" path="$2" minp="$3" out score passed failed
  out="$(timeout 240 docker run --rm "$IMG" m test --engine ydb "$path" 2>&1)"
  score="$(printf '%s' "$out" | mtest_score)"
  passed="${score%% *}"; failed="${score##* }"
  if [ "$failed" = 0 ] && [ "$passed" != NOTOK ] && [ "$passed" != ERR ] && [ "$passed" -ge "$minp" ] 2>/dev/null; then
    echo "  ✓ $label: m test green — $passed passed, 0 failed"
  else
    fail "$label: expected >=$minp passed / 0 failed, got passed=$passed failed=$failed"$'\n'"$(printf '%s' "$out" | tail -20)"
  fi
}

echo "== G9: durable library install — m lib list + verify (ledger matches engine) =="
LIST="$(run "$IMG" m lib list --engine ydb 2>&1)"
for lib in m-stdlib f-stdlib; do
  grep -q "$lib" <<<"$LIST" || fail "G9: '$lib' absent from \`m lib list\`:"$'\n'"$LIST"
done
for lib in m-stdlib f-stdlib; do
  OUT="$(run "$IMG" m lib verify --engine ydb "$lib" 2>&1)"
  if grep -qE '"ok": *true' <<<"$OUT"; then
    echo "  ✓ $lib: verify ok — engine matches the ledger"
  else
    fail "G9: \`m lib verify $lib\` did not report ok:true (ledger drift?):"$'\n'"$(tail -8 <<<"$OUT")"
  fi
done

echo "== G10: FileMan resident — a FileMan API call through the seam =="
OUT="$(run "$IMG" m vista exec --engine ydb --transport local \
        'set DUZ=1,DUZ(0)="@",U="^" write "GET1=",$$GET1^DIQ(1,"1,",.01)' 2>&1)"
if grep -q 'GET1=FILE' <<<"$OUT"; then
  echo "  ✓ \$\$GET1^DIQ(1,\"1,\",.01) = FILE — FileMan 22.2 is installed and answering"
else
  fail "G10: FileMan API call did not return FILE:"$'\n'"$(tail -8 <<<"$OUT")"
fi

echo "== G11: FSL resident + working on FileMan — the full f-stdlib suite =="
suite_green "f-stdlib suite" /opt/fsl/tests 1

echo "== G12: examples/hello — the MD-D2 acceptance seed (STD* + FSL*, green) =="
suite_green "examples/hello" /opt/examples/hello/tests 5

echo "== G13: PR-11 — a bare \`m test\` selects the baked engine (no --engine) =="
# The truest attach simulation: cwd = the project, no flags, no exported vars
# beyond image ENV. Transport stays LOCAL (no --docker), correct for the devbox.
BARE_OUT="$(timeout 240 docker run --rm -w /opt/examples/hello "$IMG" m test 2>&1)"; BARE_RC=$?
BARE_SCORE="$(printf '%s' "$BARE_OUT" | mtest_score)"
BARE_PASS="${BARE_SCORE%% *}"; BARE_FAIL="${BARE_SCORE##* }"
if [ "$BARE_RC" -eq 0 ] && [ "$BARE_FAIL" = 0 ] && [ "$BARE_PASS" != NOTOK ] && [ "$BARE_PASS" != ERR ] && [ "$BARE_PASS" -ge 5 ] 2>/dev/null; then
  echo "  ✓ bare \`m test\` (no --engine) green — $BARE_PASS passed, 0 failed; baked M_ENGINE=ydb resolved the engine"
else
  fail "G13 positive: bare \`m test\` expected exit 0 / >=5 passed / 0 failed, got rc=$BARE_RC passed=$BARE_PASS failed=$BARE_FAIL"$'\n'"$(printf '%s' "$BARE_OUT" | tail -20)"
fi
# Negative control: unset the baked selector → the tool must REFUSE, not default
# to ydb. `-e M_ENGINE=` overrides the image ENV with empty (== unset to Resolve).
NEG_OUT="$(timeout 120 docker run --rm -e M_ENGINE= -w /opt/examples/hello "$IMG" m test 2>&1)"; NEG_RC=$?
if [ "$NEG_RC" -eq 4 ] && grep -q ENGINE_UNRESOLVED <<<"$NEG_OUT"; then
  echo "  ✓ negative control: M_ENGINE unset → exit 4 ENGINE_UNRESOLVED (selector is load-bearing, not an ambient default)"
else
  fail "G13 negative: M_ENGINE unset must exit 4 with ENGINE_UNRESOLVED, got rc=$NEG_RC"$'\n'"$(printf '%s' "$NEG_OUT" | tail -20)"
fi

echo "== G14: §3.1 — devcontainer mounts: \$ydb_dir (/data) on a NAMED VOLUME =="
DC="$HERE/../.devcontainer/devcontainer.json"
if [ ! -f "$DC" ]; then
  fail "G14: no .devcontainer/devcontainer.json at $DC"
else
  # (a) STATIC: parse the JSONC and enforce the two mount rules + PR-6 user.
  DC_OUT="$(python3 - "$DC" 2>&1 <<'PY'
import json, re, sys
raw = open(sys.argv[1]).read()
noc = re.sub(r'(^|\s)//[^\n]*', r'\1', raw)          # strip // line comments
cfg = json.loads(noc)
def kv(m): return dict(p.split("=", 1) for p in m.split(",") if "=" in p)
mounts = cfg.get("mounts", [])
allm = list(mounts) + ([cfg["workspaceMount"]] if "workspaceMount" in cfg else [])
errs = []
if not any(kv(m).get("target") == "/data" and kv(m).get("type") == "volume" for m in mounts):
    errs.append("/data is not mounted as a named volume (type=volume)")
for m in allm:
    if kv(m).get("target") == "/data" and kv(m).get("type") == "bind":
        errs.append("/data is BIND-mounted — YDB region locking corrupts over bind mounts")
if cfg.get("remoteUser") != "devbox":
    errs.append("remoteUser is not devbox (PR-6)")
if cfg.get("updateRemoteUserUID") is not True:
    errs.append("updateRemoteUserUID is not true (PR-6)")
if errs:
    print("; ".join(errs)); sys.exit(1)
print("/data=named volume, no bind on /data, remoteUser=devbox + updateRemoteUserUID")
PY
)"
  if [ $? -eq 0 ]; then
    echo "  ✓ static: $DC_OUT"
  else
    fail "G14 static: $DC_OUT"
  fi
  # (b) FUNCTIONAL: the image under the devcontainer topology — a fresh named
  # volume at /data (Docker seeds it from the baked DB) — bare `m test` green.
  VOL=m-devbox-g14-verify
  docker volume rm "$VOL" >/dev/null 2>&1 || true
  G14_OUT="$(timeout 240 docker run --rm -v "$VOL":/data -w /opt/examples/hello "$IMG" m test 2>&1)"; G14_RC=$?
  docker volume rm "$VOL" >/dev/null 2>&1 || true
  G14_SCORE="$(printf '%s' "$G14_OUT" | mtest_score)"; G14_P="${G14_SCORE%% *}"; G14_F="${G14_SCORE##* }"
  if [ "$G14_RC" -eq 0 ] && [ "$G14_F" = 0 ] && [ "$G14_P" != NOTOK ] && [ "$G14_P" != ERR ] && [ "$G14_P" -ge 5 ] 2>/dev/null; then
    echo "  ✓ functional: named-volume /data (seeded from the baked DB) — bare \`m test\` green, $G14_P passed, 0 failed"
  else
    fail "G14 functional: bare \`m test\` on a named-volume /data expected exit 0 / >=5 passed / 0 failed, got rc=$G14_RC passed=$G14_P failed=$G14_F"$'\n'"$(printf '%s' "$G14_OUT" | tail -20)"
  fi
fi

echo "== G15: MD-D5 — the baked m-vscode .vsix matches its source (no drift) =="
vsix_src=( "$FORGE/m-vscode/"*.vsix )
if [ "${#vsix_src[@]}" -ne 1 ] || [ ! -f "${vsix_src[0]}" ]; then
  fail "G15: expected exactly one m-vscode/*.vsix under $FORGE/m-vscode, found ${#vsix_src[@]}"
else
  SRC_SHA="$(sha256sum "${vsix_src[0]}" | cut -d' ' -f1)"
  BAKED_SHA="$(run "$IMG" sha256sum /opt/m-vscode/m-vscode.vsix 2>/dev/null | cut -d' ' -f1)"
  if [ -n "$BAKED_SHA" ] && [ "$BAKED_SHA" = "$SRC_SHA" ]; then
    echo "  ✓ baked .vsix sha256 == m-vscode source ($(basename "${vsix_src[0]}"), ${SRC_SHA:0:12}…) — no drift"
  else
    fail "G15: baked .vsix sha ($BAKED_SHA) != m-vscode source sha ($SRC_SHA) — rebake needed (stale staged .vsix, or m-vscode released and the image was not re-baked)"
  fi
fi

echo "== G16: PR-12 — baked routines link + run under a READ-ONLY rootfs (no host writes) =="
VOL=m-devbox-g16-verify
docker volume rm "$VOL" >/dev/null 2>&1 || true
# Only-writable = tmpfs (run-lock home /home/devbox + /tmp) + named vol /data.
# --read-only makes the whole rootfs (incl. the baked source dirs) read-only.
G16_OUT="$(timeout 240 docker run --rm --read-only --user 1000:0 \
  -v "$VOL":/data --tmpfs /home/devbox --tmpfs /tmp \
  -w /opt/examples/hello "$IMG" m test 2>&1)"; G16_RC=$?
docker volume rm "$VOL" >/dev/null 2>&1 || true
G16_SCORE="$(printf '%s' "$G16_OUT" | mtest_score)"; G16_P="${G16_SCORE%% *}"; G16_F="${G16_SCORE##* }"
if [ "$G16_RC" -eq 0 ] && [ "$G16_F" = 0 ] && [ "$G16_P" != NOTOK ] && [ "$G16_P" != ERR ] && [ "$G16_P" -ge 5 ] 2>/dev/null; then
  echo "  ✓ read-only rootfs (writable = tmpfs run-lock-home + /tmp + named-vol /data only) — bare \`m test\` green, $G16_P passed, 0 failed"
else
  fail "G16: bare \`m test\` under --read-only expected exit 0 / >=5 passed / 0 failed, got rc=$G16_RC passed=$G16_P failed=$G16_F"$'\n'"$(printf '%s' "$G16_OUT" | tail -25)"
fi

echo "== G17: PR-23 — code-server boots OFFLINE and the m-vscode extension is baked =="
# The whole point of MD-D8: the VS Code server is IN the image, so the first
# open works with no network, and the extension was installed from the local
# .vsix at build time (no Open VSX). Prove both under --network none.
G17_OUT="$(timeout 150 docker run --rm --network none "$IMG" bash -c '
  set -e
  # (a) the extension is baked into the read-only extensions dir (offline install)
  if code-server --list-extensions --extensions-dir /opt/code-server/extensions | grep -qi "vista-forge.m-vscode"; then
    echo "EXT_OK"
  else
    echo "EXT_MISSING"; exit 1
  fi
  # (b) code-server binds its HTTP server with NO network (loopback only)
  CODE_SERVER_STATE=/tmp/cs /usr/local/bin/devbox-code-server >/tmp/cs.log 2>&1 &
  for i in $(seq 1 60); do grep -qiE "listening on|HTTP server listening" /tmp/cs.log && break; sleep 1; done
  if grep -qiE "listening on|HTTP server listening" /tmp/cs.log; then echo "BOOT_OK"; else echo "BOOT_FAIL"; tail -25 /tmp/cs.log; exit 1; fi
' 2>&1)"; G17_RC=$?
if [ "$G17_RC" -eq 0 ] && printf '%s' "$G17_OUT" | grep -q EXT_OK && printf '%s' "$G17_OUT" | grep -q BOOT_OK; then
  echo "  ✓ code-server binds under --network none and the m-vscode extension is baked (offline VS Code, no download)"
else
  fail "G17: code-server offline boot / baked-extension check failed (rc=$G17_RC)"$'\n'"$(printf '%s' "$G17_OUT" | tail -25)"
fi

if [ $rc -eq 0 ]; then echo; echo "verify-devbox: OK — all gates green ($IMG)"; fi
exit $rc
