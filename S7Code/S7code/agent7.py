"""agent7.py — Session 7 agent orchestrator.

The loop layout is unchanged from Session 6. The only thing that changed
underneath is the Memory service: writes now compute an embedding via the
gateway's V7 embed endpoint and append to a FAISS index; reads use vector
similarity first and fall back to keyword search when the vector path is
empty. Two new MCP tools, index_document and search_knowledge, surface
the same machinery to the model so the agent can ingest external
documents on demand.

The four typed layers:

    memory.read -> perception.observe -> decision.next_step ->
    action.execute -> memory.record_outcome

Perception is the only layer that maintains goal state across iterations.
Memory is a typed service (read / write). The artifact store carries raw
bytes; Decision sees them only when Perception attached them to the
current goal.

Run from this folder:
    uv run agent7.py "What is the current time in Tokyo and Bangalore?"
"""

from __future__ import annotations

import asyncio
import json
import os
import sys
import uuid
from pathlib import Path

# Windows pipes default to charmap (cp1252); force UTF-8 so Unicode content
# (e.g. Wikipedia pages with → glyphs) doesn't raise UnicodeEncodeError.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

import action
import artifacts
import decision
import memory
import perception
from gateway import ensure_gateway
from schemas import Goal
from tracer import RunTracer

MCP_SERVER = Path(__file__).parent / "mcp_server.py"
MAX_ITERATIONS = 20


def _mcp_tools_for_decision(tools) -> list[dict]:
    """Convert MCP tool descriptors into the shape the gateway expects."""
    return [
        {
            "name": t.name,
            "description": t.description or "",
            "input_schema": t.inputSchema or {"type": "object", "properties": {}},
        }
        for t in tools
    ]


async def run(query: str) -> str:
    ensure_gateway()
    run_id = uuid.uuid4().hex[:8]
    tracer = RunTracer(run_id=run_id, query=query)
    print(f"\n{'═' * 78}")
    print(f"run {run_id}  ─  query: {query}")
    print(f"{'═' * 78}")

    # Persist the user query as a fact so it survives future runs. Use
    # add_fact (no LLM classifier) — user queries are always facts and the
    # LLM classify call adds no value while costing an extra API round-trip.
    try:
        memory.add_fact(
            descriptor=query[:200],
            value={"raw": query},
            source="user_query",
            run_id=run_id,
        )
    except Exception as e:
        print(f"[memory.record_query] skipped: {e}")

    _env = {**os.environ, "PYTHONIOENCODING": "utf-8"}
    server_params = StdioServerParameters(command=sys.executable, args=[str(MCP_SERVER)], env=_env)
    history: list[dict] = []
    prior_goals: list[Goal] = []
    final_answer: str = ""

    async with stdio_client(server_params) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()
            mcp_tools = (await session.list_tools()).tools
            tools_for_decision = _mcp_tools_for_decision(mcp_tools)
            print(f"[mcp] loaded {len(mcp_tools)} tools: {[t.name for t in mcp_tools]}")

            for it in range(1, MAX_ITERATIONS + 1):
                print(f"\n─── iter {it} ─────────────────────────────────────────────")

                # 1. MEMORY READ
                hits = memory.read(query, history)
                print(f"[memory.read]   {len(hits)} hits")

                # 2. PERCEPTION
                try:
                    obs = perception.observe(query, hits, history, prior_goals, run_id)
                except Exception as e:
                    print(f"[perception] LLM call failed ({e!r}), skipping iteration")
                    continue
                prior_goals = obs.goals
                for g in obs.goals:
                    flag = "✓" if g.done else "○"
                    attach = f"  attach={g.attach_artifact_id}" if g.attach_artifact_id else ""
                    print(f"[perception]    {flag} {g.id} — {g.text}{attach}")

                if obs.all_done:
                    print(f"\n[done] all {len(obs.goals)} goals satisfied")
                    break

                goal = obs.next_unfinished()
                if goal is None:
                    print(f"\n[done] no unfinished goal — stopping")
                    break

                # Perception decided whether to attach an artifact.
                attached: list[tuple[str, bytes]] = []
                if goal.attach_artifact_id and artifacts.exists(goal.attach_artifact_id):
                    blob = artifacts.get_bytes(goal.attach_artifact_id)
                    attached.append((goal.attach_artifact_id, blob))
                    print(f"[attach]        {goal.attach_artifact_id} ({len(blob)} bytes)")

                # 3. DECISION
                try:
                    out = decision.next_step(goal, hits, attached, history, tools_for_decision)
                except Exception as e:
                    print(f"[decision] LLM call failed ({e!r}), skipping iteration")
                    continue

                if out.is_answer:
                    print(f"[decision]      ANSWER: {out.answer[:200]}{'...' if len(out.answer) > 200 else ''}")
                    tracer.record_iter(
                        iteration=it,
                        memory_hits=len(hits),
                        goals=obs.goals,
                        decision_type="answer",
                        answer_text=out.answer,
                    )
                    history.append({
                        "iter": it,
                        "kind": "answer",
                        "goal_id": goal.id,
                        "text": out.answer,
                    })
                    final_answer = out.answer
                    # Mark this goal done locally so the next iteration's
                    # Perception call is skipped when no work remains.
                    prior_goals = [
                        g.model_copy(update={"done": True}) if g.id == goal.id else g
                        for g in prior_goals
                    ]
                    if all(g.done for g in prior_goals):
                        break
                    continue

                # 4. ACTION
                tc = out.tool_call
                print(f"[decision]      TOOL_CALL: {tc.name}({json.dumps(tc.arguments)[:120]})")
                result_text, art_id = await action.execute(session, tc)
                preview = result_text[:200].replace("\n", " ")
                print(f"[action]        → {preview}{'...' if len(result_text) > 200 else ''}"
                      + (f"   +{art_id}" if art_id else ""))

                tracer.record_iter(
                    iteration=it,
                    memory_hits=len(hits),
                    goals=obs.goals,
                    decision_type="tool_call",
                    tool_name=tc.name,
                    tool_args=tc.arguments,
                    action_result=result_text,
                    artifact_id=art_id,
                )

                # 5. MEMORY WRITE (zero-LLM for tool outcomes)
                memory.record_outcome(
                    tool_call=tc,
                    result_text=result_text,
                    artifact_id=art_id,
                    run_id=run_id,
                    goal_id=goal.id,
                )
                history.append({
                    "iter": it,
                    "kind": "action",
                    "goal_id": goal.id,
                    "tool": tc.name,
                    "arguments": tc.arguments,
                    "result_descriptor": result_text[:300],
                    "artifact_id": art_id,
                })

    tracer.finish(final_answer)
    trace_file = tracer.save()
    print(f"\n{'═' * 78}")
    print(f"FINAL: {final_answer}")
    print(f"[trace] appended to {trace_file}")
    print(f"{'═' * 78}\n")
    return final_answer


def main() -> None:
    query = " ".join(sys.argv[1:]) or "What is the current time in Asia/Tokyo and Asia/Kolkata? Tell me the difference in hours."
    asyncio.run(run(query))


if __name__ == "__main__":
    main()
