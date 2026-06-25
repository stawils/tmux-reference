#!/usr/bin/env bash
# tmux-gen — portable tmux workspace command generator (zero deps, pure bash)
# Source: https://stawils.github.io/tmux-reference/generate.sh
# Mirrors the client-side generation logic of the tmux Workstation Builder.
#
# Usage:
#   generate.sh --name dev --path ~/proj --layout grid --detached 1 --panes "nvim .|cargo run|lazygit|cargo watch -x test"
#   generate.sh --layout side-by-side --panes "nvim .|zsh"
#
# Agents: curl this script, run it, read stdout. No browser, no Node, no Python needed.
set -euo pipefail

NAME="dev"
PATH_DIR="."            # default to current dir (always exists; agents should pass --path)
LAYOUT="side-by-side"
DETACHED=0              # default non-detached: one command drops you in (no attach step)
PANES=""
EXEC=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)     NAME="$2"; shift 2 ;;
    --path)     PATH_DIR="$2"; shift 2 ;;
    --layout)   LAYOUT="$2"; shift 2 ;;
    --detached) DETACHED="$2"; shift 2 ;;
    --panes)    PANES="$2"; shift 2 ;;
    --exec)     EXEC=1; shift ;;      # shell-command passthrough (100% reliable, no timing)
    -h|--help)
      sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

# ── resolve layout to index (mirrors resolveLayout in index.html) ──
resolve_layout() {
  local v="${1,,}"  # lowercase
  case "$v" in
    0|single|one|1pane)         echo 0 ;;
    1|side-by-side|sidebyside|2col|cols|horizontal|split-h) echo 1 ;;
    2|stacked|2row|rows|vertical|split-v)   echo 2 ;;
    3|main-side|main+side|mainside|main-vertical) echo 3 ;;
    4|grid|2x2|4grid|quad)      echo 4 ;;
    5|main-3|main+3|main3)      echo 5 ;;
    6|3col|3columns|cols3|three) echo 6 ;;
    7|custom|dyn|dynamic)       echo 7 ;;
    *) echo 1 ;;  # default
  esac
}

# ── geometry helpers are inline in split_spec/final_layout below ──

LID=$(resolve_layout "$LAYOUT")

# ── split panes into array ──
IFS='|' read -ra PANE_ARR <<< "$PANES"
# filter empties
PANES_CLEAN=()
for p in "${PANE_ARR[@]}"; do [[ -n "$p" ]] && PANES_CLEAN+=("$p")
done
N=${#PANES_CLEAN[@]}
[[ $N -eq 0 ]] && PANES_CLEAN=("zsh") && N=1

# ── quote session name/path if needed ──
quote_if_needed() {
  local s="$1"
  # quote if it contains spaces or shell metacharacters
  if [[ "$s" =~ [[:space:]] || "$s" == *[\<\>\;\|\&\(\)\{\}\$\`\'\"\#]* ]]; then
    # escape special chars inside double quotes
    s="${s//\\/\\\\}"
    s="${s//\$/\\\$}"
    s="${s//\`/\\\`}"
    s="${s//\"/\\\"}"
    echo "\"$s\""
  else
    echo "$s"
  fi
}
QNAME=$(quote_if_needed "$NAME")
QPATH=$(quote_if_needed "$PATH_DIR")

# ── safety check: warn loudly if --path doesn't exist (silent failures are worse than noise) ──
# (don't block — the user/agent may intend a relative path or a dir that will be created. Just warn.)
if [[ "$PATH_DIR" != "." && "$PATH_DIR" != "$PWD" ]]; then
  EXPANDED="${PATH_DIR/#\~/$HOME}"
  if [[ ! -d "$EXPANDED" ]]; then
    echo "# WARNING: --path '$PATH_DIR' does not exist. tmux -c will land panes in a broken cwd." >&2
    echo "#          Detect the real project dir (pwd, ls) or use --path . for the current directory." >&2
  fi
fi

# ── build command (base-index agnostic: never addresses panes by index) ──
# Two modes:
#   default (--exec off): send-keys to each pane's shell. Natural for humans
#     pasting into a live terminal; panes keep a shell after the command exits.
#   --exec: pass each command as the new-session/split-window argument so tmux
#     runs it AS the pane process. 100% reliable for programmatic/detached
#     launch (no prompt-readiness race). Tradeoff: pane closes when cmd exits.
OUT="tmux new-session"
if [[ "$DETACHED" =~ ^(1|true|yes|on)$ ]]; then
  OUT+=" -d"
  # give the detached window a real size so panes fit at creation time
  # (otherwise the default 80x24 silently hits 'no space for new pane' for 4+ panes).
  # on attach the client resizes anyway.
  OUT+=" -x 220 -y 56"
fi
OUT+=" -s $QNAME -c $QPATH"

# helper: single-quote-escape a command for safe embedding in send-keys '...' or exec '...'
# Canonical bash idiom: each literal ' becomes '"'"'
# (end single-quote, double-quoted literal quote, restart single-quote)
sq() { local s="$1"; s="${s//\'/\'\"\'\"\'}"; echo "$s"; }

# split spec per layout: one spec PER LINE, for panes 1..N-1.
# Each line is the full split-window options (e.g. "-h -p 38").
split_spec() {
  local lid=$1 n=$2
  case "$lid" in
    0) ;;                                              # single: no splits
    1) for ((i=1;i<n;i++)); do echo "-h"; done ;;      # side-by-side
    2) for ((i=1;i<n;i++)); do echo "-v"; done ;;      # stacked
    3) echo "-h -p 38"; for ((i=2;i<n;i++)); do echo "-h"; done ;;  # main-side
    4) for ((i=1;i<n;i++)); do echo "-v"; done ;;      # grid → select-layout tiled
    5) echo "-h -p 38"; for ((i=2;i<n;i++)); do echo "-v"; done ;;  # main-3 → main-vertical
    6) for ((i=1;i<n;i++)); do echo "-h"; done ;;      # 3 columns
    7) for ((i=1;i<n;i++)); do echo "-v"; done ;;      # custom
  esac
}
final_layout() {
  case "$1" in
    4) echo "tiled" ;;       # grid
    5) echo "main-vertical" ;; # main-3
    7) echo "tiled" ;;       # custom (n>=4: stacking is useless, tile instead)
    *) echo "" ;;
  esac
}

# ── pane 0: initial pane (active) ──
cmd0="${PANES_CLEAN[0]#"${PANES_CLEAN[0]%%[![:space:]]*}"}"  # ltrim
cmd0_sq=$(sq "$cmd0")
if [[ $EXEC -eq 1 ]]; then
  # exec mode: command becomes the new-session shell-command (accurate pane_current_command
  # so agents can verify each pane is running the expected app; a failed cmd closes the pane,
  # which shows up as a missing pane in tmux list-panes)
  [[ -n "$cmd0" ]] && OUT+=" '$cmd0_sq'"
else
  [[ -n "$cmd0" ]] && OUT+=" \\; send-keys '$cmd0_sq' Enter"
fi

# ── panes 1..N-1: split-window + (send-keys | shell-command) ──
mapfile -t SPECS < <(split_spec "$LID" "$N")
si=0
for cmd in "${PANES_CLEAN[@]:1}"; do
  dir="${SPECS[$si]:--v}"   # default -v if spec runs out (extra panes)
  si=$((si+1))
  cmd_trimmed="${cmd#"${cmd%%[![:space:]]*}"}"
  cmd_sq=$(sq "$cmd_trimmed")
  if [[ $EXEC -eq 1 ]]; then
    OUT+=" \\; split-window $dir -c \"#{pane_current_path}\""
    [[ -n "$cmd_trimmed" ]] && OUT+=" '$cmd_sq'"   # runs as pane process
  else
    OUT+=" \\; split-window $dir -c \"#{pane_current_path}\""
    [[ -n "$cmd_trimmed" ]] && OUT+=" \\; send-keys '$cmd_sq' Enter"
  fi
done

# ── final arrangement for grid / main shapes ──
FL=$(final_layout "$LID")
[[ -n "$FL" ]] && OUT+=" \\; select-layout $FL"

# ── output ──
echo "$OUT"
echo "# tmux attach -t $QNAME"
