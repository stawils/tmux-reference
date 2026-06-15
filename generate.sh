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
PATH_DIR="~/workspaces/project"
LAYOUT="side-by-side"
DETACHED=1
PANES=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)     NAME="$2"; shift 2 ;;
    --path)     PATH_DIR="$2"; shift 2 ;;
    --layout)   LAYOUT="$2"; shift 2 ;;
    --detached) DETACHED="$2"; shift 2 ;;
    --panes)    PANES="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,9p' "$0"; exit 0 ;;
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
    echo "\"$s\""
  else
    echo "$s"
  fi
}
QNAME=$(quote_if_needed "$NAME")
QPATH=$(quote_if_needed "$PATH_DIR")

# ── build command (base-index agnostic: never addresses panes by index) ──
# Strategy: send cmd0 to the initial pane, then for each additional pane do
# split-window + send-keys to the now-active new pane. For grid/main shapes,
# finish with select-layout. No select-pane -t N / send-keys -t N anywhere,
# so it works under base-index 0 OR 1.
OUT="tmux new-session"
[[ "$DETACHED" =~ ^(1|true|yes|on)$ ]] && OUT+=" -d"
OUT+=" -s $QNAME -c $QPATH"

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
    *) echo "" ;;
  esac
}

# ── send cmd0 to the initial pane (active) ──
first=1
for cmd in "${PANES_CLEAN[@]}"; do
  cmd_trimmed="${cmd#"${cmd%%[![:space:]]*}"}"  # ltrim
  if [[ $first -eq 1 ]]; then
    [[ -n "$cmd_trimmed" ]] && OUT+=" \\; send-keys '$cmd_trimmed' Enter"
    first=0
  fi
done

# ── split + send each remaining pane to the active pane ──
mapfile -t SPECS < <(split_spec "$LID" "$N")
si=0
for cmd in "${PANES_CLEAN[@]:1}"; do
  dir="${SPECS[$si]:--v}"   # default -v if spec runs out (extra panes)
  si=$((si+1))
  OUT+=" \\; split-window $dir -c \"#{pane_current_path}\""
  cmd_trimmed="${cmd#"${cmd%%[![:space:]]*}"}"
  [[ -n "$cmd_trimmed" ]] && OUT+=" \\; send-keys '$cmd_trimmed' Enter"
done

# ── final arrangement for grid / main shapes ──
FL=$(final_layout "$LID")
[[ -n "$FL" ]] && OUT+=" \\; select-layout $FL"

# ── output ──
echo "$OUT"
echo "# tmux attach -t $QNAME"
