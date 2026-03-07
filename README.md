# MsgVault UI — SwiftUI POC

A lightweight macOS SwiftUI app that wraps the `msgvault` CLI to provide a native UI for browsing and searching your email archive.

## Prerequisites

- macOS 14 (Sonoma) or later
- Xcode 15+
- `msgvault` installed and configured with at least one synced account

## Quick Setup

### Option 1: Open as Swift Package (fastest)

```bash
cd MsgVaultUI
open Package.swift
```

Xcode will open the package. Select **My Mac** as the build target, then **⌘R** to run.

### Option 2: Build from terminal

```bash
cd MsgVaultUI
swift build
swift run
```

## What It Does

- **Search**: Full-text search using msgvault's Gmail-like syntax (`from:`, `to:`, `subject:`, `has:attachment`, `after:`, `before:`)
- **Top Senders**: Aggregated view of who sends you the most email
- **Stats**: Archive overview (total messages, accounts, attachments, DB size)
- **Message Detail**: View individual message content
- **Settings**: Configure msgvault binary path, test connection, syntax reference

## Architecture

This is intentionally simple — it shells out to the `msgvault` CLI rather than linking against any library. This means:

- No additional dependencies
- Works with any msgvault version
- Read-only (no write operations)
- All data stays local

The app auto-detects msgvault at common install paths (`/usr/local/bin/`, `/opt/homebrew/bin/`, `~/.local/bin/`, `~/go/bin/`). Override in Settings if needed.

## Notes

- This is a POC for testing. The JSON parsing is best-effort since msgvault's output format may vary.
- If search returns no results, check that your msgvault database has synced messages (`msgvault stats`).
- The app needs permission to run `msgvault` as a subprocess — macOS may prompt for approval.
