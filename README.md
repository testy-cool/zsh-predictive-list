# zsh-predictive-list

PSReadLine-style **ListView** prediction for zsh. Predictions come **only from commands that exited 0** — typos and failures stay in raw history but never pollute your suggestions.

Inspired by [PSReadLine](https://github.com/PowerShell/PSReadLine)'s `ListView` prediction mode for PowerShell.

## What it does

<p align="center">
  <img src="preview.svg" alt="zsh-predictive-list preview" width="720">
</p>

- **No ghost text.** The list sits below the prompt, not mixed into your input.
- **Header line.** It shows `[-/N]` when nothing is selected and `[K/N]` when item K is selected.
- **Success-only.** Only commands that exited 0 feed predictions.
- **Ranked by use.** Commands you run often and recently come first. Each run counts, and its weight halves every 50 commands.
- **Buffer updates on navigation.** ↓ selects an item and puts it in your buffer, and ↑ restores your typed text.

## Install

### zinit
```zsh
zinit light testycool/zsh-predictive-list
```

### oh-my-zsh
```zsh
git clone https://github.com/testycool/zsh-predictive-list ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-predictive-list
# Add to plugins=(...) in .zshrc
```

### Manual
```zsh
source /path/to/zsh-predictive-list.plugin.zsh
```

## Keybindings

| Key | Action |
|-----|--------|
| Type anything | List updates automatically |
| `Down` | Enter list / select next item (buffer updates to match) |
| `Up` | Select previous item / deselect (restores typed text) |
| `Right` | Accept top prediction (or selected) when cursor is at end of line |
| `Tab` | Accept current selection (only while navigating); otherwise normal completion |
| `Enter` | Execute current buffer |
| `Ctrl+G` | Dismiss list and restore typed text, or cancel the line when no list is shown |
| `Alt+P` | Toggle predictions on/off |

Additional widgets (not bound by default — bind them yourself if needed):

| Widget | Action |
|--------|--------|
| `zpred-delete-entry` | Remove the selected entry from prediction history |

When no list is shown, `Up`, `Down`, `Right`, `Tab` and `Ctrl+G` keep their normal behavior. A line you recall from history shows no list until you edit it, so `Up` and `Down` move through history as usual.

## Configuration

Set these before sourcing the plugin:

```zsh
# History file location (default: ~/.local/share/zsh-predictive-list/success_history)
ZPRED_HISTORY="$HOME/.zsh_success_history"

# Max visible predictions (default: 6)
ZPRED_MAX_SHOW=8

# Max distinct commands kept for predictions (default: 5000).
# The file is trimmed to this many lines once it grows past twice that.
ZPRED_MAX_HISTORY=5000

# Match mode: "prefix" (default) or "contains" (substring matching, prefix results shown first)
ZPRED_MATCH_MODE="contains"

# Characters to type before the list appears (default: 1).
# Try 2 or 3 in terminals that redraw slowly.
ZPRED_MIN_CHARS=2

# Styles (zsh region_highlight format)
ZPRED_STYLE_EMPHASIS="fg=yellow"      # typed text inside unselected items
ZPRED_STYLE_SELECTED="standout"       # selected item (reverse video)
ZPRED_STYLE_DIM="fg=8"               # header and the rest of each unselected item
```

## Importing existing history

New installs start with an empty prediction list. Import from your existing zsh history:

```zsh
zpred-import              # imports from $HISTFILE (handles both plain and EXTENDED_HISTORY format)
zpred-import /path/to/file  # import from a specific file
```

Since exit codes aren't stored in `$HISTFILE`, all entries are imported. The prediction list will self-correct over time as successful commands get recorded.

## How it works

1. `preexec` captures each command before execution
2. `precmd` checks `$?` — if 0, the command is appended to the success history file
3. `zle-line-pre-redraw` detects buffer changes and updates the prediction list
4. Matching runs against the deduplicated success history, best score first (prefix or substring). A command's score adds up its runs, and each run's weight halves every 50 commands.
5. List renders via `POSTDISPLAY` + `region_highlight` (no ghost text)
6. Navigation with ↓ updates BUFFER to the selected command; ↑ at top restores typed text
7. Ctrl+G dismisses the list, and typing again brings it back. With no list shown, Ctrl+G cancels the line.
8. A line recalled from history shows no list until you edit it
9. History file auto-truncates when it exceeds 2× `ZPRED_MAX_HISTORY`

## How it differs from other plugins

| | zsh-predictive-list | zsh-autosuggestions | zsh-autocomplete |
|---|---|---|---|
| Display | List below prompt | Inline ghost text | Completion menu |
| Source | Success history only | Full history + completion | Completion system |
| Navigation | ↑/↓ through list | → to accept | Tab cycling |
| Buffer | Updates on selection | Unchanged until accept | Unchanged until accept |

## Requirements

- zsh >= 5.4 (for `zle-line-pre-redraw`)
- `awk` and `sort`, which score the history when a shell starts
- zsh 5.9 or later is recommended. On older versions, list colors can land in the wrong place while you edit a line.

## Compatibility

- Chains with existing `zle-line-init`, `zle-line-pre-redraw`, and `zle-line-finish` hooks
- **Conflicts with zsh-autosuggestions** — both use `POSTDISPLAY`. Use one or the other.

## License

MIT
