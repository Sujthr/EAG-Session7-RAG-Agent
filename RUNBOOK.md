# RUNBOOK — Session 7 RAG Agent

Everything you need to start, run, and validate the system from scratch.

---

## System Overview

```
Ollama (local)              ← primary LLM + embedding
  ↓ on failure
Gemini cascade              ← 4 models × 5 keys (auto-rotation)
  gemini-2.5-flash-lite-preview-06-17
  gemini-2.5-flash-lite
  gemini-2.0-flash-lite
  gemini-2.5-flash
  ↓ all exhausted
Groq / NVIDIA / Cerebras    ← optional cloud fallbacks
```

Two processes you run:
1. **Gateway V7** — FastAPI on port 8107 (LLM + embed router)
2. **Agent** — runs per query, auto-starts gateway if needed

One optional process:
3. **Streamlit dashboard** — port 8501

---

## Prerequisites

### 1. Install Ollama (if not already done)

Download from https://ollama.com and install. Verify:
```
ollama --version
```

### 2. Pull required models (run from any directory)

```
ollama pull nomic-embed-text
ollama pull qwen3:8b
```

`nomic-embed-text` is the embedding model — **768-dim, fixed for the lifetime of your FAISS index. Never change it after first use.**

Verify both are present:
```
ollama list
```

### 3. Confirm Ollama server is running

Ollama auto-starts on Windows when installed. Check:
```
ollama ps
```

If nothing shows:
```
ollama serve
```

### 4. Install uv (Python package manager)

```
pip install uv
```

---

## One-Time Setup

### Step 1 — Configure Gateway

```
cd "D:\EAG\EAG\Class 23 May\Solution_Submission\Gateway"
copy .env.example .env
```

Open `Gateway\.env` in any editor. Fill in your values:

```env
# ── Gemini keys (minimum: key 1; add more for better rate-limit resilience) ──
GEMINI_API_KEY_1=AIzaSy...your-first-key
GEMINI_API_KEY_2=AIzaSy...your-second-key
GEMINI_API_KEY_3=AIzaSy...your-third-key
GEMINI_API_KEY_4=AIzaSy...your-fourth-key
GEMINI_API_KEY_5=AIzaSy...your-fifth-key

# ── Gemini model cascade (cheapest first, most capable last) ──────────────────
GEMINI_MODEL_ORDER=gemini-2.5-flash-lite-preview-06-17,gemini-2.5-flash-lite,gemini-2.0-flash-lite,gemini-2.5-flash

# ── Ollama ────────────────────────────────────────────────────────────────────
OLLAMA_MODEL=qwen3:8b
OLLAMA_URL=http://localhost:11434
EMBED_OLLAMA_MODEL=nomic-embed-text

# ── (Optional) Leave blank if you don't have these ───────────────────────────
GROQ_API_KEY=
CEREBRAS_API_KEY=
NVIDIA_API_KEY=
OPEN_ROUTER_API_KEY=
GITHUB_ACCESS_TOKEN=
```

Save and close.

### Step 2 — Install Gateway dependencies

```
cd "D:\EAG\EAG\Class 23 May\Solution_Submission\Gateway\llm_gatewayV7"
uv sync
```

### Step 3 — Configure Agent

```
cd "D:\EAG\EAG\Class 23 May\Solution_Submission\S7Code\S7code"
copy .env.example .env
```

Open `S7Code\S7code\.env` and add your Tavily key (optional — DuckDuckGo works without it):

```env
TAVILY_API_KEY=tvly-...your-key
```

### Step 4 — Install Agent dependencies

```
cd "D:\EAG\EAG\Class 23 May\Solution_Submission\S7Code\S7code"
uv sync
```

---

## Starting the System

### Terminal 1 — Start Gateway

```
cd "D:\EAG\EAG\Class 23 May\Solution_Submission\Gateway\llm_gatewayV7"
uv run main.py
```

Expected output:
```
[providers] Gemini cascade active: 4 models × 5 keys
[providers] Gemini model order: gemini-2.5-flash-lite-preview-06-17 → gemini-2.5-flash-lite → gemini-2.0-flash-lite → gemini-2.5-flash
INFO:     Uvicorn running on http://0.0.0.0:8107
```

Keep this terminal open. Gateway dashboard: http://localhost:8107

### Terminal 2 — Run Queries

```
cd "D:\EAG\EAG\Class 23 May\Solution_Submission\S7Code\S7code"
uv run agent7.py "your query here"
```

The agent auto-starts the gateway if Terminal 1 is not running.

### Terminal 2 (alternative) — Streamlit Dashboard

```
cd "D:\EAG\EAG\Class 23 May\Solution_Submission\S7Code\S7code"
streamlit run app.py
```

Opens at http://localhost:8501

---

## Running the 8 Mandatory Queries

Run each from `S7Code\S7code\` with `uv run agent7.py "..."`.

**Query A** — Web fetch + extraction
```
uv run agent7.py "Fetch https://en.wikipedia.org/wiki/Claude_Shannon and extract his birth date, death date, and 3 key contributions to information theory."
```

**Query B** — Multi-step + weather
```
uv run agent7.py "Find 3 family-friendly things to do in Tokyo this weekend. Check Saturday's weather forecast. Pick the most appropriate one given the weather."
```

**Query C — Run 1** — Memory write
```
uv run agent7.py "Mom's birthday is on 15 May 2026. Create reminder files: one 2 weeks before and one on the day itself."
```

**Query C — Run 2** — Cross-run memory recall (run as a separate command after Run 1)
```
uv run agent7.py "When is mom's birthday?"
```
Expected: agent answers from memory without fetching anything.

**Query D** — Web research + synthesis
```
uv run agent7.py "Search for Python asyncio best practices, read the top 3 results, and summarize the agreed-upon advice."
```

**Query E** — Single document index + extract
```
uv run agent7.py "Index the file papers/attention.md and extract 3 key contributions of the Transformer architecture."
```

**Query F — Run 1** — Bulk index
```
uv run agent7.py "Index all .md files under papers/. How many total chunks were created?"
```

**Query F — Run 2** — Semantic recall (run after F-Run1)
```
uv run agent7.py "Across all indexed papers, what do they collectively say about chain-of-thought reasoning?"
```

**Query G** — Semantic retrieval
```
uv run agent7.py "Across all indexed papers, how do they approach the credit assignment problem?"
```

**Query H** — Cross-document synthesis
```
uv run agent7.py "Compare the ReAct and Chain-of-Thought papers on their use of intermediate reasoning steps."
```

---

## Indexing the Full 55-Document Corpus

Run this once before attempting Queries F, G, H, or any custom semantic queries:

```
uv run agent7.py "List all files in the papers directory, then index every .md file you find using index_document."
```

Or via the Streamlit dashboard: **Index Corpus page → "Index All Papers"**

After indexing, check how many chunks were created:
```
uv run agent7.py "How many fact chunks are currently stored in memory?"
```

---

## RAG vs No-RAG Comparison

To demonstrate quality degradation without FAISS:

```
# With FAISS (default)
uv run agent7.py "How do ReAct and Chain-of-Thought papers differ on intermediate reasoning?"

# Without FAISS
set S7_DISABLE_FAISS=1
uv run agent7.py "How do ReAct and Chain-of-Thought papers differ on intermediate reasoning?"
set S7_DISABLE_FAISS=
```

With FAISS: answers cite specific paper details, 2-3 iterations.
Without FAISS: generic response, may attempt to fetch URLs, more iterations.

---

## Verifying Perception Tool-Blindness

```
grep -i "index_document" S7Code\S7code\perception.py
grep -i "search_knowledge" S7Code\S7code\perception.py
grep -i "mcp" S7Code\S7code\perception.py
```

All three must return **zero matches**.

---

## Quick Health Checks

### Is Ollama running?
```
curl http://localhost:11434/api/tags
```

### Is Gateway running?
```
curl http://localhost:8107/v1/status
```

### Which embedding provider is active?
```
curl -X POST http://localhost:8107/v1/embed -H "Content-Type: application/json" -d "{\"text\":\"test\",\"task_type\":\"retrieval_query\"}"
```
Look for `"provider": "ollama"` (local) or `"provider": "gemini"` (cloud fallback).

### How many items in FAISS?
```
uv run agent7.py "How many memory items are currently stored?"
```

---

## Troubleshooting

### Gateway won't start
- Check `Gateway\.env` exists (not just `.env.example`)
- Verify at least `GEMINI_API_KEY_1` or `GEMINI_API_KEY` is set
- Run `uv sync` in `Gateway\llm_gatewayV7\` to ensure dependencies are installed

### "Gateway V7 directory not found"
- The agent looks for the gateway at `Solution_Submission\Gateway\llm_gatewayV7`
- Make sure you haven't moved the folders relative to each other

### Embedding fails / FAISS errors
- Ensure `ollama pull nomic-embed-text` completed successfully
- Run `ollama list` and confirm `nomic-embed-text` appears
- Check gateway logs for `[embedders]` lines on startup

### Gemini 404 on model
- The model name is not available on your account or API tier
- The cascade automatically falls through to the next model — watch for `[gemini_cascade]` log lines
- To skip unavailable models permanently, edit `GEMINI_MODEL_ORDER` in `Gateway\.env`

### FAISS index missing after restart
- This is normal — vector_index.py rebuilds the FAISS index from `state\memory.json` on cold start
- The rebuild is automatic; no action needed

### Query C Run 2 returns wrong answer
- Confirm Run 1 completed and created files in `sandbox\`
- Check `state\memory.json` contains an entry with "15 May 2026" in the descriptor
- If memory.json is empty, Run 1 didn't persist — check for errors in that run's output

---

## File Locations Reference

```
Solution_Submission\
├── RUNBOOK.md                    ← this file
├── README.md                     ← architecture + corpus manifest
├── Gateway\
│   ├── .env                      ← your API keys (create from .env.example)
│   ├── .env.example              ← template
│   └── llm_gatewayV7\
│       └── main.py               ← start with: uv run main.py
└── S7Code\S7code\
    ├── .env                      ← Tavily key (create from .env.example)
    ├── .env.example              ← template
    ├── agent7.py                 ← run with: uv run agent7.py "query"
    ├── app.py                    ← run with: streamlit run app.py
    ├── state\
    │   ├── memory.json           ← persisted memory (survives restarts)
    │   ├── index.faiss           ← FAISS binary index
    │   └── index_ids.json        ← FAISS id map
    └── sandbox\papers\           ← 55 .md corpus files
```
