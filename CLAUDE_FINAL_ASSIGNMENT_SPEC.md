# CLAUDE_FINAL_ASSIGNMENT_SPEC.md

# EAG V3 SESSION 7 - FINAL IMPLEMENTATION SPECIFICATION

## OBJECTIVE

Build a Session-7 compliant Retrieval Augmented Generation (RAG) system that:

- Passes Queries A-H exactly as defined in Session 7
- Indexes 50+ documents
- Uses FAISS for vector retrieval
- Demonstrates semantic recall
- Demonstrates cross-document synthesis
- Demonstrates persistence across runs
- Demonstrates failure when retrieval is disabled
- Preserves Perception tool-blindness
- Runs primarily offline
- Supports Gemini fallback providers via multiple API keys

---

# TECHNOLOGY STACK

## Primary (Offline)

- Python 3.11+
- Ollama
- nomic-embed-text
- qwen3:8b
- FAISS
- Streamlit
- Pydantic

## Free Internet Sources

- requests
- beautifulsoup4
- duckduckgo-search
- Open-Meteo

## Optional Fallback

Gemini API

Used ONLY when:

- Ollama unavailable
- Ollama timeout
- Ollama embedding failure
- Ollama generation failure

---

# GEMINI FAILOVER DESIGN

Environment file:

```env
GEMINI_API_KEY_1=xxxxx
GEMINI_API_KEY_2=xxxxx
GEMINI_API_KEY_3=xxxxx
GEMINI_API_KEY_4=xxxxx
GEMINI_API_KEY_5=xxxxx
```

Implement provider chain:

1. Ollama (Primary)
2. Gemini Key 1
3. Gemini Key 2
4. Gemini Key 3
5. Gemini Key 4
6. Gemini Key 5

If provider fails:

- log failure
- rotate to next provider
- continue execution

Never stop indexing because of one provider failure.

---

# RECOMMENDED CORPUS

60+ AI Research Papers

Topics:

- RAG
- ReAct
- Chain of Thought
- Tree of Thoughts
- LoRA
- QLoRA
- RLHF
- DPO
- Constitutional AI
- Multi-Agent Systems
- Tool Use
- Agent Memory
- Prompt Engineering
- AI Evaluation

Store under:

corpus/

---

# ARCHITECTURE

User
→ Perception
→ Decision
→ Action
→ Memory
→ FAISS
→ Decision
→ Response

Perception MUST remain tool-blind.

---

# PERCEPTION RULES

Allowed:

- understand intent
- decompose goals
- track completion

Forbidden:

- tool selection
- tool names
- MCP references

Validation:

grep -Ri "index_document" perception.py
grep -Ri "search_knowledge" perception.py
grep -Ri "index_folder" perception.py

Expected result:

No matches.

---

# DECISION RULES

Decision owns:

- tool selection
- retrieval strategy
- final answer strategy

Decision receives:

- goals
- memory hits
- history
- tool catalog
- tool docstrings

---

# MEMORY DESIGN

Files:

state/memory.json
state/index.faiss
state/index_ids.json

Memory JSON = source of truth

FAISS = retrieval accelerator

If FAISS missing:

rebuild from memory.json

---

# EMBEDDINGS

Primary:

nomic-embed-text

Dimension:

768

Fallback:

Gemini embedding model

Normalize all vectors before insertion.

Normalize all vectors before search.

---

# CHUNKING

Chunk Size:

400 words

Overlap:

80 words

Metadata:

- source
- chunk_number
- chunk_text
- indexed_at

---

# MCP TOOLS

index_document(path)

search_knowledge(query, k)

index_folder(folder_path)

Tool usage guidance belongs in docstrings.

Never teach tool usage inside Perception.

---

# SESSION 7 QUERIES (MANDATORY)

## Query A

Fetch https://en.wikipedia.org/wiki/Claude_Shannon and tell me his birth date, death date, and three key contributions to information theory.

Expected Iterations: 3

---

## Query B

Find 3 family-friendly things to do in Tokyo this weekend.

Check Saturday's weather forecast there and tell me which one is most appropriate.

Expected Iterations: 8

---

## Query C - Run 1

My mom's birthday is 15 May 2026.

Remember that and create reminders for two weeks before and on the day.

Expected Iterations: 4

### Query C - Run 2

When is mom's birthday?

Expected Iterations: 3

---

## Query D

Search for "Python asyncio best practices", read the top 3 results, and give me a short numbered list of the advice they agree on.

Expected Iterations: 6

---

## Query E

Index the file papers/attention.md and tell me what the three key contributions of the Transformer architecture are according to this paper.

Expected Iterations: 5

---

## Query F - Run 1

Index every .md file under papers/.

Confirm how many chunks were indexed in total.

Expected Iterations: 11

### Query F - Run 2

Across the papers I have indexed, what do they say about chain-of-thought reasoning?

Expected Iterations: 3

---

## Query G

Across these papers, how do they handle the credit assignment problem?

Expected Iterations: 4

Must demonstrate semantic retrieval.

---

## Query H

Compare how the ReAct paper and the Chain-of-Thought paper differ in their treatment of intermediate reasoning.

Expected Iterations: 3

Must demonstrate cross-document synthesis.

---

# FIVE CUSTOM QUERIES

Q1:
How do these papers achieve model alignment?

Q2:
How do these papers reduce memory requirements during training?

Q3:
Compare ReAct and AutoGPT task execution.

Q4:
Which papers discuss reasoning before acting?

Q5:
What strategies improve retrieval quality?

At least two must be semantic recall examples.

---

# NO-RAG VALIDATION

For every custom query:

Run with FAISS.

Save answer.

Disable FAISS.

Run again.

Save answer.

Demonstrate quality degradation.

---

# STREAMLIT PAGES

Home

Index

Search

Diagnostics

Settings

Provider Status

---

# README MUST CONTAIN

Architecture Diagram

Corpus Manifest

Session Query Traces A-H

Custom Query Traces

RAG vs No-RAG Comparison

Installation Guide

Gemini Failover Design

Video Link

---

# FINAL ACCEPTANCE CRITERIA

[ ] 50+ documents indexed
[ ] Queries A-H passed
[ ] 5 custom queries completed
[ ] 2 semantic recall examples
[ ] Persistence proven
[ ] No-RAG comparison proven
[ ] Perception tool-blindness proven
[ ] README complete
[ ] Video complete
[ ] Local execution supported
[ ] Gemini failover implemented
