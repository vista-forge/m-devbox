#!/usr/bin/env bash
# m-run <routine.m> — run an M routine file on the devbox's local YottaDB.
#
# Code Runner's executor for `.m` calls this (see the baked default settings).
# A standalone routine in the user's /work project is not on the image's baked
# $ydb_routines, so add its directory to the path (the engine then finds AND
# compiles it — YDB writes the .o beside the .m, which is why the mount must be
# writable), then execute the routine's top label through the sanctioned
# `m vista exec` local seam. `-o text` prints the routine's own output, not the
# JSON envelope.
set -eu

f="${1:?usage: m-run <routine.m>}"
dir="$(cd "$(dirname "$f")" && pwd)"
name="$(basename "$f" .m)"

export ydb_routines="$dir${ydb_routines:+ $ydb_routines}"
exec m vista exec --engine ydb --transport local -o text "do ^$name"
