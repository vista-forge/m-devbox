---
name: explicit-flags-in-a-gate-hide-broken-defaults
description: A gate that passes the flag explicitly cannot see a broken default — measured twice in this battery (G13 engine selector, G20 transport), so assert the BARE invocation a real user types
metadata:
  type: project
---

**A verification gate that spells out the flag is testing the flag, not the
default — and the default is what a real user gets.** Measured **twice** in this
repo's own battery, on two different inputs:

1. **PR-11 / G13 (engine).** Every gate passed `--engine ydb`, so the battery was
   green while a bare `m test` refused `ENGINE_UNRESOLVED`. Fixed by asserting
   the bare invocation + an `M_ENGINE=` negative control.
   ([[engine-selector-baked-and-gated]])
2. **PR-25 / G20 (transport), 2026-07-25.** G18 asserted the m-vscode status
   probe **with `--transport local`** — which was itself the *workaround* the
   extension shipped in v0.4.1. So G18 was green for three days while a bare
   `m engine status --engine ydb` in the same image still refused
   "remote transport needs a host." The gate was pinned to the workaround, so it
   could never see the defect the workaround was working around.

**Why it keeps happening here:** the battery is written by someone who knows the
invocation that works, and that knowledge leaks into the assertion. The devbox's
whole value proposition is *zero-config attach* — so every flag in a gate is a
small lie about what the image delivers.

**How to apply.** For any input with a default (engine, transport, namespace,
charset, container), the battery owes **two** assertions:
- the **bare** invocation a user actually types, with **no** flag; and
- a **negative control** that proves the resolution is real rather than
  re-hardcoded elsewhere — G13 unsets `M_ENGINE` and expects exit 4; G20 sets
  `M_YDB_TRANSPORT=remote` and expects the refusal, proving m-cli delegated to
  the driver instead of substituting a new hardcoded `local`.
An explicit-flag assertion may stay **beside** those as the override control
(G18's retained role) — never instead of them.

Corollary, and the reason this is worth its own file: **when a defect is closed
by a workaround in a consumer, the gate must still target the root path.** G18
was added by the same increment that shipped the m-vscode workaround, which is
precisely how it inherited the workaround's blind spot.

Ruling that closed the transport case:
[transport-resolution-on-invoke ADR](../../../docs/background/transport-resolution-on-invoke-adr.md).
See also [[degrade-loud-or-refuse]].
