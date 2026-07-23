---
name: devcontainer-mount-topology
description: devcontainer.json — $ydb_dir (/data) on a NAMED VOLUME never a bind mount (YDB locking corrupts over virtiofs/9p); a fresh named volume SEEDS from the baked DB; overrideCommand:false + updateRemoteUserUID keep PR-6.
metadata:
  type: project
---

`.devcontainer/devcontainer.json` (P3, proposal §3.1/§5.3). Non-obvious, durable
facts, each proven by `verify-devbox.sh` **G14** on image `32bdb1e4`:

**1. `$ydb_dir` (/data) is a NAMED VOLUME, never a bind mount.** The database is
`/data/m.gld` + `/data/g/m.dat`, so the mount target is `/data` (not just the
gbldir file). YottaDB's fcntl region locking is unreliable over the virtiofs/9p
translation Docker Desktop uses for bind mounts on macOS/Windows, and a lost lock
**corrupts the database** — so `/data` must be a named volume (Docker-VM-native
filesystem, locking honoured). Only the developer's own source binds (to `/work`),
where plain-file bind mounts are correct. G14 red-gates both: `/data` is
`type=volume` and nothing bind-mounts `/data`.

**2. A fresh named volume SEEDS from the baked DB.** This is the load-bearing,
easily-misread mechanic: on first attach Docker copies the image's baked `/data`
(the DB with FileMan + MSL + FSL) into the empty named volume, then persists it
across rebuilds. So the persistent volume is **not** empty — it carries the full
baked database. Proven: `docker run -v <fresh-vol>:/data … m test` → 5/0 green.
(Corollary: to re-seed, `docker volume rm` the volume; a non-empty volume is NOT
re-seeded.)

**3. PR-6 holds on the devcontainer path via `remoteUser` + `updateRemoteUserUID`,
with `overrideCommand:false` as a second guard.** The run-lock home is
passwd-derived and fails closed ([[passwd-row-is-an-image-obligation]]), so every
runtime uid needs a `/etc/passwd` row. `updateRemoteUserUID: true` rewrites the
baked `devbox` user's uid to the host uid **while keeping its passwd row** (the
sanctioned devcontainer path, proposal §5.3; the entrypoint's own error message
names it). `overrideCommand: false` keeps the image ENTRYPOINT (the PR-6 passwd
self-heal) running at container start — belt-and-suspenders — since our `CMD
tail -f /dev/null` is a valid keep-alive. Default `overrideCommand:true` would
bypass the ENTRYPOINT; the combo above still satisfies PR-6, but keeping the
entrypoint live costs nothing and guards the injected-uid path.

The `.vsix` install-at-attach (MD-D5) is the next increment; the
`customizations.vscode` block is the seam it lands in.
