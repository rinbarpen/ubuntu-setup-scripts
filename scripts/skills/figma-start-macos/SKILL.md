---
name: figma-start-macos
description: Start a Figma design session on macOS with Vibma. Opens Figma, launches plugin, then verifies MCP connection.
allowed-tools: Bash, mcp__vibma__connection
argument-hint: "[new|reconnect]"
---

Start or restore a Figma + Vibma MCP session on macOS.

## Arguments

- No args or `new`: open Figma, create new file, open plugin, connect
- `reconnect`: only reconnect MCP (skip launching new file)

## 1. Check current state

```bash
pgrep -x Figma >/dev/null 2>&1 && echo "FIGMA_RUNNING" || echo "FIGMA_NOT_RUNNING"
```

Try `connection(method: "get")`. If it already returns `pong`, stop and report ready.

## 2. Launch Figma (if needed)

```bash
open -a "Figma"
sleep 3
```

## 3. Create a new file (`new` only)

```bash
osascript -e '
tell application "Figma" to activate
delay 1
tell application "System Events"
    tell process "Figma"
        keystroke "n" using command down
    end tell
end tell
'
```

Wait 5 seconds.

If accessibility permissions block AppleScript, tell user to enable terminal app in:
`System Settings > Privacy & Security > Accessibility`.

## 4. Open Vibma plugin

```bash
osascript -e '
tell application "Figma" to activate
delay 0.5
tell application "System Events"
    tell process "Figma"
        keystroke "k" using command down
        delay 0.8
        keystroke "Vibma"
        delay 1.5
        keystroke return
    end tell
end tell
'
```

Wait 4 seconds.

## 5. Verify MCP chain

1. `connection(method: "create")`
2. `connection(method: "get")`

If `get` times out, retry up to 3 times with 3-second waits.

If still failing:

- Confirm tunnel is running on expected port.
- Confirm plugin UI port/channel match MCP.
- Ask user to close/reopen plugin and retry.

## 6. Report ready state

When `get` returns `pong`, report document name and current page.
