# zsh-predictive-list — PSReadLine ListView prediction for zsh
#
# Predictions come only from commands that exited 0.
# No ghost text — clean list below the prompt, exactly like PSReadLine.
# Requires zsh >= 5.4 (for zle-line-pre-redraw).

(( ${+_ZPRED_LOADED} )) && return 0
typeset -gi _ZPRED_LOADED=1

zmodload -F zsh/stat b:zstat 2>/dev/null
autoload -Uz add-zle-hook-widget add-zsh-hook

# ── Configuration ───────────────────────────────────────────────
typeset -g  ZPRED_HISTORY="${ZPRED_HISTORY:-${XDG_DATA_HOME:-$HOME/.local/share}/zsh-predictive-list/success_history}"
typeset -gi ZPRED_MAX_SHOW=${ZPRED_MAX_SHOW:-6}
typeset -gi ZPRED_MAX_HISTORY=${ZPRED_MAX_HISTORY:-5000}
typeset -g  ZPRED_MATCH_MODE="${ZPRED_MATCH_MODE:-prefix}"
typeset -gi ZPRED_MIN_CHARS=${ZPRED_MIN_CHARS:-1}
typeset -g  ZPRED_STYLE_EMPHASIS="${ZPRED_STYLE_EMPHASIS:-fg=yellow}"
typeset -g  ZPRED_STYLE_SELECTED="${ZPRED_STYLE_SELECTED:-standout}"
typeset -g  ZPRED_STYLE_DIM="${ZPRED_STYLE_DIM:-fg=8}"
typeset -gi ZPRED_ENABLED=1

# ── Internal state ──────────────────────────────────────────────
typeset -ga _zpred_mem=()
typeset -ga _zpred_matches=()
typeset -gi _zpred_sel=-1
typeset -g  _zpred_typed=""
typeset -gi _zpred_dismissed=0
typeset -gi _zpred_navigating=0
typeset -ga _zpred_hl=()
typeset -g  _zpred_prev_buf=""
typeset -g  _zpred_last_cmd=""
typeset -g  _zpred_hist_mtime=""

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
    (( ${#_zpred_mem} >= ZPRED_MAX_HISTORY )) && break
  done < <(tac "$ZPRED_HISTORY" 2>/dev/null || tail -r "$ZPRED_HISTORY")
}

_zpred_record() {
  local cmd="$1"
  [[ -d "${ZPRED_HISTORY:h}" ]] || mkdir -p "${ZPRED_HISTORY:h}"
  print -r -- "$cmd" >> "$ZPRED_HISTORY"
  _zpred_mem=("$cmd" "${(@)_zpred_mem:#$cmd}")
  (( ${#_zpred_mem} > ZPRED_MAX_HISTORY )) && \
    _zpred_mem=("${(@)_zpred_mem[1,ZPRED_MAX_HISTORY]}")
  local lines
  lines=$(wc -l < "$ZPRED_HISTORY" 2>/dev/null) || return
  if (( lines > ZPRED_MAX_HISTORY * 2 )); then
    local tmp="${ZPRED_HISTORY}.tmp.$$"
    tail -n "$ZPRED_MAX_HISTORY" "$ZPRED_HISTORY" > "$tmp" && \
      mv -f "$tmp" "$ZPRED_HISTORY"
  fi
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

zpred-import() {
  local src="${1:-$HISTFILE}"
  [[ -r "$src" ]] || { print "zpred-import: cannot read $src" >&2; return 1; }
  [[ -d "${ZPRED_HISTORY:h}" ]] || mkdir -p "${ZPRED_HISTORY:h}"
  local -A seen=()
  local line
  if [[ -r "$ZPRED_HISTORY" ]]; then
    while IFS= read -r line; do
      [[ -n "$line" ]] && seen[$line]=1
    done < "$ZPRED_HISTORY"
  fi
  local count=0
  while IFS= read -r line; do
    [[ "$line" == ': '[0-9]*';'* ]] && line="${line#*;}"
    [[ -n "$line" && "$line" != *$'\n'* ]] || continue
    (( ${+seen[$line]} )) && continue
    seen[$line]=1
    print -r -- "$line" >> "$ZPRED_HISTORY"
    (( count++ ))
  done < "$src"
  print "zpred-import: imported $count commands from $src"
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

add-zsh-hook preexec _zpred_preexec
add-zsh-hook precmd  _zpred_precmd

# ── Matching ────────────────────────────────────────────────────
_zpred_match() {
  _zpred_matches=()
  (( ZPRED_ENABLED )) || return
  (( ${#_zpred_typed} >= ZPRED_MIN_CHARS )) || return

  _zpred_matches=("${(@M)_zpred_mem:#${_zpred_typed}*}")
  _zpred_matches=("${(@)_zpred_matches:#${_zpred_typed}}")

  if [[ "$ZPRED_MATCH_MODE" == "contains" ]] && (( ${#_zpred_matches} < ZPRED_MAX_SHOW )); then
    local -a sub
    sub=("${(@M)_zpred_mem:#*${_zpred_typed}*}")
    sub=("${(@)sub:#${_zpred_typed}}")
    local -A seen
    local p; for p in "${_zpred_matches[@]}"; do seen[$p]=1; done
    local s; for s in "${sub[@]}"; do
      (( ${+seen[$s]} )) && continue
      _zpred_matches+=("$s")
      (( ${#_zpred_matches} >= ZPRED_MAX_SHOW )) && break
    done
  fi

  (( ${#_zpred_matches} > ZPRED_MAX_SHOW )) && \
    _zpred_matches=("${(@)_zpred_matches[1,ZPRED_MAX_SHOW]}")
}

# ── Display ─────────────────────────────────────────────────────
_zpred_clear_hl() {
  local h
  for h in "${_zpred_hl[@]}"; do
    region_highlight=("${(@)region_highlight:#$h}")
  done
  _zpred_hl=()
}

_zpred_clear_display() {
  _zpred_clear_hl
  POSTDISPLAY=""
}

_zpred_hl_add() {
  _zpred_hl+=("$1")
  region_highlight+=("$1")
}

_zpred_render() {
  _zpred_clear_hl
  _zpred_match

  local count=${#_zpred_matches}
  if (( !count || _zpred_dismissed )); then
    POSTDISPLAY=""
    return
  fi

  local pos=$#BUFFER
  local pd=""
  local typed_len=${#_zpred_typed}

  local sel_label
  (( _zpred_sel >= 0 )) && sel_label="$(( _zpred_sel + 1 ))" || sel_label="-"
  local header="[${sel_label}/${count}]"

  pd+=$'\n'"$header"
  (( pos += 1 ))
  _zpred_hl_add "$pos $(( pos + ${#header} )) $ZPRED_STYLE_DIM"
  (( pos += ${#header} ))

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

    local ls=$pos
    local ms=$(( ls + 2 ))
    local te=$(( ms + typed_len ))
    local ce=$(( ms + ${#cmd_display} ))
    local le=$(( ls + ${#line} ))

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
}

_zpred_pre_redraw() {
  (( ZPRED_ENABLED )) || return
  if (( _zpred_navigating )); then
    _zpred_navigating=0
    return
  fi
  [[ "$BUFFER" != "$_zpred_prev_buf" ]] || return
  _zpred_prev_buf="$BUFFER"
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

zpred-up() {
  local count=${#_zpred_matches}
  if (( count && !_zpred_dismissed && _zpred_sel >= 0 )); then
    if (( _zpred_sel == 0 )); then
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

zpred-tab() {
  if (( _zpred_sel >= 0 && ${#_zpred_matches} && !_zpred_dismissed )); then
    _zpred_typed="$BUFFER"
    _zpred_dismissed=1
    _zpred_sel=-1
    _zpred_clear_display
  else
    zle expand-or-complete
  fi
}
zle -N zpred-tab

zpred-right() {
  if (( ${#_zpred_matches} && !_zpred_dismissed && CURSOR == $#BUFFER )); then
    local target
    if (( _zpred_sel >= 0 )); then
      target="${_zpred_matches[$(( _zpred_sel + 1 ))]}"
    else
      target="${_zpred_matches[1]}"
    fi
    _zpred_typed="$target"
    _zpred_dismissed=1
    _zpred_sel=-1
    _zpred_navigating=1
    BUFFER="$target"
    CURSOR=$#BUFFER
    _zpred_prev_buf="$BUFFER"
    _zpred_clear_display
  else
    zle forward-char
  fi
}
zle -N zpred-right

zpred-dismiss() {
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
zle -N zpred-dismiss

zpred-delete-entry() {
  (( _zpred_sel >= 0 && ${#_zpred_matches} )) || return
  local entry="${_zpred_matches[$(( _zpred_sel + 1 ))]}"
  _zpred_mem=("${(@)_zpred_mem:#${entry}}")
  if [[ -w "$ZPRED_HISTORY" ]]; then
    local tmp="${ZPRED_HISTORY}.tmp.$$"
    command grep -vxF -- "$entry" "$ZPRED_HISTORY" > "$tmp" && \
      mv -f "$tmp" "$ZPRED_HISTORY"
  fi
  _zpred_clear_display
  _zpred_match
  (( _zpred_sel >= ${#_zpred_matches} )) && (( _zpred_sel = ${#_zpred_matches} - 1 ))
  _zpred_navigating=1
  if (( _zpred_sel >= 0 )); then
    BUFFER="${_zpred_matches[$(( _zpred_sel + 1 ))]}"
  else
    BUFFER="$_zpred_typed"
  fi
  CURSOR=$#BUFFER
  _zpred_prev_buf="$BUFFER"
  _zpred_render
}
zle -N zpred-delete-entry

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
bindkey '^[[C'  zpred-right    # Right (CSI)
bindkey '^[OC'  zpred-right    # Right (application)
bindkey '^I'    zpred-tab      # Tab
bindkey '^G'    zpred-dismiss  # Ctrl+G
bindkey '^[p'   zpred-toggle   # Alt+P

# ── Unload ──────────────────────────────────────────────────────
_zpred_unload() {
  add-zsh-hook -d preexec _zpred_preexec
  add-zsh-hook -d precmd  _zpred_precmd
  add-zle-hook-widget -d line-init       _zpred_line_init
  add-zle-hook-widget -d line-pre-redraw _zpred_pre_redraw
  add-zle-hook-widget -d line-finish     _zpred_line_finish
  bindkey '^[[A'  up-line-or-history
  bindkey '^[OA'  up-line-or-history
  bindkey '^[[B'  down-line-or-history
  bindkey '^[OB'  down-line-or-history
  bindkey '^[[C'  forward-char
  bindkey '^[OC'  forward-char
  bindkey '^I'    expand-or-complete
  bindkey '^G'    send-break
  bindkey -r '^[p'
  _zpred_clear_display
  unset _ZPRED_LOADED
}

# ── Init ────────────────────────────────────────────────────────
_zpred_sync
