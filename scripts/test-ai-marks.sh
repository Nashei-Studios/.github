#!/usr/bin/env bash
# Tests the AI-mark detector of the pr-gate workflow. The detector is extracted from the workflow
# itself (between the ai-marks:begin/end markers), so the test cannot drift from what runs in CI.
set -euo pipefail

workflow="$(dirname "$0")/../.github/workflows/pr-gate.yml"
eval "$(sed -n '/# ai-marks:begin/,/# ai-marks:end/p' "$workflow")"

failures=0
expect() { # expect <fail|pass> <label> <message>
  local want="$1" label="$2" msg="$3" got=pass
  printf '%s\n' "$msg" | ai_marks > /dev/null || got=fail
  if [ "$got" = "$want" ]; then echo "ok   $label"; else echo "FAIL $label (wanted $want, got $got)"; failures=$((failures + 1)); fi
}

expect fail "Co-Authored-By of Claude"      $'feat: x\n\nCo-Authored-By: Claude <noreply@anthropic.com>'
expect fail "Co-Authored-By of Codex"       $'feat: x\n\nCo-authored-by: Codex <codex@openai.com>'
expect fail "Claude-Session trailer"        $'feat: x\n\nClaude-Session: https://claude.ai/code/session_x'
expect fail "claude.ai session link"        'Details at https://claude.ai/code/session_abc123'
expect fail "Generated with Claude Code"    $'## Summary\n\n\🤖 Generated with Claude Code'
expect fail "Generated with [Claude Code]"  'Generated with [Claude Code](https://claude.com/claude-code)'
expect fail "robot emoji alone"             $'fix: x\n\n\🤖'
expect pass "Co-Authored-By of a person"    $'feat: x\n\nCo-Authored-By: Leon <leon@example.com>'
expect pass "plain message"                 $'fix(ui): align the shop buttons\n\nCloses #12'
expect pass "mentions Claude without mark"  'docs: explain how Claude Code reads CLAUDE.md'

if [ "$failures" -eq 0 ]; then echo "all cases passed"; else echo "$failures case(s) failed"; exit 1; fi
