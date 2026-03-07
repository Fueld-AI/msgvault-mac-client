# POD: Next-Generation Search Experience

## Vision

Transform MsgVault's search from a functional filter-based system into an intelligent, multi-modal search experience that exploits the speed of local SQLite/FTS5 and optionally layers on a local LLM for natural-language query translation — all without ever leaving the machine.

---

## Part 1: Enhanced UI Search Mechanics

### What we have today

The current `SearchView` provides:
- A keyword search bar (free text, sent to msgvault as-is)
- Filter panel with: From, To, Subject, Label (text fields), After/Before (date pickers), Has Attachment (toggle)
- Sort options: Default, Date, Sender, Subject
- Active filter chips with remove

### What msgvault supports but we don't expose

| Operator | What it does | Status |
|----------|-------------|--------|
| `cc:` | CC recipient | **Not in UI** |
| `bcc:` | BCC recipient | **Not in UI** |
| `older_than:` | Relative date (`7d`, `2w`, `1m`, `1y`) | **Not in UI** |
| `newer_than:` | Relative date | **Not in UI** |
| `larger:` | Min size (`100K`, `5M`) | **Not in UI** |
| `smaller:` | Max size | **Not in UI** |
| `--account` | Per-account filtering | **Not in UI** |

### Proposed UI enhancements

#### 1a. Quick Date Presets (high impact, low effort)
Replace or augment the calendar date pickers with one-tap presets:
- **Today** / **Yesterday** / **Last 7 days** / **Last 30 days** / **Last 3 months** / **Last year**
- These map directly to `newer_than:1d`, `newer_than:7d`, etc.
- Keep the calendar for custom ranges, but presets cover 90% of use.

#### 1b. Size Filter (medium impact)
Add a size slider or dropdown in the filter panel:
- "Any size" / "Larger than 1MB" / "Larger than 5MB" / "Larger than 10MB"
- Useful for finding emails with large attachments (reports, decks, media).
- Maps to `larger:1M`, `larger:5M`, etc.

#### 1c. CC/BCC Fields (low–medium impact)
Add optional CC and BCC filter fields alongside From/To. Less commonly needed, but rounds out the filter panel for power users.

#### 1d. Account Picker (medium impact, multi-account users)
For users with multiple accounts, add a segmented control or dropdown:
- "All accounts" (default) / specific account email
- Maps to `--account <email>` on the CLI.

#### 1e. Search Scope Toggle (high impact)
A segmented control above the search bar:
- **Everything** (default) — full text across subject + body
- **Subject only** — wraps the keyword in `subject:`
- **From/To** — wraps the keyword in `from:` or `to:`

This lets the top-level search bar itself become more targeted without needing to open the filter panel. Users type "invoice" and toggle to "Subject only" to get `subject:invoice`.

#### 1f. Saved Searches / Recent Queries
- Persist the last N search queries (keyword + filters) in UserDefaults.
- Show as a dropdown when the search bar is focused but empty.
- Optional: let users pin/save frequent searches with a name.

#### 1g. Search-as-you-type / Debounced Live Search
Since everything is local and fast:
- After a 300ms debounce, automatically trigger search on keystroke.
- Show a lightweight inline count ("~142 results") before the user hits Enter.
- Full result list loads on Enter or after idle threshold.

---

## Part 2: LLM Natural-Language Search Layer

### Concept

Add a "smart search" mode where users can type (or speak) freeform queries like:

> "emails from McKinsey last week about AI strategy with attachments"

The LLM translates this into the structured query:

```
from:mckinsey newer_than:7d subject:"AI strategy" has:attachment
```

This is pure query translation — the LLM never sees the email content. It only parses intent into operators.

### Architecture

```
┌─────────────────────────────────────────────────┐
│  Search Bar  (unified)                          │
│  ┌───────────────────────────────────────────┐  │
│  │ "invoices from HSBC bigger than 1MB"      │  │
│  └───────────────────────────────────────────┘  │
│        │                                        │
│        ▼                                        │
│  ┌──────────┐    ┌───────────────────────┐      │
│  │ LLM      │───▶│ Structured Query      │      │
│  │ available?│    │ from:hsbc             │      │
│  │          │    │ subject:invoice        │      │
│  │  YES ────│    │ larger:1M              │      │
│  │  NO  ────│──▶ pass through as-is      │      │
│  └──────────┘    └───────┬───────────────┘      │
│                          │                      │
│                          ▼                      │
│                  msgvault search                 │
└─────────────────────────────────────────────────┘
```

### How it works

1. **Detection**: If a local LLM is available (model file exists on disk), a small sparkle/wand icon appears in the search bar indicating "AI search" mode.
2. **Prompt template**: The LLM receives a system prompt with the full operator grammar and today's date. The user query goes in. The LLM outputs JSON:
   ```json
   {
     "keywords": "AI strategy",
     "from": "mckinsey",
     "to": null,
     "subject": "AI strategy",
     "after": null,
     "before": null,
     "newer_than": "7d",
     "older_than": null,
     "has_attachment": true,
     "larger": null,
     "smaller": null,
     "label": null
   }
   ```
3. **Query builder**: The app assembles this JSON into the operator string and fires the search.
4. **Transparency**: Show the translated query in a subtle bar below the search field so the user can see (and edit) what the LLM interpreted. This builds trust and lets them learn the operator syntax over time.
5. **Fallback**: If the LLM is not installed, the search bar works exactly as it does today — direct keyword/operator pass-through.

### Prompt Design

The system prompt is tiny and deterministic:

```
You translate natural language email search queries into structured JSON.
Available operators: from, to, cc, bcc, subject, label, has_attachment (bool),
after (YYYY-MM-DD), before (YYYY-MM-DD), newer_than (e.g. 7d, 2w, 1m, 1y),
older_than, larger (e.g. 1M, 500K), smaller, keywords (free text).
Today's date is {TODAY}.
Output ONLY valid JSON. No explanation.
```

This is a constrained extraction task — among the simplest things a small model can do reliably.

### Voice Input (bonus)

macOS provides `NSSpeechRecognizer` / `SFSpeechRecognizer` for on-device speech-to-text. The flow becomes:

1. User clicks microphone icon in search bar
2. macOS transcribes speech to text (built-in, no model needed)
3. Transcribed text feeds into the LLM translation layer
4. Structured query fires

The LLM is the perfect glue here because spoken language is inherently messy — "show me stuff from John about the budget, I think it was sometime in January" — and the model normalises it.

---

## Part 3: Lightweight Local LLM — Model Selection

### Requirements

| Requirement | Rationale |
|------------|-----------|
| < 2 GB on disk (quantized) | Optional download, not a blocker |
| < 1 GB RAM at inference | Runs alongside the app comfortably |
| Fast inference (< 1s for this task) | Must feel instant, not "loading…" |
| Structured JSON output | Must reliably produce parseable output |
| Runs on Apple Silicon natively | M1/M2/M3/M4, no CUDA dependency |
| Open-source, permissive license | Can bundle with app |
| No cloud dependency | Privacy-first, matches MsgVault ethos |

### Model Shortlist

| Model | Params | Quantized Size | RAM | Speed (M3) | License | Fit |
|-------|--------|---------------|-----|------------|---------|-----|
| **Qwen 3 0.6B** (Q4_K_M) | 0.6B | ~350 MB | ~500 MB | 200+ tok/s | Apache 2.0 | Smallest option. May struggle with edge cases. |
| **Qwen 3 1.7B** (Q4_K_M) | 1.7B | ~1 GB | ~1.2 GB | 120+ tok/s | Apache 2.0 | **Sweet spot.** Reliable structured output at minimal cost. |
| **Phi-4 Mini** (Q4_K_M) | 3.8B | ~2.2 GB | ~2.5 GB | 60+ tok/s | MIT | Overkill for this task, but excellent structured output / function calling. |
| **Llama 3.2 1B** (Q4_K_M) | 1.3B | ~750 MB | ~1 GB | 150+ tok/s | Llama 3.2 | Good middle ground. Llama license has some restrictions for commercial. |
| **Llama 3.2 3B** (Q4_K_M) | 3.2B | ~1.8 GB | ~2 GB | 80+ tok/s | Llama 3.2 | Reliable but heavier than needed. |

### Recommendation: **Qwen 3 1.7B (Q4_K_M)**

- **350 MB → 1 GB disk**: small enough to be an optional "Enable AI Search" download.
- **Reliable structured JSON**: at 1.7B params, Qwen 3 handles constrained extraction tasks well — this is simpler than code generation or reasoning.
- **Apache 2.0**: no license friction, can bundle freely.
- **200ms inference for a 50-token output on M-series**: feels instant.

Fallback plan: if the 1.7B occasionally misfires on complex queries, we can offer Phi-4 Mini as a "higher accuracy" alternative download.

### Integration: MLX Swift (recommended over llama.cpp)

**Why MLX over llama.cpp:**
- **Native Swift API**: `mlx-swift` and `MLXLLM` are Swift packages — drop them into `Package.swift`, no C bridging.
- **21–87% faster on Apple Silicon** than llama.cpp (MLX exploits unified memory, lazy evaluation, Metal natively).
- **First-party Apple ecosystem**: maintained by Apple's ML research team (`ml-explore`).
- **Already has SwiftUI examples**: `mlx-swift-examples` repo has `LLMEval` app as a reference implementation.

**Integration steps:**
1. Add `mlx-swift-examples` / `MLXLLM` as a Swift package dependency.
2. Create a `QueryTranslator` service that loads the Qwen 3 1.7B MLX model from a known path (e.g. `~/Library/Application Support/MsgVaultUI/models/`).
3. On app launch, check if the model directory exists. If yes, enable AI search. If no, show an "Enable AI Search" button in Settings that triggers a download.
4. At query time, run the prompt through `MLXLLM`, parse the JSON output, and assemble the msgvault query string.

### Model Distribution

Two options:

**Option A — In-app download (recommended):**
- Settings page has an "AI Search" section.
- "Download Model (~1 GB)" button fetches the GGUF/MLX model from Hugging Face.
- Progress bar. Once done, AI search icon appears in the search bar.
- User can delete the model to reclaim space.

**Option B — Bundled with app:**
- Ship the model inside the `.app` bundle.
- Makes the app download 1 GB larger.
- Simpler, but not everyone wants/needs it.

Option A is better for a local-first tool where users value control over disk space.

---

## Implementation Phases

### Phase 1: UI Mechanics (no LLM, pure SwiftUI)
- [ ] Add quick date presets (Today, 7d, 30d, 3mo, 1yr)
- [ ] Add size filter (larger/smaller dropdown)
- [ ] Add CC/BCC filter fields
- [ ] Add account picker for multi-account users
- [ ] Add search scope toggle (Everything / Subject / From)
- [ ] Add saved/recent searches
- [ ] Explore debounced live search

### Phase 2: LLM Query Translation
- [ ] Add `MLXLLM` Swift package dependency
- [ ] Create `QueryTranslator` service with prompt template
- [ ] Add AI search toggle in search bar (sparkle icon)
- [ ] Show translated query preview bar
- [ ] Add model download/management in Settings
- [ ] Test with edge cases (ambiguous dates, partial names, mixed intent)

### Phase 3: Voice Input
- [ ] Add microphone button to search bar
- [ ] Integrate `SFSpeechRecognizer` for on-device transcription
- [ ] Pipe transcription through LLM translation layer
- [ ] Handle permissions (microphone access prompt)

---

## Risk & Mitigation

| Risk | Impact | Mitigation |
|------|--------|------------|
| Small model hallucinates operators | Bad search results | Validate JSON output against known operator schema; fallback to raw query |
| Model download fails / HF rate limit | AI search unavailable | Graceful degradation — everything works without the model |
| MLX Swift API changes | Build breaks | Pin dependency version; MLX Swift is stable post-2.x |
| User dictates ambiguous query | Wrong interpretation | Show translated query, let user edit before searching |
| Model RAM pressure on 8GB machines | App slowdown | Unload model from memory after 30s idle; lazy load on search |

---

## UX Mock: Search Bar States

```
┌─ Normal mode (no LLM) ───────────────────────────────────┐
│ 🔍 Search your emails...                    ≡  [Search]  │
└───────────────────────────────────────────────────────────┘

┌─ AI mode (LLM available) ────────────────────────────────┐
│ ✨🔍 Ask anything about your emails...       ≡  [Search] │
└───────────────────────────────────────────────────────────┘
│ ↳ Translated: from:hsbc subject:invoice larger:1M        │
└───────────────────────────────────────────────────────────┘

┌─ AI mode + voice ────────────────────────────────────────┐
│ ✨🔍 "emails from HSBC about invoices..."  🎤 ≡ [Search] │
└───────────────────────────────────────────────────────────┘
```

---

## References

- msgvault search syntax: https://www.msgvault.io/usage/searching/
- msgvault API server: https://www.msgvault.io/api-server/
- MLX Swift: https://github.com/ml-explore/mlx-swift
- MLX Swift Examples (LLMEval): https://github.com/ml-explore/mlx-swift-examples
- Qwen 3 0.6B–1.7B GGUF: https://huggingface.co/Qwen/Qwen3-0.6B-GGUF
- Apple SFSpeechRecognizer: https://developer.apple.com/documentation/speech/sfspeechrecognizer
