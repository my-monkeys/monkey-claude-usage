# How it works

The [README](../README.md) says what the app does. This page says how, and why a few things are
stranger than they look.

- [Why it exists](#why-it-exists)
- [Signing in](#signing-in)
- [Reading your usage](#reading-your-usage)
- [Reading the menu bar](#reading-the-menu-bar)
- [The two charts in the popover](#the-two-charts-in-the-popover)
- [The two histories](#the-two-histories)
- [Notifications](#notifications)
- [Updates](#updates)
- [Privacy](#privacy)
- [Build from source](#build-from-source)
- [Architecture](#architecture)

## Why it exists

Two reasons, one technical and one practical.

**The API changed shape.** `GET /api/oauth/usage` no longer describes limits as fixed fields
(`five_hour`, `seven_day_opus`, …). It returns a generic `limits` array where each entry carries
its own scope:

```json
{"kind":"weekly_scoped","group":"weekly","percent":54,"severity":"normal",
 "resets_at":"2026-09-14T18:00:00.435695+00:00",
 "scope":{"model":{"id":null,"display_name":"Fable"}},"is_active":true}
```

Model-scoped weekly windows now live **only** in that array. An app still reading
`seven_day_opus` gets `null` and shows nothing, even while you sit at 54 % of your weekly Fable
budget. Monkey Claude Usage reads the array, falls back to the legacy fields when it is absent,
and renders whatever windows your plan happens to have. No model list is hard-coded — the
payload also carries inert keys (`tangelo`, `nimbus_quill`, `iguana_necktie`…) which are ignored.

**And most meters watch one account.** If you juggle a personal account and a work one, you were
switching apps, or reading the wrong number.

## Signing in

- **OAuth 2.1 with PKCE** against `claude.ai`, using the public Claude Code client id — the same
  flow the CLI runs, once per account. Tokens refresh on their own.
- **Tokens live in your login Keychain**, one item per account, under the service
  `fr.mymonkey.monkeyclaudeusage.credentials`, keyed by the account's UUID.
- **The account's identity** comes from `GET /api/oauth/profile`. Not `/userinfo`, which answers
  404: the project this one grew out of called that endpoint and fell back to reading
  `~/.claude.json`, which only ever knows whichever account the CLI is signed into — no use at
  all once there are two. The response carries
  `account.uuid`, which is stable and is what deduplication runs on; the e-mail is only a
  fallback and can change. It also carries `organization.rate_limit_tier`
  (`default_claude_max_20x` → **Max 20×**), shown next to the account.
- **Rename accounts** from the tab or from Settings → Accounts. Worth doing: the profile endpoint
  tends to name every account after the same person.
- **Removing an account** deletes its Keychain item and its history file. The Claude account
  itself is untouched.

### The second-account trap

Each account gets its own PKCE flow and its own Keychain item — but the authorization page runs
on your **browser session**. Adding a second account without signing out of Claude first returns
a token for the *same* account. The app notices and refreshes the existing tab instead of
creating a duplicate, so nothing breaks; you have simply not added what you wanted. Sign out
first, or use a private window.

### Why it does not reuse the Claude Code CLI session

Tempting, and deliberately rejected. The CLI keeps its tokens in the `Claude Code-credentials`
Keychain item, which could be read. But the **refresh token would then have two owners**: at the
first renewal, whichever side did not perform it is left holding a dead token. In practice the
app could sign `claude` out, or the reverse, with nothing to connect cause and effect. One OAuth
flow per account, and that is that.

## Reading your usage

- **Endpoint** — `GET https://api.anthropic.com/api/oauth/usage`, with `Authorization: Bearer
  <token>` and `anthropic-beta: oauth-2025-04-20`. It is the endpoint behind the official
  dashboard.
- **Cadence** — every 15 minutes by default, adjustable from 5 to 60, backing off when the API
  asks for it.
- **Dates** — `resets_at` carries **six** fractional digits of a second, which strict ISO-8601
  parsers reject depending on the OS version. Parsing tries with and without the fraction, then
  truncates.

## Reading the menu bar

The icon is drawn as a template image, so macOS handles contrast in light and dark menu bars.

**One account** — rows are labelled: `5h` for the session, `7d` for the week, then one row per
model-scoped window (`Fa` for Fable, `Op` for Opus…).

**Several accounts** — labels give way to one letter per account, and the row order carries the
meaning instead: session first, weekly next, model-scoped last. Rows are shared across accounts
so the bars line up vertically; an account missing a given window gets a dashed bar in its place.
Two accounts whose names start with the same letter — the default, since the profile endpoint
names both after you — fall back to position numbers rather than showing `M` twice. Rename them
in Settings → Accounts to choose your letters.

**A spent window** replaces that account's bars with a short code and the time left on the
**soonest** of its spent windows: `Fa 2d` means Fable is out for two days. The budget is four
characters, which is what the countdown formatter is tested against. The rest of the detail is
one click away in the popover.

The usable height is 18 pt, and bars shrink once an account has more than three windows. Past
five, the menu bar stops being readable — the popover is the better place to look.

## The two charts in the popover

The session window turns over five times a day, the weekly ones once a week. On a shared scale
the slower one is flattened into a line, so they get two different forms:

- **Session** — bars of the quota burned per bucket, with roll-overs marked.
- **Each weekly window** — a level line.

Two subtleties worth knowing when you read them:

- **A drop in level between two polls is a reset**, not negative consumption. It is marked as a
  boundary, and buckets the app never observed are left **blank** rather than smeared with a jump
  that did not happen there.
- **The polling cadence is measured, not read from settings.** Using the current setting would
  retroactively condemn a week polled at another rhythm as a gap. The app takes the *median* of
  observed intervals — robust to the long gap of a sleeping Mac, which an average is not — and
  refuses a bucket finer than that cadence, which would otherwise read as every other bucket
  being idle.

Time buckets are aligned on **local** midnight, not on a multiple of 86 400 Unix seconds, which
is midnight UTC — the same care applies to hourly buckets in half-hour and quarter-hour zones.

## The two histories

The usage endpoint reports a level, never a curve. So there are two sources, and only one of them
can be attributed to an account.

**1. Quota history, per account.** Every successful poll is appended to
`~/Library/Application Support/fr.mymonkey.monkeyclaudeusage/history/<account>.json` and pruned to
your retention window on write. It feeds the session bars and the weekly lines. It therefore
**starts empty and fills in as the app runs**, and it cannot show a period during which the app
was not running — that is a fact, not a bug.

**2. Local activity, with no account.** `~/.claude/projects/**/*.jsonl` — Claude Code's own
transcripts — hold months of real history, available the first time you open the app. That is
what the Activity pane charts: tokens per bucket, stacked by model.

The transcripts carry **no account identifier** (no `account`, no `org`, no e-mail — checked).
That is exactly why the Activity pane sits *outside* the account tabs and says "every account
together": pinning the figure on whichever tab is open would be a lie.

Three details make it fast — all measured on 1.7 GB of transcripts:

- A date formatter allocated per call cost **35 s** over 96 000 lines. One reusable value-typed
  format style instead.
- Accumulating into a buffer and re-slicing it recopies the tail on every line (O(n²)): **50 s**.
  The file is memory-mapped and scanned with `memchr`/`memmem` instead.
- **Every assistant message is written to its transcript twice** — 46 945 duplicates over 48 608
  ids. Without deduplication every number would be doubled. The fingerprint is an FNV-1a hash,
  not `hashValue`, which is re-seeded on each launch and would invalidate the cache.

Net result: about 10 seconds on the first scan, 0.1 second afterwards, since only changed files
are re-read.

## Notifications

At **80 %**, **95 %**, and when a window is spent — including a window locked below 100 %, which
happens and would otherwise pass unnoticed.

## Updates

The app updates itself through [Sparkle](https://sparkle-project.org). It reads the
[appcast](../appcast.xml) served from this repository, and every release is signed with an EdDSA
key whose public half ships inside the app: an update it cannot verify is refused. Turn the check
off in **Settings**, or run it by hand from **Check for Updates…** in the menu bar's right-click
menu.

Installing through Homebrew stays perfectly fine: the cask and the built-in updater install the
same disk image, so `brew upgrade` and the in-app update lead to the same place. Nothing is
reported anywhere — the app asks GitHub for one XML file, and that is the whole of it.

Coming from **0.1.0**? That version shipped before Sparkle and cannot update itself. Run
`brew upgrade --cask monkey-claude-usage` once, or install the newer `.dmg`, and it takes over
from there.

## Privacy

No analytics, no crash reporting, no network call anywhere except `claude.ai`,
`platform.claude.com` and `api.anthropic.com` — plus `raw.githubusercontent.com` and `github.com`
when the updater looks for a new version, which carries nothing about you. Your tokens stay in
your Keychain and your history stays in your Application Support folder.

## Build from source

Requires macOS 14+ and Swift 6.

```bash
git clone https://github.com/my-monkeys/monkey-claude-usage.git
cd monkey-claude-usage
swift test                 # 15 tests: payload parsing, countdowns, history, appcast, translations
./scripts/build-dmg.sh     # → dist/Monkey Claude Usage.app and dist/MonkeyClaudeUsage-<v>.dmg
```

There is no linter: `swift build` is expected to finish without a single warning.

**Liquid Glass is conditional twice over.** `glassEffect` is reached behind
`#available(macOS 26, *)` rather than by raising the deployment target — a menu bar utility is
precisely the kind of thing people keep on an old machine. But `#available` is a runtime test and
the symbol still has to exist at compile time, so it is also wrapped in `#if compiler(>=6.2)`,
which stands in for "built with Xcode 26 or later". A contributor on an older Xcode compiles the
plain-material fallback; **published binaries must be built with Xcode 26+**, or they ship
without glass.

Signing, notarization, the GitHub release and the Homebrew cask are one command, documented in
[`RELEASING.md`](RELEASING.md). The README's hero image is composed from the app's own preview
renders by `scripts/make-hero.py`, so it cannot drift from what the app looks like.

## Architecture

```
Sources/MonkeyClaudeUsageCore/   business logic and I/O — no AppKit, unit-tested
  Model/       UsageLimit, UsagePayload, Activity, Countdown formatting
  Services/    OAuthClient (PKCE), Keychain, AccountMonitor, AppState,
               UsageHistoryStore, LocalActivityStore, notifications
Sources/MonkeyClaudeUsage/       the menu bar app
  App/         NSStatusItem, popover, settings window, Sparkle updater
  UI/          menu bar rendering, popover, charts, settings
```

The split is deliberate: everything that can go wrong with tokens, parsing and dates lives in a
target with no UI, so it can be tested without a screen. A corollary — `OAuthClient` only builds
the authorization URL; opening it is the UI's job. No `NSWorkspace` down there.
