# Docker Hub page — the published overview text

The source of truth for what appears on
`hub.docker.com/r/rafaelrichards/m-devbox`. Paste the body below into the
repository's **Overview**; keep this file and the page in step.

**Who it is written for:** someone who has heard of MUMPS, has never written a
line of it, and is deciding whether to spend 509 MB finding out. Every acronym
is expanded on first use, and the stack is explained as **layers** rather than
listed as parts — a newcomer cannot evaluate a bag of component names, but they
can follow "each layer exists because the one below it leaves something out."
If a sentence assumes you already know what FileMan is, that is a bug in this
page.

**Short description** (100-char field):

```
Learn and build on M/MUMPS: YottaDB, FileMan, two standard libraries, and VS Code — one container.
```

---

## Overview body — paste from here down

# m-devbox

**A complete M (MUMPS) development environment in one container.** Start it,
open a browser, and you are writing and running M code against a real database
in about a minute — no compiler, no toolchain, nothing to install but Docker.

M is one of the oldest languages still doing serious work: it runs a large share
of the world's hospital and core-banking systems. It is also famously hard to
*start* with, because the ecosystem assumes you already have an engine, a
database, and forty years of context. This image is the missing on-ramp.

```bash
docker run --rm -p 127.0.0.1:8080:8080 -v "$PWD":/work \
  rafaelrichards/m-devbox:0.1.0
```

Open **http://127.0.0.1:8080** — VS Code, in your browser, wired to a live
engine.

> **Always name a version.** There is no `latest` tag: a plain
> `docker pull rafaelrichards/m-devbox` fails with `manifest unknown`, on
> purpose. Mutable tags are how reproducibility quietly dies, so every release
> is immutable and pinnable by digest.

---

## The stack, from the metal up

Six layers ship in this image. Each exists because the layer below it leaves
something out.

```
        your application code
   ┌───────────────────────────────────────────────────────────┐
   │  FSL   FileMan Standard Library    fsldb · fsldd · fslq …  │  build apps
   │  FM    VA FileMan 22.2             data dictionary + DBMS  │  on data
   ├───────────────────────────────────────────────────────────┤
   │  MSL   M Standard Library          stdjson · stdcrypto …   │  write modern M
   ├───────────────────────────────────────────────────────────┤
   │  m     developer toolchain         test · lint · fmt …     │  work on code
   │  m-ydb engine adapter              hides mupip/gde/dse     │  talk to engine
   ├───────────────────────────────────────────────────────────┤
   │  YottaDB   the M engine — ACID transactions, daemonless    │  store data
   └───────────────────────────────────────────────────────────┘
```

### 1. YottaDB — the engine

The database and the language runtime in one. It stores hierarchical, sparse
key-value structures called **globals**, and it is serious infrastructure: ACID
transactions, journaling, replication, and a lineage (GT.M) that has run
national-scale banking and health systems for decades. Already installed,
initialised and running here.

### 2. `m-ydb` — the engine adapter

YottaDB is operated through a family of specialist utilities — `mupip`, `gde`,
`dse`, `lke` — plus rules about process lifecycle and locking. `m-ydb` is the
**vendor adapter** that hides all of that behind one neutral contract, so the
tools above it never learn YottaDB-specific commands. You will rarely call it
directly. It is what keeps everything above portable across M engines.

### 3. `m` — the developer inner loop

The toolchain a modern developer expects, for a language that never had one.
This is what you will actually type:

| Command | What it does |
|---|---|
| `m test` | run test suites, with assertion counts |
| `m lint` | static analysis — the squiggles in the editor |
| `m fmt` | format code |
| `m coverage` | test coverage |
| `m watch` | re-run tests as you edit |
| `m lib` | install / verify / uninstall libraries on the engine |
| `m vista exec` | evaluate one line of M against the live engine |

The last one is misnamed, and it is worth saying so plainly rather than letting
you discover it: **it has nothing to do with VistA and requires none of it.** It
evaluates a line of M against whatever engine is attached — this image uses it
on a bare YottaDB throughout. Read it as "evaluate"; the `vista` in the middle
is a historical artifact of where the toolchain grew up.

Twenty verbs in all; run `m` with no arguments to browse them.

### 4. MSL — the **M Standard Library**

M's built-in library is tiny by modern standards: no JSON, no HTTP, no crypto,
no regular expressions. MSL closes that gap with **40 modules**, already
installed on the engine and callable by name:

- **Data formats** — `stdjson`, `stdxml`, `stdcsv`, `stdtoml`, `stdb64`, `stdhex`
- **Crypto & security** — `stdcrypto`, `stdcsprng`, `stdjwt`, `stdsigv4`
- **Network** — `stdhttp`, `stdhttpd`, `stdnet`, `stdurl`, `stds3`
- **Text & data** — `stdstr`, `stdregex`, `stdcoll`, `stdkv`, `stdmath`, `stddate`
- **Engineering** — `stdassert`, `stdlog`, `stdmock`, `stdprof`, `stdfs`, `stduuid`

Calling one needs no import, no build step and no dependency file — just the
name:

```m
write $$toUpperASCII^STDSTR("hello")
write $$sha256^STDCRYPTO("abc")
```

### 5. FileMan — the database *management* system

**VA FileMan** (*FileMan*, or FM) is where M stops being a key-value store and
becomes an application platform. It is a **data-dictionary driven DBMS**: you
define files and fields — a schema, itself held as data — and FileMan then
provides validation, data types, cross-references, indexes, lookups, queries and
reporting, enforced consistently for every program that touches the data.

It is over forty years old, in continuous production, and is the foundation of
VistA — the electronic health record running the entire U.S. Department of
Veterans Affairs hospital system. Version **22.2**, standalone and ready.

### 6. FSL — the **FileMan Standard Library**

FileMan's own calling conventions were designed in another era and show it. FSL
is a clean, modern API over the same engine — **7 modules** that let you build
data-driven applications without wrestling the legacy interface:

| Module | What it covers |
|---|---|
| `fsldb` | create, read, update, delete |
| `fsldd` | the data dictionary — files, fields, types |
| `fslq` | queries and lookups |
| `fsldate` | FileMan's date format ↔ ISO 8601 |
| `fslerr` | a consistent error envelope |
| `fslenv`, `fslfix` | environment setup and test fixtures |

Together that is **an ACID-compliant engine, a real schema layer on top of it,
and a modern standard library on either side** — enough to build a genuine
data-driven application, not just a demo.

---

## Your first ten minutes

The IDE opens on four folders: **your code** first, then the examples and both
libraries — so the source of everything you call is one click away. Open a
terminal with `` Ctrl+` ``:

1. **Prove it works.** Open `examples/hello/src/HELLO.m` and press *Run Code*
   (▷, or `Ctrl+Alt+N`).
2. **Tour the whole stack.** Run `examples/hello/src/DEMO.m` — it walks MSL →
   FileMan → FSL, printing *call / returns / means* at every step.
3. **Run real tests.** `m test /opt/examples/hello/tests` — 25 assertions.
4. **Read a library while you use it.** Open `MSL/src/STDSTR.m` beside
   `MSL/docs/modules/stdstr.md`.
5. **See how libraries are installed.** `bash /opt/examples/lib-demo/tour.sh`
   installs one, calls it, verifies it, removes it, and leaves the engine back
   at its starting state.

## What else is in the box

**VS Code in the browser** (code-server), fully offline, with four extensions
baked in: **m-vscode** (M language support, live linting, test explorer, engine
status), **Code Runner** (the ▷ button, wired to run `.m` files), **Error Lens**
(lint findings shown inline) and **Rainbow CSV**. `git` is installed, so Source
Control works. Nothing is downloaded on first run.

## Know before you pull

- **linux/amd64 and linux/arm64**, both verified by the same 27-gate acceptance
  battery. Apple Silicon runs natively, not emulated.
- **One thing drives the engine at a time.** The engine lock refuses instantly
  rather than queueing, so a command can fail if the IDE is probing in the
  background. Re-run it — by design, and it cannot deadlock.
- **`/work` must be writable** — YottaDB writes compiled objects beside your
  sources. Add `*.o` to your `.gitignore`.
- **A green exit code from `m vista exec` is not proof of success.** YottaDB
  exits 0 even when it reports an M error, so read the output. A fix is ruled
  and pending.
- **The first terminal paste may be refused** by your browser until you grant
  clipboard permission; `Shift`+right-click pastes without it.
- The IDE runs **without authentication** — keep the port on loopback.

## Licence and source

AGPL-3.0-or-later, with a commercial option. The image assembles AGPL YottaDB,
Apache-2.0 VA FileMan (774 of its 861 routines carry the Medsphere/Apache
notice), MIT code-server and extensions, and GPL-2.0 `git`. The full inventory —
every licence read from the artifact itself, not from a listing — ships inside:

```bash
docker run --rm rafaelrichards/m-devbox:0.1.0 cat /opt/licenses/NOTICE
```

**Corresponding source.** As AGPL software, this image entitles you to the
source it was built from, published for every release at
<https://github.com/vista-forge/m-devbox/tree/main/releases> — all ten
contributing repositories at the exact commits the image was built from. The
build is pin-reproducible, and the module versions embedded in the shipped
binaries are gated against the committed pins.

Not affiliated with or endorsed by the U.S. Department of Veterans Affairs.
