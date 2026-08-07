#!/usr/bin/env bash
# m-run <routine.m> — Code Runner's executor: run an M routine file on the
# devbox's LOCAL engine, selected by M_ENGINE (ydb is the default; rsm per
# m-rsm proposal A22 — the same .m, run from the IDE, on either engine).
#
# Code Runner's executor for `.m` calls this (see the baked default settings).
set -u

f="${1:?usage: m-run <routine.m>}"
dir="$(cd "$(dirname "$f")" && pwd)"
name="$(basename "$f" .m)"

case "${M_ENGINE:-ydb}" in
  rsm)
    # RSM routines are DATABASE ROWS, not files (m-rsm §7.2), so "run this
    # file" means load → run → unstage through the m-rsm driver — the same
    # sanctioned client conformance drives — under a run bracket, staged
    # into a scratch UCI so the engine is left exactly as it was found.
    # The connection resolves from the M_RSM_* environment (devbox bakes
    # the local lane; a test harness may point M_RSM_CONTAINER elsewhere).
    # Output discipline mirrors the ydb arm: on success, the routine's own
    # output only — load/unstage chrome (the "staged into" narration, the
    # loaded list) and the hold's trailing release line are dropped; on a
    # NON-zero exit everything is printed, so a red is never silent.
    out="$(m runlock hold --engine rsm -o text -- bash -c '
      set -u
      f="$1"; name="$2"; tok="mrun$$"
      drv() { m-rsm "$@" --stage-dir "$tok" --run-lock "$M_RUN_LOCK_TOKEN"; }
      trap "drv exec unstage -o text >/dev/null 2>&1" EXIT
      out="$(drv exec load "$f" -o text 2>&1)" || { printf "%s\n" "$out"; exit 1; }
      drv exec eval "do ^$name" -o text
    ' m-run-rsm "$f" "$name" 2>&1)"; rc=$?
    if [ "$rc" -eq 0 ]; then
      printf '%s\n' "$out" | sed -e '${/^run-lock .* released$/d}' | sed -e '${/^$/d}'
    else
      printf '%s\n' "$out"
    fi
    exit "$rc"
    ;;
  *)
    # YottaDB: a standalone routine in the user'\''s /work project is not on
    # the image'\''s baked $ydb_routines, so add its directory to the path
    # (the engine then finds AND compiles it — YDB writes the .o beside the
    # .m, which is why the mount must be writable), then execute the
    # routine'\''s top label through the sanctioned `m engine exec` local
    # seam.
    #
    # `-o text` prints the routine'\''s own output followed by a trailing
    # "status N". On success we print just the routine'\''s output (drop the
    # "status 0" chrome and the blank separator line); on a NON-zero status
    # we print everything so a failure is never silent.
    export ydb_routines="$dir${ydb_routines:+ $ydb_routines}"

    out="$(m engine exec --engine "${M_ENGINE:-ydb}" --transport local -o text "do ^$name" 2>&1)"; rc=$?
    if [ "$rc" -eq 0 ]; then
      printf '%s\n' "$out" | sed -e '${/^status [0-9]*$/d}' | sed -e '${/^$/d}'
    else
      printf '%s\n' "$out"
    fi
    exit "$rc"
    ;;
esac
