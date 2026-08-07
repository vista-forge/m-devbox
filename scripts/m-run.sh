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
    # file" means load → run → remove through the m-rsm driver — the same
    # sanctioned client conformance drives — under a run bracket. The file
    # loads into the MANAGER UCI beside the baked MSL (a scratch UCI would
    # isolate the run AWAY from the library: it sees only its own routines
    # plus %*, and staging 40 MSL modules per Run Code is no IDE loop),
    # guarded so a user's routine name can never overwrite a resident one,
    # and removed again on exit. The connection resolves from the M_RSM_*
    # environment (devbox bakes the local lane; a test harness may point
    # M_RSM_CONTAINER elsewhere).
    #
    # Output discipline mirrors the ydb arm: on success, the routine's own
    # output only; on a NON-zero exit everything is printed, so a red is
    # never silent.
    export MRUN_FILE="$f" MRUN_NAME="$name"
    out="$(m runlock hold --engine rsm -o text -- bash -c '
      set -u
      drv() { m-rsm "$@" --run-lock "$M_RUN_LOCK_TOKEN"; }
      probe="$(drv exec eval "write \$select(\$text(+1^$MRUN_NAME)=\"\":0,1:1)" -o text 2>/dev/null | head -1)"
      if [ "${probe:-0}" = "1" ]; then
        echo "m-run: a resident routine named ^$MRUN_NAME already exists on RSM — rename your file (it would be overwritten and then REMOVED)" >&2
        exit 4
      fi
      trap "drv sync rm \"$MRUN_NAME\" -o text >/dev/null 2>&1" EXIT
      lo="$(drv exec load --no-compile "$MRUN_FILE" -o text 2>&1)" || { printf "%s\n" "$lo"; exit 1; }
      drv exec eval "do ^$MRUN_NAME" -o text
    ' 2>&1)"; rc=$?
    # RSM's terminal device writes CRLF for `!` where YottaDB writes LF —
    # normalize so the same routine prints the same bytes on both engines
    # (A22 is about the routine's OUTPUT, not the device's line discipline).
    out="$(printf '%s' "$out" | tr -d '\r')"
    if [ "$rc" -eq 0 ]; then
      printf '%s\n' "$out" | sed -e '${/^run-lock .* released$/d}' | sed -e '${/^$/d}'
    else
      printf '%s\n' "$out"
    fi
    exit "$rc"
    ;;
  *)
    # YottaDB: a standalone routine in the user's /work project is not on
    # the image's baked $ydb_routines, so add its directory to the path
    # (the engine then finds AND compiles it — YDB writes the .o beside the
    # .m, which is why the mount must be writable), then execute the
    # routine's top label through the sanctioned `m engine exec` local
    # seam.
    #
    # `-o text` prints the routine's own output followed by a trailing
    # "status N". On success we print just the routine's output (drop the
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
