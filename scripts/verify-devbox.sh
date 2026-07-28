#!/usr/bin/env bash
# Acceptance gates for the m-devbox image — all engine execution through the
# driver seam (`m engine exec` / `m test`), never a raw exec.
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
#       project is green. Its DEMO suite drives MSL (STD*), FileMan, and FSL
#       (FSL*) CRUD/query/DD end to end, so a green run is the falsifiable form
#       of "the environment is real".
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
#   ── MD-D9 (the libraries, readable + demonstrated) ─────────────────────────
#   G21 The MSL/FSL READING trees are baked (source + per-module reference +
#       guides + licence), are byte-identical to the routines actually resident
#       on the engine, are OFF $ydb_routines (so a documentation copy can never
#       shadow the installed library), and are surfaced by the baked multi-root
#       workspace beside the user's own /work.
#   G22 The examples/lib-demo tour runs end to end in the image: install a
#       library, call it, verify it, uninstall it, and prove the engine is back
#       where it started — twice, from a fresh container each time. Its negative
#       control asserts the demo library is NOT resident in a fresh image, so a
#       green tour cannot be a no-op.
#   G23 The IDE opens TRUSTED. VS Code disables any extension lacking
#       `capabilities.untrustedWorkspaces` in Restricted Mode — which is BOTH
#       baked extensions — so "installed" (G17/G19) was never "running".
#       Gates the wiring: the launch flag, its continued existence in the
#       pinned code-server, and the settings fallback. Activation itself is a
#       browser proof, recorded in the tracker — a green G23 is not that.
#   G24 MD-D10 — the companion extensions (Error Lens, Rainbow CSV) are baked,
#       `git` is present so code-server's built-in Source Control works, and —
#       the leg that earns the others — EXACTLY ONE baked extension claims the
#       M language, namely m-vscode. A second M extension would mean two
#       highlighters and two linters on one file; this refuses it structurally
#       rather than by review.
#   G25 PR-15 — the licence TEXTS travel with the artifact (/opt/licenses/),
#       the baked NOTICE matches the repo, and the shipped FileMan routines
#       retain their Medsphere/Apache attribution. 774 of 861 are Apache-2.0,
#       so §4(a)+(b) are obligations, not decoration.
#   G26 The image carries its own provenance — OCI labels naming the vendor,
#       source repo, licence and /opt/licenses path. The published namespace is
#       a personal account whose username is fixed, so the registry path cannot
#       carry identity; the artifact must, and image.source is where an AGPL
#       recipient goes to ask for corresponding source.
#   G27 PR-24 — the BAKED binaries are pin-built. Go embeds the compiled-in
#       module versions; a workspace build stamps siblings (devel), a pinned
#       build stamps semvers. Asserts: clean semvers only, equal to committed
#       go.mod pins, and one SDK version across both binaries. The artifact
#       testifies; the gate cross-examines.
#   ── (earlier P3 gates) ─────────────────────────────────────────────────────
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
OUT="$(run "$IMG" m engine exec --engine ydb --transport local 'write $$sha256^STDCRYPTO("abc")' 2>&1)"
if grep -q "$KAT_ABC" <<<"$OUT"; then
  echo "KAT ok: sha256('abc') = $KAT_ABC"
else
  fail "KAT mismatch or error:"$'\n'"$OUT"
fi

echo "== G3: availability probes =="
OUT="$(run "$IMG" m engine exec --engine ydb --transport local 'write $$available^STDCRYPTO(),":",$$available^STDCOMPRESS(),":",$$available^STDHTTP(),":",$$available^STDFS(),":",$$useCallout^STDCSPRNG()' 2>&1)"
# Expected "1::1:1:1": STDCOMPRESS's available() returns "" on SUCCESS
# (missing-library list; empty = both libz and libzstd loaded).
if grep -q '1::1:1:1' <<<"$OUT"; then
  echo "all five callout families available"
else
  fail "availability probe:"$'\n'"$OUT"
fi

echo "== G4 (informational): emptied ydb_xc_* =="
OUT="$(timeout 30 docker run --rm -e ydb_xc_stdcrypto= "$IMG" \
  m engine exec --engine ydb --transport local 'write $$sha256^STDCRYPTO("abc")' 2>&1)"
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
  m engine exec --engine ydb --transport local 'write $$sha256^STDCRYPTO("abc")' 2>&1)"
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
OUT="$(run "$IMG" m engine exec --engine ydb --transport local \
        'set DUZ=1,DUZ(0)="@",U="^" write "GET1=",$$GET1^DIQ(1,"1,",.01)' 2>&1)"
if grep -q 'GET1=FILE' <<<"$OUT"; then
  echo "  ✓ \$\$GET1^DIQ(1,\"1,\",.01) = FILE — FileMan 22.2 is installed and answering"
else
  fail "G10: FileMan API call did not return FILE:"$'\n'"$(tail -8 <<<"$OUT")"
fi

echo "== G11: FSL resident + working on FileMan — the full f-stdlib suite =="
suite_green "f-stdlib suite" /opt/fsl/tests 1

echo "== G12: examples/hello — the MD-D2 acceptance seed (STD* + FSL*, green) =="
suite_green "examples/hello" /opt/examples/hello/tests 20

echo "== G13: PR-11 — a bare \`m test\` selects the baked engine (no --engine) =="
# The truest attach simulation: cwd = the project, no flags, no exported vars
# beyond image ENV. Transport stays LOCAL (no --docker), correct for the devbox.
BARE_OUT="$(timeout 240 docker run --rm -w /opt/examples/hello "$IMG" m test 2>&1)"; BARE_RC=$?
BARE_SCORE="$(printf '%s' "$BARE_OUT" | mtest_score)"
BARE_PASS="${BARE_SCORE%% *}"; BARE_FAIL="${BARE_SCORE##* }"
if [ "$BARE_RC" -eq 0 ] && [ "$BARE_FAIL" = 0 ] && [ "$BARE_PASS" != NOTOK ] && [ "$BARE_PASS" != ERR ] && [ "$BARE_PASS" -ge 20 ] 2>/dev/null; then
  echo "  ✓ bare \`m test\` (no --engine) green — $BARE_PASS passed, 0 failed; baked M_ENGINE=ydb resolved the engine"
else
  fail "G13 positive: bare \`m test\` expected exit 0 / >=20 passed / 0 failed, got rc=$BARE_RC passed=$BARE_PASS failed=$BARE_FAIL"$'\n'"$(printf '%s' "$BARE_OUT" | tail -20)"
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
  if [ "$G14_RC" -eq 0 ] && [ "$G14_F" = 0 ] && [ "$G14_P" != NOTOK ] && [ "$G14_P" != ERR ] && [ "$G14_P" -ge 20 ] 2>/dev/null; then
    echo "  ✓ functional: named-volume /data (seeded from the baked DB) — bare \`m test\` green, $G14_P passed, 0 failed"
  else
    fail "G14 functional: bare \`m test\` on a named-volume /data expected exit 0 / >=20 passed / 0 failed, got rc=$G14_RC passed=$G14_P failed=$G14_F"$'\n'"$(printf '%s' "$G14_OUT" | tail -20)"
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
if [ "$G16_RC" -eq 0 ] && [ "$G16_F" = 0 ] && [ "$G16_P" != NOTOK ] && [ "$G16_P" != ERR ] && [ "$G16_P" -ge 20 ] 2>/dev/null; then
  echo "  ✓ read-only rootfs (writable = tmpfs run-lock-home + /tmp + named-vol /data only) — bare \`m test\` green, $G16_P passed, 0 failed"
else
  fail "G16: bare \`m test\` under --read-only expected exit 0 / >=20 passed / 0 failed, got rc=$G16_RC passed=$G16_P failed=$G16_F"$'\n'"$(printf '%s' "$G16_OUT" | tail -25)"
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

echo "== G18: the m-vscode status probe is healthy over local (PR-23) =="
# The extension's status chip runs exactly this (m-vscode argv.ts, ydb + no
# container -> --transport local). Retained as the EXPLICIT-FLAG control for
# G20: it proves the override path still wins after the transport default was
# removed. (Historic note: the "driver's REMOTE default" this once blamed was
# never the driver's — it was m-cli's own kong default. See G20.)
G18_OUT="$(timeout 60 docker run --rm "$IMG" m engine status --engine ydb --transport local -o json 2>&1)"; G18_RC=$?
if [ "$G18_RC" -eq 0 ] \
   && printf '%s' "$G18_OUT" | grep -qE '"running":[[:space:]]*true' \
   && printf '%s' "$G18_OUT" | grep -qE '"healthy":[[:space:]]*true'; then
  echo "  ✓ \`m engine status --engine ydb --transport local\`: running + healthy (the status chip's probe)"
else
  fail "G18: the extension's engine-status probe is not healthy (rc=$G18_RC)"$'\n'"$(printf '%s' "$G18_OUT" | tail -15)"
fi

echo "== G19: Code Runner baked + the .m executor runs a routine (PR-26) =="
# Code Runner is installed offline, its `.m` executor is wired to m-run in the
# baked defaults, and m-run actually executes an M routine on the local engine.
G19_OUT="$(timeout 90 docker run --rm "$IMG" bash -c '
set -e
code-server --list-extensions --extensions-dir /opt/code-server/extensions | grep -qi "formulahendry.code-runner" && echo CR_OK || { echo CR_MISSING; exit 1; }
grep -q "m-run" /opt/code-server/defaults/settings.json && echo CFG_OK || { echo CFG_MISSING; exit 1; }
mkdir -p /tmp/g19
cat > /tmp/g19/G19RUN.m <<XEOF
G19RUN ;
 write "G19-RUN-OK",!
 quit
XEOF
out="$(m-run /tmp/g19/G19RUN.m 2>&1)"
echo "$out" | grep -q G19-RUN-OK && echo RUN_OK || { echo "RUN_FAIL: $out"; exit 1; }
' 2>&1)"; G19_RC=$?
if [ "$G19_RC" -eq 0 ] \
   && printf '%s' "$G19_OUT" | grep -q CR_OK \
   && printf '%s' "$G19_OUT" | grep -q CFG_OK \
   && printf '%s' "$G19_OUT" | grep -q RUN_OK; then
  echo "  ✓ Code Runner baked + \`.m\` executor → m-run runs a routine (G19-RUN-OK)"
else
  fail "G19: Code Runner / m-run check failed (rc=$G19_RC)"$'\n'"$(printf '%s' "$G19_OUT" | tail -15)"
fi

echo "== G20: a FLAG-LESS \`m engine status\` resolves local (PR-25 residual) =="
# The residual PR-25 closed: a bare terminal `m vista` in this image, with NO
# --transport, must reach the engine sitting right beside it. m-cli no longer
# fabricates a transport the operator never expressed; it omits the flag and the
# DRIVER resolves it below the seam (m-ydb defaults local).
# Ruling: docs/background/transport-resolution-on-invoke-adr.md §5.
#
# Asserting "transport":"local" in the payload — the value the DRIVER reports —
# is what makes this a delegation gate and not merely a re-hardcoded default:
# only the driver can put that field there (ADR D5).
G20_OUT="$(timeout 60 docker run --rm "$IMG" m engine status --engine ydb -o json 2>&1)"; G20_RC=$?
if [ "$G20_RC" -eq 0 ] \
   && printf '%s' "$G20_OUT" | grep -qE '"running":[[:space:]]*true' \
   && printf '%s' "$G20_OUT" | grep -qE '"healthy":[[:space:]]*true' \
   && printf '%s' "$G20_OUT" | grep -qE '"transport":[[:space:]]*"local"'; then
  echo "  ✓ \`m engine status --engine ydb\` (no --transport): running + healthy, driver-resolved transport=local"
else
  fail "G20: the flag-less vista probe did not resolve local (rc=$G20_RC)"$'\n'"$(printf '%s' "$G20_OUT" | tail -15)"
fi

# Negative control for the ownership boundary (ADR D3): M_<ENGINE>_TRANSPORT
# governs the FORWARDING verbs and deliberately NOT the orchestrating ones —
# `m test` pins its own transport because its staging lifecycle branches on it.
# Without this control, a re-hardcoded local in m-cli would pass G20 unnoticed.
G20B_OUT="$(timeout 60 docker run --rm -e M_YDB_TRANSPORT=remote "$IMG" m engine status --engine ydb -o json 2>&1)"; G20B_RC=$?
if [ "$G20B_RC" -ne 0 ] && printf '%s' "$G20B_OUT" | grep -qi 'remote transport needs a host'; then
  echo "  ✓ negative control: M_YDB_TRANSPORT=remote IS honored by the forwarding verb (delegation is real, not a hardcoded local)"
else
  fail "G20b: M_YDB_TRANSPORT=remote was ignored by \`m engine status\` — m-cli is still fabricating a transport (rc=$G20B_RC)"$'\n'"$(printf '%s' "$G20B_OUT" | tail -15)"
fi

echo "== G21: MD-D9 — the MSL/FSL reading trees are baked, current, and OFF the routine path =="
# (a) the trees exist and carry what a learner needs: source, per-module
#     reference, the unit's manifest, the licence. Guides are MSL-only.
G21A_OUT="$(timeout 60 docker run --rm "$IMG" bash -c '
set -e
for d in /opt/msl /opt/fsl; do
  test -d "$d/src"          || { echo "MISSING $d/src"; exit 1; }
  test -d "$d/docs/modules" || { echo "MISSING $d/docs/modules"; exit 1; }
  test -f "$d/LICENSE"      || { echo "MISSING $d/LICENSE"; exit 1; }
  ls "$d"/dist/*-manifest.json >/dev/null 2>&1 || { echo "MISSING $d/dist manifest"; exit 1; }
  test "$(ls "$d"/src/*.m | wc -l)" -gt 0 || { echo "NO SOURCE in $d/src"; exit 1; }
done
test -d /opt/msl/docs/guides || { echo "MISSING /opt/msl/docs/guides"; exit 1; }
echo "TREES_OK msl_src=$(ls /opt/msl/src/*.m | wc -l) msl_docs=$(ls /opt/msl/docs/modules/*.md | wc -l) fsl_src=$(ls /opt/fsl/src/*.m | wc -l) fsl_docs=$(ls /opt/fsl/docs/modules/*.md | wc -l)"
' 2>&1)"; G21A_RC=$?
if [ "$G21A_RC" -eq 0 ] && printf '%s' "$G21A_OUT" | grep -q TREES_OK; then
  echo "  ✓ $(printf '%s' "$G21A_OUT" | grep TREES_OK)"
else
  fail "G21(a): the reading trees are incomplete (rc=$G21A_RC)"$'\n'"$(printf '%s' "$G21A_OUT" | tail -10)"
fi

# (b) THE ANTI-STALE GATE, three-way: for every routine a library's manifest
#     declares, the HOME REPO's source, the baked reading tree, and the routine
#     actually resident on the engine (/opt/lib/r, where `m lib install`
#     compiled it) must be the SAME BYTES. This is what makes "one maintained
#     copy" a fact instead of an intention — a reading tree that drifts from
#     the repo teaches code nobody runs, and one that drifts from the engine
#     teaches code THIS IMAGE does not run
#     [[data-shipping-pin-is-a-stale-grammar]].
#     Parsed host-side on purpose: the image has no python3, and the repo (the
#     single source) is a fact set INDEPENDENT of the image being tested
#     [[self-consistency-gates-cannot-see-omission]].
IMG_SHAS="$(timeout 90 docker run --rm "$IMG" \
  sh -c 'sha256sum /opt/msl/src/*.m /opt/fsl/src/*.m /opt/lib/r/*.m 2>/dev/null')"
declare -A SHA
while read -r h p; do [ -n "${p:-}" ] && SHA["$p"]="$h"; done <<<"$IMG_SHAS"
g21b_bad=(); g21b_checked=0
for pair in "m-stdlib:/opt/msl" "f-stdlib:/opt/fsl"; do
  repo="${pair%%:*}"; tree="${pair##*:}"
  man="$(ls "$FORGE/$repo/dist/"*-manifest.json 2>/dev/null | head -1)"
  if [ ! -f "$man" ]; then g21b_bad+=("$repo: no manifest at $FORGE/$repo/dist"); continue; fi
  while read -r mod; do
    [ -n "$mod" ] || continue
    repo_src="$FORGE/$repo/src/$mod.m"
    if [ ! -f "$repo_src" ]; then g21b_bad+=("$mod: declared by $repo's manifest, absent from its own src/"); continue; fi
    want="$(sha256sum "$repo_src" | cut -d' ' -f1)"
    got_read="${SHA[$tree/src/$mod.m]:-}"
    got_live="${SHA[/opt/lib/r/$mod.m]:-}"
    if [ -z "$got_read" ]; then g21b_bad+=("$mod: missing from the baked reading tree $tree/src"); continue; fi
    if [ -z "$got_live" ]; then g21b_bad+=("$mod: readable but NOT resident on the engine"); continue; fi
    g21b_checked=$((g21b_checked + 1))
    [ "$got_read" = "$want" ] || g21b_bad+=("$mod: reading tree ${got_read:0:12} != repo ${want:0:12} (stale image)")
    [ "$got_live" = "$want" ] || g21b_bad+=("$mod: resident ${got_live:0:12} != repo ${want:0:12} (stale install)")
  done < <(python3 -c 'import json,sys; print("\n".join(json.load(open(sys.argv[1]))["modules"]))' "$man")
done
if [ ${#g21b_bad[@]} -eq 0 ] && [ "$g21b_checked" -gt 0 ]; then
  echo "  ✓ $g21b_checked routines: home repo == baked reading tree == resident on the engine (one maintained copy, proven)"
else
  fail "G21(b): reading tree / resident / repo disagree (checked=$g21b_checked)"$'\n'"$(printf '  %s\n' "${g21b_bad[@]:0:8}")"
fi

# (c) the trees must stay OFF $ydb_routines: they are a second copy of routines
#     already installed into /opt/lib/r, and an on-path copy could link ahead of
#     the installed one — a library the ^mlib ledger cannot account for.
G21C_OUT="$(run "$IMG" sh -c 'echo "$ydb_routines"' 2>&1)"
if printf '%s' "$G21C_OUT" | grep -qE '(^| )/opt/(msl|fsl)/src( |$)'; then
  fail "G21(c): a reading tree is ON \$ydb_routines — it can shadow the installed library: $G21C_OUT"
else
  echo "  ✓ /opt/msl/src and /opt/fsl/src are not on \$ydb_routines (read here, run what \`m lib\` installed)"
fi

# (d) the baked multi-root workspace names the user's dir first, then the trees.
# Read the baked file first and check THAT read, then assert on it: a docker
# failure at the head of a pipe would otherwise be masked by python's status
# [[gate-invocations-never-ride-a-pipe]].
G21D_RAW="$(timeout 60 docker run --rm "$IMG" cat /opt/code-server/devbox.code-workspace 2>&1)" \
  || fail "G21(d): could not read the baked workspace file:"$'\n'"$G21D_RAW"
G21D_OUT="$(printf '%s' "$G21D_RAW" | python3 -c '
import json, re, sys
raw = sys.stdin.read()
cfg = json.loads(re.sub(r"(^|\s)//[^\n]*", r"\1", raw))
paths = [f["path"] for f in cfg["folders"]]
missing = [p for p in ("/work", "/opt/examples", "/opt/msl", "/opt/fsl") if p not in paths]
if missing or paths[0] != "/work":
    print("WORKSPACE_BAD paths=%s missing=%s" % (paths, missing)); sys.exit(1)
print("WORKSPACE_OK " + " ".join(paths))' 2>&1)"; G21D_RC=$?
if [ "$G21D_RC" -eq 0 ] && printf '%s' "$G21D_OUT" | grep -q WORKSPACE_OK; then
  echo "  ✓ $(printf '%s' "$G21D_OUT" | grep WORKSPACE_OK)"
else
  fail "G21(d): the baked workspace does not surface the libraries beside /work (rc=$G21D_RC)"$'\n'"$(printf '%s' "$G21D_OUT" | tail -10)"
fi

echo "== G22: MD-D9 — the lib-demo install/uninstall tour runs end to end =="
# Negative control FIRST: the demo library must NOT be resident in a fresh
# image. Without this, a pre-installed greeter would let the tour "pass" while
# demonstrating nothing — the install step would be a no-op and the uninstall
# would be undoing the image itself.
G22N_OUT="$(run "$IMG" m lib list --engine ydb 2>&1)"
if printf '%s' "$G22N_OUT" | grep -q greeter; then
  fail "G22 control: 'greeter' is already in the fresh image's ledger — the tour would demonstrate nothing"$'\n'"$G22N_OUT"
else
  echo "  ✓ control: the demo library is absent from the fresh image (the tour really installs it)"
fi
# The tour itself: install → call → verify → uninstall → prove-gone, with every
# step asserted inside the script (it exits nonzero at the first surprise).
G22_OUT="$(timeout 300 docker run --rm "$IMG" bash /opt/examples/lib-demo/tour.sh 2>&1)"; G22_RC=$?
if [ "$G22_RC" -eq 0 ] && printf '%s' "$G22_OUT" | grep -q TOUR-OK; then
  echo "  ✓ install → call → verify → uninstall → engine back to its starting state (TOUR-OK)"
else
  fail "G22: the lib-demo tour did not complete (rc=$G22_RC)"$'\n'"$(printf '%s' "$G22_OUT" | tail -25)"
fi
# And the round trip must be REPEATABLE: a second run proves the uninstall
# genuinely restored the pre-install state rather than leaving a residue the
# first run happened to tolerate.
G22R_OUT="$(timeout 300 docker run --rm "$IMG" bash /opt/examples/lib-demo/tour.sh 2>&1)"; G22R_RC=$?
if [ "$G22R_RC" -eq 0 ] && printf '%s' "$G22R_OUT" | grep -q TOUR-OK; then
  echo "  ✓ repeatable: a second full round trip in a fresh container is green too"
else
  fail "G22 repeat: the second tour run failed (rc=$G22R_RC)"$'\n'"$(printf '%s' "$G22R_OUT" | tail -25)"
fi

echo "== G23: the IDE opens TRUSTED — baked extensions are not disabled by Restricted Mode =="
# WHY THIS EXISTS. G17/G19 prove the extensions are installed (bytes on disk,
# `--list-extensions` names them). They do NOT prove either one ever RUNS, and
# for 2 days they did not: VS Code opens any unknown folder/workspace in
# **Restricted Mode**, and an extension without
# `capabilities.untrustedWorkspaces` is DISABLED there — which is BOTH of ours.
# Measured 2026-07-26 in a real browser session against the image: banner
# "Some features are disabled because this workspace is not trusted", on the
# workspace path AND the plain-folder path. Classic bytes-present ≠ works
# [[verify-implementation-not-manifest]].
#
# HONEST SCOPE: this gate proves the WIRING (the flag is passed, this
# code-server build still accepts it, the settings carry the fallback) — it
# cannot drive a browser, so it cannot by itself prove activation. The
# end-to-end activation proof is a browser session, recorded dated in the
# tracker. Do not read a green G23 as "the extensions ran".
G23_FLAG_OK=0
grep -q -- '--disable-workspace-trust' "$HERE/code-server-launch.sh" && G23_FLAG_OK=1
if [ "$G23_FLAG_OK" -eq 1 ]; then
  echo "  ✓ the launch script passes --disable-workspace-trust"
else
  fail "G23: code-server-launch.sh does not pass --disable-workspace-trust — every new user lands in Restricted Mode with both extensions disabled"
fi
# The flag must still EXIST in the pinned code-server. A version bump that
# renames or drops it would otherwise leave the launch line silently inert
# (code-server ignores unknown flags for some, errors for others — either way
# the trust regression returns without a red).
G23_HELP="$(timeout 60 docker run --rm "$IMG" code-server --help 2>&1)"
if printf '%s' "$G23_HELP" | grep -q -- '--disable-workspace-trust'; then
  echo "  ✓ the pinned code-server still supports --disable-workspace-trust"
else
  fail "G23: this code-server build does not list --disable-workspace-trust — the launch flag is inert and Restricted Mode is back"
fi
# Belt-and-braces in the baked user settings, so a user launching code-server
# by hand (without the image's launch script) still gets a trusting IDE, and so
# the IDE stops querying Open VSX at runtime (measured: the browser session hit
# open-vsx.org for extension metadata, 404 — a network call in an offline box).
G23_SET="$(timeout 60 docker run --rm "$IMG" cat /opt/code-server/defaults/settings.json 2>&1)"
G23_SET_OUT="$(printf '%s' "$G23_SET" | python3 -c '
import json, sys
cfg = json.load(sys.stdin)
bad = []
if cfg.get("security.workspace.trust.enabled") is not False:
    bad.append("security.workspace.trust.enabled is not false")
for k in ("extensions.autoCheckUpdates", "extensions.autoUpdate"):
    if cfg.get(k) is not False:
        bad.append(k + " is not false (runtime Open VSX query in an offline image)")
if not cfg.get("code-runner.executorMapByFileExtension", {}).get(".m"):
    bad.append("code-runner .m executor missing")
print("SETTINGS_BAD " + "; ".join(bad)) if bad else print("SETTINGS_OK")
sys.exit(1 if bad else 0)' 2>&1)"; G23_SET_RC=$?
if [ "$G23_SET_RC" -eq 0 ] && printf '%s' "$G23_SET_OUT" | grep -q SETTINGS_OK; then
  echo "  ✓ baked settings: trust disabled, no runtime marketplace queries, .m executor wired"
else
  fail "G23: baked default settings (rc=$G23_SET_RC)"$'\n'"$(printf '%s' "$G23_SET_OUT" | tail -5)"
fi

echo "== G24: MD-D10 — companion extensions baked, git present, M ownership UNCONTESTED =="
# (a) all four extensions are installed, and `git` exists so code-server's
#     built-in Git extension (shipped, but inert without the binary) works.
G24_OUT="$(timeout 90 docker run --rm "$IMG" bash -c '
set -e
for e in vista-forge.m-vscode formulahendry.code-runner usernamehw.errorlens mechatroner.rainbow-csv; do
  code-server --list-extensions --extensions-dir /opt/code-server/extensions | grep -qi "$e" \
    || { echo "MISSING_EXT $e"; exit 1; }
done
command -v git >/dev/null || { echo "MISSING_GIT"; exit 1; }
echo "EXTS_OK $(git --version)"
' 2>&1)"; G24_RC=$?
if [ "$G24_RC" -eq 0 ] && printf '%s' "$G24_OUT" | grep -q EXTS_OK; then
  echo "  ✓ four extensions baked + $(printf '%s' "$G24_OUT" | grep EXTS_OK | cut -d' ' -f2-) (built-in Source Control is now functional)"
else
  fail "G24(a): companion extensions / git (rc=$G24_RC)"$'\n'"$(printf '%s' "$G24_OUT" | tail -8)"
fi

# (b) THE CONFLICT GATE — the reason a companion extension is allowed here at
#     all. m-vscode must remain the SOLE owner of the M language: exactly one
#     baked extension may declare a `mumps` language or claim .m/.mac/.int.
#     Adding a second M extension (there are several on the marketplaces) would
#     put two highlighters and two linters on the same file and is the specific
#     regression this gate exists to refuse.
G24B_OUT="$(timeout 90 docker run --rm "$IMG" bash -c '
claims=""
for p in /opt/code-server/extensions/*/package.json; do
  id=$(basename "$(dirname "$p")")
  flat=$(tr -d "\n " < "$p")
  case "$flat" in
    *"\".m\""*|*"\".mac\""*|*"\".int\""*|*"\"id\":\"mumps\""*) claims="$claims $id" ;;
  esac
done
echo "CLAIMANTS:$claims"
' 2>&1)"
G24B_LIST="$(printf '%s' "$G24B_OUT" | sed -n 's/^CLAIMANTS://p' | tr -s ' ')"
G24B_N="$(printf '%s' "$G24B_LIST" | wc -w)"
if [ "$G24B_N" -eq 1 ] && printf '%s' "$G24B_LIST" | grep -qi 'm-vscode'; then
  echo "  ✓ exactly one extension claims the M language, and it is m-vscode ($(printf '%s' "$G24B_LIST" | tr -d ' '))"
else
  fail "G24(b): M-language ownership is contested — expected ONLY m-vscode, found ($G24B_N):$G24B_LIST"
fi

echo "== G25: PR-15 — the licences TRAVEL WITH the artifact =="
# Apache-2.0 §4(a) requires a redistribution to give recipients a copy of the
# License, and 774 of the 861 FileMan routines in this image are Apache-2.0
# (MSC FileMan 1051 lineage, measured 2026-07-26). Before that measurement the
# per-routine notices shipped but the licence text they point at did not — a
# duty met on paper and not in the artifact. This gate keeps it met in the
# artifact, which is the only place it counts.
G25_OUT="$(timeout 60 docker run --rm "$IMG" sh -c '
set -e
for f in /opt/licenses/Apache-2.0.txt /opt/licenses/AGPL-3.0.txt /opt/licenses/NOTICE; do
  test -s "$f" || { echo "MISSING $f"; exit 1; }
done
grep -q "Apache License" /opt/licenses/Apache-2.0.txt || { echo "NOT_APACHE_TEXT"; exit 1; }
grep -q "GNU AFFERO GENERAL PUBLIC LICENSE" /opt/licenses/AGPL-3.0.txt || { echo "NOT_AGPL_TEXT"; exit 1; }
grep -q "Apache License, Version 2.0" /opt/licenses/NOTICE || { echo "NOTICE_MISSING_FILEMAN_TERMS"; exit 1; }
echo "LICENSES_OK"
' 2>&1)"; G25_RC=$?
if [ "$G25_RC" -eq 0 ] && printf '%s' "$G25_OUT" | grep -q LICENSES_OK; then
  echo "  ✓ /opt/licenses/ carries the Apache-2.0 + AGPL-3.0 texts and the third-party NOTICE"
else
  fail "G25(a): licence texts missing from the image (rc=$G25_RC)"$'\n'"$(printf '%s' "$G25_OUT" | tail -6)"
fi
# The baked NOTICE must be the repo's NOTICE — a stale copy would misdescribe
# what is actually inside the artifact it ships in.
G25_SRC_SHA="$(sha256sum "$HERE/../NOTICE" | cut -d' ' -f1)"
G25_BAKED_SHA="$(run "$IMG" sha256sum /opt/licenses/NOTICE 2>/dev/null | cut -d' ' -f1)"
if [ -n "$G25_BAKED_SHA" ] && [ "$G25_BAKED_SHA" = "$G25_SRC_SHA" ]; then
  echo "  ✓ baked NOTICE is byte-identical to the repo's (${G25_SRC_SHA:0:12}…)"
else
  fail "G25(b): baked NOTICE ($G25_BAKED_SHA) != repo NOTICE ($G25_SRC_SHA) — restage and rebuild"
fi
# And the FileMan attribution notices must still be present in the SHIPPED
# routines: Apache-2.0 §4(b) is about what the recipient receives, not about
# what our source tree looked like at build time.
G25C_OUT="$(run "$IMG" sh -c 'grep -l "MSC FileMan 1051" /opt/lib/r/*.m 2>/dev/null | wc -l')"
if [ "${G25C_OUT:-0}" -ge 700 ] 2>/dev/null; then
  echo "  ✓ $G25C_OUT shipped routines retain their Medsphere/Apache attribution notice"
else
  fail "G25(c): attribution notices are missing from the shipped routines (found ${G25C_OUT:-0}, expected >=700) — Apache-2.0 §4(b)"
fi

echo "== G26: the image carries its own provenance (OCI labels) =="
# The publication namespace is a personal Docker Hub account whose username is
# fixed, so the registry PATH cannot say who published this or where the source
# is. The ARTIFACT has to. These labels are the only identity that survives a
# re-tag, a mirror, or a `docker save` handed to someone on a USB stick — and
# `image.source` is where an AGPL recipient goes to ask for corresponding source.
G26_OUT="$(docker image inspect --format '{{json .Config.Labels}}' "$IMG" 2>/dev/null \
  | python3 -c '
import json, sys
want = {
  "org.opencontainers.image.title": "m-devbox",
  "org.opencontainers.image.vendor": "vista-forge",
  "org.opencontainers.image.licenses": "AGPL-3.0-or-later",
  "org.vista-forge.licenses.path": "/opt/licenses",
}
try:
    got = json.load(sys.stdin) or {}
except Exception:
    print("LABELS_UNREADABLE"); raise SystemExit(1)
bad = [f"{k}={got.get(k)!r} (want {v!r})" for k, v in want.items() if got.get(k) != v]
if not got.get("org.opencontainers.image.source", "").startswith("https://"):
    bad.append("image.source is not an https URL — an AGPL recipient cannot find the source")
print("LABELS_BAD " + "; ".join(bad)) if bad else print("LABELS_OK")
sys.exit(1 if bad else 0)' 2>&1)"; G26_RC=$?
if [ "$G26_RC" -eq 0 ] && printf '%s' "$G26_OUT" | grep -q LABELS_OK; then
  echo "  ✓ vendor, title, licence, source URL and the licences path are all declared on the image"
else
  fail "G26: OCI provenance labels (rc=$G26_RC)"$'\n'"$(printf '%s' "$G26_OUT" | tail -5)"
fi

echo "== G27: PR-24 — the BAKED binaries are pin-built (no go.work leak) =="
# The image's `m` and `m-ydb` carry, embedded by the Go toolchain itself, the
# module versions they were compiled against. A workspace build stamps sibling
# deps `(devel)`; a pinned GOWORK=off build stamps exact semvers. So the
# artifact testifies about its own provenance, and this gate cross-examines it:
#   (a) every vista-forge dep in both binaries is a clean semver — never
#       `(devel)`, never a `=>` replacement;
#   (b) each version equals the consuming repo's COMMITTED go.mod pin;
#   (c) both binaries agree on the m-driver-sdk version (the one seam the
#       driver-coordination model serializes).
# This is what closes PR-24 as a gate rather than a habit: a reverted
# stage-context.sh, a hand-built context, or a stale image all red HERE,
# against the image, independent of how it claims it was built.
G27_TMP="$(mktemp -d)"
G27_CID="$(docker create "$IMG" 2>/dev/null)"
if [ -z "$G27_CID" ]; then
  fail "G27: could not create a container from $IMG to extract the binaries"
else
  docker cp -q "$G27_CID:/usr/local/bin/m" "$G27_TMP/m" 2>/dev/null \
    && docker cp -q "$G27_CID:/usr/local/bin/m-ydb" "$G27_TMP/m-ydb" 2>/dev/null
  docker rm -f "$G27_CID" >/dev/null 2>&1
  g27_bad=()
  g27_sdk_m=""; g27_sdk_ydb=""
  g27_check() { # $1 = extracted binary, $2 = repo dir, $3 = label
    local bin="$1" repo="$2" label="$3" dep ver pin
    if [ ! -f "$bin" ]; then g27_bad+=("$label: binary missing from the image"); return; fi
    if go version -m "$bin" | grep -q '=>'; then
      g27_bad+=("$label: carries a module replacement (=>)")
    fi
    while read -r _ dep ver _; do
      case "$dep" in github.com/vista-forge/*) ;; *) continue ;; esac
      pin="$(awk -v d="$dep" '$1==d {print $2}' "$repo/go.mod")"
      case "$ver" in
        "(devel)"|"") g27_bad+=("$label: $dep is $ver — a workspace build leaked into the image") ;;
        "$pin") ;;
        *) g27_bad+=("$label: $dep $ver != committed pin $pin") ;;
      esac
      if [ "$dep" = "github.com/vista-forge/m-driver-sdk" ]; then
        case "$label" in m) g27_sdk_m="$ver" ;; m-ydb) g27_sdk_ydb="$ver" ;; esac
      fi
    done < <(go version -m "$bin" | awk '$1=="dep"')
  }
  g27_check "$G27_TMP/m"     "$FORGE/m-cli" "m"
  g27_check "$G27_TMP/m-ydb" "$FORGE/m-ydb" "m-ydb"
  if [ -n "$g27_sdk_m" ] && [ -n "$g27_sdk_ydb" ] && [ "$g27_sdk_m" != "$g27_sdk_ydb" ]; then
    g27_bad+=("SDK skew inside one image: m has $g27_sdk_m, m-ydb has $g27_sdk_ydb")
  fi
  rm -rf "$G27_TMP"
  if [ ${#g27_bad[@]} -eq 0 ]; then
    echo "  ✓ baked m + m-ydb: every vista-forge dep is a pinned semver matching committed go.mod (SDK $g27_sdk_m in both)"
  else
    fail "G27: baked-binary pin audit:"$'\n'"$(printf '    %s\n' "${g27_bad[@]}")"
  fi
fi

if [ $rc -eq 0 ]; then echo; echo "verify-devbox: OK — all gates green ($IMG)"; fi
exit $rc
