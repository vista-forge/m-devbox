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
Learn and build on M/MUMPS: YottaDB + RSM, FileMan, standard libraries, VS Code — one container.
```

---

## Overview body — paste from here down

# m-devbox

**A modern, integrated M development environment - batteries included.** Start it, open a browser, and you are writing and running M code against a real database in about a minute — no compiler, no toolchain, nothing to install but Docker.

M is one of the oldest languages still doing serious work: it runs a large share of the world's hospitals and core-banking systems. It is also famously hard to *start* with, because the ecosystem assumes you already have an engine, a database, and forty years of context. This image is the missing on-ramp.


## Get started in three steps

__1. Pull the image__
```bash
docker pull rafaelrichards/m-devbox:latest
```

__2. Run the image__
```bash
docker run --rm -p 127.0.0.1:8080:8080 -v "$PWD":/work \
  rafaelrichards/m-devbox
```

__3. Open the web developer console__  
```bash
open http://127.0.0.1:8080 
```

You will now have a web-based M development environment with the directory you launched from mounted at /work.  



## The M developer stack, from the metal up

Six layers ship in this image. Each exists because the layer below it leaves something out.

```
  +----------------------------------------+
  |  your app     (the code you write)     |
  +----------------------------------------+
  |  FSL          FileMan Standard Library |
  |  FM           FileMan                  |
  +----------------------------------------+
  |  MSL          M Standard Library       |
  +----------------------------------------+
  |  m            M developer toolchain    |
  |  m-driver-sdk (one neutral contract)   |
  +-------------------+--------------------+
  |  m-ydb            |  m-rsm             |
  +-------------------+--------------------+
  |  YottaDB          |  RSM               |
  |  (production)     |  (reference)       |
  +-------------------+--------------------+
```

### 1. M engines (YottaDB, plus RSM as a reference)

The database and the language runtime in one. YottaDB stores hierarchical,
sparse key-value structures called **globals**, and it is serious
infrastructure: ACID transactions, journaling, replication, and a lineage
(GT.M) that has run national-scale banking and health systems for decades.
Already installed, initialised and running here.

Since 0.3.0 a second engine rides along: **Reference Standard M** (RSM, Fourth
Watch Software) — a solo-maintainer implementation of the M standard itself.
Set `M_ENGINE=rsm` and the same tools, tests and Run Code work against it.
It is a working *reference*, not a YottaDB alternative: the portable core of
the standard library runs on it, and what does not — transactions, call-outs,
the `$Z` extensions — is documented rather than discovered (see
"what works on RSM" in the m-rsm repository).

### 2. m-driver-sdk and the drivers (m-ydb, m-rsm)

Each engine is operated through its own specialist surface — YottaDB via
`mupip`/`gde`/`dse`/`lke`, RSM via its `rsm` runtime — plus rules about
process lifecycle and locking. `m-driver-sdk` is the **one neutral
contract**; each driver is the vendor adapter that realizes it for its
engine, so the tools above never learn engine-specific commands. You will
rarely call a driver directly. This layer is what keeps everything above
portable across M engines — and the reason `M_ENGINE=rsm` is a one-variable
switch (see the engines guide at `/opt/guides/engines.md`).

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

**FileMan** is where M stops being a key-value store and becomes an
application platform. It is a **data-dictionary driven DBMS**: you
define files and fields — a schema, itself held as data — and FileMan then
provides validation, data types, cross-references, indexes, lookups, queries and
reporting, enforced consistently for every program that touches the data.

It is over forty years old, in continuous production, and is the foundation of
VistA — the electronic health record running the entire U.S. Department of
Veterans Affairs hospital system. It is installed here standalone and ready.

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

- **Runs natively on Intel/AMD and on Apple Silicon** — both are built and
  tested, so nothing is emulated.
- **One thing drives the engine at a time.** The engine lock refuses instantly
  rather than queueing, so a command can fail if the IDE is probing in the
  background. Re-run it — by design, and it cannot deadlock.
- **`/work` must be writable** — YottaDB writes compiled objects beside your
  sources. Add `*.o` to your `.gitignore`.
- **The first terminal paste may be refused** by your browser until you grant
  clipboard permission; `Shift`+right-click pastes without it.
- The IDE runs **without authentication** — keep the port on loopback.

## Licence and source

AGPL-3.0-or-later, with a commercial option. The image assembles AGPL YottaDB,
Apache-2.0 FileMan, MIT code-server and extensions, and GPL-2.0 `git`. The
full inventory ships inside the image:

```bash
docker run --rm rafaelrichards/m-devbox \
  cat /opt/licenses/NOTICE
```

**Corresponding source.** As AGPL software, this image entitles you to the
source it was built from, published for every release at
<https://github.com/vista-forge/m-devbox/tree/main/releases> — every
repository it was built from, at the exact commits used.

Not affiliated with or endorsed by the U.S. Department of Veterans Affairs.
