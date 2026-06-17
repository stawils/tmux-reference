#!/usr/bin/env bash
# test_generate.sh — regression tests for generate.sh quoting and structure
#
# Tests are split into two categories:
# 1. STRUCTURAL: output shape is valid (starts with tmux, has separators, balanced quotes)
# 2. ROUND-TRIP (definitive): sq() output, when eval'd inside single quotes,
#    reconstructs the original input exactly. This is the only honest correctness test.
#
# Usage: bash test_generate.sh
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/generate.sh"
PASS=0 FAIL=0

GREEN='\033[0;32m'
RED='\033[0;31m'
RESET='\033[0m'

# ── helpers ──
pass() { printf "${GREEN}  ✔${RESET} %s\n" "$1"; PASS=$((PASS + 1)); }
fail() { printf "${RED}  ✗${RESET} %s\n" "$1"; FAIL=$((FAIL + 1)); }

assert_contains() {
  local label="$1" haystack="$2" needle="$3"
  [[ "$haystack" == *"$needle"* ]] \
    && pass "$label" \
    || fail "$label — expected substring: $needle"
}

assert_not_contains() {
  local label="$1" haystack="$2" needle="$3"
  [[ "$haystack" != *"$needle"* ]] \
    && pass "$label" \
    || fail "$label — should NOT contain: $needle"
}

# Replicate the canonical sq() from generate.sh for independent testing.
sq() { local s="$1"; s="${s//\'/\'\"\'\"\'}"; printf '%s' "$s"; }

# Definitive round-trip: eval the escaped string inside single quotes
# and verify it reconstructs the original input.
assert_sq_roundtrip() {
  local label="$1" input="$2"
  local escaped roundtrip
  escaped=$(sq "$input")
  # Wrap in single quotes and eval — if quoting is wrong, this fails
  eval "roundtrip='$escaped'" 2>/dev/null || {
    fail "$label — eval FAILED on escaped output (unparseable quoting)"
    return
  }
  if [[ "$roundtrip" == "$input" ]]; then
    pass "$label"
  else
    fail "$label — mismatch: got '$roundtrip', expected '$input'"
  fi
}

# Verify the generated output contains the expected escaped command string
# (proves sq() is wired in, not just defined).
assert_output_contains_escaped() {
  local label="$1" output="$2" input="$3"
  local escaped
  escaped=$(sq "$input")
  [[ "$output" == *"'$escaped'"* ]] \
    && pass "$label" \
    || fail "$label — output missing properly escaped form of '$input'"
}

assert_balanced_single_quotes() {
  local label="$1" output="$2"
  local body
  body=$(printf '%s\n' "$output" | grep -v '^# tmux attach')
  local count
  count=$(printf '%s' "$body" | tr -cd "'" | wc -c)
  [[ $((count % 2)) -eq 0 ]] \
    && pass "$label (even quote count: $count)" \
    || fail "$label (ODD quote count: $count — unbalanced!)"
}

assert_starts_with_tmux() {
  local label="$1" output="$2"
  local body
  body=$(printf '%s\n' "$output" | grep -v '^# tmux attach')
  [[ "$body" == tmux* ]] \
    && pass "$label" \
    || fail "$label — output does not start with 'tmux'"
}

assert_has_tmux_separators() {
  local label="$1" output="$2"
  printf '%s' "$output" | grep -qF '\;' \
    && pass "$label" \
    || fail "$label — missing tmux \\; separators"
}

# ── sq() round-trip: independent unit tests ──
echo "=== sq() round-trip unit tests ==="
echo ""

assert_sq_roundtrip "plain command" "echo hi"
assert_sq_roundtrip "embedded single quote" "cargo watch -x 'test --nocapture'"
assert_sq_roundtrip "double quotes" 'echo "hello world"'
assert_sq_roundtrip "semicolon" "echo a; echo b"
assert_sq_roundtrip "backslash" "echo path\\to\\file"
assert_sq_roundtrip "single quote only" "echo 'it works'"
assert_sq_roundtrip "nested single quotes" "cargo watch -x 'test -- --nocapture'"
assert_sq_roundtrip "no quotes" "nvim ."
assert_sq_roundtrip "empty string" ""
echo ""

# ── adversarial: prove tests catch a broken sq() ──
echo "Test: adversarial — known-bad sq() must FAIL round-trip"
(
  sq_bad() { local s="$1"; s="${s//\\/\\\\}"; s="${s//\'/\\\'\"\'\'\"}"; printf '%s' "$s"; }
  INPUT="cargo watch -x 'test'"
  escaped=$(sq_bad "$INPUT")
  eval "roundtrip='$escaped'" 2>/dev/null && {
    if [[ "$roundtrip" == "$INPUT" ]]; then
      printf "${RED}  ✗${RESET} adversarial FAILED — bad sq() passed (test is broken)\n"
      FAIL=$((FAIL + 1))
    else
      printf "${GREEN}  ✔${RESET} adversarial: bad sq() detected (mismatch)\n"
      PASS=$((PASS + 1))
    fi
  } || {
    printf "${GREEN}  ✔${RESET} adversarial: bad sq() detected (eval failed)\n"
    PASS=$((PASS + 1))
  }
)
echo ""

# ── integration: generated output contains correct escaped forms ──
echo "=== integration: output containment + structure ==="
echo ""

# T1: the original bug — embedded single quote
T1=$(bash "$SCRIPT" --name t --layout even-horizontal \
  --panes "echo hi|cargo watch -x 'test --nocapture'")
echo "Test: T1 embedded single quote"
assert_output_contains_escaped "pane 0 in output" "$T1" "echo hi"
assert_output_contains_escaped "pane 1 in output" "$T1" "cargo watch -x 'test --nocapture'"
assert_not_contains "no raw 6-quote danger" "$T1" "send-keys 'cargo watch -x 'test"
assert_balanced_single_quotes "balanced quotes" "$T1"
assert_starts_with_tmux "starts with tmux" "$T1"
assert_has_tmux_separators "has \\; separators" "$T1"
echo ""

# T1b: --exec mode
T1E=$(bash "$SCRIPT" --name t --layout even-horizontal --exec \
  --panes "echo hi|cargo watch -x 'test --nocapture'")
echo "Test: T1 --exec mode"
assert_output_contains_escaped "pane 0 in exec output" "$T1E" "echo hi"
assert_output_contains_escaped "pane 1 in exec output" "$T1E" "cargo watch -x 'test --nocapture'"
assert_balanced_single_quotes "balanced quotes" "$T1E"
echo ""

# T2: double quotes
T2=$(bash "$SCRIPT" --name t --layout side-by-side \
  --panes 'echo "hello world"|zsh')
echo "Test: T2 double quotes"
assert_output_contains_escaped "pane 0 in output" "$T2" 'echo "hello world"'
assert_output_contains_escaped "pane 1 in output" "$T2" "zsh"
echo ""

# T3: semicolon
T3=$(bash "$SCRIPT" --name t --layout side-by-side \
  --panes 'echo a; echo b|zsh')
echo "Test: T3 semicolon"
assert_output_contains_escaped "pane 0 in output" "$T3" "echo a; echo b"
echo ""

# T4: backslash
T4=$(bash "$SCRIPT" --name t --layout side-by-side \
  --panes 'echo path\to\file|zsh')
echo "Test: T4 backslash"
assert_output_contains_escaped "pane 0 in output" "$T4" "echo path\\to\\file"
echo ""

# T5: empty panes
T5=$(bash "$SCRIPT" --name t --layout grid --panes '|')
echo "Test: T5 empty panes fallback"
assert_starts_with_tmux "starts with tmux" "$T5"
assert_has_tmux_separators "has \\; separators" "$T5"
echo ""

# T6: 4-pane mixed
T6=$(bash "$SCRIPT" --name t --layout grid \
  --panes "nvim .|cargo watch -x 'test -- --nocapture'|echo it\\\\s ok|lazygit")
echo "Test: T6 4-pane mixed"
assert_output_contains_escaped "pane 1 escaped" "$T6" "cargo watch -x 'test -- --nocapture'"
assert_output_contains_escaped "pane 3 escaped" "$T6" "lazygit"
echo ""

# T7: exec with quotes
T7=$(bash "$SCRIPT" --name t --layout side-by-side --exec \
  --panes "echo 'hello'|cargo run")
echo "Test: T7 --exec quotes"
assert_output_contains_escaped "pane 0 in exec" "$T7" "echo 'hello'"
assert_output_contains_escaped "pane 1 in exec" "$T7" "cargo run"
echo ""

# T8: spaced session name
T8=$(bash "$SCRIPT" --name "my dev" --layout single --panes "zsh")
echo "Test: T8 spaced session name"
assert_contains "session name quoted" "$T8" '"my dev"'
echo ""

# T9: 4-pane plain
T9=$(bash "$SCRIPT" --name dev --layout grid \
  --panes "nvim .|cargo run|lazygit|cargo watch -x test")
echo "Test: T9 plain 4-pane"
assert_output_contains_escaped "pane 0" "$T9" "nvim ."
assert_output_contains_escaped "pane 1" "$T9" "cargo run"
assert_output_contains_escaped "pane 2" "$T9" "lazygit"
assert_output_contains_escaped "pane 3" "$T9" "cargo watch -x test"
echo ""

# T10: single pane with quotes
T10=$(bash "$SCRIPT" --name t --layout single --panes "echo 'it works'")
echo "Test: T10 single pane quotes"
assert_output_contains_escaped "pane 0" "$T10" "echo 'it works'"
echo ""

# ── summary ──
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
