# m-devbox

**A portable M development environment in one container image.** YottaDB, the
five native `m-stdlib` callouts, the `m` / `m-ydb` toolchain, the **M Standard
Library (MSL) and the FileMan Standard Library (FSL) installed durably via
`m lib`**, **standalone VA FileMan 22.2**, and an `examples/hello` starter —
built entirely from pins, no compiler and no Go toolchain required on the
developer's machine.

> **Status: P2 built.** The image below is real, built, verified and archived
> (265 MB; MSL + FSL + FileMan resident, `examples/hello` green). The
> devcontainer and baked `.vsix` (P3), the one-command launchers (P4),
> multi-arch (P5) and publication (P6) are not built yet. The live status of
> every prerequisite is the
> [prerequisites tracker](../docs/proposals/m-devbox/m-devbox-prerequisites-remediation-tracker.md)
> — not this README, and not the proposal.

## Quick start (from an org checkout)

```bash
make build     # sync-time: assemble the context from pins, docker build
make verify    # offline: the acceptance battery, all through the driver seam
make check     # offline: the full gate (pins + waterline + docs + shell + verify)
```

If the image is missing but the org archive is present, restore it offline:

```bash
make load      # zstd -dc ~/data/vista-forge/images/... | docker load
```

## Opening the IDE (code-server)

The devbox ships **code-server** — VS Code in the image, served to a browser.
There is no desktop VS Code app to install and no client↔server version to keep
in sync: code-server ships its own matched web client, so you can update your
own VS Code as often as you like and nothing here breaks (MD-D8). The m-vscode
extension is **baked in** (installed from the local `.vsix` at build time), so
the first open works fully offline — no download.

```bash
# serve the IDE on localhost only; mount your project at /work
docker run --rm -p 127.0.0.1:8080:8080 -v "$PWD":/work m-devbox:0.1.0-local
# then open http://localhost:8080  → editor + terminal + `m test`, offline
```

Bind to `127.0.0.1` (as above): code-server runs with `--auth none` for a
zero-friction local box, so do not expose the port to a network.

## Using the image headlessly

The IDE is only the default command — pass your own and it runs headless (this
is how every gate runs):

```bash
# a known-answer digest through the driver seam, on a bare `docker run`
docker run --rm m-devbox:0.1.0-local \
  m vista exec --engine ydb --transport local 'write $$sha256^STDCRYPTO("abc")'

# run an MSL suite
docker run --rm m-devbox:0.1.0-local m test --engine ydb /opt/msl/tests/STDSTRTST.m
```

### Running as a non-root user

The image supports three shapes, and refuses a fourth **loudly** rather than
failing three layers down:

| Invocation | Result |
|---|---|
| default (root) | works |
| `--user devbox` (baked, uid 1000) | works |
| `--user <any-uid>:0` | works — the entrypoint adds the passwd entry |
| `--user <any-uid>:<non-zero-gid>` | **refuses, exit 78**, naming the fix |

Why gid 0 matters: the toolchain derives its run-lock home from `/etc/passwd`,
never `$HOME`, and fails closed — deliberately, so a divergent `$HOME` cannot
split the run-lock's serialization domain. A `CGO_ENABLED=0` binary reads
`/etc/passwd` with no NSS fallback, so a uid with no entry there refuses *every*
engine verb. The image therefore guarantees the entry: group 0 owns a
`g=u`-mode `/etc/passwd` (the standard arbitrary-uid container recipe) and
`scripts/entrypoint.sh` appends the row for whatever uid it is run as. For
VS Code Dev Containers the ordinary path is `remoteUser: devbox` with
`updateRemoteUserUID: true`, which keeps a real passwd entry throughout.

## What is in the image

| Layer | Basis |
|---|---|
| Debian trixie-slim | pinned by digest |
| YottaDB r2.06 | installed in-build by the project's own `ydbinstall.sh`, pinned by commit + `sha256sum -c` |
| 5 native callouts (`std_compress`, `std_crypto`, `std_csprng`, `std_fs`, `std_http`) | compiled during `docker build` by a throwaway gcc stage running `m callouts install`; no compiler ships in the final image |
| `m` + `m-ydb` | rebuilt from the local checkouts at stage time |
| MSL (source + suites) | copied from `m-stdlib` at stage time |

Measured sizes and the exact pins are in the
[image dossier](docs/design/image-dossier.md).

## How this repo is organised

```
Dockerfile              the image, pins in its header
scripts/stage-context.sh    assemble the ephemeral build context (sync-time)
scripts/entrypoint.sh       the arbitrary-uid passwd guarantee
scripts/verify-devbox.sh    the acceptance battery G1–G12 (driver seam only)
scripts/check-pins.sh       offline drift gate: header pins == build pins
examples/hello/             the baked starter project (MD-D2)
docs/design/image-dossier.md  measured contents, sizes, and the sweep baseline
```

Nothing is vendored. Every source lands in an **ephemeral** build context
assembled from the sibling repos — see [CLAUDE.md](CLAUDE.md) for why, and for
the sync-time / gate-time split that keeps the gate offline.

## The gate, and what is deliberately not gated

`make check` runs offline and includes the acceptance battery. `make sweep`
(the full MSL run) is a **measurement, not a gate**: 11 suites in
`STDS3MINIOTST` need a live MinIO service and fail without one, so the target
can never be green here. The expected numbers and how to read a change in them
are in the [image dossier](docs/design/image-dossier.md).

## License

AGPL-3.0-or-later with a commercial option — see [LICENSE](LICENSE) and
[NOTICE](NOTICE). The image assembles AGPL YottaDB and, from P2, public-domain
VA FileMan; the combined-work disposition is a prerequisite of publication, not
of building (tracker PR-17).
