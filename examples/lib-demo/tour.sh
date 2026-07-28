#!/usr/bin/env bash
# examples/lib-demo — install and uninstall a library on a live M engine.
#
#   bash /opt/examples/lib-demo/tour.sh
#
# A guided, runnable walkthrough of `m lib`, the library manager this image
# already used at build time to install MSL and FSL. It installs the tiny
# `greeter` library, calls it, verifies it, uninstalls it, and proves the
# engine is back exactly where it started. Safe to run any number of times.
#
# Needs a writable container (the default `docker run`) — the install compiles
# routines into /opt/lib/r. Engine access is the driver seam only (`m lib`,
# `m engine exec`); that is the sanctioned path everywhere in this org.
set -u

DEMO=/opt/examples/lib-demo
step=0

say()  { printf '\n\e[1m%s\e[0m\n' "$*"; }
tell() { printf '%s\n' "$*"; }
die()  { printf 'TOUR-FAILED at step %s: %s\n' "$step" "$*" >&2; exit 1; }

# Run a command that MUST succeed, showing it first.
must() {
  printf '\n  $ %s\n' "$*"
  "$@" 2>&1 | sed 's/^/  /' || die "command failed: $*"
}

# Ask the engine for the greeting and require that it CANNOT give one — the
# routine is not resident. We assert on what the ENGINE said, not on the exit
# code: YottaDB reports an unresolvable routine as a message and still exits 0,
# so `m engine exec` returns a green envelope carrying the error in `stderr`.
# (The engine's own words are the lesson anyway — that %YDB-E-ZLINKFILE is what
# a missing routine looks like in real life.)
expect_absent() {
  local out
  printf '\n  $ m engine exec --engine ydb -o text %s\n' "'write \$\$greet^GREETER(\"devbox\")'"
  out="$(m engine exec --engine ydb -o text 'write $$greet^GREETER("devbox")' 2>&1)"
  printf '%s\n' "$out" | grep -v '^status ' | sed 's/^/  /'
  case "$out" in
    *"Hello, DEVBOX!"*) die "GREETER answered — it is resident when it should not be" ;;
    *ZLINKFILE*|*FILENOTFND*) : ;;
    *) die "expected the engine to report it cannot link GREETER, got: $out" ;;
  esac
}

say "== lib-demo: how libraries get onto (and off) an M engine =="
tell "
An M 'library' is nothing exotic: routines resident on the engine's routine
path (\$ydb_routines). What makes it a managed library is the UNIT and the
TOOL:

  the unit   src/*.m + dist/<name>-manifest.json  (the manifest IS the unit —
             it declares exactly which routines belong to the library)
  the tool   m lib install / list / verify / uninstall — installs are recorded
             in an on-engine ledger (^mlib) with pre-images, so every install
             is inspectable and reversible. Copying .m files by hand gives you
             none of that.

MSL (m-stdlib) and FSL (f-stdlib) were installed into this image at build time
with the exact same verb you are about to run."

step=1
say "-- step 1: what is already installed --"
tell "call    : m lib list --engine ydb
means   : read the engine's ^mlib ledger — what does IT say is installed?"
must m lib list --engine ydb

step=2
say "-- step 2: before the install, the library is not there --"
tell "call    : \$\$greet^GREETER(\"devbox\") through the driver seam
returns : %YDB-E-ZLINKFILE … File GREETER.m not found
means   : the engine cannot LINK ^GREETER — nothing by that name is on the
          routine path yet. That error is the lesson (and it is exactly what
          you will see whenever a routine is missing)."
expect_absent

step=3
say "-- step 3: install it --"
tell "call    : m lib install --name greeter $DEMO/greeter/src
unit    : src/GREETER.m + dist/greeter-manifest.json (open both — together they
          are the whole library)
means   : pre-images captured, intent written to ^mlib, routines compiled onto
          the live routine path (/opt/lib/r), verified, committed. Idempotent —
          run it twice and the second run is a no-op."
must m lib install --engine ydb --name greeter "$DEMO/greeter/src"

step=4
say "-- step 4: call it --"
tell "call    : \$\$greet^GREETER(\"devbox\")
returns : Hello, DEVBOX!
means   : your code calls an installed library by name — no import ceremony.
          GREETER itself calls \$\$toUpperASCII^STDSTR, so this one line also
          proves an installed library can build on MSL underneath it."
out="$(m engine exec --engine ydb -o text 'write $$greet^GREETER("devbox")' 2>&1)" \
  || die "greet call failed: $out"
printf '\n  $ m engine exec --engine ydb -o text '\''write $$greet^GREETER("devbox")'\''\n'
printf '%s\n' "$out" | sed 's/^/  /'
case "$out" in *"Hello, DEVBOX!"*) : ;; *) die "unexpected greet output: $out" ;; esac

step=5
say "-- step 5: verify it --"
tell "call    : m lib verify greeter
means   : re-derive the library FROM THE ENGINE and compare against the ledger.
          Green means what is running is exactly what was installed — drift
          (someone edited a routine in place) exits 3 instead."
must m lib verify --engine ydb greeter

step=6
say "-- step 6: uninstall it --"
tell "call    : m lib uninstall greeter
means   : displaced pre-images restored, greenfield routines deleted (.m AND
          the compiled .o), ledger row removed. Back-out is a first-class verb,
          not an afterthought."
must m lib uninstall --engine ydb greeter

step=7
say "-- step 7: prove it is gone --"
tell "means   : the ledger no longer lists greeter, and the call from step 4
          fails again exactly like step 2 — the engine is back where it
          started. That round trip is the reversibility guarantee."
list="$(m lib list --engine ydb 2>&1)" || die "m lib list failed: $list"
printf '\n  $ m lib list --engine ydb\n'
printf '%s\n' "$list" | sed 's/^/  /'
case "$list" in *greeter*) die "greeter still in the ledger after uninstall" ;; esac
expect_absent

say "== WHAT NOW =="
tell "
- Read the library you just installed: $DEMO/greeter/ (src + manifest — the
  whole unit, two files).
- Read the real ones the image ships, same unit shape only bigger: /opt/msl
  (MSL — source, module docs, user guides) and /opt/fsl (FSL). They appear as
  folders in the IDE's file explorer.
- MSL and FSL were installed by this same verb at image build; 'm lib
  uninstall m-stdlib' would genuinely back MSL out — don't, in this image:
  FSL, the examples and the demo you just ran all sit on it.
- Your own library: give any project the same shape — src/*.m plus
  dist/<name>-manifest.json — and 'm lib install --engine ydb --name <name>
  <path>/src' puts it on any engine this toolchain manages. 'm lib' refuses
  on a Kernel-bearing (full VistA) engine, where KIDS governs installs —
  there the org's 'v pkg' is the tool.

TOUR-OK"
