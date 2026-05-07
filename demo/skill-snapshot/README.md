# Skill package snapshot

This directory contains the Robot Money skill package as it existed at the
time of the Phase 7 demo run.

Snapshot taken: 2026-05-07
Source: `plugins/robotmoney-cli/` at commit
`302493a` (feat/116 worktree initialization).

The canonical, living copy of the skill is at `plugins/robotmoney-cli/` in
the repo root. This snapshot exists so the demo can be reproduced at the
exact skill version used for the recorded artifacts in `demo/artifacts/`,
even if the skill is later updated.

## Contents

- `robotmoney-cli/plugin.json` — plugin manifest (name, version, skills list)
- `robotmoney-cli/skills/robotmoney-cli/SKILL.md` — agent-facing skill doc
- `robotmoney-cli/skills/robotmoney-cli/references/read.md` — read-command reference
- `robotmoney-cli/skills/robotmoney-cli/references/write.md` — write-command reference
- `robotmoney-cli/skills/robotmoney-cli/references/safety.md` — refusal cases
- `robotmoney-cli/skills/robotmoney-cli/references/examples.md` — command traces

## Loading into OpenClaw

Point OpenClaw at `demo/skill-snapshot/robotmoney-cli/` and at the rmpc
binary at `clients/rust-payment-client/target/debug/rmpc`.
