# Session 7 RAG Agent — Submission

**FAISS-backed Retrieval-Augmented Generation · 5-key Gemini rotation · Ollama-primary · OpenAI last-resort fallback**

---

## One-Click Run (Windows)

```powershell
cd "D:\EAG\EAG\Class 23 May\Solution_Submission\S7Code\S7code"

# Fill in Gateway/.env with your API keys first (see Environment Variables section)

.\start.ps1   # starts gateway, warms up Ollama, runs all 15 queries
.\stop.ps1    # shuts down the gateway when done
```

`start.ps1` fully automates:
1. Checks Ollama is running (pulls models if missing)
2. Starts LLM Gateway V7 on port 8107 (kills any stale process first)
3. Polls `/v1/routers` until the gateway is healthy (120s timeout)
4. Smoke-tests `/v1/chat` to confirm the full request path works
5. Warms up `qwen3:8b` in VRAM
6. Runs all 15 queries sequentially via `run_all_queries.py`

---

## Manual Quick Start

```bash
# Prerequisites
ollama pull nomic-embed-text   # embedding model
ollama pull qwen3:8b           # primary LLM

# Fill in Gateway/.env (see Environment Variables section)

# Start gateway
cd Gateway/llm_gatewayV7
uv run main.py          # port 8107

# Run a single query (auto-starts gateway if not running)
cd S7Code/S7code
uv run agent7.py "What do the indexed papers say about chain-of-thought reasoning?"

# Run all 15 benchmark queries
uv run python run_all_queries.py

# Launch Streamlit dashboard
streamlit run app.py
```

**Prerequisites:** Python 3.11+, [uv](https://github.com/astral-sh/uv), Ollama

---

## Architecture

```
User Query
    │
    ▼
┌─────────────────────────────────────────────────────────────┐
│  1. MEMORY READ                                              │
│     FAISS vector search (cosine similarity, 768-dim)         │
│     → keyword fallback when vector returns nothing           │
│     Returns ≤12 relevant MemoryItems from prior runs         │
└────────────────────────┬────────────────────────────────────┘
                         │ hits
                         ▼
┌─────────────────────────────────────────────────────────────┐
│  2. PERCEPTION  (TOOL-BLIND layer)                           │
│     Receives: query + history (10 events) + hits (12 max)   │
│     Outputs: structured Goal list (position-based identity)  │
│     NEVER mentions tools, MCP, or index_document            │
└────────────────────────┬────────────────────────────────────┘
                         │ Goal
                         ▼
┌─────────────────────────────────────────────────────────────┐
│  3. DECISION  (one LLM call per iteration)                   │
│     Sees: goal + hits + attached artifact bytes (optional)   │
│     Outputs: ANSWER  ── or ──  TOOL_CALL                     │
└──────────┬──────────────────────┬──────────────────────────┘
           │ answer                │ tool_call
           ▼                      ▼
      [return final]    ┌─────────────────────┐
                        │  4. ACTION  (no LLM) │
                        │  MCP tool dispatch   │
                        │  >4KB → artifact:// │
                        └──────────┬──────────┘
                                   │ result
                                   ▼
                        ┌─────────────────────┐
                        │  MEMORY WRITE        │
                        │  embed + FAISS add   │
                        │  persist to disk     │
                        └─────────────────────┘
```

### Persistence

| File | Purpose |
|------|---------|
| `state/memory.json` | Source of truth — all MemoryItems with embeddings |
| `state/index.faiss` | FAISS binary index (rebuilt from memory.json on cold start) |
| `state/index_ids.json` | Parallel list: FAISS integer position → MemoryItem.id |
| `state/artifacts/` | Content-addressed blob store (SHA-256 keyed) |

---

## Provider Cascade Design

### LLM Path (Offline-first per spec)

```
Ollama qwen3:8b  (local, PRIMARY — no API calls, no quota)
    ↓ on failure / unavailable
Groq  (free tier)
    ↓
Gemini cascade  (5 API keys × 3 models, cheapest-first)
    gemini-2.5-flash-lite  key1→key5
    gemini-2.0-flash-lite  key1→key5
    gemini-2.5-flash       key1→key5
    ↓ all exhausted
NVIDIA  →  GitHub  →  OpenRouter  →  Cerebras
    ↓ all exhausted
OpenAI gpt-4.1-mini  (paid, LAST RESORT)
```

### Embedding Path

```
Ollama nomic-embed-text  (local, 768-dim, PRIMARY)
    ↓ on failure
Gemini gemini-embedding-001  key1 → key2 → ... → key5
```

Both LLM and embedding providers share the same 5 Gemini keys.
Key rotation is automatic and transparent — no code changes needed.

### Environment Variables

```bash
# Gateway/.env
OLLAMA_MODEL=qwen3:8b
OLLAMA_URL=http://localhost:11434
EMBED_OLLAMA_MODEL=nomic-embed-text

GEMINI_API_KEY_1=your-key-1   # primary
GEMINI_API_KEY_2=your-key-2
GEMINI_API_KEY_3=your-key-3
GEMINI_API_KEY_4=your-key-4
GEMINI_API_KEY_5=your-key-5   # last resort
GEMINI_MODEL_ORDER=gemini-2.5-flash-lite,gemini-2.0-flash-lite,gemini-2.5-flash

GROQ_API_KEY=your-groq-key
NVIDIA_API_KEY=your-nvidia-key
GITHUB_ACCESS_TOKEN=your-github-pat
OPEN_ROUTER_API_KEY=your-openrouter-key

# OpenAI — last resort fallback (paid). Leave blank to skip.
OPENAI_API_KEY=sk-proj-...
OPENAI_MODEL=gpt-4.1-mini

GATEWAY_V7_PORT=8107
```

---

## MCP Tools (12)

| Tool | Description |
|------|-------------|
| `web_search` | Tavily (primary) + DuckDuckGo fallback, ≤5 results |
| `fetch_url` | crawl4ai headless Chromium → clean markdown |
| `get_time` | Current time in any IANA timezone |
| `currency_convert` | ISO-3 currency via frankfurter.dev |
| `read_file` | Read sandbox file |
| `list_dir` | List sandbox directory |
| `create_file` | Create file in sandbox |
| `update_file` | Overwrite sandbox file |
| `edit_file` | Find-and-replace in sandbox file |
| `index_document` | Chunk one file → fact records → FAISS index |
| `index_folder` | Bulk-index all matching files in a folder (e.g. all 55 .md papers) |
| `search_knowledge` | Vector search over indexed fact chunks |

---

## Corpus Manifest (55 documents)

All documents are in `S7Code/S7code/sandbox/papers/`.

### Foundational Architectures
| File | Paper |
|------|-------|
| `attention.md` | Attention Is All You Need (Vaswani et al., 2017) |
| `bert.md` | BERT: Pre-training of Deep Bidirectional Transformers (Devlin et al., 2018) |
| `gpt2.md` | Language Models are Unsupervised Multitask Learners / GPT-2 (Radford et al., 2019) |
| `gpt3.md` | Language Models are Few-Shot Learners / GPT-3 (Brown et al., 2020) |
| `t5.md` | Exploring the Limits of Transfer Learning with T5 (Raffel et al., 2019) |

### Efficient Transformers & Alternatives
| File | Paper |
|------|-------|
| `flash_attention.md` | FlashAttention: Fast Memory-Efficient Attention (Dao et al., 2022) |
| `attention_variants.md` | MHA, MQA, GQA, Sparse, Linear Attention survey |
| `sparse_attention.md` | Sparse Transformers + Longformer (Child et al., 2019) |
| `mamba.md` | Mamba: Linear-Time Sequence Modeling (Gu & Dao, 2023) |
| `rwkv.md` | RWKV: Reinventing RNNs for the Transformer Era (Peng et al., 2023) |
| `long_context.md` | Longformer, BigBird, RoPE, ALiBi for long sequences |

### Open Models & Scaling
| File | Paper |
|------|-------|
| `llama.md` | LLaMA: Open and Efficient Foundation Models (Meta, 2023) |
| `llama2.md` | Llama 2: Open Foundation and Fine-Tuned Chat Models (Meta, 2023) |
| `mistral.md` | Mistral 7B (Mistral AI, 2023) |
| `phi.md` | Phi-1/2/3: Small but Capable Models (Microsoft Research) |
| `gemma.md` | Gemma: Open Models Based on Gemini Research (Google DeepMind, 2024) |
| `mixture_of_experts.md` | Mixture of Experts: MoE, Switch Transformer, Mixtral |

### Alignment & Fine-Tuning
| File | Paper |
|------|-------|
| `rlhf.md` | RLHF: Learning from Human Feedback (Stiennon 2020, Ouyang 2022) |
| `constitutional_ai.md` | Constitutional AI: Harmlessness from AI Feedback (Anthropic, 2022) |
| `dpo.md` | Direct Preference Optimization (Rafailov et al., 2023) |
| `instruction_tuning.md` | Instruction Tuning / FLAN / LIMA |
| `lora.md` | LoRA: Low-Rank Adaptation of Large Language Models (Hu et al., 2021) |
| `knowledge_distillation.md` | Knowledge Distillation (Hinton et al., 2015) + DistilBERT |
| `quantization.md` | GPTQ / AWQ / GGUF Quantization |

### Reasoning & Agents
| File | Paper |
|------|-------|
| `react.md` | ReAct: Synergizing Reasoning and Acting in LLMs (Yao et al., 2022) |
| `cot.md` | Chain-of-Thought Prompting (Wei et al., 2022) |
| `self_consistency.md` | Self-Consistency Improves CoT Reasoning (Wang et al., 2022) |
| `tree_of_thoughts.md` | Tree of Thoughts: Deliberate Problem Solving (Yao et al., 2023) |
| `self_refine.md` | Self-Refine: Iterative Refinement with Self-Feedback (Madaan et al., 2023) |
| `reflexion.md` | Reflexion: Language Agents with Verbal RL (Shinn et al., 2023) |
| `toolformer.md` | Toolformer: Language Models Can Use Tools (Schick et al., 2023) |
| `voyager.md` | Voyager: Open-Ended Embodied Agent with LLMs (Wang et al., 2023) |
| `agents_survey.md` | LLM-Powered Autonomous Agents Survey |

### RAG & Retrieval
| File | Paper |
|------|-------|
| `rag.md` | Retrieval-Augmented Generation (Lewis et al., 2020) |
| `hyde.md` | HyDE: Precise Zero-Shot Dense Retrieval (Gao et al., 2022) |
| `agentic_rag.md` | Agentic RAG: IRCoT, Self-RAG, Corrective RAG |
| `hybrid_retrieval.md` | Hybrid Retrieval: BM25 + Dense + RRF |
| `chunking_strategies.md` | Chunking Strategies for RAG |
| `embeddings.md` | Sentence Embeddings: SBERT, E5, GTE |
| `vector_databases.md` | Vector Databases: FAISS, Pinecone, Weaviate, Chroma |
| `faiss.md` | FAISS: Billion-Scale Similarity Search (Johnson et al., 2017) |
| `colbert.md` | ColBERT: Late Interaction Dense Retrieval (Khattab & Zaharia, 2020) |
| `cross_encoder.md` | Cross-Encoders for Reranking in RAG |

### Learning Paradigms
| File | Paper |
|------|-------|
| `in_context_learning.md` | In-Context Learning as Meta-Learning (Dai et al., 2022) |
| `few_shot_prompting.md` | Few-Shot Prompting Strategies |
| `zero_shot.md` | Zero-Shot Learning in NLP (CLIP, GPT, FLAN) |
| `self_supervised.md` | Self-Supervised Learning: MLM, autoregressive, contrastive |
| `contrastive_learning.md` | Contrastive Learning: SimCLR, MoCo, ANCE |

### Specialized Topics
| File | Paper |
|------|-------|
| `clip.md` | CLIP: Learning from Natural Language Supervision (Radford et al., 2021) |
| `multimodal.md` | Multimodal LLMs: Flamingo, BLIP-2, LLaVA, GPT-4V |
| `code_llm.md` | Code LLMs: Codex, CodeLlama, AlphaCode, StarCoder |
| `ppo.md` | Proximal Policy Optimization (Schulman et al., 2017) |
| `speculative_decoding.md` | Speculative Decoding (Leviathan et al., 2022) |
| `memory_augmented.md` | Memory-Augmented Neural Networks: NTM, DNC |
| `credit_assignment.md` | Credit Assignment: BPTT, LSTM, TD, ResNets, Transformers |

---

## Session 7 Mandatory Queries (A–H)

### Query A — Web Fetch + Extraction
```
Fetch https://en.wikipedia.org/wiki/Claude_Shannon and extract his
birth date, death date, and 3 key contributions to information theory.
```
Expected: ~3 iterations (fetch_url → extract → answer)

### Query B — Multi-step + Weather
```
Find 3 family-friendly things to do in Tokyo this weekend. Check
Saturday's weather forecast. Pick the most appropriate one given the weather.
```
Expected: ~8 iterations (web_search × 2 + fetch + weather + synthesize)

### Query C — Persistence Test (2 runs)
**Run 1:**
```
Mom's birthday is on 15 May 2026. Create reminder files:
one 2 weeks before and one on the day itself.
```
Expected: ~4 iterations (remember → create_file × 2 → answer)

**Run 2 (separate invocation — tests cross-run memory):**
```
When is mom's birthday?
```
Expected: ~3 iterations (memory.read returns birthday fact → answer)

### Query D — Web Research
```
Search for "Python asyncio best practices", read the top 3 results,
and summarize the agreed-upon advice.
```
Expected: ~6 iterations (web_search → fetch × 3 → synthesize)

### Query E — Document Indexing
```
Index the file papers/attention.md and extract 3 key contributions
of the Transformer architecture.
```
Expected: ~5 iterations (index_document → search_knowledge → answer)

### Query F — Bulk Indexing + Semantic Recall (2 runs)
**Run 1:**
```
Index all .md files under papers/. How many total chunks were created?
```
Expected: ~11 iterations (list_dir → index_document × 55 → count → answer)

**Run 2:**
```
Across all indexed papers, what do they collectively say about
chain-of-thought reasoning?
```
Expected: ~3 iterations (search_knowledge → synthesize → answer)

### Query G — Semantic Retrieval
```
Across all indexed papers, how do they approach the credit assignment problem?
```
Expected: ~4 iterations (search_knowledge → answer)

### Query H — Cross-Document Synthesis
```
Compare the ReAct and Chain-of-Thought papers on their use of
intermediate reasoning steps.
```
Expected: ~3 iterations (search_knowledge × 2 → compare → answer)

---

## 5 Custom Queries

### Custom Q1 — Semantic Recall: Model Alignment
```
How do the indexed papers approach model alignment with human values?
Compare at least 3 different papers.
```
RAG finds: rlhf.md, constitutional_ai.md, dpo.md, instruction_tuning.md
No-RAG: Generic response without paper-specific detail.

### Custom Q2 — Semantic Recall: Memory Reduction
```
What techniques do the indexed papers describe for reducing memory
requirements during training or inference?
```
RAG finds: lora.md, quantization.md, flash_attention.md, knowledge_distillation.md
No-RAG: General techniques without specific citations.

### Custom Q3 — Cross-document: Reasoning Before Acting
```
Which of the indexed papers discuss the importance of reasoning before
acting? How do they differ in their approach?
```
RAG finds: react.md, cot.md, tree_of_thoughts.md, reflexion.md, self_refine.md

### Custom Q4 — Semantic: Retrieval Quality
```
What strategies do the indexed papers recommend for improving the
quality of information retrieval in AI systems?
```
RAG finds: hybrid_retrieval.md, rag.md, colbert.md, cross_encoder.md, hyde.md

### Custom Q5 — Multi-hop: Credit Assignment Across Time
```
How do modern LLM training techniques solve the credit assignment
problem that plagued earlier neural networks?
```
RAG finds: credit_assignment.md, rlhf.md, ppo.md, dpo.md, cot.md

---

## Perception Tool-Blindness Verification

```bash
# Expected output: 0 matches for all three
grep -i "index_document" S7Code/S7code/perception.py
grep -i "search_knowledge" S7Code/S7code/perception.py
grep -i "mcp" S7Code/S7code/perception.py
```

Perception produces structured Goals that describe *what information is needed*,
never *how to get it*. Decision layer owns all tool-call decisions.

---

## RAG vs No-RAG Comparison

To disable FAISS and test quality degradation:
```bash
# With FAISS (default)
uv run agent7.py "How do ReAct and CoT differ on intermediate reasoning?"

# Without FAISS
S7_DISABLE_FAISS=1 uv run agent7.py "How do ReAct and CoT differ on intermediate reasoning?"
```

Without FAISS:
- Memory.read falls through to keyword search only
- Agent cannot retrieve the specific content from indexed papers
- Answer is generic, cites no specific paper details
- Often requires more iterations as agent tries to fetch URLs

With FAISS:
- Semantic search finds cot.md and react.md chunks immediately
- Agent answers accurately with specific paper details in 2-3 iterations

---

## Installation

```bash
# Prerequisites
ollama pull nomic-embed-text   # embedding model (768-dim, fixed)
ollama pull qwen3:8b           # primary LLM

# Gateway
cd Gateway/llm_gatewayV7
uv sync
cp ../env.example ../.env      # fill in API keys
uv run main.py                 # starts on http://localhost:8107

# Agent
cd S7Code/S7code
uv sync                        # installs faiss-cpu, mcp, streamlit, etc.
cp .env.example .env           # fill in TAVILY_API_KEY

# Run a query
uv run agent7.py "What is the current time in Tokyo?"

# Launch dashboard
streamlit run app.py
```

---

## Directory Structure

```
Solution_Submission/
├── README.md                          ← this file
├── CLAUDE_FINAL_ASSIGNMENT_SPEC.md    ← original assignment spec
├── Axiom — Learning OS- Session7.pdf  ← session notes
│
├── Gateway/
│   ├── .env.example                   ← 5 Gemini keys + all providers
│   └── llm_gatewayV7/
│       ├── main.py        FastAPI app (port 8107)
│       ├── providers.py   GeminiKeyRingProvider (5-key rotation)
│       ├── embedders.py   GeminiKeyRingEmbedder (5-key rotation)
│       ├── router.py      RouterPool (TINY/LARGE/HUGE tiers)
│       ├── schemas.py     Pydantic models
│       ├── cache.py       Gemini prompt cache
│       ├── db.py          SQLite call logging
│       ├── client.py      Python SDK (LLM.chat, LLM.embed)
│       └── static/        Dashboard HTML
│
└── S7Code/S7code/
    ├── start.ps1          One-click: gateway + warmup + all 15 queries
    ├── stop.ps1           Graceful gateway shutdown
    ├── run_all_queries.py Runs all 15 spec queries with per-query logs
    ├── log_setup.py       TeeWriter + QueryLogger + SessionLog
    ├── agent7.py          Main orchestrator (4-layer loop)
    ├── perception.py      Goal orchestrator (tool-blind)
    ├── decision.py        One LLM call per turn
    ├── action.py          Zero-LLM MCP dispatcher
    ├── memory.py          FAISS-backed typed memory service
    ├── vector_index.py    FAISS wrapper (IndexFlatIP)
    ├── mcp_server.py      12 MCP tools (stdio)
    ├── gateway.py         Gateway V7 bridge + auto-start
    ├── artifacts.py       Content-addressed blob store
    ├── schemas.py         Pydantic contracts
    ├── tracer.py          Per-run trace recorder
    ├── app.py             Streamlit dashboard (6 pages)
    ├── .env.example       API key template
    ├── state/             Persisted FAISS + memory (git-ignored)
    └── sandbox/
        └── papers/        55 AI research papers (corpus)
```
