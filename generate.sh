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

# ── layout geometry ──
layout_cols() {
  case "$1" in 0) echo 1;; 1) echo 2;; 2) echo 1;; 3) echo 2;; 4) echo 2;; 5) echo 2;; 6) echo 3;; 7) echo 0;; esac
}
layout_rows() {
  case "$1" in 0) echo 1;; 1) echo 1;; 2) echo 2;; 3) echo 1;; 4) echo 2;; 5) echo 2;; 6) echo 1;; 7) echo 0;; esac
}
layout_panes() {
  case "$1" in 0) echo 1;; 1) echo 2;; 2) echo 2;; 3) echo 2;; 4) echo 4;; 5) echo 4;; 6) echo 3;; 7) echo 0;; esac
}
layout_ratio() {  # only main-side / main-3 have a ratio
  case "$1" in 3|5) echo 62;; *) echo 0;; esac
}

LID=$(resolve_layout "$LAYOUT")
COLS=$(layout_cols "$LID")
ROWS=$(layout_rows "$LID")
DEFAULT_PANES=$(layout_panes "$LID")
RATIO=$(layout_ratio "$LID")

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

# ── build command ──
OUT="tmux new-session"
[[ "$DETACHED" =~ ^(1|true|yes|on)$ ]] && OUT+=" -d"
OUT+=" -s $QNAME -c $QPATH"

build_splits() {
  local lid=$1 cols=$2 rows=$3 ratio=$4 n=$5
  local splits=()

  # custom layout: just stack vertical splits
  if [[ $cols -eq 0 ]]; then
    for ((i=1; i<n; i++)); do splits+=('split-window -v -c "#{pane_current_path}"'); done
    printf '%s\n' "${splits[@]}"
    return
  fi

  local max=$((rows * cols))

  # row splits across the whole width
  for ((r=1; r<rows; r++)); do
    splits+=('split-window -v -c "#{pane_current_path}"')
  done

  # column splits within each row
  for ((r=0; r<rows; r++)); do
    for ((c=1; c<cols; c++)); do
      local target=$((r * cols))
      local split='split-window -h -c "#{pane_current_path}"'
      # apply ratio to first column split of main-side layouts
      if [[ $ratio -gt 0 && $c -eq 1 && $r -eq 0 ]]; then
        local pct=$((100 - ratio))
        split="split-window -h -p $pct -c \"#{pane_current_path}\""
      fi
      splits+=("select-pane -t $target \\; $split")
    done
  done

  # extra panes beyond the grid: append as vertical splits
  for ((i=max; i<n; i++)); do
    splits+=('split-window -v -c "#{pane_current_path}"')
  done

  printf '%s\n' "${splits[@]}"
}

# ── assemble splits ──
if [[ $N -ge 2 ]]; then
  while IFS= read -r line; do
    [[ -n "$line" ]] && OUT+=" \\; $line"
  done < <(build_splits "$LID" "$COLS" "$ROWS" "$RATIO" "$N")
fi

# ── send keys to each pane ──
i=0
for cmd in "${PANES_CLEAN[@]}"; do
  cmd_trimmed="${cmd#"${cmd%%[![:space:]]*}"}"  # ltrim
  [[ -n "$cmd_trimmed" ]] && OUT+=" \\; send-keys -t $i '$cmd_trimmed' Enter"
  i=$((i+1))
done

# ── output ──
echo "$OUT"
echo "# tmux attach -t $QNAME"
