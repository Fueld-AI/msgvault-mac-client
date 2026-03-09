<div align="center">

<img src="https://msgvault.fueld.ai/og-image.png" alt="MsgVault — Fast Email Search for Mac" width="100%" />

<br /><br />

# MsgVault for macOS

**A beautiful, native macOS app for searching, browsing, and understanding your entire email archive — entirely offline.**

[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-30B0C7?style=for-the-badge&logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Built with SwiftUI](https://img.shields.io/badge/SwiftUI-Native-30B0C7?style=for-the-badge&logo=swift&logoColor=white)](https://developer.apple.com/xcode/swiftui/)
[![Website](https://img.shields.io/badge/Website-msgvault.fueld.ai-30B0C7?style=for-the-badge&logo=safari&logoColor=white)](https://msgvault.fueld.ai)
[![msgvault CLI](https://img.shields.io/badge/msgvault%20CLI-msgvault.io-30B0C7?style=for-the-badge&logoColor=white)](https://www.msgvault.io)
[![Made by Fueld](https://img.shields.io/badge/Made%20by-Fueld.ai-30B0C7?style=for-the-badge&logoColor=white)](https://fueld.ai)

</div>

---

## What is MsgVault?

**[Visit the MsgVault website →](https://msgvault.fueld.ai)**

MsgVault is a native macOS desktop application built by the team at [Fueld.ai](https://fueld.ai), wrapping the powerful [`msgvault`](https://www.msgvault.io) CLI to give you a polished, fast, and fully offline interface to explore your entire Gmail archive. Every search, every filter, every AI query — runs entirely on your machine. No cloud. No subscriptions. Your data stays yours.

Whether you have 10,000 emails or 10 million, MsgVault handles them all with speed and elegance.

> **msgvault CLI** — the open-source engine powering MsgVault Desktop. [Read the full documentation at msgvault.io →](https://www.msgvault.io)

---

## Features

### Search That Actually Works
- **Full-text search** with Gmail-like syntax — `from:`, `to:`, `subject:`, `has:attachment`, `after:`, `before:`, `label:` and more
- **Voice search** — speak your query directly into the search bar
- **Real-time filtering** by label, date range, account, and attachment type
- **Calendar view** — visually browse your archive by date
- Results in milliseconds, even across hundreds of thousands of messages

### Sender Intelligence
- See exactly who sends you the most email, ranked by volume
- Filter and drill into any sender's full message history
- Identify the noise in your inbox at a glance

### Archive Stats & Insights
- At-a-glance overview of your total messages, accounts, attachments, and database size
- **Mail Action insights** — surface your top unopened emails and flag large attachments for cleanup
- Track growth over time

### Local AI — Completely Private
- Ask natural-language questions about your archive using on-device AI (via Ollama)
- Supports leading open-source models: **Qwen**, **Phi-4**, **Gemma 3**, **Llama 3.2**, **DeepSeek-R1**
- Zero data ever leaves your Mac — fully air-gapped AI

### Multi-Account
- Connect and search across multiple Gmail accounts in a single unified view
- Cross-account search with per-account filtering

### Beautiful by Default
- Five hand-crafted themes: **Teal**, Midnight, Forest, Sunset, and Ocean
- Full light / dark / system mode support
- Designed to feel at home on macOS — native controls, native animations

---

## Requirements

| Requirement | Minimum |
|---|---|
| macOS | 14 (Sonoma) or later |
| Xcode | 15+ (to build from source) |
| msgvault CLI | Installed and configured |

---

## Installation

### Step 1 — Install msgvault

Visit [msgvault.io](https://www.msgvault.io) for the full setup guide, or install directly:

```bash
curl -fsSL https://msgvault.io/install.sh | bash
```

Then [set up OAuth credentials](https://www.msgvault.io/guides/oauth-setup/) and sync your Gmail:

```bash
msgvault --local sync-full your@email.com
```

### Step 2 — Run MsgVault Desktop

**Option A: Open in Xcode**
```bash
open MsgVaultMacDesktop/MsgVaultMacDesktop.xcodeproj
```
Select **My Mac** as the target, then press **⌘R**.

**Option B: Build from terminal**
```bash
cd MsgVaultMacDesktop
xcodebuild -scheme MsgVaultMacDesktop -configuration Release
```

---

## Architecture

MsgVault Desktop is intentionally lean — it shells out to the `msgvault` CLI rather than bundling any library, which means:

- **No additional dependencies** — one binary, nothing else
- **Works with any msgvault version** — CLI upgrades automatically apply
- **Read-only by design** — no accidental writes to your archive
- **All data stays local** — nothing touches the network except initial Gmail sync

The app auto-detects `msgvault` at all common install locations (`/usr/local/bin/`, `/opt/homebrew/bin/`, `~/.local/bin/`, `~/go/bin/`). You can override the path in Settings if needed.

---

## Local AI Setup

MsgVault can connect to a locally running [Ollama](https://ollama.ai) instance to power AI-assisted search and summarisation. Go to **Settings → AI Setup** to choose your model:

| Model | Size | Best For |
|---|---|---|
| Qwen 3.5 0.8B | ~1.0 GB | Ultra-fast, minimal RAM |
| Qwen 3.5 2B | ~2.7 GB | Best balance — recommended |
| Phi-4 Mini 3.8B | ~2.5 GB | Excellent structured output |
| Gemma 3 4B | ~3.3 GB | Strong multilingual support |
| Llama 3.2 3B | ~2.0 GB | Fast and open |
| DeepSeek-R1 7B | ~5.2 GB | Strong reasoning |

All inference runs on-device. No API keys. No usage fees. No data leaving your Mac.

---

## Useful Links

| Resource | URL |
|---|---|
| MsgVault Website | [msgvault.fueld.ai](https://msgvault.fueld.ai) |
| msgvault CLI Docs | [msgvault.io](https://www.msgvault.io) |
| msgvault Setup Guide | [msgvault.io/setup](https://www.msgvault.io/setup/) |
| msgvault OAuth Guide | [msgvault.io/guides/oauth-setup](https://www.msgvault.io/guides/oauth-setup/) |
| Fueld.ai | [fueld.ai](https://fueld.ai) |

---

## Contributing

Pull requests are welcome. For significant changes, please open an issue first to discuss what you'd like to change.

---

<div align="center">

<br />

**Made with care by the team at**

<br />

<a href="https://fueld.ai">
  <img src="https://fueld.ai/logos/Fueld-logo-midnight%20green.svg" alt="Fueld.ai" height="40" />
</a>

<br /><br />

[fueld.ai](https://fueld.ai) — Health intelligence, not just tracking.

<br />

*Building tools that put you in control of your data.*

<br />

</div>
