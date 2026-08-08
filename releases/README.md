# Corresponding source bundles

**If you pulled the container image and want the source it was built from, it is
here.** One `.tar.gz` per released version, with a `.sha256` beside it.

```bash
sha256sum -c m-devbox-0.1.0-corresponding-source.tar.gz.sha256
tar -xzf m-devbox-0.1.0-corresponding-source.tar.gz
```

## Why this exists

The image ships AGPL-3.0-or-later software — YottaDB and vista-forge's own code
— so anyone who receives the image is entitled to the source it was built from.
Publishing it here, in the image's own public repository, is how that
obligation is met: no request to make, no address to write to, nothing to wait
for.

## What is inside

All **eleven** contributing repositories, each archived at the exact commit
the image was staged from, plus the pinned RSM engine source export
(`rsm-upstream/`), plus `COMMITS.txt` naming every one of those commits,
the `NOTICE` inventory, the `LICENSE`, and a README explaining what is *not*
included and where to get it.

Ten, not four, because the `m` and `m-ydb` binaries statically link `clikit`,
`m-driver-sdk` and `m-parse` — a binary's corresponding source includes its
dependencies'.

Deliberately not vendored here: YottaDB, VA FileMan, code-server, `git` and the
VS Code extensions. Each is pinned by version and checksum in the Dockerfile,
and the bundle's README points at each upstream.

## What makes it trustworthy

The correspondence is machine-checked rather than asserted. The bundle refuses
to be built at all if any repository has uncommitted changes, if any
repository's HEAD has moved since the image was staged, or if a dependency's
archived commit is not the version the binaries were compiled against. The
image's own acceptance battery re-checks the last of those against the shipped
binaries (gate G27), by reading the module versions Go embeds into them.

So: what is in this tarball is what is in that image, and both can be shown.
