# Plan: MsgVaultUI Marketing Website

## Status
Draft — ready for design and build

---

## Overview

A standalone marketing website for **MsgVaultUI** — the native macOS GUI for the open-source [msgvault](https://github.com/wesm/msgvault) CLI. Hosted on Firebase Hosting. Positioned as a sub-brand of Fueld, with its own mini visual identity. The site serves as the primary landing page, feature showcase, setup reference, and GitHub gateway for the app.

---

## Goals

1. Drive downloads and GitHub stars for MsgVaultUI.
2. Communicate the core value proposition clearly: local-first, private, fast email archive on your Mac.
3. Provide a lightweight setup guide so new users can get from zero to first sync without leaving the site.
4. Establish credibility by cross-linking to Fueld (parent brand), msgvault.io (upstream project), and GitHub.
5. Receive inbound traffic from Fueld's website and from msgvault.io as a recommended GUI client.
6. Act as a soft marketing touchpoint for Fueld and future projects (e.g. Flank).

---

## Brand Identity

### Name
**MsgVault** — app name used throughout.
**MsgVaultUI** — technical name used in code/GitHub references.

### Sub-brand relationship
MsgVault sits under the **Fueld** family. The Fueld wordmark and link appear in the site footer ("Made by [Fueld](https://fueld.com)"). The sub-brand is distinct enough to stand alone but shares Fueld's design sensibility: clean, developer-adjacent, purposeful.

### Logo Concept
The logo mark combines two ideas:
- **An email envelope** — representing the content being archived.
- **A shield or search loop** overlaid on or around the envelope — representing the privacy-first, local-only ethos (shield) and the instant search capability (search loop).

Two directions to explore with a designer or generative tool:

**Direction A — Shield + Envelope**
A minimal flat envelope icon contained inside or backed by a shield shape. The shield communicates "your email, protected — on your machine." Works well in monochrome and as an app icon derivative. Colour suggestion: deep navy shield, white envelope, with a small Fueld-family accent colour (could use Fueld brand blue/orange).

**Direction B — Search Loop + Envelope**
A search magnifier where the circular loop frames or contains a small envelope icon. Communicates speed and discoverability of your own archive. Works especially well as a favicon and in-app icon.

**Recommendation:** Direction B for the wordmark logo (search = primary user action), Direction A shield variant as a secondary trust badge used on privacy-related copy sections.

### Colour palette (proposed)
| Token | Value | Usage |
|---|---|---|
| `--brand-ink` | `#111827` | Body text, dark backgrounds |
| `--brand-surface` | `#F9FAFB` | Page background |
| `--brand-primary` | `#2563EB` | CTAs, links, highlights |
| `--brand-accent` | `#F97316` | Fueld family accent (matches Fueld brand) |
| `--brand-muted` | `#6B7280` | Secondary text, captions |
| `--brand-border` | `#E5E7EB` | Dividers, card borders |

Dark mode variants should be provided for all tokens.

### Typography
- **Heading font**: Inter Display or Geist — clean, modern, legible at large sizes.
- **Body font**: Inter — widely readable, pairs naturally with the heading.
- **Code font**: JetBrains Mono or Geist Mono — used in setup steps and CLI snippets.

### Voice & tone
- Confident and direct. Not corporate-speak.
- Developer-adjacent but accessible to power users and non-developers alike.
- Privacy-forward without being paranoid.
- Short sentences. Active voice.

---

## Site Architecture

```
/                   → Home (hero + features summary + CTA)
/features           → Full features breakdown
/setup              → Setup guide (abbreviated, links to msgvault.io for depth)
/download           → Download page (GitHub release link + install command)
/changelog          → Release notes / version history (optional v1, auto-generated from GitHub releases)
/readme             → GitHub README mirror or embed (for inbound GitHub traffic context)
```

### Navigation bar
```
[MsgVault logo]   Home   Features   Setup   Download        [GitHub ↗]
```

Footer:
```
Made by [Fueld ↗] · Built on [msgvault ↗] by Wes McKinney · [GitHub ↗] · Privacy
```

---

## Page Specifications

---

### Page 1: Home (`/`)

**Purpose:** Convert first-time visitors. Communicate the key value prop in under 10 seconds.

#### Hero section

**Headline (large):**
> Your entire Gmail history. On your Mac. Instantly searchable.

**Sub-headline:**
> MsgVault is a free, open-source macOS app that archives your Gmail locally and gives you lightning-fast full-text search — with no cloud, no subscriptions, and no one else seeing your email.

**CTA buttons:**
- Primary: `Download for Mac` → `/download`
- Secondary: `View on GitHub ↗` → GitHub repo

**Hero visual:** Dark-mode screenshot or mockup of the MsgVaultUI app showing the search results view with a fast result list. Consider an animated typing demo showing a query appearing and results loading instantly.

**Trust signals row (below hero):**
- `🔒 100% local — emails never leave your Mac`
- `⚡ SQLite FTS5 — search 500k emails in milliseconds`
- `🆓 Free & open source`
- `🍎 Native macOS — Apple Silicon optimised`

---

#### Feature teaser section

Three-column card grid. Each card: icon, short title, 2-line description.

| Icon | Title | Description |
|---|---|---|
| 🔍 | Instant full-text search | Search across every email you've ever received — subject, body, sender — in milliseconds. |
| 🗄️ | Full archive, offline | Your entire Gmail history synced to your Mac. No internet required to search. |
| 👤 | Multi-account | Add multiple Gmail accounts. Search across all of them simultaneously. |
| 📊 | Sender analytics | See who emails you most. Drill into any sender's full thread history with one click. |
| 🤖 | AI-powered search *(coming soon)* | Type in plain English. A local LLM translates your intent — privately, on-device. |
| 🔐 | You own your credentials | Your Google Cloud project, your OAuth credentials, your data. Nobody else in the chain. |

Link: `→ See all features` linking to `/features`

---

#### How it works (3-step visual)

```
① Sync once          ② Search forever          ③ Stay private
msgvault pulls your  Full-text SQLite search   Your GCP credentials.
full Gmail archive   across all emails,         Your machine.
to your Mac.         instantly.                 Your data.
```

Brief note: "Syncing a large archive (100k+ emails) takes a few hours. After that, new email syncs are incremental — fast and automatic."

---

#### "Built on open source" section

> MsgVault is a native macOS GUI built on top of [msgvault](https://www.msgvault.io) — the open-source command-line email archive tool created by Wes McKinney (creator of pandas). All the heavy lifting — syncing, indexing, and searching — happens inside the msgvault binary. MsgVaultUI wraps it in a beautiful native Mac app.

Logo: `msgvault.io` text link + short blurb. Establishes credibility and upstream attribution.

---

#### Fueld attribution section (footer pre-footer)

Subtle section, not a full marketing blast:

> MsgVault is a project by **[Fueld](https://fueld.com)** — a small studio building tools for developers and knowledge workers.

Fueld logo (light/dark variant, already in `/Resources/Branding/`). Link to fueld.com.

---

### Page 2: Features (`/features`)

**Purpose:** Full breakdown for users evaluating the app in depth.

#### Section structure

**1. Instant Local Search**
- Full-text search using SQLite FTS5 — the same engine used by major desktop apps.
- Searches subject, body, sender, recipients, and labels simultaneously.
- Filters: From, To, CC, BCC, Subject, Label, Date range (relative and absolute), Attachment presence, Email size.
- Sort by: Date, Sender, Subject.
- Saved searches and recent query history.
- Search scope toggle: Everything / Subject only / From/To.
- Account picker for targeted per-account searches.
- *(Coming soon)* Natural-language AI search — type "invoices from HSBC last month" and MsgVault translates it into structured operators, entirely on-device.

**2. Full Gmail Archive**
- Syncs your complete Gmail history to a local SQLite database.
- Incremental syncs for new email — only fetches what's new.
- Resumable sync — safe to interrupt and restart.
- Multiple sync modes: full archive (`sync-full`), limited test sync (`--limit`), per-account targeting.
- No message size restrictions — full bodies, all labels, all metadata.

**3. Multi-Account**
- Connect as many Gmail accounts as you need.
- Each account uses its own OAuth credentials — no cross-account credential sharing.
- Search and stats work across all accounts simultaneously by default.
- Per-account targeting available in search and sync.
- Google Workspace (custom domain) accounts supported — same setup flow.

**4. Sender Analytics**
- Ranked list of who emails you most, by message count.
- Click any sender to see their complete message history in a detail panel.
- Filter messages by subject keyword within a sender's history.
- One-click jump to Search tab with `from:<email>` pre-filled.

**5. Guided Setup Wizard**
- Zero-to-syncing guided flow for first-time users.
- Step-by-step: installs msgvault CLI, walks through Google Cloud project creation, Gmail API enablement, OAuth consent screen, credential download, account connection, and first sync.
- No terminal knowledge required.
- Detects existing msgvault installations and skips completed steps automatically.
- Deep-links into Google Cloud Console at exactly the right pages.
- Drag-and-drop credential file import with validation.

**6. Privacy by Design**
- Your Google Cloud project. Your OAuth credentials. Your machine.
- No centralised OAuth app — MsgVault never holds a token that can access your Gmail.
- No telemetry, no analytics, no crash reporting phoning home.
- No subscription, no account, no server.
- Open source — the code is auditable.

**7. Native macOS**
- Built in SwiftUI for macOS 14 (Sonoma) and later.
- Optimised for Apple Silicon (M1/M2/M3/M4).
- Follows macOS conventions: Dark Mode, system fonts, native window management.
- Keyboard-first search experience.

**8. AI Search *(coming soon)***
- Optional local LLM layer for natural-language query translation.
- Queries like "emails from my accountant in January with attachments" automatically translate to msgvault operators.
- Runs entirely on-device using Apple MLX — no API calls, no data leaves your Mac.
- Powered by Qwen 3 1.7B (Apache 2.0) — ~1 GB optional download.
- Shows the translated query so you can see (and learn) exactly what was searched.
- Gracefully degrades — everything works without the model.

**9. Voice Search *(coming soon)***
- Speak your search query using on-device macOS speech recognition.
- Pairs with the AI layer: speech → text → structured operator → results.

---

### Page 3: Setup Guide (`/setup`)

**Purpose:** Concise, actionable setup walkthrough. Reduces friction for new users. Not a full duplication of msgvault.io docs — links out for depth.

#### Structure

**Intro copy:**
> Getting MsgVault running takes about 10–15 minutes and a one-time setup in Google Cloud. The app's Setup Wizard walks you through every step — but this page gives you a map of the journey.

---

**Step 1 — Download MsgVault**

Download the latest release from [GitHub Releases ↗](#) or use the direct download button. Unzip and move `MsgVaultUI.app` to your Applications folder.

---

**Step 2 — Install the msgvault CLI**

MsgVaultUI's Setup Wizard can install this for you automatically. Or run manually:

```bash
curl -fsSL https://msgvault.io/install.sh | bash
```

> Full installation docs: [msgvault.io/setup ↗](https://www.msgvault.io/setup/)

---

**Step 3 — Create a Google Cloud Project**

*Why?* MsgVault connects to Gmail using the official Gmail API. You create a personal Google Cloud project so you own the credentials — Google never grants access to anyone but you.

1. Go to [console.cloud.google.com](https://console.cloud.google.com/projectcreate) → Create a new project (name it `msgvault`).
2. Enable the [Gmail API ↗](https://console.cloud.google.com/apis/library/gmail.googleapis.com) for your project.
3. Set up an [OAuth Consent Screen ↗](https://console.cloud.google.com/apis/credentials/consent) — choose External, fill in your email, add your Gmail as a Test User.

> **You do not need Google's approval.** Keeping the app in "Testing" mode is intentional and works permanently for personal use.

> Full guide: [msgvault.io/guides/oauth-setup ↗](https://www.msgvault.io/guides/oauth-setup/)

---

**Step 4 — Download Your OAuth Credentials**

In [Google Cloud Credentials ↗](https://console.cloud.google.com/apis/credentials):

1. Create Credentials → OAuth client ID → **Desktop app**.
2. Download the JSON file.
3. Drag it into MsgVaultUI's Setup Wizard — the app handles the rest.

---

**Step 5 — Connect Your Gmail Account**

The wizard prompts for your Gmail address and opens a browser for Google's standard OAuth sign-in flow. Sign in, grant access, and you're done. Your credentials stay on your machine.

> Multi-account: [msgvault.io/usage/multi-account ↗](https://www.msgvault.io/usage/multi-account/)

---

**Step 6 — Sync Your Archive**

Start with a test sync (100 messages) to confirm everything works. Then launch a full sync. Expect:
- ~50 messages/second on a fast connection.
- Large archives (200k+ messages) may take several hours.
- Sync is resumable — safe to pause and restart.

After the first full sync, incremental syncs are fast and can run on a schedule.

---

**Having trouble?** Open an issue on [GitHub ↗](#) or check the [msgvault documentation ↗](https://www.msgvault.io).

---

### Page 4: Download (`/download`)

**Purpose:** Single, frictionless path to getting the app.

**Content:**

```
Download MsgVault for Mac

Version 1.x.x  ·  Requires macOS 14 (Sonoma) or later  ·  Apple Silicon & Intel

[  ⬇ Download .zip (macOS)  ]      [  View on GitHub ↗  ]

SHA-256: <checksum>
```

- System requirements: macOS 14+, Apple Silicon recommended, Intel supported.
- Note: "MsgVault is not yet notarised. Right-click → Open the first time you launch."
- Note about open-source: "This is free software. No licence, no account, no payment."

Also surface the CLI install command for users who want to start with msgvault itself:

```bash
# Install the msgvault CLI (required by MsgVaultUI)
curl -fsSL https://msgvault.io/install.sh | bash
```

Link to msgvault.io for full CLI documentation.

---

### Page 5: Changelog (`/changelog`) *(optional — v1 launch)*

Auto-generated from GitHub Releases or manually maintained. Simple reverse-chronological list of versions with release notes.

Can be seeded from GitHub Releases API at build time (works well with Astro/Next.js static generation).

---

### Page 6: README (`/readme`)

**Purpose:** A rendered version of the GitHub README for users landing from the GitHub repo who want a nicer reading experience, and to capture some GitHub referral traffic back to the site.

Content mirrors `README.md` from the GitHub repo. Can be auto-rendered at build time from the repo's README.

Include a banner at the top: "You're reading the MsgVault README. [View on GitHub ↗](#)"

---

## Cross-linking Strategy

### Inbound links to the MsgVaultUI site

| Source | Placement | Copy |
|---|---|---|
| **msgvault.io** | GUI Clients section or sidebar | "Looking for a macOS GUI? Try [MsgVaultUI ↗]" |
| **Fueld website** | Projects/Tools page | "MsgVault — local-first Gmail archive for Mac [↗]" |
| **GitHub repo** | README hero | Badge + link: "Website: msgvaultui.com" |

### Outbound links from the MsgVaultUI site

| Destination | Placement | Purpose |
|---|---|---|
| msgvault.io | Footer, Setup page, Features page | Upstream attribution and deep doc links |
| GitHub repo | Nav bar, Download page | Primary code/release source |
| **Fueld** | Footer, "Built by" section | Parent brand awareness |
| **Flank** *(when live)* | Footer or "From the same studio" section | Cross-project discovery |

### Fueld website integration
A small "Made by Fueld" attribution appears in the footer with the Fueld logo. The Fueld website should reciprocate with a Projects or Tools listing. The Fueld logo assets are already present in `/MsgVaultUI/Resources/Branding/` — these can be reused on the marketing site.

---

## Tech Stack

| Layer | Choice | Rationale |
|---|---|---|
| Framework | **Astro** (static) | Zero JS by default, fast, great for content sites, easy Firebase deploy |
| Styling | **Tailwind CSS** | Rapid consistent styling, dark mode built-in |
| Hosting | **Firebase Hosting** | CDN-backed, custom domain, free tier generous, instant deploys |
| Analytics | **PostHog** (via existing setup) | Already integrated in the Fueld ecosystem — use the same project or create a new one |
| Icons | **Heroicons** or **Phosphor Icons** | Consistent, open-source, SVG |
| Code blocks | **Shiki** (via Astro integration) | Beautiful, accurate syntax highlighting, zero runtime |

### Firebase Hosting config (outline)

```json
{
  "hosting": {
    "public": "dist",
    "ignore": ["firebase.json", "**/.*", "**/node_modules/**"],
    "rewrites": [
      { "source": "**", "destination": "/index.html" }
    ],
    "headers": [
      {
        "source": "**/*.@(js|css|woff2)",
        "headers": [{ "key": "Cache-Control", "value": "max-age=31536000" }]
      }
    ]
  }
}
```

### Deployment

```bash
# Build
npm run build          # Astro outputs to /dist

# Deploy to Firebase Hosting
firebase deploy --only hosting
```

---

## Domain

Suggested: **msgvaultui.com** or **msgvault.app** (check availability).

If neither is available:
- **getmsgvault.com**
- **msgvaultapp.com**

Subdomain fallback if keeping under Fueld domain: **msgvault.fueld.com** (simple, no registration needed, makes the sub-brand relationship explicit).

---

## SEO & Metadata

### Target keywords
- "gmail archive mac app"
- "local gmail search mac"
- "offline gmail search"
- "msgvault gui"
- "private email archive macos"

### Meta tags per page

```html
<!-- Home -->
<title>MsgVault — Local Gmail Archive for Mac</title>
<meta name="description" content="Search your entire Gmail history instantly — offline, private, and free. A native macOS app built on msgvault." />

<!-- Features -->
<title>Features — MsgVault</title>

<!-- Setup -->
<title>Setup Guide — MsgVault</title>

<!-- Download -->
<title>Download MsgVault for Mac</title>
```

### Open Graph
- `og:image` — dark-mode app screenshot or branded card (1200×630).
- `og:type` — `website`.
- Twitter Card: `summary_large_image`.

---

## GitHub README Alignment

The GitHub `README.md` for the MsgVaultUI repo should:
- Include a hero badge linking to the marketing website.
- Include a one-line pitch matching the website headline.
- Link to `/setup` for the setup guide (rather than duplicating it fully in the README).
- Include the install command and a screenshot.
- Attribute msgvault (upstream) and Fueld.

---

## Flank Cross-Promotion

When Flank launches, the MsgVault site should include a subtle "From the same studio" or "Also by Fueld" section in the footer or a dedicated `/studio` page listing both products. This creates a lightweight discovery loop between projects without diluting MsgVault's focused positioning.

---

## Launch Checklist

- [ ] Logo mark finalised (search loop + envelope, plus shield variant)
- [ ] Domain registered and pointed at Firebase Hosting
- [ ] Astro project scaffolded with Tailwind
- [ ] Firebase project created (`msgvaultui` or under existing Fueld project)
- [ ] Home page built and reviewed
- [ ] Features page built
- [ ] Setup Guide page built
- [ ] Download page built (manual release link v1)
- [ ] App screenshot(s) captured (dark mode, light mode)
- [ ] Open Graph image created (1200×630)
- [ ] SEO meta tags on all pages
- [ ] PostHog analytics wired up
- [ ] Firebase Hosting deploy tested end-to-end
- [ ] Custom domain configured with SSL
- [ ] Cross-links from Fueld website added
- [ ] msgvault.io GUI clients link negotiated / submitted
- [ ] GitHub README updated with site link and badge
- [ ] `/readme` page seeded from README.md

---

## Open Questions

1. **Domain**: msgvaultui.com, msgvault.app, or fueld.com subdomain? Check availability.
2. **Notarisation**: Should the Download page include a clear "not yet notarised — here's how to open it" note, or is notarisation a launch prerequisite?
3. **Changelog automation**: Manually maintain or auto-generate from GitHub Releases at build time?
4. **Fueld reciprocal link**: Coordinate timing so both the MsgVault site launch and the Fueld site update go live together.
5. **msgvault.io GUI listing**: Reach out to Wes McKinney's team to request a "GUI clients" section or mention on msgvault.io with a backlink.
6. **Analytics project**: New PostHog project specifically for the website, or share with the existing Fueld project?
