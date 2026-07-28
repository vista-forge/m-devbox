# Releasing a new version

The order matters, and not for taste: `source-bundle` refuses if the tree is
dirty or if the image was staged from commits that have since moved, so
building before committing produces a release whose corresponding source cannot
be certified. Work down the list.

Substitute the new version for `0.2.0` throughout.

## 1. Commit first

```bash
git status --short          # must be clean, here and in every sibling repo
```

Every repository that feeds the image — `m-cli`, `m-ydb`, `m-stdlib`,
`f-stdlib`, `m-vscode`, `fileman`, plus `clikit`, `m-driver-sdk`, `m-parse` —
must be committed *before* the build, because the bundle records the commit each
one was staged from. A dirty tree at build time yields an image whose source
cannot be shown, only asserted.

## 2. Build and gate both architectures

```bash
make build                            # amd64, here
make check                            # G1–G27 offline, against that image
make build-arm64                      # arm64, natively on the Apple Silicon host
make verify-arm64                     # the same battery, there
```

`build-arm64` needs the remote host reachable: Tailscale up, Remote Login on,
Docker running. `make mac-connect` on its own reports whether it is.

Emulation is not an option — the build runs the engine, and YottaDB refuses to
verify itself under qemu.

## 3. Publish

```bash
echo "$DOCKERHUB_TOKEN" | docker login -u "$DOCKERHUB_USER" --password-stdin
make publish PUBLISH_OK=1 PUBLISH_TAG=0.2.0
```

Credentials come from `~/data/vista-forge/auth.env` via direnv. `publish`
re-verifies **both** images, pushes each from its own daemon, joins them into
one manifest, moves `latest`, and prints the digest. It refuses without
`PUBLISH_OK=1`, and again without a login — both before anything is tagged.

**Record the digest it prints.**

## 4. Corresponding source (AGPL — not optional)

```bash
make source-bundle PUBLISH_TAG=0.2.0 DIGEST=sha256:<the digest from step 3>
cp ~/data/vista-forge/source-bundles/m-devbox-0.2.0-*.tar.gz* releases/
git add releases/ && git commit && git push
```

The bundle refuses unless every repo is committed and matches what the image was
staged from. If it refuses, the release is not reproducible — fix that rather
than passing `--allow-dirty`, which stamps the bundle NON-CORRESPONDING.

## 5. Archive both architectures

```bash
make archive                                  # amd64, via the org script
DOCKER_HOST="unix://$PWD/.mac-docker.sock" \
  docker save m-devbox:0.2.0-local-arm64 \
  | zstd -T0 -3 -q -o ~/data/vista-forge/images/m-devbox_0.2.0-local-arm64.tar.zst
```

The arm64 save is manual: the org archive script only saves images on the *local*
daemon. Write an `.id` file beside it recording the image ID, or the archive
silently goes stale on the next arm64 build.

## 6. Update the Docker Hub page

```bash
scripts/hub-page.sh                 # both fields, labelled
scripts/hub-page.sh --body | xclip -selection clipboard
```

This step is manual because it has to be: a Docker Hub personal access token
authorises push and pull but **not** the management API — `PATCH` on the
repository returns `403 insufficient scope`. Editing the description needs a
password-derived session, so no token you can safely script with will do it.

## 7. Tracker

Record the release in `docs/proposals/m-devbox/m-devbox-prerequisites-remediation-tracker.md`
(in the `docs` repo): version, both platform digests, and anything the release
surfaced.

---

## If something refuses

| Refusal | Meaning |
|---|---|
| `publish: REFUSED … needs PUBLISH_OK=1` | working as designed; a push is one-way |
| `publish: REFUSED — no Docker credentials` | `auth.env` not loaded, or not logged in |
| `source-bundle: REFUSED — uncommitted changes` | commit, then rebuild, then bundle |
| `source-bundle: REFUSED — would not correspond` | the image predates your commits; `make build` again |
| `stage: REFUSED — build context holds files this script did not stage` | leftovers from an older layout; `make clean && make stage` |
| `stage: PIN VIOLATION` | a binary was not built from its committed pins |
| `check-docs-sync: DRIFT` | README and the Hub page disagree; edit both |
