#!/bin/sh
# devbox-entrypoint — PR-6: guarantee the running uid has a /etc/passwd entry
# before anything in the `m` toolchain asks passwd where home is.
#
# WHY THIS EXISTS. The run-lock home is derived from passwd, never $HOME
# (m-driver-sdk runlock.go DefaultRunLockDir), and it fails CLOSED on a lookup
# error — deliberately: two processes with divergent $HOMEs would derive two
# lock files for one engine, i.e. two lanes each "holding" the bracket while
# mutating the same instance. `CGO_ENABLED=0` means the lookup reads
# /etc/passwd directly with no NSS fallback. So an injected uid with no passwd
# entry refuses EVERY engine verb (measured 2026-07-22: RUNLOCK_FAILED, exit 5),
# and since PR-1 put every local verb inside the bracket, that is total.
#
# The fix belongs to the IMAGE, not the toolchain: the passwd-derived home is a
# load-bearing invariant of the run-lock seam and is not up for renegotiation
# here (org tripwire — a run-lock DESIGN change is a different, Fable-5-tier
# conversation).
#
# Three cases:
#   root / the baked `devbox` user (uid 1000) / any uid already in passwd
#       -> nothing to do.
#   an arbitrary uid with gid 0 (`--user 4242:0`)
#       -> /etc/passwd is group-0 writable (Dockerfile `chmod g=u`), so append
#          an entry for it. This is the standard arbitrary-uid container recipe.
#   an arbitrary uid with a NON-ZERO gid (`--user 4242:4242`)
#       -> OUT OF CONTRACT. Refuse loudly, naming the fix. Never fall through:
#          the failure would resurface three layers down as an opaque
#          RUNLOCK_FAILED from a verb that looks unrelated.
set -eu

uid="$(id -u)"

if ! getent passwd "$uid" >/dev/null 2>&1; then
  if [ -w /etc/passwd ]; then
    printf 'devbox:x:%s:0:m-devbox user:/home/devbox:/bin/bash\n' "$uid" >> /etc/passwd
  else
    cat >&2 <<EOF
devbox: FATAL — uid $uid has no /etc/passwd entry and /etc/passwd is not writable.

  The m toolchain derives its run-lock home from passwd (never \$HOME) and fails
  closed, so every engine verb would refuse with an opaque RUNLOCK_FAILED.

  Fix — use one of:
    --user $uid:0        (gid 0; this entrypoint then adds the passwd entry)
    --user devbox        (the baked user, uid 1000)
    devcontainer.json    remoteUser: devbox  +  updateRemoteUserUID: true
EOF
    exit 78
  fi
fi

# $HOME is not what the run-lock reads, but keep it consistent with passwd so
# nothing else in the container disagrees with the seam about where home is.
HOME="$(getent passwd "$uid" | cut -d: -f6)"
export HOME

exec "$@"
