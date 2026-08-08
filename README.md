# m-devbox

**A complete M (MUMPS) development environment in one container image.** A
YottaDB engine, the `m` toolchain, two standard libraries with their source and
documentation, standalone FileMan, and a full VS Code IDE in your browser —
with nothing to install but Docker.

You do not need a compiler, a Go toolchain, a clone of this organization, or
any network access after the image is on your machine.

---

## Start here

```bash
docker run --rm --name m-devbox -p 127.0.0.1:8080:8080 -v "$PWD":/work \
  rafaelrichards/m-devbox
```

Then open **http://127.0.0.1:8080**. (Building it yourself instead? The local
tag is `m-devbox:0.3.1-local` — see *For maintainers* below.)

Use the IP, not `localhost` — the port is published on IPv4 loopback only, and
`localhost` often resolves to IPv6 first, which shows `ERR_CONNECTION_REFUSED`
while the server is running fine. `-v "$PWD":/work` mounts **the directory you
ran the command from**, so `cd` to your project first (or pass an absolute
path). The port is bound to loopback deliberately: the IDE runs without
authentication, so do not expose it to a network.

Drop this in `~/.bashrc` to launch from any project directory with one word.
It force-removes the previous container first, which is what frees port 8080:

```bash
mdevbox() {
  docker rm -f m-devbox >/dev/null 2>&1
  docker run --rm --name m-devbox -p 127.0.0.1:8080:8080 -v "$PWD":/work \
    rafaelrichards/m-devbox
}
```

**Don't launch it from this repository's own checkout.** If you do, the explorer
shows `examples/` twice — once as `work/examples` (the *source*, which lives
here) and once as `examples (baked in image)` (the copies the image actually
runs). They are not duplicates and they are not linked: editing one does not
change the other, and which one runs depends on how you invoke it — *Run Code*
executes the file you have open, while `m test /opt/examples/...` always runs
the baked copy. Launch from a project directory instead, and the confusion
disappears.

### Your first ten minutes

The IDE opens on a four-folder workspace: **your code** first, then the
examples and both libraries. Everything below runs in the built-in terminal
(``Ctrl+` ``) unless it says otherwise.

1. **Prove the environment is alive.** Open `examples/hello/src/HELLO.m` and
   press *Run Code* (▷, or `Ctrl+Alt+N`). It prints a greeting built with a
   library call.
2. **Take the guided tour of the stack.** Open `examples/hello/src/DEMO.m` and
   run it the same way. It walks MSL → FileMan → FSL, printing *call / returns
   / means* at every step.
3. **Run the tests.** `m test /opt/examples/hello/tests` — 25 assertions
   exercising the libraries end to end.
4. **Read a library you just called.** Open `MSL/src/STDSTR.m` beside
   `MSL/docs/modules/stdstr.md`. This is the point of the MSL and FSL folders:
   the source you are calling, and its reference, side by side.
5. **Learn how libraries get installed.** `bash /opt/examples/lib-demo/tour.sh`
   installs a small library, calls it, verifies it, removes it, and proves the
   engine is back where it started.

---

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

## What is in the image

| Component | Version / size | Notes |
|---|---|---|
| YottaDB | r2.06 | byte mode (`ydb_chset=M`), VistA-sized database already created |
| Native callouts | 5 libraries | `std_compress`, `std_crypto`, `std_csprng`, `std_fs`, `std_http`, compiled during the build |
| `m` / `m-ydb` toolchain | built from source at image build | test runner, linter, formatter, library installer, engine driver |
| **MSL** — M Standard Library | 40 routines, 47 doc pages | installed on the engine *and* readable at `/opt/msl` |
| **FSL** — FileMan Standard Library | 7 routines, 8 doc pages | installed on the engine *and* readable at `/opt/fsl` |
| FileMan | 22.2 | standalone (no Kernel), built into the image |
| code-server | 4.130.0 (VS Code 1.130.0) | the IDE, served to your browser, fully offline |
| `git` | 2.47.3 | so VS Code's Source Control panel actually works |

906 routines are resident in `/opt/lib/r` once MSL, FSL and FileMan are counted
together.

**Image size, three honest numbers**, because the tooling reports different
things: **509.6 MB** as the sum of layer content (`docker image inspect`),
**1.72 GB** unpacked on disk under the containerd snapshotter (`docker image
ls`), and **477 MB** as the compressed archive. Most of it is the IDE —
code-server alone is 645 MB unpacked. Component-by-component detail:
[image dossier](docs/design/image-dossier.md).

### Platform support

| Platform | Status |
|---|---|
| linux/amd64 | **verified** — the full G1–G27 battery |
| linux/arm64 (incl. Apple Silicon) | **verified** — the same G1–G27 battery, run natively |

Both architectures are built and gated the same way, and published under one
tag, so `docker pull` resolves the right one with no flag.

**How arm64 is built, and why it cannot be emulated.** The image build *runs*
the engine — `GDE`, `mupip create`, `m lib install`, FileMan's `DINIT`. Under
qemu, YottaDB checks `$ydb_dist` against its own executable path, sees the
emulator, and refuses with `YDBDISTUNVERIF`. So an emulated arm64 build does
not produce a questionable image; it produces **no image**. The arm64 leg is
therefore built on real Apple Silicon:

```bash
make build-arm64     # stages arm64, builds natively on the remote host
make verify-arm64    # the same battery, against that image
```

Only the `docker build` is remote. The `m` and `m-ydb` binaries cross-compile
here (`CGO_ENABLED=0`, statically linked), so the build host needs nothing but
Docker.

### The IDE and its extensions

Four extensions are baked in and installed from local files at build time, so
the first launch works with no network and no marketplace:

| Extension | What it gives you |
|---|---|
| **m-vscode** | the M language itself — highlighting, `m lint` diagnostics, the test explorer, and an engine-health status chip |
| **Code Runner** | the ▷ *Run Code* button, wired to run `.m` routines on the local engine |
| **Error Lens** | shows `m lint` findings inline on the offending line instead of only in the Problems panel |
| **Rainbow CSV** | column colouring for `.csv`/`.tsv` — MSL ships a CSV module and FileMan exports CSV |

**m-vscode is the only extension that touches M.** Error Lens contributes no
language at all (it renders diagnostics other extensions produce) and Rainbow
CSV claims only `.csv`/`.tsv`/`.tab`. That is enforced, not just intended:
acceptance gate **G24** fails the build if more than one baked extension claims
`.m`/`.mac`/`.int` or declares a `mumps` language. Do not add another MUMPS
extension — two highlighters and two linters on one file is exactly what the
gate refuses.

**Pasting into the terminal.** The first paste may fail with *"Unable to read
from the browser's clipboard…"*. Nothing is wrong with the image: VS Code in a
browser pastes via `navigator.clipboard.readText()`, which needs the browser's
**clipboard-read** permission, and it starts out ungranted (measured at
`http://127.0.0.1:8080`: `isSecureContext: true`, permission state `prompt`).
Serving over HTTPS does **not** help — `127.0.0.1` is already a trusted origin.

| Fix | How |
|---|---|
| Grant it once (Chrome/Edge) | Click the icon left of the address bar → *Site settings* → **Clipboard → Allow**, then reload. |
| Grant it once (Firefox) | Set `dom.events.asyncClipboard.readText` to `true` in `about:config`, or click the **Paste** confirmation Firefox pops up. |
| Skip the permission | **Shift + right-click** gives the browser's own context menu, whose Paste needs no permission. On Linux, **middle-click** pastes the primary selection. |

---

## Working on your own code

Mount your project at `/work` and it becomes the first folder in the explorer.
Two things are worth knowing before you do:

**`/work` must be writable.** YottaDB writes the compiled `.o` object beside
each `.m` source when a routine runs, so running M out of a read-only mount
fails. This also means running code from a git working tree drops `.o` files
into it — add `*.o` to that project's `.gitignore`, or work from a scratch
directory.

**Your routines need to be on the engine's routine path.** The baked libraries,
examples and test suites are already there. A project of your own is not:

```bash
export ydb_routines="/work $ydb_routines"   # your dir first
m test /work/tests                          # now your suite resolves
```

The *Run Code* button handles this for you (its helper adds the file's own
directory before running), so this only matters for `m test` and hand-run
routines from a directory you mounted yourself.

### One thing drives the engine at a time

The engine is single-writer, and the toolchain enforces it with a lock that
**refuses immediately rather than queueing**. So if the IDE's status chip or
test explorer touches the engine while a terminal command is mid-run — or you
start a second `m test` in another terminal — the newcomer fails at once with a
run-lock message rather than waiting its turn.

That is by design, not a bug, and the failure is deliberately loud: a silent
wait would hide the fact that two writers wanted the same engine, and a
deadlock is impossible because the lock never blocks. Re-run the command once
the first finishes.

Practical version: if a command refuses unexpectedly, something else is already
using the engine — usually the extension probing it in the background. Wait a
moment and try again.

### Running M

```bash
m test /opt/examples/hello/tests     # a suite, with assertion counts
m test /opt/msl/tests/STDSTRTST.m    # a single MSL suite
m lint /work/MYROUTINE.m             # the linter behind the editor squiggles
m engine exec 'write $$sha256^STDCRYPTO("abc")'    # one-off M through the driver
m lib list                           # what libraries are installed
```

No `--engine` or `--transport` flags are needed: the image bakes `M_ENGINE=ydb`
and the driver resolves the local engine sitting beside you.

### Switching engines (YottaDB ⇄ RSM)

One variable selects the engine — for a whole container:

```bash
docker run --rm -p 127.0.0.1:8080:8080 -v "$PWD":/work \
  -e M_ENGINE=rsm rafaelrichards/m-devbox
```

or inside a running terminal: `export M_ENGINE=rsm` (and `=ydb` to switch
back). Run Code and `m test` follow it. The full guide — what is identical,
what differs per engine, and where the deeper documentation lives — is baked
at **`/opt/guides/engines.md`**; RSM's measured capability boundary is at
**`/opt/rsm/docs/what-works-on-rsm.md`**.

⚠️ **`m engine exec` reports the engine's *process* status, and YottaDB exits 0
even when it reports an M error** (an unresolvable routine, for instance). So a
green exit code does not mean your command worked — read the output. This is a
known open toolchain question, tracked as PR-28.

### What is and is not in the terminal

Present: the `m` toolchain, `git`, `bash`, `sha256sum` and the usual coreutils.

**Absent by design:** `python3`, `curl`, `wget`, `make`, `gcc`, `less`, `vim`,
`nano`. This is a runtime, not a build box — the compiler lives only in a
throwaway build stage, and the IDE is your editor. If you need one of these for
your own work, that is a case for changing the image, not for installing it
into a running container (which vanishes on the next `docker run --rm`).

### Running as a non-root user

| Invocation | Result |
|---|---|
| default (root) | works |
| `--user devbox` (baked, uid 1000) | works |
| `--user <any-uid>:0` | works — the entrypoint adds the passwd entry |
| `--user <any-uid>:<non-zero-gid>` | **refuses, exit 78**, naming the fix |

Why group 0 matters: the toolchain derives its run-lock home from `/etc/passwd`
rather than `$HOME`, and fails closed — deliberately, so a divergent `$HOME`
cannot split the run-lock's serialization domain. A `CGO_ENABLED=0` binary
reads `/etc/passwd` with no NSS fallback, so a uid absent from it is refused
every engine verb. The image guarantees the entry: group 0 owns a `g=u`-mode
`/etc/passwd`, and the entrypoint appends the row for whatever uid it runs as.

---

## Adding, replacing, or writing libraries

MSL and FSL were installed with `m lib`, the same verb available to you:

| Verb | What it does |
|---|---|
| `m lib list` | what the engine's ledger says is installed |
| `m lib install --name <n> <path>/src` | capture pre-images, compile onto the routine path, verify, commit — idempotent |
| `m lib verify <n>` | re-derive from the engine, compare to the ledger |
| `m lib uninstall <n>` | restore pre-images, delete what it added, drop the ledger row |

A library is a two-part unit: `src/*.m` plus `dist/<name>-manifest.json`, which
declares exactly which routines belong to it. Give your own project that shape
and it installs like any other. `bash /opt/examples/lib-demo/tour.sh` walks the
whole cycle, and [examples/lib-demo/README.md](examples/lib-demo/README.md)
explains the unit.

The MSL and FSL folders in the IDE are for **reading**. The routines that
actually run were installed onto the engine; those trees are documentation
copies kept byte-identical to both their home repositories and the resident
routines (gate G21). Edit a library in its own repo — `m-stdlib` or `f-stdlib`
— and rebuild the image.

---

## For maintainers: building and gating

Two clocks, deliberately separated:

| Clock | Targets | Network |
|---|---|---|
| **sync time** | `make stage` · `make build` · `make rebuild` · `make archive` | allowed, deliberate, never automatic |
| **gate time** | `make check` · `make verify` · `make load` | **none** |

```bash
make build     # sync-time: assemble the context from pins, docker build
make check     # offline: pins + waterline + docs + shell + the full battery
make load      # offline: restore the image from the org archive
```

`make check` needs the image present and never fetches it; if it is missing,
`make load` restores it from `~/data/vista-forge/images`. The archive, not a
rebuild, is the recovery path.

**Both architectures of a published release are archived**, so neither depends
on the registry to come back:

| Archive | Managed by |
|---|---|
| `m-devbox_0.3.1-local.tar.zst` (amd64) | the org archive script — change-detected, refreshed by `make archive` |
| `m-devbox_0.3.1-local-arm64.tar.zst` | **manually**, saved from the remote build host |

⚠️ The arm64 archive is a **point-in-time copy**. The org script saves images
from the *local* daemon, and the arm64 image lives on the Apple Silicon host, so
nothing re-saves it automatically — rebuild arm64 and this archive silently goes
stale. Its `.id` companion records the image ID it was cut from; compare against
`docker image inspect` on the build host before trusting it. A stale archive
that looks current is worse than no archive, which is why the limitation is
written down rather than assumed.

**Nothing is vendored in this repo.** Every binary, routine and document is
single-sourced in its owning repository and assembled into an ephemeral build
context by `scripts/stage-context.sh`. Always restage before building — a
`docker build` against a stale context silently produces a different program
than the one you tested.

⚠️ **This repository is public, but it is not self-contained.** `make build`
needs six sibling repositories checked out beside it (`m-cli`, `m-ydb`,
`m-stdlib`, `f-stdlib`, `fileman`, `m-vscode`), and `make check` shells out to
the organization's `.github` scripts. Those are not public today, so a bare
clone can be *read* but not built or gated. The published image is the artifact
intended for use; this repo is how it is made.

The acceptance battery is **G1–G24**, and every engine call in it goes through
the driver seam (`m engine exec` / `m test`), never a raw `docker exec`. Gates
worth knowing: G9 library ledger, G10 FileMan, G12 the example suite, G16
read-only rootfs, G17 offline IDE boot, G21 library reading trees, G22 the
install/uninstall round trip, G23 the IDE opens trusted, G24 extension
ownership.

`make sweep` (the full MSL run) is a **measurement, not a gate**: 11 suites
need a live MinIO service and fail without one.

### Publishing

The strategy is **publish the artifact, not the build**: the image is produced
here by the pinned, gated `make build` and pushed as-is, so what a stranger
runs is exactly what G1–G24 verified. Docker Hub does not build this repo and
could not — nothing is vendored, and the sibling repositories it assembles from
are private.

**Channel: `docker.io/rafaelrichards/m-devbox`** — a free personal Docker Hub
namespace. Docker Hub's free tier no longer covers *organizations*, but a free
personal account still allows unlimited **public** repositories.

The username is fixed and cannot be changed, so **the namespace does not carry
the project identity — the image does.** Every published image is labelled with
its vendor, source repository, licence and documentation URL, so a consumer can
ask the artifact itself rather than infer from the path:

```bash
docker inspect --format '{{json .Config.Labels}}' rafaelrichards/m-devbox:0.3.1
# org.opencontainers.image.vendor    vista-forge
# org.opencontainers.image.source    https://github.com/vista-forge/m-devbox
# org.opencontainers.image.licenses  AGPL-3.0-or-later
# org.vista-forge.licenses.path      /opt/licenses
```

**One-time setup.** Create a Personal Access Token on Docker Hub (*Account
Settings → Personal access tokens*, Read/Write scope), then put it in the org's
single credential file — never in a forge secret store:

```bash
# ~/data/vista-forge/auth.env   (chmod 600, outside every repo, direnv-loaded)
DOCKERHUB_USER=rafaelrichards
DOCKERHUB_TOKEN=dckr_pat_...
```

**Every publish.**

```bash
make build                                   # sync-time: the pinned, gated build
make check                                   # offline: G1–G24 must be green
echo "$DOCKERHUB_TOKEN" | docker login -u "$DOCKERHUB_USER" --password-stdin
make publish PUBLISH_OK=1                    # re-verifies, then tags + pushes
```

`make publish` refuses twice before it can do damage: once unless `PUBLISH_OK=1`
is set explicitly, and again if you are not logged in — both *before* anything
is tagged. When it does run, it re-runs the whole acceptance battery against the
exact image being pushed, then prints the resulting **digest**.

**Each release publishes two tags**: the immutable version and `latest` moved
to it, so a bare `docker pull rafaelrichards/m-devbox` works for a first-time
user. `make publish PUBLISH_TAG=0.3.1` sets both.

The org's rule against mutable tags ([[iris-community-hub-rebuild-breaks-boot]])
governs what we *consume* — everything this image builds on is pinned, never a
moving `latest`. Offering one to our own users is a separate question, and a
working first command wins.

Licence inventory for anything you distribute: [NOTICE](NOTICE), also baked into
the image at `/opt/licenses/`.

**Cutting a release?** The order matters — the source bundle refuses if the
image was built before the commits it must correspond to. Follow
[docs/guides/releasing.md](docs/guides/releasing.md), which is the whole
sequence with the refusals decoded.

### Corresponding source (required by the AGPL)

The image ships AGPL software — YottaDB and vista-forge's own code — so whoever
pulls it is entitled to the corresponding source. **That duty does not depend on
our repositories being public**, so every published image gets a source bundle
published beside it:

```bash
make source-bundle                     # → ~/data/vista-forge/source-bundles/
make source-bundle DIGEST=sha256:...   # after publishing, bind it to the digest
```

The bundle is a single `.tar.gz` (~3.7 MB) holding `git archive` of all ten
contributing repositories, a `COMMITS.txt` naming every commit, the NOTICE and
LICENSE, and a README explaining what is *not* included (YottaDB, FileMan,
code-server and the extensions — each pinned, each pointed at its upstream).

It refuses rather than produce something unverifiable:

| Refusal | Why |
|---|---|
| uncommitted changes in any repo | a bundle cut from a dirty tree corresponds to no commit anyone can check |
| a repo whose HEAD differs from what the image was staged from | it would not be the source of *that* image |
| the image was staged from a DIRTY tree | the correspondence is unprovable, which is the failure mode itself |

That last check is why the order is **commit → `make build` → `make
source-bundle`**: the bundle is validated against `.build-context/context.provenance`,
which `make build` writes as it stages.

**The pins, the bundle, and the binaries agree — and three instruments prove
it.** The image binaries are built `GOWORK=off` against the committed `go.mod`
pins; the stage refuses a binary whose embedded module list disagrees with the
pins; gate **G27** re-reads that module list out of the *baked* binaries (a
workspace build stamps its siblings `(devel)`, so a leak is unambiguous); and
the bundle refuses unless every dependency repo's archived commit carries
exactly the tag the consumers pin. A rebuilder can start from the pins or from
the bundle's directories — they are the same source, verifiably.

```
Dockerfile                    the image, pins in its header
scripts/stage-context.sh      assemble the build context (sync-time)
scripts/verify-devbox.sh      the acceptance battery G1–G24
scripts/check-pins.sh         offline drift gate: header pins == build pins
scripts/devbox.code-workspace the multi-root workspace the IDE opens
examples/hello/               the starter project
examples/lib-demo/            installing and uninstalling libraries
docs/design/image-dossier.md  measured contents, sizes, sweep baseline
```

---

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `port is already allocated` | a previous container still holds 8080 — `docker rm -f m-devbox`, or use the `mdevbox` function above |
| `ERR_CONNECTION_REFUSED` | you used `localhost` (IPv6) — use `http://127.0.0.1:8080` |
| Clipboard error on paste | browser permission, not the image — see the clipboard table above |
| A routine will not link | it is not on `$ydb_routines` — see "Working on your own code" |
| `m test` reports "made no assertions" | same cause: the suite's directory is not on the routine path |
| Green exit code, wrong result | `m engine exec` reports process status, not M errors — read the output (PR-28) |

Live status for every prerequisite and open question is the m-devbox
prerequisites tracker — `proposals/m-devbox/m-devbox-prerequisites-remediation-tracker.md`
in the organization's `docs` repository, which is not public — not this README.

## License

AGPL-3.0-or-later with a commercial option — see [LICENSE](LICENSE) and
[NOTICE](NOTICE). The image assembles AGPL YottaDB and public-domain VA
FileMan; the combined-work disposition gates publication, not building
(tracker PR-17).
