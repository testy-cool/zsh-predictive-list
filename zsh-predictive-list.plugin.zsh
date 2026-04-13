# zsh-predictive-list — PSReadLine ListView prediction for zsh
#
# Predictions come only from commands that exited 0.
# No ghost text — clean list below the prompt, exactly like PSReadLine.
# Requires zsh >= 5.4 (for zle-line-pre-redraw).

# Clean up history-list plugin hooks if present
zmodload -F zsh/stat b:zstat 2>/dev/null
autoload -Uz add-zle-hook-widget
for _zpred_fn in _zhl_line_preredraw _zhl_line_init _zhl_line_finish; do
  add-zle-hook-widget -d line-pre-redraw $_zpred_fn 2>/dev/null
  add-zle-hook-widget -d line-init       $_zpred_fn 2>/dev/null
  add-zle-hook-widget -d line-finish     $_zpred_fn 2>/dev/null
done
unset _zpred_fn

(( ${+_ZPRED_LOADED} )) && return 0
typeset -gi _ZPRED_LOADED=1

# ── Configuration ───────────────────────────────────────────────
typeset -g  ZPRED_HISTORY="${ZPRED_HISTORY:-${XDG_DATA_HOME:-$HOME/.local/share}/zsh-predictive-list/success_history}"
typeset -gi ZPRED_MAX_SHOW=${ZPRED_MAX_SHOW:-6}
typeset -g  ZPRED_STYLE_EMPHASIS="${ZPRED_STYLE_EMPHASIS:-fg=yellow}"
typeset -g  ZPRED_STYLE_SELECTED="${ZPRED_STYLE_SELECTED:-standout}"
typeset -g  ZPRED_STYLE_DIM="${ZPRED_STYLE_DIM:-fg=8}"
typeset -gi ZPRED_ENABLED=1

# ── Internal state ──────────────────────────────────────────────
typeset -ga _zpred_mem=()          # success history (most-recent-first, deduped)
typeset -ga _zpred_matches=()     # current prefix matches
typeset -gi _zpred_sel=-1         # -1 = no selection, 0+ = selected index
typeset -g  _zpred_typed=""       # what the user actually typed (before navigation)
typeset -gi _zpred_dismissed=0    # 1 = list hidden by Escape
typeset -gi _zpred_navigating=0   # 1 = skip next pre-redraw (we changed BUFFER ourselves)
typeset -ga _zpred_hl=()          # our region_highlight entries
typeset -g  _zpred_prev_buf=""    # change detection
typeset -g  _zpred_last_cmd=""    # captured in preexec
typeset -g  _zpred_hist_mtime="" # mtime of history file (for cross-session sync)

# ── History I/O ─────────────────────────────────────────────────
_zpred_load() {
  _zpred_mem=()
  [[ -r "$ZPRED_HISTORY" ]] || return 0
  local -A seen=()
  local line
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    (( ${+seen[$line]} )) && continue
    seen[$line]=1
    _zpred_mem+=("$line")
  done < <(tac "$ZPRED_HISTORY" 2>/dev/null || tail -r "$ZPRED_HISTORY")
}

_zpred_record() {
  local cmd="$1"
  [[ -d "${ZPRED_HISTORY:h}" ]] || mkdir -p "${ZPRED_HISTORY:h}"
  print -r -- "$cmd" >> "$ZPRED_HISTORY"
  _zpred_mem=("$cmd" "${(@)_zpred_mem:#$cmd}")
}

_zpred_sync() {
  [[ -r "$ZPRED_HISTORY" ]] || return 0
  local mtime
  mtime=$(zstat +mtime "$ZPRED_HISTORY" 2>/dev/null) || \
    mtime=$(command stat -c %Y "$ZPRED_HISTORY" 2>/dev/null) || return 0
  [[ "$mtime" == "$_zpred_hist_mtime" ]] && return 0
  _zpred_hist_mtime="$mtime"
  _zpred_load
}

# ── Hooks ───────────────────────────────────────────────────────
_zpred_preexec() { _zpred_last_cmd="$1"; }

_zpred_precmd() {
  local rc=$?
  _zpred_sync
  if [[ -n "$_zpred_last_cmd" ]] && (( rc == 0 )); then
    [[ "$_zpred_last_cmd" != *$'\n'* ]] && _zpred_record "$_zpred_last_cmd"
  fi
  _zpred_last_cmd=""
}

autoload -Uz add-zsh-hook
add-zsh-hook preexec _zpred_preexec
add-zsh-hook precmd  _zpred_precmd

# ── Matching ────────────────────────────────────────────────────
_zpred_match() {
  _zpred_matches=()
  (( ZPRED_ENABLED )) || return
  [[ -n "$_zpred_typed" ]] || return
  local c
  for c in "${_zpred_mem[@]}"; do
    [[ "$c" == "$_zpred_typed"* && "$c" != "$_zpred_typed" ]] || continue
    _zpred_matches+=("$c")
    (( ${#_zpred_matches} >= ZPRED_MAX_SHOW )) && break
  done
}

# ── Display ─────────────────────────────────────────────────────
_zpred_clear_display() {
  local h
  for h in "${_zpred_hl[@]}"; do
    region_highlight=("${(@)region_highlight:#$h}")
  done
  _zpred_hl=()
  POSTDISPLAY=""
}

_zpred_hl_add() {
  _zpred_hl+=("$1")
  region_highlight+=("$1")
}

_zpred_render() {
  _zpred_clear_display
  _zpred_match

  local count=${#_zpred_matches}
  (( count )) || return
  (( _zpred_dismissed )) && return

  local pos=$#BUFFER
  local pd=""
  local typed_len=${#_zpred_typed}

  # ── Header: [sel/count] ──
  local sel_label
  (( _zpred_sel >= 0 )) && sel_label="$(( _zpred_sel + 1 ))" || sel_label="-"
  local header="[${sel_label}/${count}]"

  pd+=$'\n'"$header"
  (( pos += 1 ))
  _zpred_hl_add "$pos $(( pos + ${#header} )) $ZPRED_STYLE_DIM"
  (( pos += ${#header} ))

  # ── List items ──
  local i match cmd_display line
  local cmd_max=$(( ${COLUMNS:-80} - 4 ))
  (( cmd_max < 20 )) && cmd_max=20

  for (( i = 1; i <= count; i++ )); do
    match="${_zpred_matches[$i]}"

    if (( ${#match} > cmd_max )); then
      cmd_display="${match[1,$(( cmd_max - 1 ))]}…"
    else
      cmd_display="$match"
    fi

    if (( i - 1 == _zpred_sel )); then
      line="> ${cmd_display}"
    else
      line="  ${cmd_display}"
    fi

    pd+=$'\n'"$line"
    (( pos += 1 ))

    local ls=$pos                           # line start
    local ms=$(( ls + 2 ))                  # after "> " or "  "
    local te=$(( ms + typed_len ))          # typed-prefix end
    local ce=$(( ms + ${#cmd_display} ))    # command end
    local le=$(( ls + ${#line} ))           # full line end

    (( te > ce )) && te=$ce

    if (( i - 1 == _zpred_sel )); then
      _zpred_hl_add "$ls $le $ZPRED_STYLE_SELECTED"
    else
      (( te > ms )) && _zpred_hl_add "$ms $te $ZPRED_STYLE_EMPHASIS"
      (( ce > te )) && _zpred_hl_add "$te $ce $ZPRED_STYLE_DIM"
    fi

    pos=$le
  done

  POSTDISPLAY="$pd"
}

# ── ZLE hooks ───────────────────────────────────────────────────
_zpred_line_init() {
  _zpred_sel=-1
  _zpred_typed=""
  _zpred_dismissed=0
  _zpred_navigating=0
  _zpred_prev_buf=""
  _zpred_hl=()
  _zpred_matches=()
  # Don't set POSTDISPLAY here — it triggers a redraw that can re-enter line-init
}

_zpred_pre_redraw() {
  (( ZPRED_ENABLED )) || return
  if (( _zpred_navigating )); then
    _zpred_navigating=0
    return
  fi
  [[ "$BUFFER" != "$_zpred_prev_buf" ]] || return
  _zpred_prev_buf="$BUFFER"
  # User typed something — update typed text, reset selection, un-dismiss
  _zpred_typed="$BUFFER"
  _zpred_sel=-1
  _zpred_dismissed=0
  _zpred_render
}

_zpred_line_finish() {
  _zpred_hl=()
  _zpred_matches=()
  _zpred_prev_buf=""
  POSTDISPLAY=""
}

add-zle-hook-widget line-init       _zpred_line_init
add-zle-hook-widget line-pre-redraw _zpred_pre_redraw
add-zle-hook-widget line-finish     _zpred_line_finish

# ── Widgets ─────────────────────────────────────────────────────

# ↓: enter list or move selection down. Buffer updates to match selection.
zpred-down() {
  local count=${#_zpred_matches}
  if (( count && !_zpred_dismissed )); then
    if (( _zpred_sel == -1 )); then
      _zpred_sel=0
    else
      (( _zpred_sel = (_zpred_sel + 1) % count ))
    fi
    _zpred_navigating=1
    BUFFER="${_zpred_matches[$(( _zpred_sel + 1 ))]}"
    CURSOR=$#BUFFER
    _zpred_prev_buf="$BUFFER"
    _zpred_render
  else
    zle down-line-or-history
  fi
}
zle -N zpred-down

# ↑: move selection up. At top → deselect and restore typed text.
zpred-up() {
  local count=${#_zpred_matches}
  if (( count && !_zpred_dismissed && _zpred_sel >= 0 )); then
    if (( _zpred_sel == 0 )); then
      # Back to no selection — restore what user typed
      _zpred_sel=-1
      _zpred_navigating=1
      BUFFER="$_zpred_typed"
      CURSOR=$#BUFFER
      _zpred_prev_buf="$BUFFER"
    else
      (( _zpred_sel-- ))
      _zpred_navigating=1
      BUFFER="${_zpred_matches[$(( _zpred_sel + 1 ))]}"
      CURSOR=$#BUFFER
      _zpred_prev_buf="$BUFFER"
    fi
    _zpred_render
  else
    zle up-line-or-history
  fi
}
zle -N zpred-up

# Tab: select first item (if none selected) or accept selection and dismiss.
zpred-tab() {
  local count=${#_zpred_matches}
  if (( count && !_zpred_dismissed )); then
    if (( _zpred_sel == -1 )); then
      # Select first item
      _zpred_sel=0
      _zpred_navigating=1
      BUFFER="${_zpred_matches[1]}"
      CURSOR=$#BUFFER
      _zpred_prev_buf="$BUFFER"
      _zpred_render
    else
      # Accept: keep buffer, dismiss list
      _zpred_typed="$BUFFER"
      _zpred_dismissed=1
      _zpred_sel=-1
      _zpred_clear_display
    fi
  else
    zle expand-or-complete
  fi
}
zle -N zpred-tab

# Escape: dismiss list, restore typed text.
zpred-escape() {
  if (( ${#_zpred_matches} && !_zpred_dismissed )); then
    _zpred_dismissed=1
    _zpred_navigating=1
    _zpred_sel=-1
    BUFFER="$_zpred_typed"
    CURSOR=$#BUFFER
    _zpred_prev_buf="$BUFFER"
    _zpred_clear_display
  fi
}
zle -N zpred-escape

# Alt+P: toggle predictions on/off
zpred-toggle() {
  (( ZPRED_ENABLED = !ZPRED_ENABLED ))
  if (( ZPRED_ENABLED )); then
    _zpred_dismissed=0
    _zpred_prev_buf=""
    _zpred_pre_redraw
    zle -M "zsh-predictive-list: on"
  else
    _zpred_clear_display
    zle -M "zsh-predictive-list: off"
  fi
}
zle -N zpred-toggle

# ── Keybindings ─────────────────────────────────────────────────
bindkey '^[[A'  zpred-up       # Up    (CSI)
bindkey '^[OA'  zpred-up       # Up    (application)
bindkey '^[[B'  zpred-down     # Down  (CSI)
bindkey '^[OB'  zpred-down     # Down  (application)
bindkey '^I'    zpred-tab      # Tab
bindkey '^G'    zpred-escape   # Ctrl+G (dismiss list)
bindkey '^[p'   zpred-toggle   # Alt+P

# ── Init ────────────────────────────────────────────────────────
_zpred_sync
