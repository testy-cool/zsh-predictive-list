# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

PSReadLine-style ListView prediction for zsh. Shows a list of matching commands from history below the prompt — only commands that exited with status 0. Pure zsh, single file, no compilation, no dependencies beyond zsh >= 5.4.

## Development

No build step. The entire plugin is `zsh-predictive-list.plugin.zsh`. To test changes, source it in a zsh session:

```zsh
source ./zsh-predictive-list.plugin.zsh
```

There is no test suite or linter. Verify changes manually in a live zsh session.

## Architecture

Single-file plugin with six functional layers:

1. **Configuration & state** — `ZPRED_*` user variables (including `ZPRED_MAX_HISTORY`, `ZPRED_MATCH_MODE`) and `_zpred_*` internal state
2. **History I/O** — `_zpred_load()` reads success history reverse-chronological, deduplicates, caps at `ZPRED_MAX_HISTORY`; `_zpred_record()` appends and auto-truncates file at 2× cap; `zpred-import()` imports from `$HISTFILE`
3. **Shell hooks** — `preexec` captures the command, `precmd` checks `$?` and records on success
4. **Matching engine** — `_zpred_match()` uses zsh parameter expansion (`${(@M)array:#pattern}`) for fast matching; supports `prefix` (default) and `contains` modes via `ZPRED_MATCH_MODE`
5. **Display system** — `_zpred_render()` builds POSTDISPLAY, uses `region_highlight` for styling; `_zpred_clear_display()` tears it down
6. **ZLE widgets & keybindings** — `zpred-down`, `zpred-up`, `zpred-tab`, `zpred-right`, `zpred-dismiss`, `zpred-delete-entry`, `zpred-toggle`
7. **Lifecycle** — `_zpred_unload()` cleanly removes all hooks, widgets, and keybindings

**Critical flow:** User types → `zle-line-pre-redraw` detects buffer change → `_zpred_match()` → `_zpred_render()` → POSTDISPLAY shows styled list. Down enters navigation, Right accepts top prediction, Tab accepts during navigation, Enter executes. Successful commands get recorded via `precmd` hook.

**Success history:** Plain text file at `~/.local/share/zsh-predictive-list/success_history` (configurable via `ZPRED_HISTORY`), one command per line. Auto-truncates when file exceeds 2× `ZPRED_MAX_HISTORY`.

## Key Design Constraints

- All display goes through POSTDISPLAY (below prompt), never inline ghost text
- Only exit-code-0 commands enter the history — prevents typo pollution
- Must coexist with other zsh plugins via standard hook chaining (`add-zsh-hook`)
- Keybindings cover both CSI (`^[[A/B`) and application mode (`^[OA/B`) arrow sequences
