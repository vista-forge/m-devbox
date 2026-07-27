# m-devbox — the portable, container-delivered M development environment.
#
# Two clocks, deliberately separated (org de-GitHub rules 1 and 5):
#
#   SYNC TIME (network allowed, deliberate, never automatic)
#       make stage   assemble the build context (fetch the pinned ydbinstall.sh
#                    once, rebuild `m`/`m-ydb` from the local checkouts)
#       make build   stage + docker build from the pins
#       make archive add the built image to the org's engine-image archive
#
#   GATE TIME (OFFLINE — never a pull, never apt, never a fetch)
#       make check   the gate: pin drift + waterline + docs + shell syntax +
#                    the full acceptance battery against the BUILT image
#       make verify  the acceptance battery alone
#       make load    restore the image from the archive (the recovery path —
#                    the archive, not a rebuild, is how this image comes back)
#
# `make check` needs the image PRESENT but never fetches it: if it is missing,
# `make load` restores it offline from ~/data/vista-forge/images. That is the
# whole point of rule 5 — the archive is the recovery path.
#
# Engine access is ONLY through the driver stack (`m` / `m-ydb`). Raw
# `docker exec` into an engine is forbidden org-wide and harness-denied; the
# `docker run`s below launch the IMAGE UNDER TEST and then talk to it through
# `m vista exec` / `m test`, which is the sanctioned seam.

IMAGE   ?= m-devbox:0.1.0-local
CTX     ?= $(CURDIR)/.build-context
ARCHIVE ?= $(HOME)/data/vista-forge/images

.PHONY: help stage build rebuild verify sweep check arch-check docs-gate shell-gate pins archive publish source-bundle load clean mac-connect build-arm64 verify-arm64

help: ## Show this help
	@grep -hE '^[a-zA-Z0-9_.-]+:.*##' $(MAKEFILE_LIST) | sort | \
	  awk 'BEGIN{FS=":.*##"}{printf "  \033[36m%-12s\033[0m %s\n",$$1,$$2}'

# ── sync time (network) ─────────────────────────────────────────────────────

ARCH        ?= amd64
IMAGE_ARM64 ?= m-devbox:0.1.0-local-arm64

# Remote arm64 builder. The image build RUNS the engine (GDE, mupip create,
# `m lib install`, FileMan DINIT), and YottaDB refuses to verify itself under
# qemu (YDBDISTUNVERIF), so an emulated arm64 build produces no image at all —
# it must be built on real Apple Silicon. The Mac's Docker daemon is reached
# over Tailscale by forwarding its socket, which avoids needing `docker` on the
# Mac's non-interactive PATH (Docker's own ssh:// helper does).
MAC_HOST ?= rafael@100.107.77.10
MAC_SOCK ?= $(CURDIR)/.mac-docker.sock
MAC_REMOTE_SOCK ?= /Users/rafael/.docker/run/docker.sock

stage: ## SYNC-TIME: assemble the build context (pinned fetch + rebuild m/m-ydb at HEAD)
	scripts/stage-context.sh "$(CTX)" "$(ARCH)"

build: stage ## SYNC-TIME: stage + docker build the image from the pins
	docker build -t "$(IMAGE)" "$(CTX)"
	@docker image inspect --format 'built: $(IMAGE) {{.Id}} ({{.Size}} bytes)' "$(IMAGE)"

mac-connect: ## Open the forwarded socket to the Apple Silicon build host
	@if [ -S "$(MAC_SOCK)" ] && DOCKER_HOST="unix://$(MAC_SOCK)" docker version >/dev/null 2>&1; then \
	  echo "mac: already connected"; \
	else \
	  rm -f "$(MAC_SOCK)"; \
	  ssh -o BatchMode=yes -o ExitOnForwardFailure=yes -fnNT \
	    -L "$(MAC_SOCK):$(MAC_REMOTE_SOCK)" "$(MAC_HOST)" || \
	    { echo "mac-connect: ssh forward failed (is Remote Login on?)"; exit 1; }; \
	fi
	@DOCKER_HOST="unix://$(MAC_SOCK)" docker version \
	  --format 'mac builder: {{.Server.Os}}/{{.Server.Arch}} docker {{.Server.Version}}'

build-arm64: mac-connect ## SYNC-TIME: stage arm64 + build NATIVELY on the Apple Silicon host
	scripts/stage-context.sh "$(CTX)" arm64
	DOCKER_HOST="unix://$(MAC_SOCK)" docker build --platform linux/arm64 -t "$(IMAGE_ARM64)" "$(CTX)"
	@DOCKER_HOST="unix://$(MAC_SOCK)" docker image inspect \
	  --format 'built: $(IMAGE_ARM64) {{.Id}} ({{.Architecture}}, {{.Size}} bytes)' "$(IMAGE_ARM64)"

verify-arm64: mac-connect ## OFFLINE: run the acceptance battery against the arm64 image on the Mac
	DOCKER_HOST="unix://$(MAC_SOCK)" scripts/verify-devbox.sh "$(IMAGE_ARM64)"

rebuild: stage ## SYNC-TIME: --no-cache rebuild (the PR-4 reproducibility check)
	docker build --no-cache -t "$(IMAGE)" "$(CTX)"

archive: ## SYNC-TIME-ish: fold the image into the org engine-image archive (change-detected)
	bash ../.github/scripts/engine-image-archive.sh

# ── gate time (offline) ─────────────────────────────────────────────────────

# The gate. Engine-free gates first (they are fast and catch the boring
# breakage), then the acceptance battery against the built image.
check: pins arch-check docs-gate shell-gate verify ## OFFLINE gate: pins + waterline + docs + shell + acceptance battery

pins: ## Offline: Dockerfile header pins == what the build/staging path uses
	bash scripts/check-pins.sh

arch-check: ## Offline: m/v waterline + repo.meta.json shape
	@command -v m >/dev/null 2>&1 \
	  && m arch check . \
	  || { echo "arch-check: FAILED — 'm' is not on PATH; the waterline gate cannot run (fix: workspace/scripts/link-tools.sh)"; exit 1; }

docs-gate: ## Offline: docs link + layout gate
	python3 ../.github/scripts/link-check.py docs README.md CLAUDE.md
	python3 ../.github/scripts/layout-check.py docs

# Every shipped script, wherever it lives: scripts/ AND the scripts baked into
# examples/ (lib-demo's tour is run by users and by G22 — it is shipped code).
SHELL_SOURCES := $(wildcard scripts/*.sh) $(wildcard examples/*/*.sh)

shell-gate: ## Offline: syntax-check every shipped shell script (bash -n floor, + shellcheck when present)
	@set -e; for f in $(SHELL_SOURCES); do bash -n "$$f"; done; \
	  echo "bash -n: clean ($(words $(SHELL_SOURCES)) scripts)"
	@sh -n scripts/entrypoint.sh && echo "sh -n: entrypoint.sh clean (it runs under /bin/sh, not bash)"
	@if command -v shellcheck >/dev/null 2>&1; then \
	  shellcheck -x $(SHELL_SOURCES) && echo "shellcheck: clean"; \
	else \
	  echo "shellcheck: not installed — the bash -n floor above ran instead (apt install shellcheck to add it)"; \
	fi

verify: ## Offline: the acceptance battery against the built image (driver seam only)
	scripts/verify-devbox.sh "$(IMAGE)"

sweep: ## Offline: the FULL MSL suite sweep on the image (a measurement, not a gate — see README)
	docker run --rm "$(IMAGE)" m test --engine ydb /opt/msl/tests

# ── publication (sync-time, GATED — see the refusal below) ──────────────────
# Strategy: we publish the ARTIFACT, not the build. The image is produced here
# by the pinned, gated `make build` and pushed as-is, so what a stranger runs is
# exactly what G1–G24 verified. Docker Hub does NOT build this repo (it cannot —
# nothing is vendored, and five sibling repos are private).
#
# `publish` REFUSES until the publication prerequisites are ruled, because a
# push is irreversible in practice: the digest is public the moment it lands.
# CHANNEL: docker.io/rafaelrichards — the owner's PERSONAL Docker Hub namespace
# (ruled 2026-07-27). Docker Hub's free tier no longer covers ORGANIZATIONS, but
# a free personal account still allows unlimited PUBLIC repositories. The
# username is FIXED and cannot be changed, so the namespace does NOT carry the
# vista-forge identity — the IMAGE does instead, via OCI labels
# (org.opencontainers.image.vendor/source/licenses; see the Dockerfile). A
# consumer runs `docker inspect` and learns who published it and where the
# source lives, regardless of whose namespace it sits in. Nothing else about the
# 2026-07-21 channel ruling changes: same registry, same install-time argument,
# no new vendor, no rule to overturn.
#
#   PR-15  VA licence posture — ✅ CLOSED 2026-07-26 (FileMan measured Apache-2.0)
#   PR-17  combined-work disposition — ✅ RULED 2026-07-26
#   PR-16  credentials not yet in ~/data/vista-forge/auth.env (never a forge
#          secret store), and no first push recorded — THE LAST BLOCKER
# Clear it, then set PUBLISH_OK=1 for the run that actually pushes.
#
# MULTI-ARCH. amd64 builds here; arm64 builds natively on Apple Silicon over
# Tailscale (see build-arm64 — qemu cannot run the engine, so emulation is not
# an option). Each daemon pushes its own native image under an arch-suffixed
# tag, then `buildx imagetools create` joins them into one manifest list, so a
# user's `docker pull` resolves the right architecture with no flag.
#
# NO `latest` TAG, deliberately. A mutable tag is how this org lost a working
# IRIS image ([[iris-community-hub-rebuild-breaks-boot]]): `latest` moved under
# it and the only good copy survived by luck. Publish immutable version tags and
# let consumers pin a digest, which this target prints after the push.
REGISTRY ?= docker.io/rafaelrichards
PUBLISH_TAG ?= 0.1.0

publish: ## SYNC-TIME: push BOTH arches + a multi-arch manifest (REFUSES without PUBLISH_OK=1)
	@if [ "$(PUBLISH_OK)" != "1" ]; then \
	  echo "publish: REFUSED — this is a one-way door, so it needs PUBLISH_OK=1."; \
	  echo "  PR-15 VA licence posture ............. OK  closed 2026-07-26"; \
	  echo "  PR-17 combined-work disposition ...... OK  ruled  2026-07-26"; \
	  echo "  PR-16 $(REGISTRY) org ......... register + creds in auth.env"; \
	  echo "  target: $(REGISTRY)/m-devbox:$(PUBLISH_TAG)  (linux/amd64 + linux/arm64, no 'latest')"; \
	  echo "  When ready: make publish PUBLISH_OK=1"; \
	  exit 2; \
	fi
	@docker image inspect "$(IMAGE)" >/dev/null 2>&1 || { echo "publish: no local amd64 image $(IMAGE) — run 'make build'"; exit 1; }
	@# Login check reads what `docker login` ACTUALLY writes, not `docker info`.
	@# Measured 2026-07-27: this Docker has NO .Username field in `docker info`
	@# — the template errors — so the old check refused even a valid login. A
	@# gate that cannot pass is not a gate, it is an outage waiting for a
	@# deadline. Credential HELPERS store the secret outside config.json, so a
	@# configured helper counts as authenticated too.
	@python3 -c "import json,os,sys;\
	p=os.path.expanduser('~/.docker/config.json');\
	d=json.load(open(p)) if os.path.exists(p) else {};\
	reg=sys.argv[1].split('/')[0];\
	key='https://index.docker.io/v1/' if reg=='docker.io' else reg;\
	a=d.get('auths',{}).get(key,{});\
	ok=bool(a.get('auth')) or bool(d.get('credsStore')) or bool(d.get('credHelpers',{}).get(key));\
	print('publish: authenticated for '+key) if ok else sys.exit(1)" "$(REGISTRY)" || { \
	   echo "publish: REFUSED — no Docker credentials for $(REGISTRY)."; \
	   echo "  echo \"\$$DOCKERHUB_TOKEN\" | docker login -u \"\$$DOCKERHUB_USER\" --password-stdin"; \
	   echo "  (both come from ~/data/vista-forge/auth.env via direnv — never a forge secret store)"; \
	   exit 3; \
	 }
	@$(MAKE) --no-print-directory mac-connect
	@DOCKER_HOST="unix://$(MAC_SOCK)" docker image inspect "$(IMAGE_ARM64)" >/dev/null 2>&1 || \
	  { echo "publish: no arm64 image on the Mac — run 'make build-arm64'"; exit 1; }
	@echo "publish: re-verifying BOTH images before either leaves this machine"
	scripts/verify-devbox.sh "$(IMAGE)"
	DOCKER_HOST="unix://$(MAC_SOCK)" scripts/verify-devbox.sh "$(IMAGE_ARM64)"
	@echo "publish: pushing per-arch tags (each daemon pushes its own native image)"
	docker tag "$(IMAGE)" "$(REGISTRY)/m-devbox:$(PUBLISH_TAG)-amd64"
	docker push "$(REGISTRY)/m-devbox:$(PUBLISH_TAG)-amd64"
	DOCKER_HOST="unix://$(MAC_SOCK)" docker tag "$(IMAGE_ARM64)" "$(REGISTRY)/m-devbox:$(PUBLISH_TAG)-arm64"
	DOCKER_HOST="unix://$(MAC_SOCK)" docker push "$(REGISTRY)/m-devbox:$(PUBLISH_TAG)-arm64"
	@echo "publish: joining both under one tag so 'docker pull' resolves per-arch"
	docker buildx imagetools create -t "$(REGISTRY)/m-devbox:$(PUBLISH_TAG)" \
	  "$(REGISTRY)/m-devbox:$(PUBLISH_TAG)-amd64" "$(REGISTRY)/m-devbox:$(PUBLISH_TAG)-arm64"
	@echo
	@echo "published: $(REGISTRY)/m-devbox:$(PUBLISH_TAG)"
	@docker buildx imagetools inspect "$(REGISTRY)/m-devbox:$(PUBLISH_TAG)" \
	  --format '{{range .Manifest.Manifests}}  {{.Platform.OS}}/{{.Platform.Architecture}}  {{.Digest}}{{println}}{{end}}' 2>/dev/null || true
	@echo "RECORD the digest above, then bind the source bundle to it:"
	@echo "    make source-bundle DIGEST=<digest>"

source-bundle: ## Corresponding source for the published image (AGPL duty; refuses on dirt or skew)
	bash scripts/source-bundle.sh --image "$(IMAGE)" --tag "$(PUBLISH_TAG)" $(if $(DIGEST),--digest "$(DIGEST)",)

load: ## Offline: restore $(IMAGE) from the org engine-image archive (rule 5 recovery path)
	@f="$(ARCHIVE)/$$(printf '%s' '$(IMAGE)' | tr '/:' '__').tar.zst"; \
	 [ -f "$$f" ] || { echo "load: FAILED — no archived image at $$f (run: make build archive)"; exit 1; }; \
	 echo "loading $$f"; zstd -dc "$$f" | docker load

clean: ## Remove the staged build context
	rm -rf "$(CTX)"
