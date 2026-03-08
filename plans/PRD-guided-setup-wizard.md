# PRD: Guided Setup Wizard — Zero-to-Syncing in MsgVaultUI

## Status
Draft — ready for execution scoping

## References
- msgvault setup guide: https://www.msgvault.io/setup/
- msgvault OAuth guide: https://www.msgvault.io/guides/oauth-setup/
- msgvault multi-account: https://www.msgvault.io/usage/multi-account/

---

## Problem

MsgVaultUI currently assumes the user has already:
1. Installed the `msgvault` CLI binary
2. Created a Google Cloud project
3. Enabled the Gmail API
4. Configured an OAuth consent screen
5. Created an OAuth client ID, downloaded `client_secret.json`
6. Added themselves as a test user
7. Created `~/.msgvault/config.toml` pointing at the credentials file
8. Successfully run `msgvault add-account` at least once

That is 8 manual steps across two products (Google Cloud Console and a terminal) before the app is usable at all. For non-developer users this is an insurmountable wall. Even for developers it is tedious and poorly documented in the context of the macOS app.

---

## Why Not Centralised OAuth?

Before defining the solution, it is worth capturing why the obvious shortcut — registering one GCP OAuth app under the GlennMsgVault developer account and having all users authenticate through it — is not the right path.

| Concern | Detail |
|---|---|
| **Restricted scope review** | `gmail.readonly` is a restricted Gmail scope. Any published OAuth app using it must pass Google's verification process, which for restricted scopes requires a CASA Tier 2 security assessment by a Google-approved third-party assessor. Cost: roughly $15,000–$75,000. Timeline: months. |
| **Product ethos conflict** | MsgVault's core value proposition is that your emails never leave your machine. A centralised OAuth app means the developer holds a refresh token that can re-request access to every user's Gmail. This is the exact threat model the product exists to eliminate. |
| **API quota risk** | All users sharing one GCP project share one API quota. A single large sync can cause rate-limiting for other users. Each user owning their own GCP project has their own quota ceiling. |
| **Revocation risk** | If Google audits and revokes a centralised app's credentials, every user's sync breaks simultaneously. With user-owned projects, one user's issue is isolated. |
| **"Testing" status is sufficient** | When each user creates their own GCP project and adds only their own Gmail as a test user, they never need Google's production app verification. The app remains in "Testing" status indefinitely for personal use — this is fully supported and stable. |

**Decision: Keep user-owned GCP credentials. Build a wizard that automates the setup inside the app.**

---

## Goal

A first-run setup wizard inside MsgVaultUI that takes a brand-new user from zero to their first completed sync, covering:

1. Detecting and optionally installing `msgvault` CLI
2. Walking through GCP project creation and Gmail API enablement with deep-links
3. Guiding through OAuth consent screen and credential download
4. Accepting and validating `client_secret.json` via drag-and-drop or file picker
5. Writing `~/.msgvault/config.toml` automatically
6. Running `msgvault add-account` with the OAuth browser flow
7. Triggering an initial test sync with a small limit
8. Handing off to the main app UI

---

## Non-Goals (v1)

- Microsoft 365 / Outlook support (separate OAuth system, separate POD)
- iCloud / Yahoo / generic IMAP (requires msgvault IMAP support, not yet available)
- Centralised OAuth app or any credential storage server-side
- Automated GCP API calls (gcloud CLI automation is Phase 2)

---

## User Stories

**New user, non-developer**
> As someone who just downloaded MsgVaultUI, I want to connect my Gmail without having to know what Google Cloud is, so that I can start searching my email without a tutorial.

**Existing msgvault CLI user**
> As someone who already has msgvault set up, I want the app to detect my existing credentials and accounts so I don't have to re-configure anything.

**Multi-account user adding a second account**
> As a user with one account already connected, I want to add a second Gmail via the Accounts tab using the same guided flow, without redoing the GCP setup steps I already completed.

---

## Wizard Flow

### Entry Points

1. **First launch** — no `~/.msgvault/config.toml` detected: wizard launches automatically full-screen
2. **Accounts tab → "Add Account"** — wizard launches in sheet/panel mode, skips steps already completed (CLI installed, config.toml present)
3. **Settings → "Re-run Setup"** — always available as a manual entry point

### Step Detection Logic

On launch, the app checks preconditions in order. Each completed step is skipped in the wizard:

| Check | Command / File | If missing → show step |
|---|---|---|
| CLI installed | `which msgvault` | Step 1: Install msgvault |
| config.toml present | `~/.msgvault/config.toml` exists | Step 2–4: GCP + credential setup |
| client_secret.json path valid | Parse config.toml `oauth.client_secrets` | Step 3–4: Credential file |
| At least one account | `msgvault list-accounts --json` | Step 5: Add account |
| At least one sync completed | Check `msgvault stats --json` message count > 0 | Step 6: First sync |

---

## Wizard Steps (Detailed)

### Step 1 — Install msgvault CLI

**Condition:** `which msgvault` returns nothing

**UI:**
- Explains what msgvault is in one sentence (local-first email archive, open source)
- Shows install command as a styled code block:
  ```
  curl -fsSL https://msgvault.io/install.sh | bash
  ```
- "Install Automatically" button — the app runs this command in a managed shell process and streams output into a terminal-style log view
- Progress indicator while installing; success/failure state
- On success: advances automatically to Step 2

**Notes:**
- Requires the user's shell to have internet access (obvious but worth calling out in error states)
- On failure: show the raw error output and a "Copy command to run manually" fallback

---

### Step 2 — Create Google Cloud Project

**Condition:** No valid `client_secret.json` path in config.toml

**UI:**
- Explains in plain language: "Gmail requires a one-time setup in Google's developer console. You'll be the owner of these credentials — we never see them."
- "Open Google Cloud Console" button → opens `https://console.cloud.google.com/projectcreate` in the default browser
- Checklist shown in the app sidebar while the user works in their browser:
  - [ ] Create a new project (name suggestion: `msgvault`)
  - [ ] Note your Project ID

**Copy/instruction panel:**
> Go to console.cloud.google.com → click the project dropdown at the top → "New Project" → name it `msgvault` → Create.

- "Done, I created my project" button advances to Step 3

---

### Step 3 — Enable Gmail API & Configure OAuth Consent Screen

**Condition:** Same as Step 2

**UI: Two sub-steps shown on one screen**

**3a — Enable Gmail API**
- "Enable Gmail API" button → opens `https://console.cloud.google.com/apis/library/gmail.googleapis.com` in browser
- Instruction: "Select your project in the dropdown at the top, then click Enable."
- Checkbox: "I enabled the Gmail API"

**3b — Configure OAuth Consent Screen**
- "Open Consent Screen" button → opens `https://console.cloud.google.com/apis/credentials/consent` in browser
- Instructions:
  1. Select "External" user type → Create
  2. App name: `msgvault`
  3. User support email: your email address
  4. Developer contact email: your email address
  5. Save and Continue through Scopes (no changes needed)
  6. Under "Test users" → Add Users → add your Gmail address(es)
  7. Save
- Checkbox: "I configured the consent screen and added my email as a test user"

**Important note shown in UI:**
> You don't need to publish this app or submit it for Google's review. Keeping it in "Testing" mode is intentional and works permanently for personal use.

---

### Step 4 — Create OAuth Credentials & Import

**Condition:** Same as Step 2

**UI:**

**4a — Create the credential**
- "Open Credentials" button → opens `https://console.cloud.google.com/apis/credentials` in browser
- Instructions:
  1. Click "Create Credentials" → "OAuth client ID"
  2. Application type: **Desktop app**
  3. Name: `msgvault` (or anything)
  4. Click Create
  5. Click "Download JSON" on the confirmation dialog
  6. Save the file somewhere you can find it (e.g. Downloads)

**4b — Import the credential file**
- Large drag-and-drop zone: "Drop your client_secret.json here"
- Or: "Browse for file" button → `NSOpenPanel` filtered to `.json`
- On file selection:
  - Validate JSON structure (must contain `installed.client_id`, `installed.client_secret`, `installed.redirect_uris`)
  - If valid: show a green checkmark and the detected client ID (partial, for reassurance)
  - If invalid: show a clear error describing what was wrong (wrong file type, wrong credential type — must be Desktop app not Web app, etc.)
- On valid file: the app copies it to `~/.msgvault/client_secret.json` and writes `~/.msgvault/config.toml`:
  ```toml
  [oauth]
  client_secrets = "/Users/<username>/.msgvault/client_secret.json"

  [sync]
  rate_limit_qps = 5
  ```
- "Continue" advances to Step 5

---

### Step 5 — Connect Your Gmail Account

**Condition:** No accounts in `msgvault list-accounts --json`

**UI:**
- Email input field: "Enter your Gmail address"
- Optional: display name field (shown as advanced/collapsed by default)
- "Connect Account" button
- On click: runs `msgvault add-account <email>` and opens the OAuth browser window automatically
- App shows a waiting state: "Complete sign-in in your browser…"
- Polls `msgvault list-accounts --json` every 2 seconds
- On account appearing in list: shows success state with account name and avatar/initial
- Error states:
  - "Browser didn't open" → show the manual URL copy fallback
  - "Timed out after 3 minutes" → show retry button
  - "Account not in test users" → specific guidance to go back to Step 3b and add the email

---

### Step 6 — First Sync (Test Run)

**Condition:** Account connected but zero messages synced

**UI:**
- Shows the connected account card
- Explains: "Let's download a small batch of emails to confirm everything is working before syncing your full archive."
- "Start Test Sync (100 messages)" button → runs `msgvault sync-full <email> --limit 100`
- Live streaming log output in a terminal-style panel (same pattern as Step 1 install)
- On completion: shows message count fetched and a summary
- "Sync Full Archive" button → runs `msgvault sync-full <email>` (no limit) in background, hands off to main app
- "Skip for now" → goes straight to main app UI; full sync can be triggered from the Sync tab

**Notes from msgvault docs:**
> Expect roughly 50 messages/second on fast internet. Accounts with hundreds of thousands of messages may take several hours. The sync is resumable if interrupted.

The UI should set this expectation before the user clicks "Sync Full Archive".

---

### Completion

- Wizard closes, main app UI loads with the connected account visible in the Accounts tab
- A persistent "Syncing in background" indicator is shown in the toolbar if a full sync is running
- First-run tooltip: points to Accounts tab, Search tab, and Stats tab

---

## Subsequent Account Additions (Multi-Account)

When a user clicks "Add Account" in the Accounts tab and `config.toml` already exists with valid credentials:

- Skip Steps 1–4 entirely
- Jump directly to Step 5 (Connect Gmail Account) — email input, `msgvault add-account`, OAuth flow
- On success: refresh the accounts list and show the new account card
- The new account is immediately searchable across all queries

For Google Workspace accounts: same flow — the email just ends in a custom domain. No changes needed in the wizard.

---

## Error States & Recovery

| Scenario | Recovery |
|---|---|
| msgvault install fails | Show raw error + copy-to-clipboard manual install command |
| Wrong JSON file imported (e.g. Web app credential instead of Desktop app) | Clear error message identifying the mismatch, instructions to recreate as Desktop app |
| OAuth browser window never opens | Show `msgvault add-account <email> --headless` fallback instructions |
| Gmail address not added as Test User | Link directly to `https://console.cloud.google.com/apis/credentials/consent` with instructions |
| Sync fails mid-way | Reassure that it is resumable; show `msgvault sync-full <email>` command to re-run |
| User already has msgvault set up | Skip applicable steps, show what was detected (binary path, config path, accounts found) |

---

## Technical Implementation Notes

### State machine
The wizard is a `SetupWizardStore` (`ObservableObject`) that:
- Runs precondition checks on init
- Exposes `currentStep: WizardStep` (enum)
- Exposes `completedSteps: Set<WizardStep>`
- Each step's action runs a `ShellRunner` async command (same pattern as existing `EmailStore`)

### Shell execution
Reuse the existing command execution pattern from `EmailStore`. New commands needed:
- `which msgvault` — binary detection
- `curl -fsSL https://msgvault.io/install.sh | bash` — install (streaming output)
- `msgvault list-accounts --json` — account detection
- `msgvault add-account <email>` — account addition (opens browser)
- `msgvault sync-full <email> --limit 100` — test sync (streaming output)
- `msgvault sync-full <email>` — full sync (background, streaming)

### File operations
- Read `~/.msgvault/config.toml` (detect existing setup)
- Copy imported `client_secret.json` to `~/.msgvault/client_secret.json`
- Write `~/.msgvault/config.toml` with correct content

### Config.toml writing
The app constructs the TOML content as a string and writes it directly. No TOML parser dependency needed for the simple two-key structure msgvault requires.

---

## Implementation Phases

### Phase 1 — Core Wizard (MVP)
- [ ] `SetupWizardStore` with step state machine and precondition checks
- [ ] Wizard host view (full-screen for first launch, sheet for Accounts tab)
- [ ] Step 1: msgvault install with streaming output
- [ ] Step 2: GCP project creation (deep-link + instruction panel + checkbox gate)
- [ ] Step 3: Gmail API + OAuth consent (deep-link + sub-step checklist)
- [ ] Step 4: Credential creation instructions + drag-and-drop JSON import + config.toml write
- [ ] Step 5: Add account (email input + `msgvault add-account` + OAuth polling)
- [ ] Step 6: Test sync (100 messages, streaming log) + full sync launch
- [ ] Completion handoff to main app UI
- [ ] Error states for each step

### Phase 2 — gcloud CLI Automation
- [ ] Detect `gcloud` CLI presence (`which gcloud`)
- [ ] If present: offer "Auto-configure with gcloud" path that runs:
  - `gcloud projects create msgvault-<random-suffix>`
  - `gcloud services enable gmail.googleapis.com`
  - `gcloud alpha iap oauth-clients create` (or equivalent)
- [ ] Still requires manual OAuth consent screen configuration (not automatable via CLI)
- [ ] Falls back to Phase 1 manual wizard if gcloud not present

### Phase 3 — Microsoft 365 / Outlook
- [ ] Separate wizard branch for Outlook accounts
- [ ] Requires Azure AD app registration (separate deep-link flow)
- [ ] Depends on msgvault adding Outlook/Graph API support

---

## Success Metrics

| Metric | Target |
|---|---|
| Users who start wizard and reach Step 5 | > 80% |
| Users who complete first sync | > 70% of those who reach Step 5 |
| Support issues related to setup | Reduce by 80% vs. unguided flow |
| Time from app launch to first sync started | < 10 minutes for a new user |

---

## Open Questions

1. **Should the app ship with a bundled install script** or always fetch from msgvault.io? (Bundling pins a version; fetching is always current but requires internet at install time.)
2. **Sandbox considerations** — MsgVaultUI may need the `com.apple.security.temporary-exception.files.home-relative-path.read-write` entitlement to write to `~/.msgvault/` if the app is sandboxed. Confirm entitlements before implementation.
3. **Notarisation** — running `curl | bash` from inside a sandboxed app has restrictions. May need to shell out via a helper or use `NSWorkspace.open(url:)` for the install step and ask the user to run it themselves in Terminal, with a copy button.
4. **Google Workspace domains** — same OAuth flow, but the GCP project ownership. Should the wizard mention corporate IT restrictions? (Some Workspace orgs block external OAuth apps — worth a note in error states.)
