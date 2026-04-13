# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

PSReadLine-style ListView prediction for zsh. Shows a list of matching commands from history below the prompt — only commands that exited with status 0. Pure zsh, single file, no compilation, no dependencies beyond zsh >= 5.4.

## Development

No build step. The entire plugin is `zsh-predictive-list.plugin.zsh` (329 lines). To test changes, source it in a zsh session:

```zsh
source ./zsh-predictive-list.plugin.zsh
```

There is no test suite or linter. Verify changes manually in a live zsh session.

## Architecture

Single-file plugin with six functional layers:

1. **Configuration & state** — `ZPRED_*` user variables and `_zpred_*` internal state (in-memory history array, matches, selection index, display tracking)
2. **History I/O** — `_zpred_load()` reads success history file reverse-chronological and deduplicates; `_zpred_record()` appends successful commands
3. **Shell hooks** — `preexec` captures the command, `precmd` checks `$?` and records on success
4. **Matching engine** — `_zpred_match()` prefix-matches typed input against in-memory history, limited to `ZPRED_MAX_SHOW`
5. **Display system** — `_zpred_render()` builds POSTDISPLAY (no ghost text/inline suggestions), uses `region_highlight` for styling; `_zpred_clear_display()` tears it down
6. **ZLE widgets & keybindings** — `zpred-down`, `zpred-up`, `zpred-tab`, `zpred-escape`, `zpred-toggle` bound to arrows/Tab/Ctrl+G/Alt+P

**Critical flow:** User types → `zle-line-pre-redraw` detects buffer change → `_zpred_match()` → `_zpred_render()` → POSTDISPLAY shows styled list. Arrow keys navigate, Tab accepts, Enter executes. Successful commands get recorded via `precmd` hook.

**Success history:** Plain text file at `~/.local/share/zsh-predictive-list/success_history` (configurable via `ZPRED_HISTORY`), one command per line.

## Key Design Constraints

- All display goes through POSTDISPLAY (below prompt), never inline ghost text
- Only exit-code-0 commands enter the history — prevents typo pollution
- Must coexist with other zsh plugins via standard hook chaining (`add-zsh-hook`)
- Keybindings cover both CSI (`^[[A/B`) and application mode (`^[OA/B`) arrow sequences
