# POD: Multi-Account UX for MsgVaultUI

## Problem

The current UI allows search/stats/sync, but does not provide an explicit flow to add additional Gmail accounts from inside the app.

## Outcome

Add a first-class account management experience so users can:

- Add another account via `msgvault add-account <email>`
- Optionally set display name, headless flow, and force re-authorization
- View currently connected accounts with message counts and last sync timestamps
- Understand that search and sync can run across all accounts

## Documentation Basis

- Msgvault repository and CLI command set: https://github.com/wesm/msgvault
- Multi-account usage documentation: https://www.msgvault.io/usage/multi-account/

## Scope Implemented

1. New `Accounts` tab in the sidebar.
2. `EmailStore` account management state:
   - `accounts`
   - loading and action flags
   - account status and error messages
3. New `EmailStore.loadAccounts()` command integration:
   - runs `msgvault --local list-accounts --json`
   - parses account JSON payload
4. New `EmailStore.addAccount(...)` command integration:
   - runs `msgvault --local add-account <email> [--display-name] [--headless] [--force]`
   - updates status and reloads account list
   - refreshes stats after success
5. Accounts UI:
   - add-account form (email, display name, toggles)
   - connected accounts list cards (name/email/type/message count/last sync)
   - helper panel describing default cross-account search/sync behavior

## UX Notes

- The add-account flow usually opens a browser for OAuth.
- If a user is on a remote/headless machine, the UI supports the `--headless` path.
- The app remains local-first by using `--local` for command execution.

## Validation

- Command capability validated via CLI help:
  - `add-account`
  - `list-accounts --json`
  - `remove-account` (available for future UX expansion)
- Build validated:
  - `swift build` succeeds after changes.

## Top Senders UX Enhancement

### Problem
The Top Senders list showed aggregate stats but gave no way to drill into the emails themselves, nor any integration with the Search tab.

### Changes Implemented

**EmailStore additions:**
- `senderEmailCache: [String: [EmailMessage]]` — per-sender message cache (loaded on demand).
- `isLoadingSenderEmails: Set<String>` — tracks in-flight loads per email address.
- `searchForSenderRequest: String?` — published signal used to cross-navigate from Top Senders into the Search tab.
- `loadEmailsForSender(_ email: String) async` — runs `msgvault search from:<email> --json -n 200` and stores results into `senderEmailCache`.

**SendersView redesign (split view):**
- Left column: existing ranked sender list, now with `.onHover` and `.onTapGesture` per row.
  - Hovering a row loads their emails in the right detail panel (transient preview).
  - Clicking a row locks the detail panel to that sender (pin icon appears); clicking again unlocks.
- Right column: `SenderDetailPanel` — appears on hover/click.
  - Header shows sender name, email, and a message count badge.
  - **"Search in Search" button** — triggers navigation to the Search tab with `from:<email>` pre-filled.
  - Filter bar — live sub-filter on subject and snippet, with clear button.
  - Message list in **reverse chronological order** (newest first).
  - Each row shows subject, human-readable date, snippet, and attachment indicator.

**ContentView:**
- `.onChange(of: store.searchForSenderRequest)` — detects the navigation request and switches `selectedTab` to `.search`.

**SearchView:**
- `.onChange(of: store.searchForSenderRequest)` — consumes the request: clears the form, pre-fills `filterFrom` with the sender's email, opens the filter panel, and fires an immediate search.

## Next Iteration (Optional)

- Add remove-account UX with explicit confirmation.
- Add per-account sync actions (`sync <email>` and `sync-full <email>`).
- Add account filter integration in search UI (mirrors docs `tui --account` concept).
- Expand `SenderDetailPanel` to allow opening individual messages inline (using `show-message --json`).
