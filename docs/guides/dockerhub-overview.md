# Docker Hub page — the published overview text

The source of truth for what appears on
`hub.docker.com/r/rafaelrichards/m-devbox`. Paste the body below into the
repository's **Overview**; keep this file and the page in step.

**Why this file exists at all:** the GitHub repository is private, so the Hub
page is the *only* public documentation for the image. Everything a stranger
needs to start, and every limitation they are entitled to know about before
pulling 509 MB, has to be on it.

**Short description** (100-char field):

```
A complete M (MUMPS) development environment: YottaDB, FileMan, MSL/FSL, and VS Code in your browser.
```

---

## Overview body — paste from here down

# m-devbox

**A complete M (MUMPS) development environment in one image.** A YottaDB
engine, the `m` toolchain, two standard libraries with their source and
documentation, standalone VA FileMan, and a full VS Code IDE served to your
browser — with nothing to install but Docker.

## Start

```bash
docker run --rm --name m-devbox -p 127.0.0.1:8080:8080 -v "$PWD":/work \
  rafaelrichards/m-devbox:0.1.0
```

Then open **http://127.0.0.1:8080**.

**There is no `latest` tag — always name a version.** `docker pull
rafaelrichards/m-devbox` will fail with `manifest unknown`, and that is
deliberate: a mutable tag that moves under a working image is how projects lose
reproducibility, so every release is an immutable version you can pin by digest.

Use `127.0.0.1`, not `localhost` — the port is published on IPv4 loopback only,
and `localhost` often resolves to IPv6 first. `-v "$PWD":/work` mounts the
directory you ran the command from, so `cd` to your project first. The IDE runs
without authentication; keep it bound to loopback.

## What you get

| Component | Version |
|---|---|
| YottaDB | r2.06, byte mode, database already initialised |
| `m` / `m-ydb` toolchain | test runner, linter, formatter, library installer |
| **MSL** — M Standard Library | 40 routines, installed *and* readable at `/opt/msl` |
| **FSL** — FileMan Standard Library | 7 routines, installed *and* readable at `/opt/fsl` |
| VA FileMan | 22.2, standalone (no Kernel) |
| VS Code (code-server) | 1.130.0, with M language support, Run Code, Error Lens, Rainbow CSV |
| `git` | 2.47.3 |

The IDE opens on a four-folder workspace: your code first, then the examples and
both libraries — so the source of every library you call sits beside its
reference documentation.

## First ten minutes

Open the built-in terminal (`` Ctrl+` ``) and:

```bash
m test /opt/examples/hello/tests      # 25 assertions across MSL, FileMan, FSL
bash /opt/examples/lib-demo/tour.sh   # install a library, call it, remove it
```

Then open `examples/hello/src/DEMO.m` and press *Run Code* (`Ctrl+Alt+N`) for a
guided tour of the stack, and `MSL/src/STDSTR.m` beside
`MSL/docs/modules/stdstr.md` to see what reading a library here looks like.

## Know before you pull

- **linux/amd64 only.** arm64 is unverified — YottaDB refuses to verify itself
  under emulation, so Apple Silicon is unsupported rather than merely slow.
- **One thing drives the engine at a time.** The engine lock refuses instantly
  rather than queueing, so a command may fail if the IDE is probing the engine
  in the background. Re-run it; this is by design, and it cannot deadlock.
- **`/work` must be writable** — YottaDB writes compiled objects beside your
  sources. Add `*.o` to your project's `.gitignore`.
- **A `m vista exec` that reports success may still have failed.** YottaDB exits
  0 even when it reports an M error, so read the output rather than trusting the
  exit code. A fix is ruled and pending.
- **First terminal paste may be refused** by the browser until you grant the
  clipboard permission; `Shift`+right-click pastes without it.

## Licence and source

AGPL-3.0-or-later, with a commercial option. The image assembles AGPL YottaDB,
Apache-2.0 VA FileMan (774 of its 861 routines carry the Medsphere/Apache
notice), MIT code-server and extensions, and GPL-2.0 `git`.

The complete inventory — every licence read from the artifact itself — ships
**inside the image**:

```bash
docker run --rm rafaelrichards/m-devbox:0.1.0 cat /opt/licenses/NOTICE
```

`/opt/licenses/` also carries the full Apache-2.0 and AGPL-3.0 texts, and every
image is labelled with its vendor, licence and source location:

```bash
docker inspect --format '{{json .Config.Labels}}' rafaelrichards/m-devbox:0.1.0
```

**Corresponding source.** As AGPL software, this image entitles you to the
source it was built from. A source bundle is published for every release: it
contains all ten contributing repositories at the exact commits the image was
built from, and the build is pin-reproducible — the module versions embedded in
the shipped binaries are gated against the committed pins.

> ⚠️ **BEFORE PUBLISHING:** replace this paragraph with the real location of the
> corresponding-source bundle, and repoint `org.opencontainers.image.source` at
> the same place. The GitHub URL currently in the label is a private repository
> and 404s for the public — an AGPL source pointer that does not resolve is not
> a source pointer. This is the last unresolved publication prerequisite.

Not affiliated with or endorsed by the U.S. Department of Veterans Affairs.
