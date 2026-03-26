# Snowflake AI Observability: Unified Agent Tracing & Evaluation

## The Big Idea

Snowflake AI Observability provides a **single, unified framework** for tracing, evaluating, and comparing AI agents — regardless of whether they were built natively with **Cortex Agent** or externally with frameworks like **LangGraph**, **CrewAI**, **AutoGen**, or any OpenTelemetry-compatible system. Every agent's traces, tool calls, and evaluation scores land in the same `SNOWFLAKE.LOCAL.AI_OBSERVABILITY_EVENTS` table, enabling true apples-to-apples comparison.

This project demonstrates that end-to-end by building **two customer support agents** that answer the same questions using the same underlying data — then tracing and evaluating both through AI Observability.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        SNOWFLAKE AI OBSERVABILITY                       │
│                  (SNOWFLAKE.LOCAL.AI_OBSERVABILITY_EVENTS)               │
│                                                                         │
│   Unified event table storing spans, logs, metrics, and eval scores     │
│   for ALL agents — Cortex-native and external alike                     │
│                                                                         │
│   ┌──────────────┐  ┌──────────────┐  ┌───────────┐  ┌──────────────┐  │
│   │    Spans     │  │    Logs      │  │  Metrics  │  │  Eval Scores │  │
│   │ (tool calls, │  │ (debug info, │  │ (latency, │  │ (correctness,│  │
│   │  retrieval,  │  │  errors)     │  │  tokens)  │  │  groundedness│  │
│   │  generation) │  │              │  │           │  │  coherence)  │  │
│   └──────────────┘  └──────────────┘  └───────────┘  └──────────────┘  │
└───────────────────────────┬─────────────────────┬───────────────────────┘
                            │                     │
              ┌─────────────┴──────┐    ┌─────────┴──────────┐
              │   CORTEX AGENT     │    │  EXTERNAL AGENT     │
              │   (SUPPORT_AGENT)  │    │  (LANGGRAPH)        │
              │                    │    │                     │
              │  Built-in Snowflake│    │  Python notebook    │
              │  CREATE AGENT DDL  │    │  + TruLens TruGraph │
              │                    │    │  auto-instrumentation│
              │  Orchestration:    │    │                     │
              │  Cortex-managed    │    │  Orchestration:     │
              │  planning + routing│    │  LangGraph ReAct    │
              │                    │    │  agent loop         │
              └────────┬───────────┘    └────────┬────────────┘
                       │                         │
              ┌────────┴─────────────────────────┴────────┐
              │           SHARED TOOL LAYER                │
              │                                            │
              │  ┌────────────────┐  ┌──────────────────┐  │
              │  │ Cortex Search  │  │ Cortex Analyst   │  │
              │  │ (Unstructured) │  │ (Structured)     │  │
              │  │                │  │                  │  │
              │  │ Case details,  │  │ Semantic View:   │  │
              │  │ issue text,    │  │ CSAT, resolution │  │
              │  │ resolutions    │  │ times, trends,   │  │
              │  │                │  │ rep performance   │  │
              │  └────────────────┘  └──────────────────┘  │
              │                                            │
              └────────────────────┬───────────────────────┘
                                   │
                       ┌───────────┴───────────┐
                       │   SUPPORT DATA TABLES  │
                       │                        │
                       │  SUPPORT_CASES          │
                       │  CASE_METRICS           │
                       │  DAILY_SUPPORT_METRICS  │
                       │  REP_PERFORMANCE        │
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

## Key Takeaways

1. **One table to rule them all.** `SNOWFLAKE.LOCAL.AI_OBSERVABILITY_EVENTS` captures traces from Cortex Agents automatically and from external agents via TruLens/OpenTelemetry — no separate infrastructure needed.

2. **Same eval framework, different agents.** Both agents are evaluated using Snowflake's built-in evaluation capabilities (`EXECUTE_AI_EVALUATION` for Cortex, `TruGraph.add_run().compute_metrics()` for LangGraph), and results land in the same table with the same schema.

3. **SQL-native analysis.** Because everything is in a Snowflake table, you can compare agents using standard SQL — no notebooks, no external dashboards, no data exports. Join, aggregate, window, and visualize directly in Snowsight.

4. **Build anywhere, observe everywhere.** The architecture proves that teams can choose the best framework for their use case (Cortex Agent for simplicity, LangGraph for custom orchestration) without sacrificing observability or the ability to make data-driven decisions about which agent performs better.
