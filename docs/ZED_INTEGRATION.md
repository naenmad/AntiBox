# Zed Editor Integration & Agent Client Protocol (ACP) Guide

ZedGravity is built from the ground up to pair seamlessly with **Zed Editor**'s native AI Agent Client Protocol.

---

## 1. Prerequisites

1. **macOS 14.0+ (Sonoma or Sequoia)**
2. **Zed Editor** (v0.150.0 or later recommended)
3. **Google Antigravity Extension / ACP CLI**: Installed via Antigravity CLI or Google Cloud Code tools.

---

## 2. Zed Configuration

Zed communicates with the ACP server via the settings file at `~/.config/zed/settings.json`.

To ensure Zed reads credentials directly from disk without prompting macOS security popups, ensure the `AGY_ACP_FORCE_FILE_STORAGE` environment variable is enabled:

```json
{
  "assistant": {
    "version": "2",
    "provider": {
      "name": "custom",
      "servers": {
        "antigravity-acp": {
          "command": "/Users/YOUR_USERNAME/.local/bin/antigravity",
          "args": ["acp"],
          "env": {
            "AGY_ACP_FORCE_FILE_STORAGE": "1"
          }
        }
      }
    }
  }
}
```

> [!TIP]
> If you installed the Antigravity ACP server through another path (such as `~/.gemini/antigravity-ide`), point the command to that executable. The key setting is `"AGY_ACP_FORCE_FILE_STORAGE": "1"`.

---

## 3. How Hot-Swapping Works

When you switch accounts in ZedGravity (or when Auto-Switch triggers):

1. **Credentials Updated**: ZedGravity writes the new OAuth token directly to `~/.gemini/antigravity-acp/acp_token.json`.
2. **Process Respawn**: ZedGravity sends a clean termination signal (`pkill -f agy_acp_server.par`).
3. **Zero Chat Loss**: Zed Editor automatically respawns the ACP server on your next message. Your active conversation history and open editor tabs remain intact.

---

## 4. Verification

To verify that Zed is actively using your ZedGravity token:

1. In Zed, open the Assistant panel (`Cmd-?` or `Cmd-R`).
2. Ask a question using **Claude 3.7 Sonnet** or **Gemini 2.5 Pro**.
3. Check the Menu Bar in ZedGravity: the token counts and percentages will update dynamically according to your configured sync frequency.
