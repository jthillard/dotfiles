# Configurations ===============================================================

# Current default theme is monokai_pro :)

# The plugin print these variables after mode changes

# Reset then blue steady block cursor
: "${ZHM_CURSOR_NORMAL:=\e[0m\e[2 q\e]12;#78DCE8\a}"

# Reset then red steady underline cursor
: "${ZHM_CURSOR_SELECT:=\e[0m\e[4 q\e]12;#FF6188\a}"

# Reset then green steady vertical bar cursor
: "${ZHM_CURSOR_INSERT:=\e[0m\e[6 q\e]12;#A9DC76\a}"

# Uses the syntax from https://zsh.sourceforge.io/Doc/Release/Zsh-Line-Editor.html#Character-Highlighting
: "${ZHM_STYLE_CURSOR_NORMAL:=fg=#2d2a2e,bg=#78dce8}"
: "${ZHM_STYLE_CURSOR_SELECT:=fg=#2d2a2e,bg=#ff6188}"
: "${ZHM_STYLE_CURSOR_INSERT:=fg=#2d2a2e,bg=#a9dc76}"
: "${ZHM_STYLE_OTHER_CURSOR_NORMAL:=fg=#2d2a2e,bg=#61a7b0}"
: "${ZHM_STYLE_OTHER_CURSOR_SELECT:=fg=#2d2a2e,bg=#c0506d}"
: "${ZHM_STYLE_OTHER_CURSOR_INSERT:=fg=#2d2a2e,bg=#84a760}"
: "${ZHM_STYLE_SELECTION:=fg=#fcfcfa,bg=#5b595c}"

# Clipboard commands
if [[ -n $WAYLAND_DISPLAY ]]; then
  : "${ZHM_CLIPBOARD_PIPE_CONTENT_TO:=wl-copy}"
  : "${ZHM_CLIPBOARD_READ_CONTENT_FROM:=wl-paste --no-newline}"
elif [[ -n $DISPLAY ]]; then
  : "${ZHM_CLIPBOARD_PIPE_CONTENT_TO:=xclip -sel clip}"
  : "${ZHM_CLIPBOARD_READ_CONTENT_FROM:=xclip -o -sel clip}"
else
  : "${ZHM_CLIPBOARD_PIPE_CONTENT_TO:=}"
  : "${ZHM_CLIPBOARD_READ_CONTENT_FROM:=}"
fi

# Global variables =============================================================

export ZHM_MODE=insert
export ZHM_MULTILINE=0

# Shown above the buffer in multiline mode
ZHM_MULTILINE_PREDISPLAY="-- MULTILINE --"$'\n'

ZHM_PRIMARY_CURSOR_IDX=1
zhm_cursors_pos=(0)
zhm_cursors_selection_left=(0)
zhm_cursors_selection_right=(0)

ZHM_RECORD_CHANGES=1
ZHM_PRIMARY_CURSOR_IDX_PREV=1
zhm_cursors_pos_prev=(0)
zhm_cursors_selection_left_prev=(0)
zhm_cursors_selection_right_prev=(0)

# The changes history (`zhm_changes_history_*`) is initialized by
# `__zhm_reset_history`

zhm_cursors_last_moved_x=(0)

declare -gA zhm_registers
declare -gA zhm_registers_max

ZHM_ACCEPTING=0
ZHM_HOOK_IKNOWWHATIMDOING=0
ZHM_PROMPT_PREDISPLAY_OFFSET=0
ZHM_IN_PROMPT=0
ZHM_PROMPT_HOOK=
zhm_prompt_region_highlight=()
ZHM_BUFFER_BEFORE_PROMPT=

ZHM_MESSAGE_CLEAR_DELAY=0

ZHM_LAST_MOTION=""
ZHM_LAST_MOTION_CHAR=""

ZHM_CURRENT_REGISTER="\""
ZHM_JUST_SELECTED_REGISTER=0

# Utility functions ============================================================

function __zhm_read_register {
  local register=$1
  local idx=$2
  case "$register" in
    "_")
      ;;
    "#")
      printf '%s\n' "$idx"
      ;;
    ".")
      printf '%s\n' "$BUFFER[$((zhm_cursors_selection_left[$idx] + 1)),$((zhm_cursors_selection_right[$idx] + 1))]"
      ;;
    "%")
      printf '%s\n' "$(pwd)"
      ;;
    "+")
      printf '%s\n' "$(eval $ZHM_CLIPBOARD_READ_CONTENT_FROM)"
      ;;
    *)
      if (( ! ${+zhm_registers_max["$register"]} )); then
        return
      fi
      idx=$(( idx <= zhm_registers_max["$register"] ? idx : zhm_registers_max["$register"] ))
      print "${zhm_registers["${register}_${idx}"]}"
      ;;
  esac
}

function __zhm_write_register {
  local register=$1
  shift
  case "$register" in
    "_"| "#" | "." | "%")
      ;;
    "+")
      printf '%s\n' "$@" | eval $ZHM_CLIPBOARD_PIPE_CONTENT_TO
      ;;
    *)
      local i
      for i in {1..$#}; do
        zhm_registers["${register}_$i"]="$argv[$i]"
      done
      zhm_registers_max["$register"]=$#
      ;;
  esac
}

function __zhm_clear_region_highlight {
  region_highlight=(
    ${region_highlight:#*memo=zsh-helix-mode}
  )
}

function __zhm_update_region_highlight {
  region_highlight=(
    "${(@)region_highlight:#*memo=zsh-helix-mode}"
    "${(@)zhm_prompt_region_highlight}"
  )

  local offset=0
  local prefix=""
  if (( ZHM_IN_PROMPT == 1 )); then
    prefix="P"
    offset=$ZHM_PROMPT_PREDISPLAY_OFFSET
  fi

  local i
  for i in {1..$#zhm_cursors_pos}; do
    local left=$zhm_cursors_selection_left[$i]
    local right=$zhm_cursors_selection_right[$i]
    local cursor=$zhm_cursors_pos[$i]

    if (( cursor == left && cursor == right )); then
      continue
    elif (( cursor == left )) && [[ $ZHM_MODE != insert ]]; then
      # ZHM_MODE != insert is necessary to have proper highlighting when
      # cursor is a bar
      # This is hardcoded. No one is going to use a bar for other mode.. right?
      left=$((left + 1))
    elif (( cursor == right )); then
      right=$((right - 1))
    fi

    left=$(( left + offset ))
    right=$(( right + 1 + offset ))
    region_highlight+=("$prefix$left $right $ZHM_STYLE_SELECTION memo=zsh-helix-mode")
  done

  for i in {1..$#zhm_cursors_pos}; do
    local other=OTHER_
    if (( i == ZHM_PRIMARY_CURSOR_IDX )); then
      if (( ZHM_IN_PROMPT == 0 )); then
        continue
      fi
      other=
    fi
    local style_var=ZHM_STYLE_${other}CURSOR_${(U)ZHM_MODE}
    local cursor=$(( zhm_cursors_pos[i] + offset ))
    region_highlight+=("$prefix$cursor $((cursor + 1)) ${(P)style_var} memo=zsh-helix-mode")
  done
}

function __zhm_reset_history {
  ZHM_CHANGES_HISTORY_IDX=1
  zhm_changes_history_buffer=("")
  local suffix
  for suffix in pre post; do
    set -A zhm_changes_history_cursors_idx_starts_$suffix 1
    set -A zhm_changes_history_cursors_count_$suffix 1
    set -A zhm_changes_history_cursors_pos_$suffix 0
    set -A zhm_changes_history_cursors_selection_left_$suffix 0
    set -A zhm_changes_history_cursors_selection_right_$suffix 0
    set -A zhm_changes_history_primary_cursor_$suffix 1
  done
}

# Drops every history entry after the current one
function __zhm_trim_history {
  local keep=$ZHM_CHANGES_HISTORY_IDX
  zhm_changes_history_buffer=("${(@)zhm_changes_history_buffer[1,$keep]}")

  local suffix name
  for suffix in pre post; do
    local starts=zhm_changes_history_cursors_idx_starts_$suffix
    local last=$(( ${${(P)starts}[$((keep + 1))]} - 1 ))
    for name in pos selection_left selection_right; do
      name=zhm_changes_history_cursors_${name}_$suffix
      set -A $name "${(@)${(P)name}[1,$last]}"
    done
    for name in cursors_idx_starts cursors_count primary_cursor; do
      name=zhm_changes_history_${name}_$suffix
      set -A $name "${(@)${(P)name}[1,$keep]}"
    done
  done
}

# Appends the cursors stored in `zhm_cursors_*<source>` to the `suffix` (`pre`
# or `post`) part of the changes history
function __zhm_push_history_cursors {
  local suffix=$1
  local source=$2
  local primary=$3

  local starts=zhm_changes_history_cursors_idx_starts_$suffix
  local count=zhm_changes_history_cursors_count_$suffix
  local primaries=zhm_changes_history_primary_cursor_$suffix
  local history_pos=zhm_changes_history_cursors_pos_$suffix
  local source_pos=zhm_cursors_pos$source
  set -A $starts "${(@P)starts}" $(( ${#${(P)history_pos}} + 1 ))
  set -A $count "${(@P)count}" ${#${(P)source_pos}}
  set -A $primaries "${(@P)primaries}" $primary

  local name
  for name in pos selection_left selection_right; do
    local history=zhm_changes_history_cursors_${name}_$suffix
    local current=zhm_cursors_${name}$source
    set -A $history "${(@P)history}" "${(@P)current}"
  done
}

# Restores the buffer of the current history entry and the cursors stored in
# the `suffix` (`pre` or `post`) part of history entry `entry`
function __zhm_restore_history {
  local entry=$1
  local suffix=$2

  BUFFER="$zhm_changes_history_buffer[$ZHM_CHANGES_HISTORY_IDX]"
  local starts=zhm_changes_history_cursors_idx_starts_$suffix
  local count=zhm_changes_history_cursors_count_$suffix
  local primaries=zhm_changes_history_primary_cursor_$suffix
  local idx=${${(P)starts}[$entry]}
  local last=$(( idx + ${${(P)count}[$entry]} - 1 ))

  local name
  for name in pos selection_left selection_right; do
    local history=zhm_changes_history_cursors_${name}_$suffix
    set -A zhm_cursors_$name "${(@)${(P)history}[$idx,$last]}"
  done
  ZHM_PRIMARY_CURSOR_IDX=${${(P)primaries}[$entry]}

  ZHM_HOOK_IKNOWWHATIMDOING=1
  __zhm_refresh
}

function __zhm_set_mode {
  if [[ $1 == insert ]]; then
    bindkey -A hxins main
  else
    bindkey -A hxnor main
  fi
  ZHM_MODE=$1
  local cursor_var=ZHM_CURSOR_${(U)1}
  printf "${(P)cursor_var}"
}

function __zhm_exit_select_mode {
  if [[ $ZHM_MODE == select ]]; then
    __zhm_set_mode normal
  fi
}

# Moves cursor `idx` to `pos`, clamped to the buffer, without touching its
# selection
function __zhm_set_pos {
  local idx=$1
  local pos=$2
  pos=$(( pos < 0 ? 0 : pos > ${#BUFFER} ? ${#BUFFER} : pos ))

  if (( idx == ZHM_PRIMARY_CURSOR_IDX )); then
    CURSOR=$pos
  fi
  zhm_cursors_pos[$idx]=$pos
}

# Sets the selection of cursor `idx`, then puts the cursor on its right end if
# `on_right` is 1, on its left end otherwise
function __zhm_select {
  local idx=$1
  local left=$2
  local right=$3
  local on_right=$4
  zhm_cursors_selection_left[$idx]=$left
  zhm_cursors_selection_right[$idx]=$right
  zhm_cursors_pos[$idx]=$(( on_right ? right : left ))
}

# Replaces every cursor with a single one at `pos`
function __zhm_reset_cursors {
  zhm_cursors_pos=($1)
  zhm_cursors_selection_left=($1)
  zhm_cursors_selection_right=($1)
  zhm_cursors_last_moved_x=($1)
}

function __zhm_save_cursors {
  ZHM_PREV_PRIMARY_CURSOR_IDX=$ZHM_PRIMARY_CURSOR_IDX
  zhm_prev_cursors_pos=($zhm_cursors_pos)
  zhm_prev_selection_left=($zhm_cursors_selection_left)
  zhm_prev_selection_right=($zhm_cursors_selection_right)
  zhm_prev_cursors_last_moved_x=($zhm_cursors_last_moved_x)
}

function __zhm_restore_cursors {
  ZHM_PRIMARY_CURSOR_IDX=$ZHM_PREV_PRIMARY_CURSOR_IDX
  zhm_cursors_pos=($zhm_prev_cursors_pos)
  zhm_cursors_selection_left=($zhm_prev_selection_left)
  zhm_cursors_selection_right=($zhm_prev_selection_right)
  zhm_cursors_last_moved_x=($zhm_prev_cursors_last_moved_x)
}

function __zhm_clear_selection_goto {
  local idx=$1
  __zhm_set_pos $idx $2
  zhm_cursors_selection_left[$idx]=$zhm_cursors_pos[$idx]
  zhm_cursors_selection_right[$idx]=$zhm_cursors_pos[$idx]
}

function __zhm_goto {
  local idx=$1
  local left=$zhm_cursors_selection_left[$idx]
  local right=$zhm_cursors_selection_right[$idx]
  local prev_cursor=$zhm_cursors_pos[$idx]

  __zhm_set_pos $idx $2
  local cursor=$zhm_cursors_pos[$idx]

  if [[ $ZHM_MODE != select ]]; then
    zhm_cursors_selection_left[$idx]=$cursor
    zhm_cursors_selection_right[$idx]=$cursor
  elif (( prev_cursor == left )); then
    if (( cursor <= right )); then
      zhm_cursors_selection_left[$idx]=$cursor
    else
      zhm_cursors_selection_left[$idx]=$right
      zhm_cursors_selection_right[$idx]=$cursor
    fi
  elif (( prev_cursor == right )); then
    if (( cursor >= left)); then
      zhm_cursors_selection_right[$idx]=$cursor
    else
      zhm_cursors_selection_right[$idx]=$left
      zhm_cursors_selection_left[$idx]=$cursor
    fi
  fi
}

function __zhm_trailing_goto {
  local idx=$1
  local skip=$3

  if [[ $ZHM_MODE == select ]]; then
    __zhm_goto $idx $2
    return
  fi

  local prev_cursor=$zhm_cursors_pos[$idx]
  __zhm_set_pos $idx $2
  local cursor=$zhm_cursors_pos[$idx]

  if (( cursor > prev_cursor )); then
    zhm_cursors_selection_left[$idx]=$((prev_cursor + skip))
    zhm_cursors_selection_right[$idx]=$cursor
  elif (( cursor < prev_cursor)); then
    zhm_cursors_selection_right[$idx]=$((prev_cursor - skip))
    zhm_cursors_selection_left[$idx]=$cursor
  fi
}

function __zhm_update_last_moved {
  zhm_cursors_last_moved_x=()
  local i
  for i in {1..$#zhm_cursors_pos}; do
    local cursor=$zhm_cursors_pos[$i]
    local line_start=$(__zhm_find_line_start $cursor "$BUFFER")
    zhm_cursors_last_moved_x[$i]=$((cursor - line_start))
  done
}

# Syncs `CURSOR` with the primary cursor, then updates the remembered columns
# and the highlighting
function __zhm_refresh {
  CURSOR=$zhm_cursors_pos[$ZHM_PRIMARY_CURSOR_IDX]
  __zhm_update_last_moved
  __zhm_update_region_highlight
}

function __zhm_merge_cursors {
  if (( ${#zhm_cursors_pos} <= 1 )); then
    return
  fi
  local i=0
  while true; do
    i=$((i + 1))
    if (( (i + 1) > ${#zhm_cursors_pos} )); then
      break
    fi

    local i_cursor=$zhm_cursors_pos[$i]
    local i_left=$zhm_cursors_selection_left[$i]
    local i_right=$zhm_cursors_selection_right[$i]

    local j=$i
    while true; do
      j=$((j + 1))
      if (( j > ${#zhm_cursors_pos} )); then
        break
      fi

      local j_left=$zhm_cursors_selection_left[$j]
      local j_right=$zhm_cursors_selection_right[$j]

      if (( !(i_right < j_left || i_left > j_right) )); then
        local new_left=$((i_left > j_left ? j_left : i_left))
        local new_right=$((i_right > j_right ? i_right : j_right))
        __zhm_select $i $new_left $new_right $(( i_cursor == i_right ))
        zhm_cursors_pos[$j]=()
        zhm_cursors_selection_left[$j]=()
        zhm_cursors_selection_right[$j]=()

        j=$((j - 1))
      fi
    done
  done
}

function __zhm_prompt {
  local prompt="$1"

  ZHM_BUFFER_BEFORE_PROMPT="$BUFFER"
  local prev_cursor="$CURSOR"

  local header=
  if (( ZHM_MULTILINE == 1 )); then
    header=$ZHM_MULTILINE_PREDISPLAY
  fi
  ZHM_PROMPT_PREDISPLAY_OFFSET=${#header}
  PREDISPLAY="$header$ZHM_BUFFER_BEFORE_PROMPT
$prompt"

  BUFFER=""

  zhm_prompt_region_highlight=()
  local highlight
  for highlight in $region_highlight; do
    if [[ $highlight =~ "memo=zsh-helix-mode" ]]; then
      continue
    fi
    if [[ $highlight =~ "([0-9]*) ([0-9]*) " ]]; then
      local left=$((match[1] + ZHM_PROMPT_PREDISPLAY_OFFSET))
      local right=$((match[2] + ZHM_PROMPT_PREDISPLAY_OFFSET))
      highlight="$left $right ${highlight:$MEND}"
    fi

    zhm_prompt_region_highlight+=("P${highlight/memo=*/memo=zsh-helix-mode}")
  done

  region_highlight=()

  ZHM_PROMPT_HOOK="$2"
  ZHM_IN_PROMPT=1
  printf "$ZHM_CURSOR_INSERT"
  bindkey -A hxprompt main

  zle recursive-edit
  local stat=$?

  zhm_prompt_region_highlight=()

  ZHM_IN_PROMPT=0
  ZHM_PROMPT_HOOK=

  PREDISPLAY="$header"
  REPLY="$BUFFER"
  BUFFER="$ZHM_BUFFER_BEFORE_PROMPT"
  CURSOR="$prev_cursor"

  __zhm_set_mode $ZHM_MODE
  __zhm_update_region_highlight
  return $stat
}

function __zhm_show_message {
  zle -M "$1"
  ZHM_MESSAGE_CLEAR_DELAY=2
}

function __zhm_find_line_end  {
  setopt localoptions rematchpcre
  local pos=$1
  local buffer="$2"
  if [[ "${buffer:$pos}" =~ '\A[^\n]*\n|\A[^\n]*' ]]; then
    printf '%s\n' $((pos + MEND - 1))
  fi
}

function __zhm_find_line_start {
  setopt localoptions rematchpcre
  local pos=$1
  local buffer="$2"
  if [[ "${buffer:0:$((pos + 1))}" =~ '[^\n]*\n\z|[^\n]*\z' ]]; then
    printf '%s\n' $((MBEGIN - 1))
  fi
}

# Sets `reply` to the 1-based line and the column of an offset in the buffer
function __zhm_line_col {
  local before="${BUFFER:0:$1}"
  local newlines="${before//[^$'\n']/}"
  local tail="${before##*$'\n'}"
  reply=($(( ${#newlines} + 1 )) ${#tail})
}

# Sets `reply` to the content of every selection
function __zhm_selections_content {
  reply=()
  local i
  for i in {1..$#zhm_cursors_pos}; do
    local left=$zhm_cursors_selection_left[$i]
    local right=$zhm_cursors_selection_right[$i]
    reply+=("${BUFFER[$((left + 1)),$((right + 1))]}")
  done
}

# Sets `reply` to the content of `register` for every selection
function __zhm_register_contents {
  reply=()
  local i
  for i in {1..$#zhm_cursors_pos}; do
    reply+=("$(__zhm_read_register "$1" $i)")
  done
}

# Replaces every selection with the matching argument after `skip_empty`,
# keeping the cursor on the same side of its selection. With `skip_empty`,
# selections matched with an empty argument are left untouched
function __zhm_replace_selections {
  local skip_empty=$1
  shift
  local contents=("$@")

  local amount_modified=0
  local i
  for i in {1..$#zhm_cursors_pos}; do
    local cursor=$(( zhm_cursors_pos[i] + amount_modified ))
    local left=$(( zhm_cursors_selection_left[i] + amount_modified ))
    local right=$(( zhm_cursors_selection_right[i] + amount_modified ))
    local content="$contents[$i]"

    if (( skip_empty )) && [[ -z "$content" ]]; then
      zhm_cursors_pos[$i]=$cursor
      zhm_cursors_selection_left[$i]=$left
      zhm_cursors_selection_right[$i]=$right
      continue
    fi

    local prev_content="${BUFFER[$((left + 1)),$((right + 1))]}"
    BUFFER="${BUFFER:0:$left}$content${BUFFER:$((right + 1))}"
    local diff=$(( ${#content} - ${#prev_content} ))
    __zhm_select $i $left $((right + diff)) $(( cursor == right ))
    amount_modified=$((amount_modified + diff))
  done
  CURSOR=$zhm_cursors_pos[$ZHM_PRIMARY_CURSOR_IDX]
}

function __zhm_yank_selections {
  local reply=()
  __zhm_selections_content
  __zhm_write_register "$1" "$reply[@]"
}

# Yanks every selection into the current register, then deletes them
function __zhm_delete_selections {
  __zhm_yank_selections "$ZHM_CURRENT_REGISTER"

  local amount_deleted=0
  local i
  for i in {1..$#zhm_cursors_pos}; do
    local left=$((zhm_cursors_selection_left[i] - amount_deleted))
    local right=$((zhm_cursors_selection_right[i] - amount_deleted))

    BUFFER="${BUFFER:0:$left}${BUFFER:$((right + 1))}"
    __zhm_select $i $left $left 0

    amount_deleted=$((amount_deleted + right - left + 1))
  done
  CURSOR=$zhm_cursors_pos[$ZHM_PRIMARY_CURSOR_IDX]
}

# Pastes the content of `register` after every selection (or before them if
# `before` is 1), then selects the pasted text
function __zhm_paste {
  local register=$1
  local before=$2

  local amount_pasted=0
  local i
  for i in {1..$#zhm_cursors_pos}; do
    local cursor=$((zhm_cursors_pos[$i] + amount_pasted))
    local left=$((zhm_cursors_selection_left[$i] + amount_pasted))
    local right=$((zhm_cursors_selection_right[$i] + amount_pasted))
    zhm_cursors_pos[$i]=$cursor
    zhm_cursors_selection_left[$i]=$left
    zhm_cursors_selection_right[$i]=$right

    local content=$(__zhm_read_register "$register" $i)
    if [[ -z "$content" ]]; then
      continue
    fi

    local at=$(( before ? left : right + 1 ))
    BUFFER="${BUFFER:0:$at}$content${BUFFER:$at}"
    __zhm_select $i $at $((at + ${#content} - 1)) $(( cursor == right ))
    amount_pasted=$((amount_pasted + ${#content}))
  done

  __zhm_refresh
  ZHM_HOOK_IKNOWWHATIMDOING=1
}

# Sets `reply` to the opening and closing characters of the pair `char` belongs
# to. Characters that are not brackets pair with themselves
function __zhm_surround_chars {
  case "$1" in
    "(" | ")")
      reply=("(" ")")
      ;;
    "[" | "]")
      reply=("[" "]")
      ;;
    "{" | "}")
      reply=("{" "}")
      ;;
    "<" | ">")
      reply=("<" ">")
      ;;
    *)
      reply=("$1" "$1")
      ;;
  esac
}

# Mode =========================================================================

function zhm_normal {
  if [[ $ZHM_MODE == insert ]]; then
    local i
    for i in {1..$#zhm_cursors_pos}; do
      local cursor=$zhm_cursors_pos[$i]
      if (( cursor > zhm_cursors_selection_right[i] )); then
        zhm_cursors_pos[$i]=$((cursor - 1))
      fi
    done
    CURSOR=$zhm_cursors_pos[$ZHM_PRIMARY_CURSOR_IDX]
  fi
  __zhm_set_mode normal
  __zhm_update_region_highlight
}

function zhm_select {
  if [[ $ZHM_MODE == select ]]; then
    __zhm_set_mode normal
  else
    __zhm_set_mode select
  fi
}

function zhm_multiline {
  ZHM_MULTILINE=$(( !ZHM_MULTILINE ))
  if (( ZHM_MULTILINE == 1 )); then
    PREDISPLAY=$ZHM_MULTILINE_PREDISPLAY
  else
    PREDISPLAY=""
  fi
}

function zhm_insert {
  zhm_cursors_pos=("$zhm_cursors_selection_left[@]")
  CURSOR=$zhm_cursors_pos[$ZHM_PRIMARY_CURSOR_IDX]
  __zhm_set_mode insert
  __zhm_update_region_highlight
}

function zhm_insert_at_line_end {
  local i
  for i in {1..$#zhm_cursors_pos}; do
    local pos=$(__zhm_find_line_end $zhm_cursors_pos[$i] "$BUFFER")
    if (( (pos + 1) >= ${#BUFFER} )); then
      pos=$((pos + 1))
    fi
    __zhm_select $i $pos $pos 0
  done
  zhm_insert
}

function zhm_insert_at_line_start {
  local i
  for i in {1..$#zhm_cursors_pos}; do
    local pos=$(__zhm_find_line_start $zhm_cursors_pos[$i] "$BUFFER")
    __zhm_select $i $pos $pos 0
  done
  zhm_insert
}

function zhm_open_below {
  local amount_inserted=0
  local i
  for i in {1..$#zhm_cursors_pos}; do
    local cursor=$zhm_cursors_pos[$i]
    local line_end=$(__zhm_find_line_end $((cursor + amount_inserted)) "$BUFFER")

    local at_buffer_end=$(( ${#BUFFER} == (line_end + 1) ))

    BUFFER="${BUFFER:0:$((line_end + 1))}"$'\n'"${BUFFER:$((line_end + 1))}"

    local pos=$((line_end + 1 + at_buffer_end))
    __zhm_select $i $pos $pos 0
    amount_inserted=$((amount_inserted + 1))
  done
  __zhm_set_mode insert
  __zhm_refresh
}

function zhm_open_above {
  local amount_inserted=0
  local i
  for i in {1..$#zhm_cursors_pos}; do
    local cursor=$zhm_cursors_pos[$i]
    local line_start=$(__zhm_find_line_start $((cursor + amount_inserted)) "$BUFFER")

    BUFFER="${BUFFER:0:$line_start}"$'\n'"${BUFFER:$line_start}"

    __zhm_select $i $line_start $line_start 0
    amount_inserted=$((amount_inserted + 1))
  done
  __zhm_set_mode insert
  __zhm_refresh
}

function zhm_append {
  local i
  for i in {1..$#zhm_cursors_pos}; do
    zhm_cursors_pos[$i]=$((zhm_cursors_selection_right[i] + 1))
  done
  CURSOR=$zhm_cursors_pos[$ZHM_PRIMARY_CURSOR_IDX]
  __zhm_set_mode insert
  __zhm_update_region_highlight
}

function zhm_change {
  __zhm_delete_selections
  __zhm_set_mode insert
  __zhm_update_region_highlight
}

function zhm_command_mode {
  local REPLY=
  __zhm_prompt ":"
  if (( $? != 0 )); then
    return
  fi

  local command=(${=REPLY})

  if (( ${#command} == 0  )); then
    return
  fi

  case "${command[1]}" in
    "o" | "open")
      if (( ${#command} <= 1  )); then
        return
      fi
      local content=
      content="$(cat "${command[2]}" 2>&1)"
      if (( $? != 0 )); then
        __zhm_show_message "$content"
        return
      fi
      BUFFER="$content"
      CURSOR=0
      __zhm_reset_cursors 0
      ;;
    *)
      __zhm_show_message "Unknown Command"
  esac
}

# Movement =====================================================================

# Moves every cursor `delta` characters with `goto_function`
function __zhm_move_horizontal {
  local delta=$1
  local goto_function=$2
  local i
  for i in {1..$#zhm_cursors_pos}; do
    $goto_function $i $((zhm_cursors_pos[i] + delta))
  done
  __zhm_refresh
}

function zhm_move_left {
  __zhm_move_horizontal -1 __zhm_goto
}

function zhm_clear_selection_move_left {
  __zhm_move_horizontal -1 __zhm_clear_selection_goto
}

function zhm_move_right {
  __zhm_move_horizontal 1 __zhm_goto
}

function zhm_clear_selection_move_right {
  __zhm_move_horizontal 1 __zhm_clear_selection_goto
}

# Moves every cursor one line down (1) or up (-1), keeping its column. If
# `history_widget` is given, it is called instead when the primary cursor is
# already on the last (or first) line
function __zhm_move_vertical {
  local direction=$1
  local history_widget=$2
  local i
  for i in {1..$#zhm_cursors_pos}; do
    local cursor=$zhm_cursors_pos[$i]
    local line_start=
    local line_end=
    if (( direction > 0 )); then
      line_start=$(( $(__zhm_find_line_end $cursor "$BUFFER") + 1 ))
      if (( line_start < ${#BUFFER} )); then
        line_end=$(__zhm_find_line_end $line_start "$BUFFER")
      fi
    else
      line_end=$(( $(__zhm_find_line_start $cursor "$BUFFER") - 1 ))
      if (( line_end >= 0 )); then
        line_start=$(__zhm_find_line_start $line_end "$BUFFER")
      fi
    fi

    if [[ -z $line_start || -z $line_end ]]; then
      if [[ -n $history_widget ]] && (( i == ZHM_PRIMARY_CURSOR_IDX )); then
        $history_widget
        return
      fi
      continue
    fi

    local goto=$((line_start + zhm_cursors_last_moved_x[i]))
    __zhm_goto $i $((goto <= line_end ? goto : line_end))
  done
  __zhm_update_region_highlight
}

function zhm_move_down {
  __zhm_move_vertical 1
}

function zhm_move_down_or_history_next {
  __zhm_move_vertical 1 zhm_history_next
}

function zhm_move_up {
  __zhm_move_vertical -1
}

function zhm_move_up_or_history_prev {
  __zhm_move_vertical -1 zhm_history_prev
}

# Moves every cursor to the end of the next match of `alternatives`, selecting
# what is crossed
function __zhm_word_motion_forward {
  setopt localoptions rematchpcre
  local regex="^\n*($1)"
  local i
  for i in {1..$#zhm_cursors_pos}; do
    local cursor=$zhm_cursors_pos[$i]
    local rbuffer="${BUFFER:$cursor}"
    if [[ $rbuffer =~ $regex ]]; then
      local skip=$((mbegin[1] - 1))
      local go=$((cursor + mend[1] - 1))
      if (( ${#match[1]} == 1 )) && [[ ${rbuffer:1} =~ $regex ]]; then
        skip=$((mbegin[1]))
        go=$((cursor + mend[1]))
      fi
      __zhm_trailing_goto $i $go $skip
    fi
  done
  __zhm_refresh
}

# Moves every cursor to the start of the previous match of `alternatives`,
# selecting what is crossed
function __zhm_word_motion_backward {
  setopt localoptions rematchpcre
  local regex="($1)\n*$"
  local i
  for i in {1..$#zhm_cursors_pos}; do
    local cursor=$zhm_cursors_pos[$i]
    local lbuffer="${BUFFER:0:$((cursor + 1))}"
    if [[ $lbuffer =~ $regex ]]; then
      local skip=$((${#lbuffer} - mend[1]))
      local go=$((mbegin - 1))
      if (( ${#match[1]} == 1 )) && [[ ${lbuffer:0:-1} =~ $regex ]]; then
        skip=$((${#lbuffer} - mend[1]))
        go=$((mbegin - 1))
      fi
      __zhm_trailing_goto $i $go $skip
    fi
  done
  __zhm_refresh
}

ZHM_WORD_START_REGEX='\w+[^\S\n]*|[^\w\s]+[^\S\n]*|[^\S\n]+'
ZHM_WORD_END_REGEX='[^\S\n]*\w+|[^\S\n]*[^\w\s]+|[^\S\n]+'
ZHM_LONG_WORD_START_REGEX='\S+[^\S\n]*|[^\S\n]+'
ZHM_LONG_WORD_END_REGEX='[^\S\n]*\S+|[^\S\n]+'

function zhm_move_next_word_start {
  __zhm_word_motion_forward "$ZHM_WORD_START_REGEX"
}

function zhm_move_prev_word_start {
  __zhm_word_motion_backward "$ZHM_WORD_START_REGEX"
}

function zhm_move_next_word_end {
  __zhm_word_motion_forward "$ZHM_WORD_END_REGEX"
}

function zhm_move_next_long_word_start {
  __zhm_word_motion_forward "$ZHM_LONG_WORD_START_REGEX"
}

function zhm_move_prev_long_word_start {
  __zhm_word_motion_backward "$ZHM_LONG_WORD_START_REGEX"
}

function zhm_move_next_long_word_end {
  __zhm_word_motion_forward "$ZHM_LONG_WORD_END_REGEX"
}

# Moves every cursor with the `motion` (find_till, find_next, till_prev or
# find_prev) towards `char`, which must already be regex escaped
function __zhm_char_motion {
  local motion=$1
  local char=$2
  local i
  for i in {1..$#zhm_cursors_pos}; do
    local cursor=$zhm_cursors_pos[$i]
    local rbuffer="${BUFFER:$cursor}"
    local lbuffer="${BUFFER:0:$cursor}"
    case "$motion" in
      "find_till")
        if [[ $rbuffer =~ ".?$char?[^$char]*" ]]; then
          __zhm_trailing_goto $i $((cursor + MEND - 1)) 0
        fi
        ;;
      "find_next")
        if [[ $rbuffer =~ "$char?[^$char]*$char" ]]; then
          __zhm_trailing_goto $i $((cursor + MEND - 1)) 0
        fi
        ;;
      "till_prev")
        if [[ $lbuffer =~ "[^$char]*$char?$" ]]; then
          __zhm_trailing_goto $i $((MBEGIN - 1)) 0
        fi
        ;;
      "find_prev")
        if [[ $lbuffer =~ "${char}[^${char}]*$" ]]; then
          __zhm_trailing_goto $i $((MBEGIN - 1)) 0
        fi
        ;;
    esac
  done
  ZHM_LAST_MOTION="$motion"
  ZHM_LAST_MOTION_CHAR="$char"
  __zhm_refresh
}

# Reads a character, then moves every cursor towards it with the `motion`
function __zhm_read_char_motion {
  local char="$(read -ek 1)"
  __zhm_char_motion $1 "$(printf '%s' "$char" | sed 's/[.[\(*^$+?{|]/\\&/g')"
}

function zhm_find_till_char {
  __zhm_read_char_motion find_till
}

function zhm_find_next_char {
  __zhm_read_char_motion find_next
}

function zhm_till_prev_char {
  __zhm_read_char_motion till_prev
}

function zhm_find_prev_char {
  __zhm_read_char_motion find_prev
}

function zhm_repeat_last_motion {
  if [[ -n "$ZHM_LAST_MOTION" ]]; then
    __zhm_char_motion "$ZHM_LAST_MOTION" "$ZHM_LAST_MOTION_CHAR"
  fi
}

# Changes ======================================================================

function zhm_delete {
  __zhm_delete_selections
  __zhm_exit_select_mode
  __zhm_update_region_highlight
}

function zhm_replace {
  local char="$(read -ek 1)"
  local reply=()
  __zhm_selections_content
  local replaced=()
  local content
  for content in "$reply[@]"; do
    replaced+=("${(pl:${#content}::$char:)}")
  done
  __zhm_replace_selections 0 "$replaced[@]"
  __zhm_exit_select_mode
  __zhm_update_region_highlight
}

function zhm_replace_with_yanked {
  local reply=()
  __zhm_register_contents "$ZHM_CURRENT_REGISTER"
  __zhm_replace_selections 1 "$reply[@]"
  __zhm_refresh
}

function zhm_replace_selections_with_clipboard {
  local reply=()
  __zhm_register_contents "+"
  __zhm_replace_selections 1 "$reply[@]"
  __zhm_refresh
}

function zhm_switch_case {
  local reply=()
  __zhm_selections_content
  local switched=()
  local content
  for content in "$reply[@]"; do
    local result=
    local char=
    for char in "${(@s::)content}"; do
      if [[ $char == [[:lower:]] ]]; then
        result+="${(U)char}"
      else
        result+="${(L)char}"
      fi
    done
    switched+=("$result")
  done
  __zhm_replace_selections 0 "$switched[@]"
  __zhm_update_region_highlight
}

function zhm_switch_to_lowercase {
  local reply=()
  __zhm_selections_content
  __zhm_replace_selections 0 "${(@L)reply}"
  __zhm_update_region_highlight
}

function zhm_switch_to_uppercase {
  local reply=()
  __zhm_selections_content
  __zhm_replace_selections 0 "${(@U)reply}"
  __zhm_update_region_highlight
}

function zhm_paste_after_or_replace_with_yanked {
  if [[ $ZHM_MODE == select ]]; then
    zhm_replace_with_yanked
  else
    zhm_paste_after
  fi
}

function zhm_clipboard_paste_after_or_replace {
  if [[ $ZHM_MODE == select ]]; then
    zhm_replace_selections_with_clipboard
  else
    zhm_clipboard_paste_after
  fi
}

# Moves every line touched by a selection one line down (1) or up (-1),
# keeping the cursors and selections on the moved lines
function __zhm_move_lines {
  local direction=$1
  local lines=("${(@ps:\n:)BUFFER}")
  local line_count=$#lines
  if (( line_count < 2 )); then
    return
  fi

  local reply=()
  local pos_line=() pos_col=() left_line=() left_col=() right_line=() right_col=()
  local selected=()
  local line_delta=()
  local i line
  for i in {1..$line_count}; do
    selected[$i]=0
    line_delta[$i]=0
  done
  for i in {1..$#zhm_cursors_pos}; do
    __zhm_line_col $zhm_cursors_pos[$i]
    pos_line[$i]=$reply[1]; pos_col[$i]=$reply[2]
    __zhm_line_col $zhm_cursors_selection_left[$i]
    left_line[$i]=$reply[1]; left_col[$i]=$reply[2]
    __zhm_line_col $zhm_cursors_selection_right[$i]
    right_line[$i]=$reply[1]; right_col[$i]=$reply[2]
    for line in {$left_line[$i]..$right_line[$i]}; do
      selected[$line]=1
    done
  done

  # Moves each block of consecutive selected lines, starting from the block
  # closest to where the lines are moving
  i=$(( direction > 0 ? line_count : 1 ))
  while (( i >= 1 && i <= line_count )); do
    if (( selected[i] == 0 )); then
      i=$((i - direction))
      continue
    fi
    local block_end=$i
    while (( i - direction >= 1 && i - direction <= line_count && selected[i - direction] == 1 )); do
      i=$((i - direction))
    done
    local block_start=$i
    i=$((i - direction))

    local top=$(( block_start < block_end ? block_start : block_end ))
    local bottom=$(( block_start < block_end ? block_end : block_start ))
    if (( direction > 0 && bottom < line_count )); then
      lines=(
        "${(@)lines[1,$((top - 1))]}"
        "$lines[$((bottom + 1))]"
        "${(@)lines[$top,$bottom]}"
        "${(@)lines[$((bottom + 2)),-1]}"
      )
    elif (( direction < 0 && top > 1 )); then
      lines=(
        "${(@)lines[1,$((top - 2))]}"
        "${(@)lines[$top,$bottom]}"
        "$lines[$((top - 1))]"
        "${(@)lines[$((bottom + 1)),-1]}"
      )
    else
      continue
    fi
    for line in {$top..$bottom}; do
      line_delta[$line]=$direction
    done
  done

  BUFFER="${(pj:\n:)lines}"

  local line_starts=(0)
  for line in {2..$line_count}; do
    line_starts[$line]=$(( line_starts[line - 1] + ${#lines[line - 1]} + 1 ))
  done
  for i in {1..$#zhm_cursors_pos}; do
    line=$((pos_line[i] + line_delta[pos_line[i]]))
    zhm_cursors_pos[$i]=$(( line_starts[line] + pos_col[i] ))
    line=$((left_line[i] + line_delta[left_line[i]]))
    zhm_cursors_selection_left[$i]=$(( line_starts[line] + left_col[i] ))
    line=$((right_line[i] + line_delta[right_line[i]]))
    zhm_cursors_selection_right[$i]=$(( line_starts[line] + right_col[i] ))
  done

  __zhm_refresh
  ZHM_HOOK_IKNOWWHATIMDOING=1
}

function zhm_move_lines_down {
  __zhm_move_lines 1
}

function zhm_move_lines_up {
  __zhm_move_lines -1
}

function zhm_undo {
  if (( ZHM_CHANGES_HISTORY_IDX > 1 )); then
    ZHM_CHANGES_HISTORY_IDX=$((ZHM_CHANGES_HISTORY_IDX - 1))
    __zhm_restore_history $((ZHM_CHANGES_HISTORY_IDX + 1)) pre
  fi
}

function zhm_redo {
  if (( ZHM_CHANGES_HISTORY_IDX < ${#zhm_changes_history_buffer} )); then
    ZHM_CHANGES_HISTORY_IDX=$((ZHM_CHANGES_HISTORY_IDX + 1))
    __zhm_restore_history $ZHM_CHANGES_HISTORY_IDX post
  fi
}

function zhm_yank {
  __zhm_yank_selections "$ZHM_CURRENT_REGISTER"
  __zhm_exit_select_mode
}

function zhm_clipboard_yank {
  __zhm_yank_selections "+"
  __zhm_exit_select_mode
}

function zhm_paste_after {
  __zhm_paste "$ZHM_CURRENT_REGISTER" 0
}

function zhm_clipboard_paste_after {
  __zhm_paste "+" 0
}

function zhm_paste_before {
  __zhm_paste "$ZHM_CURRENT_REGISTER" 1
}

function zhm_clipboard_paste_before {
  __zhm_paste "+" 1
}

function zhm_select_register {
  local register="$(read -ek 1)"
  if [[ -z "$register" ]]; then
    return
  fi
  ZHM_CURRENT_REGISTER="$register"
  ZHM_JUST_SELECTED_REGISTER=1
}

# Shell ========================================================================

function zhm_shell_pipe {
  local REPLY=
  __zhm_prompt "pipe:"
  if (( $? != 0 )) || [[ -z "$REPLY" ]]; then
    return
  fi
  local command="$REPLY"

  local reply=()
  __zhm_selections_content
  local results=()
  local content
  for content in "$reply[@]"; do
    results+=("$(printf '%s\n' "$content" | eval $command 2>&1)")
  done
  __zhm_replace_selections 0 "$results[@]"
  __zhm_refresh
}

# Selection manipulation =======================================================

function __zhm_select_regex_hook {
  setopt localoptions rematchpcre

  local regex="$BUFFER"
  if [[ -z "$regex" ]]; then
    __zhm_restore_cursors
    ZHM_HOOK_IKNOWWHATIMDOING=1
    return
  fi

  local matches_left=()
  local matches_right=()
  local i
  for i in {1..$#zhm_prev_selection_left}; do
    local string_begin=$((zhm_prev_selection_left[i] + 1))
    local string_end=$((zhm_prev_selection_right[i] + 1))

    while true; do
      local substring="${ZHM_BUFFER_BEFORE_PROMPT[$string_begin,$string_end]}"
      if ! [[ $substring =~ "$regex" ]] 2>/dev/null; then
        break
      fi

      matches_left+=( $((string_begin + $MBEGIN - 2)) )
      matches_right+=( $((string_begin + $MEND - 2)) )

      string_begin=$((string_begin + $MEND))
      if (( ${#MATCH} == 0 )); then
        string_begin=$((string_begin + 1))
        if (( (string_begin - 1) > string_end )); then
          break
        fi
      fi
    done
  done
  if (( ${#matches_left} > 0 )); then
    zhm_cursors_selection_left=($matches_left)
    zhm_cursors_selection_right=($matches_right)
    zhm_cursors_pos=($zhm_cursors_selection_right)
    ZHM_PRIMARY_CURSOR_IDX=1
    __zhm_update_last_moved
  else
    __zhm_restore_cursors
  fi
  ZHM_HOOK_IKNOWWHATIMDOING=1
}

function zhm_select_regex {
  __zhm_save_cursors
  local REPLY=
  __zhm_prompt "select:" __zhm_select_regex_hook
  local prompt_stat=$?

  # Compiled the same way as in `__zhm_select_regex_hook`
  local regex_error=$( setopt rematchpcre; [[ "" =~ "$REPLY" ]] 2>&1 )
  if [[ -n "$regex_error" ]]; then
    __zhm_show_message "$regex_error"
  fi

  if [[ -n "$regex_error" ]] || (( prompt_stat != 0 )) ; then
    __zhm_restore_cursors
  fi

  CURSOR=$zhm_cursors_pos[$ZHM_PRIMARY_CURSOR_IDX]
  ZHM_HOOK_IKNOWWHATIMDOING=1
}

function zhm_trim_selections {
  setopt localoptions rematchpcre
  local i
  for i in {1..$#zhm_cursors_pos}; do
    local cursor=$zhm_cursors_pos[$i]
    local left=$zhm_cursors_selection_left[$i]
    local right=$zhm_cursors_selection_right[$i]
    if (( left == right )); then
      continue
    fi
    if [[ "${BUFFER[$((left + 1)),$((right + 1))]}" =~ '\A\s*([\S\s]+?)\s*\z' ]]; then
      __zhm_select $i $((left + mbegin[1] - 1)) $((left + mend[1] - 1)) $(( cursor == right ))
    else
      __zhm_select $i $cursor $cursor 0
    fi
  done
  CURSOR=$zhm_cursors_pos[$ZHM_PRIMARY_CURSOR_IDX]

  ZHM_HOOK_IKNOWWHATIMDOING=1
  __zhm_update_region_highlight
}

function zhm_collapse_selection {
  zhm_cursors_selection_left=("$zhm_cursors_pos[@]")
  zhm_cursors_selection_right=("$zhm_cursors_pos[@]")
  __zhm_update_region_highlight
}

function zhm_flip_selections {
  local i
  for i in {1..$#zhm_cursors_pos}; do
    local left=$zhm_cursors_selection_left[$i]
    local right=$zhm_cursors_selection_right[$i]
    zhm_cursors_pos[$i]=$(( zhm_cursors_pos[i] == right ? left : right ))
  done
  __zhm_refresh
}

function zhm_ensure_selections_forward {
  zhm_cursors_pos=("$zhm_cursors_selection_right[@]")
  __zhm_update_last_moved
  __zhm_update_region_highlight
}

function zhm_keep_primary_selection {
  zhm_cursors_pos=( $zhm_cursors_pos[$ZHM_PRIMARY_CURSOR_IDX] )
  zhm_cursors_selection_left=( $zhm_cursors_selection_left[$ZHM_PRIMARY_CURSOR_IDX] )
  zhm_cursors_selection_right=( $zhm_cursors_selection_right[$ZHM_PRIMARY_CURSOR_IDX] )
  zhm_cursors_last_moved_x=( $zhm_cursors_last_moved_x[$ZHM_PRIMARY_CURSOR_IDX] )
  ZHM_PRIMARY_CURSOR_IDX=1
  __zhm_update_region_highlight
}

function zhm_remove_primary_selection {
  if (( ${#zhm_cursors_pos} <= 1 )); then
    return
  fi
  zhm_cursors_pos[$ZHM_PRIMARY_CURSOR_IDX]=()
  zhm_cursors_selection_left[$ZHM_PRIMARY_CURSOR_IDX]=()
  zhm_cursors_selection_right[$ZHM_PRIMARY_CURSOR_IDX]=()
  zhm_cursors_last_moved_x[$ZHM_PRIMARY_CURSOR_IDX]=()
  ZHM_PRIMARY_CURSOR_IDX=$(( ZHM_PRIMARY_CURSOR_IDX <= ${#zhm_cursors_pos} ? ZHM_PRIMARY_CURSOR_IDX : ${#zhm_cursors_pos} ))
  CURSOR=$zhm_cursors_pos[$ZHM_PRIMARY_CURSOR_IDX]
  ZHM_HOOK_IKNOWWHATIMDOING=1
  __zhm_update_region_highlight
}

# Makes the next (1) or previous (-1) selection the primary one
function __zhm_rotate_selections {
  local count=${#zhm_cursors_pos}
  ZHM_PRIMARY_CURSOR_IDX=$(( (ZHM_PRIMARY_CURSOR_IDX - 1 + $1 + count) % count + 1 ))
  CURSOR=$zhm_cursors_pos[$ZHM_PRIMARY_CURSOR_IDX]
  ZHM_HOOK_IKNOWWHATIMDOING=1
  __zhm_update_region_highlight
}

function zhm_rotate_selections_backward {
  __zhm_rotate_selections -1
}

function zhm_rotate_selections_forward {
  __zhm_rotate_selections 1
}

# Gives every selection the content of the next (1) or previous (-1) one,
# along with the side its cursor was on
function __zhm_rotate_selection_contents {
  local direction=$1
  local count=${#zhm_cursors_pos}
  local reply=()
  __zhm_selections_content
  local contents=("$reply[@]")

  local on_right=()
  local rotated=()
  local i
  for i in {1..$count}; do
    on_right+=($(( zhm_cursors_pos[i] == zhm_cursors_selection_right[i] )))
  done
  for i in {1..$count}; do
    rotated+=("$contents[$(( (i - 1 + direction + count) % count + 1 ))]")
  done

  __zhm_replace_selections 0 "$rotated[@]"
  for i in {1..$count}; do
    local source=$(( (i - 1 + direction + count) % count + 1 ))
    __zhm_select $i $zhm_cursors_selection_left[$i] $zhm_cursors_selection_right[$i] $on_right[$source]
  done

  ZHM_HOOK_IKNOWWHATIMDOING=1
  __zhm_refresh
}

function zhm_rotate_selection_contents_backward {
  __zhm_rotate_selection_contents 1
}

function zhm_rotate_selection_contents_forward {
  __zhm_rotate_selection_contents -1
}

function zhm_select_all {
  ZHM_PRIMARY_CURSOR_IDX=1
  zhm_cursors_pos=(${#BUFFER})
  zhm_cursors_selection_left=(0)
  zhm_cursors_selection_right=(${#BUFFER})
  __zhm_refresh
}

function zhm_extend_line_below {
  local i
  for i in {1..$#zhm_cursors_pos}; do
    local left=$zhm_cursors_selection_left[$i]
    local right=$zhm_cursors_selection_right[$i]

    local top_line_start=$(__zhm_find_line_start $left "$BUFFER")
    local bottom_line_end=$(__zhm_find_line_end $right "$BUFFER")
    if (( left == top_line_start && right == bottom_line_end )); then
      bottom_line_end=$(__zhm_find_line_end $((bottom_line_end + 1)) "$BUFFER")
    fi
    __zhm_select $i $top_line_start $bottom_line_end 1
  done

  __zhm_refresh
  ZHM_HOOK_IKNOWWHATIMDOING=1
}

function zhm_extend_to_line_bounds {
  local i
  for i in {1..$#zhm_cursors_pos}; do
    local left=$zhm_cursors_selection_left[$i]
    local right=$zhm_cursors_selection_right[$i]

    __zhm_select $i \
      $(__zhm_find_line_start $left "$BUFFER") \
      $(__zhm_find_line_end $right "$BUFFER") \
      $(( zhm_cursors_pos[i] == right ))
  done

  __zhm_refresh
  ZHM_HOOK_IKNOWWHATIMDOING=1
}

# Equivalent of `search_selection, select_mode, extend_search_next` followed by
# `normal_mode` (or `insert_mode` when used in insert mode)
function zhm_add_next_match {
  local primary_left=$zhm_cursors_selection_left[$ZHM_PRIMARY_CURSOR_IDX]
  local primary_right=$zhm_cursors_selection_right[$ZHM_PRIMARY_CURSOR_IDX]
  local needle="$BUFFER[$((primary_left + 1)),$((primary_right + 1))]"
  if [[ -z "$needle" ]]; then
    return
  fi
  local len=${#needle}

  local search_from=$((primary_right + 1))
  local wrapped=0
  local found=-1
  local i
  while (( found < 0 )); do
    local rest="${BUFFER:$search_from}"
    local before="${rest%%"$needle"*}"
    if (( ${#before} == ${#rest} )); then
      if (( wrapped )); then
        break
      fi
      wrapped=1
      search_from=0
      continue
    fi
    local match=$((search_from + ${#before}))
    if (( wrapped && match > primary_right )); then
      break
    fi

    found=$match
    for i in {1..$#zhm_cursors_pos}; do
      if (( !(match + len - 1 < zhm_cursors_selection_left[i] || match > zhm_cursors_selection_right[i]) )); then
        found=-1
        search_from=$((match + 1))
        break
      fi
    done
  done

  if (( found >= 0 )); then
    # Keeps the cursors sorted by position
    local idx=1
    while (( idx <= $#zhm_cursors_pos && zhm_cursors_selection_left[idx] < found )); do
      idx=$((idx + 1))
    done
    local pos=$((found + len - 1))
    if [[ $ZHM_MODE == insert ]]; then
      pos=$found
    fi
    zhm_cursors_pos[$idx,$((idx - 1))]=($pos)
    zhm_cursors_selection_left[$idx,$((idx - 1))]=($found)
    zhm_cursors_selection_right[$idx,$((idx - 1))]=($((found + len - 1)))
    ZHM_PRIMARY_CURSOR_IDX=$idx
  fi

  __zhm_exit_select_mode
  __zhm_refresh
  ZHM_HOOK_IKNOWWHATIMDOING=1
}

# Goto =========================================================================

function zhm_goto_first_line {
  local i
  for i in {1..$#zhm_cursors_pos}; do
    __zhm_goto $i 0
  done
  __zhm_refresh
}

function zhm_goto_last_line {
  local last_line_start=$(__zhm_find_line_start ${#BUFFER} "$BUFFER")
  local i
  for i in {1..$#zhm_cursors_pos}; do
    __zhm_goto $i $last_line_start
  done
  __zhm_refresh
}

function zhm_goto_line_start {
  local i
  for i in {1..$#zhm_cursors_pos}; do
    __zhm_goto $i $(__zhm_find_line_start $zhm_cursors_pos[$i] "$BUFFER")
  done
  __zhm_refresh
}

function zhm_goto_line_end {
  local i
  for i in {1..$#zhm_cursors_pos}; do
    local line_end=$(__zhm_find_line_end $zhm_cursors_pos[$i] "$BUFFER")
    if [[
      "$BUFFER[$((line_end + 1))]" == $'\n'
      && "$BUFFER[$line_end]" != $'\n'
    ]]; then
      line_end=$((line_end - 1))
    fi
    __zhm_goto $i $line_end
  done
  __zhm_refresh
}

function zhm_goto_line_first_nonwhitespace {
  setopt localoptions rematchpcre
  local i
  for i in {1..$#zhm_cursors_pos}; do
    local line_start=$(__zhm_find_line_start $zhm_cursors_pos[$i] "$BUFFER")
    if [[ "${BUFFER:$line_start}" =~ '\A[^\S\n]*' ]]; then
      __zhm_goto $i $((line_start + MEND))
    fi
  done
  __zhm_refresh
}

# Match ========================================================================

function __zhm_find_surround_pair {
  local left_char="$1"
  local right_char="$2"
  local left_count=0
  local right_count=0
  local cursor=$3
  local left_pos=$cursor
  local right_pos=$cursor
  local content=$4

  if [[ "${content[$cursor]}" == "$left_char" ]]; then
    left_count=$((left_count + 1))
  elif [[ "${content[$cursor]}" == "$right_char" ]]; then
    right_count=$((right_count + 1))
  fi

  while true; do
    if (( left_count == 1 && right_count == 1 )); then
      echo $left_pos $right_pos
      return 0
    elif (( left_count > right_count )); then
      right_pos=$((right_pos + 1))

      local char="${content[$right_pos]}"
      if [[ "$char" == "$right_char" ]]; then
        right_count=$((right_count + 1))
      elif [[ "$char" == "$left_char" ]]; then
        right_count=$((right_count - 1))
      fi
    else
      left_pos=$((left_pos - 1))

      local char="${content[$left_pos]}"
      if [[ "$char" == "$left_char" ]]; then
        left_count=$((left_count + 1))
      elif [[ "$char" == "$right_char" ]]; then
        left_count=$((left_count - 1))
      fi
    fi

    if (( left_pos == 0 || right_pos > ${#content} )); then
      return 1
    fi
  done
}

# Sets `reply` to the 0-based positions of the pair of `char` surrounding `pos`,
# or of the closest pair of any kind if `char` is `m`. Fails if there is none
function __zhm_find_pair {
  local char=$1
  local pos=$2
  local chars=("$char")
  if [[ "$char" == m ]]; then
    chars=("(" "[" "{" "<" "\"" "'" "\`")
  fi

  local best_left=-1
  local best_right=-1
  local c result
  for c in "$chars[@]"; do
    __zhm_surround_chars "$c"
    result=$(__zhm_find_surround_pair "$reply[1]" "$reply[2]" $((pos + 1)) "$BUFFER") || continue
    if (( ${result% *} - 1 > best_left )); then
      best_left=$((${result% *} - 1))
      best_right=$((${result#* } - 1))
    fi
  done

  (( best_left >= 0 )) || return 1
  reply=($best_left $best_right)
}

function zhm_match_brackets {
  local reply=()
  local i
  for i in {1..$#zhm_cursors_pos}; do
    local cursor=$zhm_cursors_pos[$i]
    local char="${BUFFER[$((cursor + 1))]}"
    if [[ -z "$char" || "()[]{}<>'\"\`" != *"$char"* ]]; then
      continue
    fi
    __zhm_surround_chars "$char"

    local result=
    result=$(__zhm_find_surround_pair "$reply[1]" "$reply[2]" $((cursor + 1)) "$BUFFER") || continue
    local left=$((${result% *} - 1))
    local right=$((${result#* } - 1))
    if (( cursor == left )); then
      __zhm_goto $i $right
    elif (( cursor == right )); then
      __zhm_goto $i $left
    fi
  done

  __zhm_refresh
}

function zhm_surround_add {
  local char="$(read -ek 1)"
  local reply=()
  __zhm_surround_chars "$char"
  local left_char="$reply[1]"
  local right_char="$reply[2]"

  local amount_inserted=0
  local i
  for i in {1..$#zhm_cursors_pos}; do
    local cursor=$((zhm_cursors_pos[i] + amount_inserted))
    local left=$((zhm_cursors_selection_left[i] + amount_inserted))
    local right=$((zhm_cursors_selection_right[i] + amount_inserted))

    BUFFER="${BUFFER:0:$left}$left_char${BUFFER:$left:$((right - left + 1))}$right_char${BUFFER:$((right + 1))}"

    __zhm_select $i $left $((right + 2)) $(( cursor == right ))
    amount_inserted=$((amount_inserted + 2))
  done

  __zhm_refresh
}

# Prints the number of `positions` before `pos`, or up to `pos` if `inclusive`
function __zhm_count_before {
  local pos=$1
  local inclusive=$2
  shift 2
  local count=0
  local p
  for p in "$@"; do
    if (( p < pos || (inclusive && p == pos) )); then
      count=$((count + 1))
    fi
  done
  echo $count
}

function zhm_surround_delete {
  local char="$(read -ek 1)"
  local reply=()
  local positions=()
  local i
  for i in {1..$#zhm_cursors_pos}; do
    __zhm_find_pair "$char" $zhm_cursors_pos[$i] || continue
    positions+=($reply)
  done
  # Cursors inside the same pair share its positions
  positions=(${(nuO)positions})

  local p
  for p in $positions; do
    BUFFER="${BUFFER:0:$p}${BUFFER:$((p + 1))}"
  done

  for i in {1..$#zhm_cursors_pos}; do
    local cursor=$zhm_cursors_pos[$i]
    local left=$zhm_cursors_selection_left[$i]
    local right=$zhm_cursors_selection_right[$i]
    local new_left=$((left - $(__zhm_count_before $left 0 $positions)))
    local new_right=$((right - $(__zhm_count_before $right 1 $positions)))
    if (( new_right < new_left )); then
      new_right=$new_left
    fi
    __zhm_select $i $new_left $new_right $(( cursor == right && cursor != left ))
  done

  __zhm_exit_select_mode
  __zhm_refresh
  ZHM_HOOK_IKNOWWHATIMDOING=1
}

function zhm_surround_replace {
  local from="$(read -ek 1)"
  local to="$(read -ek 1)"
  local reply=()
  __zhm_surround_chars "$to"
  local left_char="$reply[1]"
  local right_char="$reply[2]"

  # Replacing characters one for one keeps every position valid
  local i
  for i in {1..$#zhm_cursors_pos}; do
    __zhm_find_pair "$from" $zhm_cursors_pos[$i] || continue
    local left=$reply[1]
    local right=$reply[2]
    BUFFER="${BUFFER:0:$left}$left_char${BUFFER:$((left + 1))}"
    BUFFER="${BUFFER:0:$right}$right_char${BUFFER:$((right + 1))}"
  done

  __zhm_exit_select_mode
  __zhm_refresh
  ZHM_HOOK_IKNOWWHATIMDOING=1
}

# Selects around every cursor the text object starting at the match of
# `start_regex` ending at the cursor, and extending over the match of the first
# of the following regexes matching from there
function __zhm_select_text_object {
  local start_regex=$1
  shift
  local i
  for i in {1..$#zhm_cursors_pos}; do
    local cursor=$zhm_cursors_pos[$i]
    zhm_cursors_selection_left[$i]=$cursor
    zhm_cursors_selection_right[$i]=$cursor
    if (( cursor == ${#BUFFER} )) \
      || ! [[ "${BUFFER:0:$((cursor + 1))}" =~ $start_regex ]]; then
      continue
    fi

    local start=$((MBEGIN - 1))
    local end_regex
    for end_regex in "$@"; do
      if [[ "${BUFFER:$start}" =~ $end_regex ]]; then
        __zhm_select $i $((start + MBEGIN - 1)) $((start + MEND - 1)) 1
        break
      fi
    done
  done

  __zhm_refresh
  ZHM_HOOK_IKNOWWHATIMDOING=1
}

function zhm_select_word_inner {
  __zhm_select_text_object '\w+$' '^\w+'
}

function zhm_select_word_around {
  __zhm_select_text_object ' *\w+$' '\w+ +' '^ *\w+'
}

function zhm_select_long_word_inner {
  __zhm_select_text_object '[^ ]+ ?$' '[^ ]+'
}

function zhm_select_long_word_around {
  __zhm_select_text_object ' *[^ ]+ ?$' '[^ ]+ +' '^ *[^ ]+'
}

# Selects the pair of the character typed after `mi` or `ma` surrounding every
# cursor, excluding the pair characters themselves if `inner` is 1
function __zhm_select_surround_pair {
  local inner=$1
  local reply=()

  local i
  for i in {1..$#zhm_cursors_pos}; do
    local cursor=$zhm_cursors_pos[$i]
    __zhm_find_pair "${KEYS:2}" $cursor || continue
    __zhm_select $i \
      $((reply[1] + inner)) \
      $((reply[2] - inner)) \
      $(( cursor == zhm_cursors_selection_right[i] ))
  done

  ZHM_HOOK_IKNOWWHATIMDOING=1
  __zhm_refresh
}

function zhm_select_surround_pair_around {
  __zhm_select_surround_pair 0
}

function zhm_select_surround_pair_inner {
  __zhm_select_surround_pair 1
}

# Insert =======================================================================

# Inserts `text` at every cursor
function __zhm_insert_text {
  local text="$1"
  local inserted_count=0
  local i
  for i in {1..$#zhm_cursors_pos}; do
    local prev_cursor=$zhm_cursors_pos[$i]
    local cursor=$((prev_cursor + inserted_count))
    local left=$zhm_cursors_selection_left[$i]

    BUFFER="${BUFFER:0:$cursor}${text}${BUFFER:$cursor}"

    zhm_cursors_pos[$i]=$((cursor + ${#text}))
    if (( prev_cursor == left )); then
      zhm_cursors_selection_left[$i]=$((left + inserted_count + ${#text}))
    else
      zhm_cursors_selection_left[$i]=$((left + inserted_count))
    fi
    zhm_cursors_selection_right[$i]=$((zhm_cursors_selection_right[i] + inserted_count + ${#text}))

    inserted_count=$((inserted_count + ${#text}))
  done
  ZHM_HOOK_IKNOWWHATIMDOING=1
  __zhm_refresh
}

function zhm_self_insert {
  __zhm_insert_text "$KEYS"
}

function zhm_insert_newline {
  __zhm_insert_text $'\n'
}

function zhm_insert_register {
  local register="$(read -ek 1)"

  local amount_pasted=0
  local i
  for i in {1..$#zhm_cursors_pos}; do
    local cursor=$((zhm_cursors_pos[$i] + amount_pasted))
    local left=$((zhm_cursors_selection_left[$i] + amount_pasted))
    local right=$((zhm_cursors_selection_right[$i] + amount_pasted))
    zhm_cursors_pos[$i]=$cursor
    zhm_cursors_selection_left[$i]=$left
    zhm_cursors_selection_right[$i]=$right

    local content=$(__zhm_read_register "$register" $i)

    BUFFER="${BUFFER:0:$left}$content${BUFFER:$left}"

    if (( cursor == left )); then
      zhm_cursors_selection_left[$i]=$((left + ${#content}))
      zhm_cursors_selection_right[$i]=$((right + ${#content}))
      zhm_cursors_pos[$i]=$((cursor + ${#content}))
    elif (( (cursor - 1) == right )); then
      zhm_cursors_selection_right[$i]=$((right + ${#content}))
      zhm_cursors_pos[$i]=$((cursor + ${#content}))
    fi

    amount_pasted=$((amount_pasted + ${#content}))
  done

  ZHM_HOOK_IKNOWWHATIMDOING=1
  __zhm_refresh
}

function zhm_delete_char_backward {
  local removed_count=0
  local i
  for i in {1..$#zhm_cursors_pos}; do
    local prev_cursor=$zhm_cursors_pos[$i]
    local cursor=$((prev_cursor - removed_count))

    if ((cursor > 0)); then
      BUFFER="${BUFFER:0:$((cursor - 1))}${BUFFER:$cursor}"

      zhm_cursors_pos[$i]=$((cursor - 1))
      removed_count=$((removed_count + 1))

      if (( prev_cursor == zhm_cursors_selection_left[i] )); then
        zhm_cursors_selection_left[$i]=$((zhm_cursors_selection_left[i] - removed_count))
        zhm_cursors_selection_right[$i]=$((zhm_cursors_selection_right[i] - removed_count))
      else
        zhm_cursors_selection_right[$i]=$((zhm_cursors_selection_right[i] - removed_count))
        if (( zhm_cursors_selection_right[i] < zhm_cursors_selection_left[i] )); then
          zhm_cursors_selection_left[$i]=$zhm_cursors_selection_right[$i]
        fi
      fi
    fi
  done

  __zhm_refresh
}

# Prompt =======================================================================

function zhm_prompt_self_insert {
  zle .self-insert
}

function zhm_prompt_delete_char_backward {
  zle backward-delete-char
}

function zhm_prompt_accept {
  zle accept-line
}

function zhm_prompt_exit {
  zle send-break
}

# Zsh specifics ================================================================

# Browses the history with `widget`, putting a single cursor at the end
function __zhm_history {
  __zhm_exit_select_mode

  zle $1

  CURSOR=${#BUFFER}
  __zhm_reset_cursors $CURSOR

  ZHM_RECORD_CHANGES=0

  __zhm_update_last_moved
  __zhm_update_region_highlight
}

function zhm_history_prev {
  __zhm_history up-history
}

function zhm_history_next {
  __zhm_history down-history
}

# Called after a widget wrapped with `zhm_wrap_widget`. Puts a single cursor at
# `CURSOR`, selecting from `cursor_before` if `with_selection` is 1
function __zhm_after_wrapped_widget {
  local cursor_before=$1
  local with_selection=$2

  __zhm_reset_cursors $CURSOR
  if (( with_selection )); then
    zhm_cursors_selection_left=($(( CURSOR < cursor_before ? CURSOR : cursor_before )))
    zhm_cursors_selection_right=($(( CURSOR > cursor_before ? CURSOR : cursor_before )))
  fi

  __zhm_update_last_moved
  __zhm_update_region_highlight
}

# Wrap existing widget with extra ZHM compatibility code
# If `with_selection` is 1, also select the differences between cursor positions
function zhm_wrap_widget {
  local prev_name="$1"
  local new_name="$2"
  local with_selection="${3:-0}"

  functions[$new_name]="
    local cursor_before=\$CURSOR
    zle ${(q)prev_name}
    __zhm_after_wrapped_widget \$cursor_before $with_selection
  "

  zle -N $new_name
}

# Like `zhm_wrap_widget` but also select the differences between cursor positions
function zhm_wrap_widget_with_selection {
  zhm_wrap_widget "$1" "$2" 1
}

function zhm_accept {
  zle accept-line
  ZHM_ACCEPTING=1
}

function zhm_accept_then_insert_mode {
  zhm_insert
  zhm_accept
}

function zhm_accept_or_insert_newline {
  if (( ZHM_MULTILINE == 1 )); then
    zhm_insert_newline
  else
    zhm_accept
  fi
}

function zhm_accept_then_insert_mode_or_insert_newline {
  if (( ZHM_MULTILINE == 1 )); then
    zhm_insert_newline
  else
    zhm_accept_then_insert_mode
  fi
}

# Makes zsh-autosuggestions accept the suggestion with the ZHM widgets that move
# right. Does nothing until zsh-autosuggestions has declared its widget lists
function __zhm_register_autosuggest_widgets {
  (( ${+ZSH_AUTOSUGGEST_ACCEPT_WIDGETS} )) || return
  local widget
  for widget in zhm_move_right zhm_clear_selection_move_right zhm_goto_line_end; do
    if (( ! ${ZSH_AUTOSUGGEST_ACCEPT_WIDGETS[(Ie)$widget]} )); then
      ZSH_AUTOSUGGEST_ACCEPT_WIDGETS+=($widget)
    fi
  done
}

# Hooks ========================================================================

function zhm_precmd {
  __zhm_reset_cursors 0
  ZHM_PRIMARY_CURSOR_IDX=1

  ZHM_MULTILINE=0

  __zhm_reset_history

  ZHM_ACCEPTING=0

  # Runs before zsh-autosuggestions binds its widgets when it is sourced after
  __zhm_register_autosuggest_widgets

  local cursor_var=ZHM_CURSOR_${(U)ZHM_MODE}
  printf "${(P)cursor_var}"
}

function zhm_preexec {
  printf "$ZHM_CURSOR_NORMAL"
}

precmd_functions+=(zhm_precmd)
preexec_functions+=(zhm_preexec)

function zhm_zle_line_pre_redraw {
  # Keeps selection range in check

  if (( ZHM_ACCEPTING == 1)); then
    __zhm_clear_region_highlight
    return
  fi

  if (( ZHM_IN_PROMPT == 0 )); then
    # Follows `CURSOR` if it was moved by something else than ZHM
    if (( ZHM_HOOK_IKNOWWHATIMDOING == 0 )); then
      case "$ZHM_PREV_MODE $ZHM_MODE" in
        "normal normal" | "insert insert")
          local idx=$ZHM_PRIMARY_CURSOR_IDX
          if [[ $ZHM_MODE == insert ]] && (( CURSOR != ZHM_PREV_CURSOR
            && zhm_cursors_selection_left[idx] == zhm_cursors_pos[idx]
            && zhm_cursors_selection_right[idx] == zhm_cursors_pos[idx] )); then
            # A collapsed cursor stays collapsed, like the insert mode arrows
            __zhm_select $idx $CURSOR $CURSOR 1
          elif (( CURSOR > ZHM_PREV_CURSOR )); then
            zhm_cursors_selection_right[$ZHM_PRIMARY_CURSOR_IDX]=$CURSOR
            zhm_cursors_pos[$ZHM_PRIMARY_CURSOR_IDX]=$CURSOR
          elif (( CURSOR < ZHM_PREV_CURSOR )); then
            zhm_cursors_selection_left[$ZHM_PRIMARY_CURSOR_IDX]=$CURSOR
            zhm_cursors_pos[$ZHM_PRIMARY_CURSOR_IDX]=$CURSOR
          fi
          ;;
      esac
    fi

    local len=$#BUFFER
    local i
    for i in {1..$#zhm_cursors_pos}; do
      local pos=$zhm_cursors_pos[$i]
      local left=$zhm_cursors_selection_left[$i]
      local right=$zhm_cursors_selection_right[$i]
      zhm_cursors_pos[$i]=$(( pos < 0 ? 0 : pos > len ? len : pos ))
      zhm_cursors_selection_left[$i]=$(( left < 0 ? 0 : left > len ? len : left ))
      zhm_cursors_selection_right[$i]=$(( right < 0 ? 0 : right > len ? len : right ))
    done

    __zhm_merge_cursors
    __zhm_update_region_highlight

    ZHM_HOOK_IKNOWWHATIMDOING=0
    ZHM_PREV_CURSOR=$CURSOR
    ZHM_PREV_MODE=$ZHM_MODE
    if (( ZHM_JUST_SELECTED_REGISTER == 0 )); then
      ZHM_CURRENT_REGISTER="\""
    else
      ZHM_JUST_SELECTED_REGISTER=0
    fi

    # Hook based history so if 3rd plugin changed the buffer,
    # it will still recorded into the changes history

    if [[ $ZHM_MODE == insert ]]; then
      ZHM_RECORD_CHANGES=0
    fi

    if (( ZHM_RECORD_CHANGES == 1 )); then
      if [[ "$BUFFER" != "$zhm_changes_history_buffer[$ZHM_CHANGES_HISTORY_IDX]" ]]; then
        if (( ${#zhm_changes_history_buffer} > ZHM_CHANGES_HISTORY_IDX )); then
          __zhm_trim_history
        fi
        __zhm_push_history_cursors pre _prev $ZHM_PRIMARY_CURSOR_IDX_PREV
        __zhm_push_history_cursors post "" $ZHM_PRIMARY_CURSOR_IDX
        zhm_changes_history_buffer+=("$BUFFER")
        ZHM_CHANGES_HISTORY_IDX=$((ZHM_CHANGES_HISTORY_IDX + 1))
      fi

      ZHM_PRIMARY_CURSOR_IDX_PREV=$ZHM_PRIMARY_CURSOR_IDX
      zhm_cursors_pos_prev=($zhm_cursors_pos)
      zhm_cursors_selection_left_prev=($zhm_cursors_selection_left)
      zhm_cursors_selection_right_prev=($zhm_cursors_selection_right)
    fi
    ZHM_RECORD_CHANGES=1
  else
    if [[ -n "$ZHM_PROMPT_HOOK" ]]; then
      eval $ZHM_PROMPT_HOOK
    fi
    __zhm_update_region_highlight
  fi

  if (( ZHM_MESSAGE_CLEAR_DELAY > 0 )); then
    ZHM_MESSAGE_CLEAR_DELAY=$((ZHM_MESSAGE_CLEAR_DELAY - 1))
    if (( ZHM_MESSAGE_CLEAR_DELAY == 0 )); then
      zle -M ""
    fi
  fi
}

autoload -Uz add-zle-hook-widget
add-zle-hook-widget zle-line-pre-redraw zhm_zle_line_pre_redraw

function zhm-add-update-region-highlight-hook {
  function zhm-update-region-highlight {
    if (( ZHM_ACCEPTING == 1)); then
      __zhm_clear_region_highlight
      return
    fi
    __zhm_update_region_highlight
  }
  add-zle-hook-widget zle-line-pre-redraw zhm-update-region-highlight
}

# Widgets ======================================================================

# Every `zhm_*` function is a widget, except for the hooks and helpers below
() {
  local widget
  for widget in ${(k)functions[(I)zhm_*]}; do
    case $widget in
      zhm_precmd | zhm_preexec | zhm_zle_line_pre_redraw | zhm_wrap_widget*)
        ;;
      *)
        zle -N $widget
        ;;
    esac
  done
}

zhm_wrap_widget expand-or-complete zhm_expand_or_complete
zhm_wrap_widget bracketed-paste zhm_bracketed_paste

# Keybindings ==================================================================

bindkey -N hxnor vicmd
bindkey -N hxins viins
bindkey -N hxprompt
# Unbind vicmd keys that prefix minor modes, so that ZLE waits for the rest of
# the sequence instead of running them after KEYTIMEOUT
bindkey -M hxnor -r m ' '

# Normal: Movement -------------------------------------------------------------
bindkey -M hxnor h zhm_move_left
bindkey -M hxnor j zhm_move_down_or_history_next
bindkey -M hxnor k zhm_move_up_or_history_prev
bindkey -M hxnor l zhm_move_right
bindkey -M hxnor w zhm_move_next_word_start
bindkey -M hxnor b zhm_move_prev_word_start
bindkey -M hxnor e zhm_move_next_word_end
bindkey -M hxnor W zhm_move_next_long_word_start
bindkey -M hxnor B zhm_move_prev_long_word_start
bindkey -M hxnor E zhm_move_next_long_word_end
bindkey -M hxnor t zhm_find_till_char
bindkey -M hxnor f zhm_find_next_char
bindkey -M hxnor T zhm_till_prev_char
bindkey -M hxnor F zhm_find_prev_char
bindkey -M hxnor "^[." zhm_repeat_last_motion

bindkey -M hxnor "^[OC" zhm_move_right
bindkey -M hxnor "^[OD" zhm_move_left
bindkey -M hxnor "^[[C" zhm_move_right
bindkey -M hxnor "^[[D" zhm_move_left

# Normal: Changes --------------------------------------------------------------
bindkey -M hxnor r zhm_replace
bindkey -M hxnor R zhm_replace_with_yanked
bindkey -M hxnor "~" zhm_switch_case
bindkey -M hxnor "\`" zhm_switch_to_lowercase
bindkey -M hxnor "^[\`" zhm_switch_to_uppercase
bindkey -M hxnor i zhm_insert
bindkey -M hxnor a zhm_append
bindkey -M hxnor I zhm_insert_at_line_start
bindkey -M hxnor A zhm_insert_at_line_end
bindkey -M hxnor o zhm_open_below
bindkey -M hxnor O zhm_open_above
bindkey -M hxnor u zhm_undo
bindkey -M hxnor U zhm_redo
bindkey -M hxnor y zhm_yank
bindkey -M hxnor p zhm_paste_after_or_replace_with_yanked
bindkey -M hxnor P zhm_paste_before
bindkey -M hxnor d zhm_delete
bindkey -M hxnor c zhm_change
bindkey -M hxnor "\"" zhm_select_register

# Normal: Shell ----------------------------------------------------------------
bindkey -M hxnor "|" zhm_shell_pipe

# Normal: Selection manipulation -----------------------------------------------
bindkey -M hxnor s zhm_select_regex
bindkey -M hxnor "_" zhm_trim_selections
bindkey -M hxnor \; zhm_collapse_selection
bindkey -M hxnor "^[;" zhm_flip_selections
bindkey -M hxnor "^[:" zhm_ensure_selections_forward
bindkey -M hxnor "," zhm_keep_primary_selection
bindkey -M hxnor "^[," zhm_remove_primary_selection
bindkey -M hxnor "(" zhm_rotate_selections_backward
bindkey -M hxnor ")" zhm_rotate_selections_forward
bindkey -M hxnor "^[(" zhm_rotate_selection_contents_backward
bindkey -M hxnor "^[)" zhm_rotate_selection_contents_forward
bindkey -M hxnor % zhm_select_all
bindkey -M hxnor x zhm_extend_line_below
bindkey -M hxnor X zhm_extend_to_line_bounds

# Normal: Minor modes ----------------------------------------------------------
# Other keys is available inside `Normal/<minor mode>` sections.

bindkey -M hxnor v zhm_select
bindkey -M hxnor '^[' zhm_normal
bindkey -M hxnor ":" zhm_command_mode

# Normal/Goto ------------------------------------------------------------------
bindkey -M hxnor gg zhm_goto_first_line
bindkey -M hxnor ge zhm_goto_last_line
bindkey -M hxnor gh zhm_goto_line_start
bindkey -M hxnor gl zhm_goto_line_end
bindkey -M hxnor gs zhm_goto_line_first_nonwhitespace
bindkey -M hxnor "g^[[C" zhm_goto_line_end
bindkey -M hxnor "g^[OC" zhm_goto_line_end
bindkey -M hxnor "g^[[D" zhm_goto_line_start
bindkey -M hxnor "g^[OD" zhm_goto_line_start

# Normal/Match -----------------------------------------------------------------
bindkey -M hxnor mm zhm_match_brackets
bindkey -M hxnor ms zhm_surround_add
bindkey -M hxnor md zhm_surround_delete
bindkey -M hxnor mr zhm_surround_replace
() {
  local char
  for char in "(" ")" "[" "]" "<" ">" "{" "}" "\"" "'" "\`" m; do
    bindkey -M hxnor "mi$char" zhm_select_surround_pair_inner
    bindkey -M hxnor "ma$char" zhm_select_surround_pair_around
  done
}
bindkey -M hxnor 'miw' zhm_select_word_inner
bindkey -M hxnor 'maw' zhm_select_word_around
bindkey -M hxnor 'miW' zhm_select_long_word_inner
bindkey -M hxnor 'maW' zhm_select_long_word_around

# Normal/Space -----------------------------------------------------------------
bindkey -M hxnor ' y' zhm_clipboard_yank
bindkey -M hxnor ' p' zhm_clipboard_paste_after_or_replace
bindkey -M hxnor ' P' zhm_clipboard_paste_before
bindkey -M hxnor ' R' zhm_replace_selections_with_clipboard

# Normal: Plugin specifics -----------------------------------------------------
bindkey -M hxnor '^J' zhm_accept
bindkey -M hxnor '^M' zhm_accept

# Insert -----------------------------------------------------------------------
# bindkey -M hxins "jk" zhm_normal
bindkey -M hxins '^[' zhm_normal

# bindkey -M hxins '^R'"$char" zhm_insert_register
bindkey -M hxins -R ' '-'~' zhm_self_insert
bindkey -M hxins '^?' zhm_delete_char_backward

bindkey -M hxins '^I' zhm_expand_or_complete
bindkey -M hxins '^@' zhm_expand_or_complete

# Insert: Movement -------------------------------------------------------------
bindkey -M hxins "^[OC" zhm_clear_selection_move_right
bindkey -M hxins "^[OD" zhm_clear_selection_move_left
bindkey -M hxins "^[[C" zhm_clear_selection_move_right
bindkey -M hxins "^[[D" zhm_clear_selection_move_left

# Insert: Plugin specifics -----------------------------------------------------
bindkey -M hxins '^J' zhm_accept_or_insert_newline
bindkey -M hxins '^M' zhm_accept_or_insert_newline

# Normal & Insert --------------------------------------------------------------
() {
  local keymap
  for keymap in hxnor hxins; do
    # Movement
    bindkey -M $keymap "^[OA" zhm_move_up_or_history_prev
    bindkey -M $keymap "^[OB" zhm_move_down_or_history_next
    bindkey -M $keymap "^[[A" zhm_move_up_or_history_prev
    bindkey -M $keymap "^[[B" zhm_move_down_or_history_next

    # Custom config
    bindkey -M $keymap "^D" zhm_add_next_match
    bindkey -M $keymap "^[[1;3B" zhm_move_lines_down
    bindkey -M $keymap "^[^[[B" zhm_move_lines_down
    bindkey -M $keymap "^[[1;3A" zhm_move_lines_up
    bindkey -M $keymap "^[^[[A" zhm_move_lines_up

    # Plugin specifics
    bindkey -M $keymap '^[[200~' zhm_bracketed_paste
    bindkey -M $keymap '^N' zhm_history_next
    bindkey -M $keymap '^P' zhm_history_prev
    bindkey -M $keymap '^[^M' zhm_multiline
    bindkey -M $keymap '^[^J' zhm_multiline
  done
}

# Prompt -----------------------------------------------------------------------
bindkey -M hxprompt -R ' '-'~' zhm_prompt_self_insert
bindkey -M hxprompt '^?' zhm_prompt_delete_char_backward
bindkey -M hxprompt '^J' zhm_prompt_accept
bindkey -M hxprompt '^M' zhm_prompt_accept
bindkey -M hxprompt '^[' zhm_prompt_exit

# Initializing the editor ======================================================

__zhm_reset_history
__zhm_register_autosuggest_widgets
bindkey -A hxins main
