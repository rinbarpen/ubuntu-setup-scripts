---
name: figma-vibma
description: Cross-platform Vibma/Figma connection workflow. Verify tunnel, MCP, channel, and port alignment before design tasks.
---

# Figma Vibma Session Bootstrap (Cross-Platform)

Use this skill to start or recover a Vibma design session in a platform-agnostic way.

## 1. Confirm tunnel port

Expected default port is `3055` unless user configured another port.

```bash
lsof -ti:3055
```

If empty, tunnel is not running. Ask user to run:

```bash
npx @ufira/vibma-tunnel@latest
```

Or with custom port:

```bash
VIBMA_PORT=<port> npx @ufira/vibma-tunnel@latest
```

## 2. Confirm MCP can join channel

Use channel `vibma` by default unless user specified another name.

1. Call `connection(method: "create")`
2. Call `connection(method: "get")`

Success criteria:

`connection(method: "get")` returns `status: "pong"` and includes document metadata.

## 3. On timeout or disconnect

If `get` times out:

1. Verify tunnel process on the chosen port.
2. Ask user to reopen the Figma plugin window.
3. Ensure plugin UI port and channel match MCP:
   - Port: same as MCP `--port`
   - Channel: same as `connection(method: "create", channel: "...")`
4. Retry `create` then `get`.

## 4. Version/tool tier checks

If create/edit tools are missing, verify MCP args include the right access flag:

- `--create` for read + create
- `--edit` for full access

If version mismatch warning appears, update both sides:

- MCP package to `@ufira/vibma@latest`
- Figma plugin from latest `vibma-plugin.zip`

## 5. Ready signal

Session is ready only when `connection(method: "get")` returns `pong` with document name.
