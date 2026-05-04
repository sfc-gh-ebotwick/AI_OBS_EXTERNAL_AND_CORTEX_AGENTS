# Plan: Align Eval Metrics Between Cortex Agent and External Agent

## Unified Metric Taxonomy (Validated)

| Canonical Name | Cortex Agent Implementation | LangGraph Implementation | Notes |
|---|---|---|---|
| **correctness** | `answer_correctness` (built-in) | `"correctness"` (server-side OOB) | Both built-in. Cortex sees full trace; OOB sees final text. Document delta. |
| **groundedness** | Custom prompt (sentence-split, `{{tool_info}}` as evidence) | `"groundedness"` (server-side OOB) | Evolve custom prompt to match OOB sentence-splitting methodology. Validate `{{tool_info}}` contains search results. |
| **coherence** | Custom prompt (reference-free, output-only) | `"coherence"` (server-side OOB) | Add custom prompt matching OOB criteria ("well-structured, organized"). |
| **logical_consistency** | `logical_consistency` (built-in) | Client-side `Metric(provider.logical_consistency_with_cot_reasons)` | TruLens has this as a client-side feedback function operating on the full trace. Pass as `Metric` object to `compute_metrics()`. |

### Key Implementation Details

**Groundedness custom prompt**: Must use `{{tool_info}}` as evidence source (contains Cortex Search/Analyst tool outputs). Need to validate this actually includes the retrieved contexts by inspecting a sample eval trace first.

**Logical consistency for LangGraph**: Use the TruLens `Metric` class wrapping `provider.logical_consistency_with_cot_reasons` with `Selector(trace_level=True)`. This examines the full LangGraph execution trace for behavioral contradictions, matching what the Cortex built-in does.

---

## Task 1: Validate `{{tool_info}}` Contains Retrieved Contexts

Before writing the groundedness prompt, run a quick inspection to confirm `{{tool_info}}` resolves to search results and analyst outputs:

```sql
-- Inspect what tool_info contains for an existing eval record
SELECT TOOL FROM TABLE(SNOWFLAKE.LOCAL.GET_AI_RECORD_TRACE(
    'CUST_SUPPORT_DEMO', 'AGENTS', 'CORTEX_CUST_SUPPORT_AGENT', 'CORTEX AGENT', '<record_id>'));
```

If `{{tool_info}}` doesn't include actual retrieved text, we'll need to use `{{output}}` and have the judge identify unsupported claims without explicit evidence (less precise).

---

## Task 2: Evolve Groundedness Prompt with Sentence Splitting

Update [support_agent_eval_config.yaml](support_agent_eval_config.yaml) groundedness prompt:

```yaml
- name: groundedness
  score_ranges:
    min_score: [0, 0.33]
    median_score: [0.34, 0.66]
    max_score: [0.67, 1]
  prompt: |
    You are evaluating the groundedness of an AI agent's response.

    STEP 1 - CLAIM DECOMPOSITION:
    Split the agent's response into individual factual claims. Each claim should be
    a single, atomic statement that can be independently verified against the evidence.
    Ignore filler phrases, transitions, and structural language.

    STEP 2 - PER-CLAIM SCORING:
    For each claim, score against the TOOL OUTPUTS below:
    - SUPPORTED (1.0): concrete evidence in tool outputs confirms the claim
    - PARTIALLY SUPPORTED (0.5): evidence is suggestive but not definitive
    - NOT SUPPORTED (0.0): no evidence confirms it, or evidence contradicts it

    STEP 3 - FINAL SCORE:
    Return the average of all per-claim scores as a float between 0 and 1.

    Agent Response:
    {{output}}

    Tool Outputs (retrieved contexts and query results):
    {{tool_info}}

    Guidelines:
    - Numeric claims must match within reasonable rounding
    - Case ID citations are supported if those IDs appear in tool outputs
    - Hedged language ("approximately", "around") scored leniently
    - Statements of uncertainty ("I don't have data for...") always score 1.0
```

---

## Task 3: Add Coherence Custom Metric to Cortex Agent Config

```yaml
- name: coherence
  score_ranges:
    min_score: [0, 0.33]
    median_score: [0.34, 0.66]
    max_score: [0.67, 1]
  prompt: |
    Evaluate the coherence of this agent response.

    Criteria: Is the submission coherent, well-structured, and organized?

    Agent Response:
    {{output}}

    Score on a scale of 0 to 1:
    - 1.0: Well-organized, internally consistent, clear structure
    - 0.5: Partially coherent, minor structural issues or redundancy
    - 0.0: Disorganized, contradictory, or incoherent
```

---

## Task 4: Add Logical Consistency to LangGraph Eval

Update the notebook to pass `logical_consistency` as a client-side `Metric`:

```python
from trulens.core.metric import Metric
from trulens.core.metric.selector import Selector
from trulens.providers.cortex import Cortex  # or appropriate provider

provider = Cortex(snowpark_session=session, model_engine="claude-sonnet-4-6")

logical_consistency_metric = Metric(
    name="logical_consistency",
    feedback_function=provider.logical_consistency_with_cot_reasons,
    parameters={"trace": Selector(trace_level=True)},
)

metric_list = [
    "correctness",        # server-side OOB
    "groundedness",       # server-side OOB  
    "coherence",          # server-side OOB
    logical_consistency_metric,  # client-side, operates on full trace
]

run.compute_metrics(metric_list)
```

---

## Task 5: Run Cortex Agent Eval in DEVREL_ENTERPRISE

1. Ensure `CUST_SUPPORT_DEMO` DB exists (run setup.sql if needed, or just update the YAML + re-run eval)
2. Upload updated `support_agent_eval_config.yaml` to stage
3. Kick off: `CALL EXECUTE_AI_EVALUATION('START', OBJECT_CONSTRUCT('run_name', 'CORTEX_ALIGNED_EVAL_V1'), '@CUST_SUPPORT_DEMO.AGENTS.EVAL_CONFIG_STAGE/support_agent_eval_config.yaml')`
4. Poll status until complete

---

## Task 6: Run LangGraph Eval in DEVREL_ENTERPRISE

1. Execute notebook with updated `compute_metrics` call (includes `logical_consistency_metric`)
2. Use run name: `LANGGRAPH_ALIGNED_EVAL_V1`
3. Wait for completion

---

## Task 7: Validate Metric Equivalence (Real Delta)

Query `AI_OBSERVABILITY_EVENTS` comparing the two aligned runs:

```sql
-- Per-metric comparison
SELECT 
    METRIC,
    AVG(CASE WHEN AGENT = 'CORTEX' THEN SCORE END) AS CORTEX_AVG,
    AVG(CASE WHEN AGENT = 'LANGGRAPH' THEN SCORE END) AS LANGGRAPH_AVG,
    CORTEX_AVG - LANGGRAPH_AVG AS DELTA
FROM aligned_eval_scores
GROUP BY METRIC;
```

Check for:
- Systematic bias in correctness (answer_correctness vs OOB correctness)
- Groundedness alignment (custom sentence-split vs OOB sentence-split)
- Coherence alignment (custom vs OOB)
- Logical consistency comparison (both operating on full trace)

---

## Task 8: Update Analysis SQL and Dashboard

- Normalize metric names in `analyze_eval_data.sql` (`answer_correctness` -> `correctness`)
- Add per-query delta query
- Update dashboard with comparison visuals and win/loss/tie counts

---

## Expected Outcome

4 metrics, both agents, same dataset, same account (DEVREL_ENTERPRISE), inspectable in Snowsight:

| Metric | What it tells you about agent style |
|---|---|
| correctness | Does the native orchestrator or custom ReAct loop produce more factually accurate answers? |
| groundedness | Does the agent stay faithful to what tools returned, or hallucinate beyond evidence? |
| coherence | Surface-level response quality -- is one agent more verbose/cleaner? |
| logical_consistency | Is the agent's reasoning process internally consistent? Native orchestrator vs custom graph. |

Pro/con conclusions become data-driven and methodology-validated.
