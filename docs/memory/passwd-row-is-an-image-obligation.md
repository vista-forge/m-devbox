---
name: passwd-row-is-an-image-obligation
description: A tool whose identity lookup fails closed makes /etc/passwd provisioning the IMAGE's job — and CGO_ENABLED=0 deletes the NSS escape hatch, so an injected uid refuses every verb.
metadata:
  type: project
---

**Measured 2026-07-22 (m-devbox PR-6), on the pre-fix candidate image:**

```
$ docker run --rm --user 1000:1000 m-devbox-base:candidate m vista exec …
RUNLOCK_FAILED — run-lock: passwd lookup for the lock home failed
                 (no $HOME fallback …): user: unknown userid 1000
```

Not one verb. **Every** verb — since PR-1 the local transport takes the run
bracket too, so the whole surface refuses. And it is precisely the shape a
devcontainer produces on first run: a uid injected from the host with no row in
the image's `/etc/passwd`.

## The chain, because each link alone looks harmless

1. `m-driver-sdk`'s `DefaultRunLockDir` reads `user.Current().HomeDir`, **never
   `$HOME`**, and **fails closed**. Load-bearing, not incidental — a divergent
   `$HOME` would split the run-lock's serialization domain ([[run-lock-seam]]).
2. `CGO_ENABLED=0` (the org default) means `os/user` parses `/etc/passwd`
   directly. **There is no NSS fallback to configure.** `nsswitch.conf` is
   present in the image and irrelevant; so is `$HOME`.
3. Therefore the running uid must have a passwd row, and **only the image can
   guarantee that.** Not the toolchain: the fail-closed home is the invariant
   the seam is built on.

## What the image owes, and where the honest edge is

- baked `devbox` user (uid 1000, gid 0) — the `remoteUser` /
  `updateRemoteUserUID` devcontainer path, which keeps a real row throughout;
- `/etc/passwd` owned by group 0 in `g=u` mode + an entrypoint that appends the
  row for whatever uid it runs as — the standard arbitrary-uid container recipe.
  Covers `--user <any-uid>:0`;
- `--user <uid>:<non-zero-gid>` **cannot** be covered without a world-writable
  passwd, so it is **out of contract and refused loudly** (exit 78, message
  naming the fix). Falling through would resurface three layers down as an
  opaque `RUNLOCK_FAILED` from a verb that looks unrelated —
  [[degrade-loud-or-refuse]].
- State dirs (`/data`, `/opt/msl`, `/opt/stdlib`, `/work`, the home) get the
  same gid-0 treatment: the engine writes journals, the database, and `.o`
  objects beside `.m` (PR-12), so read-only-for-non-root is a second, quieter
  version of the same failure.

## The transferable rule

**Any image that ships a tool whose identity/home lookup fails closed owes that
tool a passwd row for every uid it can be run as — and owes a loud refusal for
the uids it cannot serve.** Ask it of every image the org ships, not just this
one. The symptom is maximally misleading: an error from the *lock* subsystem,
on a verb that never mentioned users.

**Gate, not vigilance:** `scripts/verify-devbox.sh` G7 runs a real `m test`
(63 assertions) as root, as `--user 4242:0`, and as the baked user; G8 pins the
exit-78 refusal. Both were **red-proofed against the real pre-fix image** — G7's
arbitrary-uid arm and G8 both fail on `m-devbox-base:candidate` and pass on
`m-devbox:0.1.0-local`. A gate that has only ever been green proves nothing.
