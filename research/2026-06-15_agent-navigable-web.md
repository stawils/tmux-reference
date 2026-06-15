# Research: Agent-Navigable Web (2025-2026)

**Date:** 2026-06-15
**Context:** Making the tmux-reference site genuinely agent-navigable and self-documenting from the agent's perspective.

## TL;DR

Agent-navigability is a **stack of discovery surfaces**, not one file. Different agent types look in different places. A genuinely agent-friendly site exposes multiple surfaces because you can't predict which agent type will visit. All of them work on static hosting (GitHub Pages) — no server required.

## The three layers

### 1. Discovery — how agents find what a site offers

| Surface | For which agent | Format |
|---|---|---|
| `/llms.txt` | Text-based agents (Claude, ChatGPT) | Markdown doc (llmstxt.org standard, Jeremy Howard 2024) |
| `/.well-known/agent-card.json` | API-calling agents (MCP clients, A2A) | JSON (Google A2A protocol) |
| `<script type="application/agent+json">` | DOM-reading agents (Codex, Playwright bots) | In-page JSON marker |
| `<link rel="alternate" type="application/json">` | Any agent reading HTML | Points to machine-readable versions |
| Visual badges / high-contrast targets | CUA screenshot agents (Operator, Claude CUA) | Pixels |

### 2. Negotiation — how agents request the right format

- `Accept: text/markdown` content negotiation (80% token reduction vs HTML)
- `content-signal` header (publisher permissions: ai-train, search, ai-input)
- `<link rel="alternate">` for JSON alternatives
- Requires a server for true content negotiation; static sites approximate via `<link>` tags

### 3. Execution — how agents act

- **URL params** — simplest, universal (what tmux-reference already uses)
- **WebMCP** — `navigator.modelContext.provideContext({tools:[...]})` — exposes JS functions as in-browser agent tools (W3C proposal, Chrome 149 origin trials June 2026)
- **A2A** — task lifecycle (submitted/working/input-needed/completed)
- **agent:// URI protocol** — IETF draft for addressing/invoking agents

## Key standards tracked

- **llms.txt** (llmstxt.org) — H1 title, blockquote summary, H2 sections linking key pages. `/llms-full.txt` = all pages concatenated.
- **A2A Agent Card** (a2a-protocol.org, Google) — `/.well-known/agent-card.json`, JSON "business card" describing capabilities, auth, skills
- **WebMCP** (webmachinelearning.github.io/webmcp) — `navigator.modelContext`, declarative tools in manifest.json + `window.agent` toolcall events
- **Agent-Web Protocol Stack** thesis (rtrvr.ai/rover) — maps the full landscape: Discovery / Negotiation / Execution / Identity / Monetization / Protection

## The three agent types (from Rover thesis)

1. **CUA (Computer-Using Agent)** — operates through screenshots (Claude CUA, Operator). Needs high-contrast visual targets.
2. **API-calling agents** — MCP clients, function-calling LLMs. Want JSON tool schemas.
3. **Text-based agents** — read markdown. Claude, ChatGPT web. Want `/llms.txt`.

## What this means for tmux-reference

Currently exposes: `/llms.txt` (text), `/options.json` (structured), URL params (execution).

To be genuinely agent-navigable, ADD:
1. `/.well-known/agent-card.json` — A2A surface for API-calling agents
2. `<script type="application/agent+json">` + `<link rel="alternate">` in HTML — DOM-reader surface + pointers
3. `navigator.modelContext.provideContext()` — WebMCP tools (compose, list_options, apply_preset). Feature-detected, zero-cost degradation.
4. Rewrite `llms.txt` as task-oriented operating manual

## Sources

- [Agent-Web Protocol Stack thesis](https://www.rtrvr.ai/rover/blog/agent-web-protocol-stack) — Rover, Apr 2026
- [llms.txt](https://llmstxt.org/) — Jeremy Howard, Sep 2024
- [A2A Protocol / Agent Discovery](https://a2a-protocol.org/latest/topics/agent-discovery/) — Google A2A
- [WebMCP API Proposal](https://webmachinelearning.github.io/webmcp/docs/proposal.html) — Walderman/Nolan (MSFT), Bokan/Sagar (Google), Aug 2025
- [llms.txt: Making Your Project Discoverable](https://www.agentpatterns.ai/standards/llms-txt/)
- [WebMCP entering Chrome 149 origin trials](https://www.infoq.com/news/2026/06/webmcp-web-agent-standard-chrome/) — InfoQ, Jun 2026
