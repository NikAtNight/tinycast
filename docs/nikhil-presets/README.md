# Nikhil's presets

Zero-code configuration for this fork. Import once per machine.

## Quicklinks

Settings → Quicklinks → Import… → `quicklinks.json`. Every entry that takes a `{argument}`
shows an argument strip in the launcher: type the name, Tab, type the query, Return. The
argument value is percent-encoded automatically; the fixed parts of each link are already
encoded (`%20` for the spaces in Obsidian folder names). The vault name is `Notes`.

## Custom commands

Settings → Commands → add each row by hand. All run in `/bin/zsh -lc`.

| Name | Command | Show output |
| --- | --- | --- |
| Spotify play/pause | `osascript -e 'tell application "Spotify" to playpause'` | off |
| Spotify next | `osascript -e 'tell application "Spotify" to next track'` | off |
| Spotify previous | `osascript -e 'tell application "Spotify" to previous track'` | off |
| Spotify now playing | `osascript -e 'tell application "Spotify" to (name of current track) & " by " & (artist of current track)'` | off (the last line shows in the confirmation pill) |
| Run screenshot cleanup now | `launchctl kickstart gui/$(id -u)/com.nikhlkapadia.cleanup-desktop-screenshots` | off |
| Open File Cleanup | `open "$HOME/Applications/File Cleanup.app"` | off |
| Cleanup log | `tail -n 40 ~/.local/var/log/cleanup-desktop-screenshots.log` | on |
| Open today's dictation history | `open "$HOME/Library/Application Support/LocalFlow/History/$(date +%F).md"` | off |
| Supacode to front | `/Applications/supacode.app/Contents/Resources/bin/supacode open` | off |
| New SXCL card | `sxcl kanban create "$1" --workspace dir:"$2"` with arguments Title and Path | on |
| New Olive card | `olive kanban create "$1" --workspace dir:"$2"` with arguments Title and Path | on |

The kanban commands need "load shell environment" on so `~/.local/bin` is on PATH.
