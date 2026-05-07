#!/usr/bin/env bash
# Canonical: docs/technical/demo-runbook.md §13 (artifact paths)
# Implements: implementation-plan §13 (Phase 7). Issue: #116.
#
# Hermetic check — no network, no fork, no rmpc binary required.
#
# Asserts:
#   1. All required demo artifact files are present.
#   2. The demo-runbook.md references each artifact path.
#   3. All five failure-case toggle commands are documented in the runbook.
#   4. The skill snapshot matches the canonical plugin directory structure.
#   5. The runbook documents the OpenClaw task prompt verbatim.
#   6. The runbook states that no explorer API or dapp is required.
#
# Exit codes:
#   0 — all checks passed
#   1 — one or more checks failed (error printed to stderr)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNBOOK="$REPO_ROOT/docs/technical/demo-runbook.md"
FAIL=0

err() { echo "FAIL: $*" >&2; FAIL=1; }
ok()  { echo "ok:   $*"; }

# --------------------------------------------------------------------
# 1. Required artifact files exist.
# --------------------------------------------------------------------
REQUIRED_FILES=(
  "demo/fork-config.toml"
  "demo/fork-metadata.json"
  "demo/openclaw-config.toml"
  "demo/rmpc-config-template.toml"
  "demo/skill-snapshot/README.md"
  "demo/skill-snapshot/robotmoney-cli/plugin.json"
  "demo/skill-snapshot/robotmoney-cli/skills/robotmoney-cli/SKILL.md"
  "demo/artifacts/read-trace.json"
  "demo/artifacts/deposit-trace.json"
  "demo/artifacts/status-trace.json"
  "demo/artifacts/final-report.json"
  "docs/technical/demo-runbook.md"
)

for f in "${REQUIRED_FILES[@]}"; do
  if [[ -f "$REPO_ROOT/$f" ]]; then
    ok "artifact present: $f"
  else
    err "artifact missing: $f"
  fi
done

# --------------------------------------------------------------------
# 2. Runbook references each artifact path.
# --------------------------------------------------------------------
ARTIFACT_REFS=(
  "demo/fork-config.toml"
  "demo/fork-metadata.json"
  "demo/rmpc-config-template.toml"
  "demo/artifacts/read-trace.json"
  "demo/artifacts/deposit-trace.json"
  "demo/artifacts/final-report.json"
)

for ref in "${ARTIFACT_REFS[@]}"; do
  if grep -q "$ref" "$RUNBOOK"; then
    ok "runbook references: $ref"
  else
    err "runbook does not reference: $ref"
  fi
done

# --------------------------------------------------------------------
# 3. All five failure-case toggle commands documented.
# --------------------------------------------------------------------
FAILURE_CASES=(
  "unauthorized agent"
  "Insufficient allowance"
  "Paused gateway"
  "Fee cap"
  "Code-hash mismatch"
)

for fc in "${FAILURE_CASES[@]}"; do
  if grep -qi "$fc" "$RUNBOOK"; then
    ok "failure case documented: $fc"
  else
    err "failure case missing from runbook: $fc"
  fi
done

# Check that ErrAgentNotAuthorized, ErrInsufficientAllowance,
# ErrGatewayPaused, ErrFeeCapExceeded, ErrCodeHashMismatch are mentioned.
ERROR_CODES=(
  "ErrAgentNotAuthorized"
  "ErrInsufficientAllowance"
  "ErrGatewayPaused"
  "ErrFeeCapExceeded"
  "ErrCodeHashMismatch"
)

for ec in "${ERROR_CODES[@]}"; do
  if grep -q "$ec" "$RUNBOOK"; then
    ok "error code documented: $ec"
  else
    err "error code missing from runbook: $ec"
  fi
done

# --------------------------------------------------------------------
# 4. Skill snapshot matches canonical plugin structure.
# --------------------------------------------------------------------
SKILL_CANONICAL="$REPO_ROOT/plugins/robotmoney-cli"
SKILL_SNAPSHOT="$REPO_ROOT/demo/skill-snapshot/robotmoney-cli"

if [[ -d "$SKILL_CANONICAL" && -d "$SKILL_SNAPSHOT" ]]; then
  # plugin.json must be present in both.
  if diff -q "$SKILL_CANONICAL/plugin.json" "$SKILL_SNAPSHOT/plugin.json" >/dev/null 2>&1; then
    ok "skill snapshot plugin.json matches canonical"
  else
    err "skill snapshot plugin.json differs from canonical (re-run: cp -r plugins/robotmoney-cli demo/skill-snapshot/)"
  fi
  ok "skill snapshot directory exists"
else
  [[ -d "$SKILL_CANONICAL" ]] || err "canonical plugin directory missing: $SKILL_CANONICAL"
  [[ -d "$SKILL_SNAPSHOT"  ]] || err "skill snapshot directory missing: $SKILL_SNAPSHOT"
fi

# --------------------------------------------------------------------
# 5. Verbatim task prompt documented.
# --------------------------------------------------------------------
if grep -q "100000000 in 6-decimal units" "$RUNBOOK"; then
  ok "verbatim task prompt present (6-decimal units specification found)"
else
  err "verbatim task prompt missing or incomplete (expected '100000000 in 6-decimal units')"
fi

# --------------------------------------------------------------------
# 6. Runbook states no explorer API or dapp required.
# --------------------------------------------------------------------
if grep -q "Phase 5 explorer API" "$RUNBOOK" && grep -q "Phase 6" "$RUNBOOK"; then
  ok "runbook explicitly excludes Phase 5 API and Phase 6 dapp"
else
  err "runbook does not explicitly state Phase 5 API / Phase 6 dapp are not required"
fi

if grep -q "explorer_api_used.*false" "$REPO_ROOT/demo/artifacts/final-report.json"; then
  ok "final-report.json confirms explorer_api_used=false"
else
  err "final-report.json missing or missing explorer_api_used=false"
fi

# --------------------------------------------------------------------
# Summary.
# --------------------------------------------------------------------
if [[ "$FAIL" -eq 0 ]]; then
  echo ""
  echo "All runbook artifact checks passed."
  exit 0
else
  echo ""
  echo "One or more checks failed — see FAIL lines above." >&2
  exit 1
fi
