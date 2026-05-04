# Snowflake AI Observability: Unified Agent Tracing & Evaluation

## The Big Idea

Snowflake AI Observability provides a **single, unified framework** for tracing, evaluating, and comparing AI agents — regardless of whether they were built natively with **Cortex Agent** or externally with frameworks like **LangGraph**, **CrewAI**, **AutoGen**, or any OpenTelemetry-compatible system. Every agent's traces, tool calls, and evaluation scores land in the same `SNOWFLAKE.LOCAL.AI_OBSERVABILITY_EVENTS` table, enabling true apples-to-apples comparison.

This project demonstrates that end-to-end by building **two customer support agents** that answer the same questions using the same underlying data — then tracing and evaluating both through AI Observability.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        SNOWFLAKE AI OBSERVABILITY                       │
│                  (SNOWFLAKE.LOCAL.AI_OBSERVABILITY_EVENTS)              │
│                                                                         │
│   Unified event table storing spans, logs, metrics, and eval scores     │
│   for ALL agents — Cortex-native and external alike                     │
│                                                                         │
│   ┌──────────────┐  ┌──────────────┐  ┌───────────┐  ┌──────────────┐   │
│   │    Spans     │  │    Logs      │  │  Metrics  │  │  Eval Scores │   │
│   │ (tool calls, │  │ (debug info, │  │ (latency, │  │ (correctness,│   │
│   │  retrieval,  │  │  errors)     │  │  tokens)  │  │  groundedness│   │
│   │  generation) │  │              │  │           │  │  coherence)  │   │
│   └──────────────┘  └──────────────┘  └───────────┘  └──────────────┘   │
└───────────────────────────┬─────────────────────┬───────────────────────┘
                            │                     │
              ┌─────────────┴──────┐    ┌─────────┴───────────┐
              │   CORTEX AGENT     │    │  EXTERNAL AGENT     │
              │   (SUPPORT_AGENT)  │    │  (LANGGRAPH)        │
              │                    │    │                     │
              │  Built-in Snowflake│    │  Python notebook    │
              │  CREATE AGENT DDL  │    │  + TruLens TruGraph │
              │                    │    │ auto-instrumentation│
              │  Orchestration:    │    │                     │
              │  Cortex-managed    │    │  Orchestration:     │
              │  planning + routing│    │  LangGraph ReAct    │
              │                    │    │  agent loop         │
              └────────┬───────────┘    └────────┬────────────┘
                       │                         │
              ┌────────┴─────────────────────────┴─────────┐
              │            TOOL LAYER                      │
              │                                            │
              │  ┌────────────────┐  ┌──────────────────┐  │
              │  │ Cortex Search  │  │ Cortex Analyst   │  │
              │  │ (Unstructured) │  │ (Structured)     │  │
              │  │                │  │                  │  │
              │  │ Case details,  │  │ Semantic View:   │  │
              │  │ issue text,    │  │ CSAT, resolution │  │
              │  │ resolutions    │  │ times, trends,   │  │
              │  │                │  │ rep performance  │  │
              │  └────────────────┘  └──────────────────┘  │
              │                                            │
              └────────────────────┬───────────────────────┘
                                   │
                       ┌───────────┴────────────┐
                       │   SUPPORT DATA TABLES  │
                       │                        │
                       │  SUPPORT_CASES         │
                       │  CASE_METRICS          │
                       │  DAILY_SUPPORT_METRICS │
                       │  REP_PERFORMANCE       │
                       └────────────────────────┘
```

### How Traces Flow

| Agent | How traces are captured | Where they land |
|-------|----------------------|-----------------|
| **SUPPORT_AGENT** (Cortex Agent) | Automatic — Snowflake instruments all planning steps, tool calls, and responses natively | `AI_OBSERVABILITY_EVENTS` with `object.type = 'CORTEX AGENT'` |
| **CUSTOMER_SUPPORT_AGENT_LANGGRAPH** (LangGraph) | TruLens `TruGraph` auto-instruments the LangGraph execution graph and exports via the Snowflake connector | `AI_OBSERVABILITY_EVENTS` with `object.type = 'EXTERNAL AGENT'` |

Both agents' data shares the **same schema** — same `RECORD_ATTRIBUTES` keys for inputs, outputs, spans, and eval scores — making cross-agent comparison straightforward with standard SQL.

---

## What's in This Project

| File | Purpose |
|------|---------|
| `setup.sql` | End-to-end setup: creates the database, tables, semantic view, Cortex Search service, Cortex Agent, evaluation dataset, and kicks off the Cortex Agent eval run |
| `langgraph_trulens_demo.ipynb` | Snowflake Notebook that builds a LangGraph ReAct agent using the same Cortex Search + Cortex Analyst tools, instruments it with TruLens `TruGraph`, and runs batch evaluation |
| `analyze_eval_data.sql` | 10 comparison queries against `AI_OBSERVABILITY_EVENTS` — performance scorecards, latency percentiles, eval score breakdowns, tool usage, side-by-side response comparison, and an executive summary |
| `support_agent_eval_config.yaml` | YAML config for the Cortex Agent evaluation run defining metrics (answer_correctness, logical_consistency, groundedness) |
| `generate_data.py` | Python script that generates synthetic customer support data (cases, metrics, rep performance) |
| `data/` | CSV files with the generated support data loaded into Snowflake during setup |

---

## Getting Started

### Prerequisites

- Snowflake account with Cortex features enabled
- `CORTEX_USER` database role
- A warehouse (default: `COMPUTE_WH`)
- For the LangGraph notebook: Python packages `langchain-snowflake`, `langgraph`, `trulens-core`, `trulens-apps-langgraph`, `trulens-connectors-snowflake`

### Step 1: Setup Infrastructure

Run `setup.sql` in a Snowflake worksheet. This will:
1. Create the `CUST_SUPPORT_DEMO` database, `AGENTS` schema, and `EVAL_ROLE`
2. Clone the GitHub repo and load CSV data into tables
3. Create a **Semantic View** (`SUPPORT_ANALYTICS`) for Cortex Analyst
4. Create a **Cortex Search Service** (`CASE_SEARCH_SERVICE`) over support case text
5. Create the **Cortex Agent** (`SUPPORT_AGENT`) wired to both tools
6. Create an evaluation dataset and kick off the Cortex Agent eval run

### Step 2: Run the LangGraph Agent + Evaluation

Open `langgraph_trulens_demo.ipynb` in a Snowflake Notebook. The notebook:
1. Defines the same two tools (Cortex Search + Cortex Analyst) as LangChain tools
2. Builds a LangGraph ReAct agent with `ChatSnowflake` as the LLM
3. Wraps the agent with TruLens `TruGraph` for automatic trace capture
4. Runs the same evaluation queries in batch, computing coherence, correctness, and groundedness

### Step 3: Compare Agents

Run the queries in `analyze_eval_data.sql` to compare both agents across:
- **Eval scores** — per-metric averages, distributions, and score buckets
- **Latency** — end-to-end P50/P90/P95, span-level breakdowns
- **Tool usage** — Cortex Search vs. Cortex Analyst duration and frequency
- **Responses** — side-by-side output comparison on the same user queries

---

## Evaluation Results: Head-to-Head Comparison

Both agents evaluated on the same 25 queries using aligned metrics (runs: `CORTEX_EVAL`, `LANGGRAPH_EVAL`):

| Metric | Cortex Agent | LangGraph |
|--------|:-----------:|:---------:|
| correctness | **0.907** | 0.861 |
| groundedness | **0.699** | 0.575 |
| coherence | 0.891 | **1.000** |
| logical_consistency | **0.947** | 0.853 |
| avg latency | 26.1s | **13.0s** |
| p50 latency | 23.4s | **12.7s** |
| p90 latency | 46.6s | **16.3s** |

### Where Cortex Agent Wins: Groundedness, Correctness & Logical Consistency

The Cortex Agent's native orchestrator produces responses that are more factually grounded, more correct against ground truth, and more logically consistent in their reasoning. The common thread: its responses stay disciplined — presenting data without embellishment, following through on what it planned to do, and giving complete answers.

**Example: "What is the overall average CSAT score across all cases?"**

| | Cortex Agent | LangGraph |
|---|---|---|
| | correctness: **1.0**, logical_consistency: **1.0**, groundedness: **1.0** | correctness: 0.67, logical_consistency: 0.67, groundedness: 0.13 |
| Response | "The overall average CSAT score is **3.82 out of 5.0**. This is based on case data spanning December 1, 2025 – February 28, 2026." | "The overall average CSAT score is **3.82 / 5.0**. This suggests moderate customer satisfaction — there's meaningful room for improvement, particularly in identifying low-scoring cases or categories dragging the average down. Would you like a breakdown?" |
| Why Cortex wins on all 3 | States the fact, cites the data range, done. Every claim is verifiable, the answer matches ground truth completely, and the plan (query metric → report it) is executed cleanly. | Same correct number, but the correctness judge penalizes the incomplete answer (no data range, no case count). Logical consistency drops because the agent's response doesn't follow through on presenting data — it pivots to unsolicited suggestions. Groundedness tanks because 3/4 sentences are interpretive. |

**Example: "What is the escalation rate for each priority level?"**

| | Cortex Agent | LangGraph |
|---|---|---|
| | logical_consistency: **1.0** | logical_consistency: 0.67 |
| Response | "Critical: 20.0%, High: 18.75%, Medium: 0.0%, Low: 0.0%. Key Takeaways: Critical and High priority cases are the only ones being escalated..." | "🔴 Critical: 20.0%, 🟠 High: 18.8%, 🟡 Medium: 0.0%, 🟢 Low: 0.0%. Key Takeaways: Escalations are exclusively concentrated in Critical and High priority cases... Critical cases have the highest escalation rate at 20% (5 out of 25 cases)..." |
| Why Cortex wins | Clean execution: query the data, present the table, summarize the pattern. Plan matches output. | The "5 out of 25 cases" detail requires a computation (25 × 0.20 = 5) that the agent derived rather than retrieved — introducing a reasoning step that the judge evaluates for consistency. The emoji decoration and extra inference steps create more surface area for plan-execution drift. |

**Example: "How many cases were there for each issue category?"**

| | Cortex Agent | LangGraph |
|---|---|---|
| | logical_consistency: **1.0** | logical_consistency: 0.67 |
| Response | Presents table, states "Login/Authentication is the top issue category with 32 cases, Billing has the fewest at 19. Total across all 8 categories is 200 cases." Then generates a chart. | Presents table, then "Key highlights: Login/Authentication is the top category with 32 cases (16%), suggesting authentication issues are the most common pain point..." |
| Why Cortex wins | States facts from the data and follows through with a visualization — exactly what was planned. | Adds "suggesting authentication issues are the most common pain point" — an interpretive leap beyond the data. The judge flags this as inconsistent with a data-retrieval task: the agent planned to retrieve data but then injected unsolicited analysis. |

**Pattern:** The Cortex Agent's native orchestrator is disciplined: it queries, presents, and stops. This produces higher scores across all three quality metrics because there's less interpretive commentary to be wrong about (groundedness), the complete data is always presented (correctness), and the execution matches the plan without tangents (logical consistency).

### Where LangGraph Wins: Latency & Execution Consistency

LangGraph achieves 2-3x faster response times and higher logical consistency on search-heavy queries. Its ReAct loop makes one tool decision at a time with a single LLM call per step, while the Cortex Agent's orchestrator adds planning overhead. The simpler loop also means less room for plan-execution drift.

**Example: "Find cases related to SSO or SAML integration failures"**

| | Cortex Agent (groundedness: 0.45) | LangGraph (groundedness: 0.88) |
|---|---|---|
| Response | Dumps 57 raw cases as a JSON table with claim "This issue pattern appears across multiple cases" — but many listed cases aren't actually SSO/SAML related (over-retrieval from Cortex Analyst). | Starts with "Note: Case IDs were not returned" (honest about limitations), then groups by issue type with occurrence counts matching search results. |
| Why | Over-claims breadth ("57 cases") by combining Cortex Search with a broad Cortex Analyst query. Makes ungrounded generalizations about pattern prevalence. | Acknowledges data limitations upfront (scores 1.0 as uncertainty statement), then sticks to what the search actually returned. |

**Example: "Search for cases involving data synchronization or export failures"**

| | Cortex Agent (logical_consistency: 0.0) | LangGraph (logical_consistency: 0.67) |
|---|---|---|
| Why LangGraph wins | Cortex Agent made 4 search calls plus a SQL query but its multi-step orchestration plan was inconsistent with the final output — the judge flagged contradictions between planning steps and what was actually presented. | LangGraph's single-step ReAct loop keeps each action tightly coupled to the next — less room for plan-execution drift. |

**Pattern:** The Cortex Agent's multi-step planning orchestrator can over-retrieve and introduce inconsistencies between its plan and execution on complex search queries. LangGraph's simpler ReAct loop — one LLM call, one tool call, repeat — produces more internally consistent traces for search-heavy tasks, at the cost of less sophisticated multi-tool coordination.

---

## Key Takeaways

1. **Unified evaluation is the only way to compare agent frameworks.** Without aligned metrics, shared datasets, and a single observability table, you're comparing apples to oranges. This project proves that Snowflake AI Observability makes true cross-framework comparison possible — both Cortex Agent and LangGraph traces land in `SNOWFLAKE.LOCAL.AI_OBSERVABILITY_EVENTS` with the same schema, enabling SQL-native side-by-side analysis.

2. **Metrics must be aligned to be meaningful.** This project uses aligned evaluation metrics across both agents — same groundedness methodology (sentence-splitting, binary NLI scoring), same correctness criteria, same coherence definition. The custom metric prompts in `support_agent_eval_config.yaml` are calibrated to match the server-side OOB scorers used by TruLens, so the comparison reflects real agent behavior differences rather than methodology artifacts.

3. **The comparison reveals real architectural tradeoffs — not just scores.** Cortex Agent's native orchestrator produces more grounded, data-first responses but at 2-3x the latency. LangGraph's ReAct loop is faster and more conversational but adds ungrounded interpretive commentary. These are genuine design tradeoffs that only surface through unified evaluation.

4. **Build anywhere, observe everywhere.** Teams can choose the best framework for their use case without sacrificing the ability to make data-driven decisions. The evaluation infrastructure is framework-agnostic — what matters is that both agents are measured with the same ruler.
