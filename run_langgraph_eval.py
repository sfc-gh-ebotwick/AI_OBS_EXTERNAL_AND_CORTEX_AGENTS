import os
import json
import time
import requests
import warnings
import pandas as pd

warnings.filterwarnings("ignore")

os.environ["SNOWFLAKE_WAREHOUSE"] = "COMPUTE_WH"
os.environ["SNOWFLAKE_DATABASE"] = "CUST_SUPPORT_DEMO"
os.environ["SNOWFLAKE_SCHEMA"] = "AGENTS"

from langchain_snowflake import create_session_from_env
session = create_session_from_env()
print(f"Connected: {session.get_current_database()}.{session.get_current_schema()}")

from langchain_core.tools import tool
from langchain_snowflake import SnowflakeCortexSearchRetriever
from trulens.core.otel.instrument import instrument
from trulens.otel.semconv.trace import SpanAttributes

CORTEX_SEARCH_SERVICE = "CUST_SUPPORT_DEMO.AGENTS.CASE_SEARCH_SERVICE"

retriever = SnowflakeCortexSearchRetriever(
    session=session,
    schema="CUST_SUPPORT_DEMO.AGENTS",
    service_name=CORTEX_SEARCH_SERVICE,
    k=10,
    auto_format_for_rag=True,
    content_field="ISSUE_SUMMARY",
    join_separator="\n\n",
    fallback_to_page_content=True,
)

@tool
@instrument(
    span_type=SpanAttributes.SpanType.RETRIEVAL,
    attributes={
        SpanAttributes.RETRIEVAL.QUERY_TEXT: "query",
        SpanAttributes.RETRIEVAL.RETRIEVED_CONTEXTS: "return",
    },
)
def search_support_cases(query: str) -> list:
    """ Search specific case details, issue descriptions, and resolution summaries by topic or keyword.
        Returns CASE_ID, CUSTOMER_ID, PRODUCT, ISSUE_CATEGORY, PRIORITY, STATUS, REP_NAME as attributes.
        Always cite CASE_ID values in responses. NOT for aggregate metrics or trends"""
    docs = retriever.invoke(query)
    return [doc.page_content for doc in docs]

print("Cortex Search tool defined.")

@tool
@instrument(
    span_type=SpanAttributes.SpanType.RETRIEVAL,
    attributes={
        SpanAttributes.RETRIEVAL.QUERY_TEXT: "question",
        SpanAttributes.RETRIEVAL.RETRIEVED_CONTEXTS: "return",
    },
)
def query_support_analytics(question: str) -> list:
    """ Quantitative support metrics: case counts, CSAT scores, resolution times, first response
        times, escalation rates, rep performance, daily/weekly trends, breakdowns by product/category/priority/rep.
        Use for aggregation, filtering, or numerical analysis. NOT for case descriptions or resolutions."""
    host = session.connection.host
    token = session.connection.rest.token

    resp = requests.post(
        url=f"https://{host}/api/v2/cortex/analyst/message",
        json={
            "messages": [
                {"role": "user", "content": [{"type": "text", "text": question}]}
            ],
            "semantic_view": "CUST_SUPPORT_DEMO.AGENTS.SUPPORT_ANALYTICS",
        },
        headers={
            "Authorization": f'Snowflake Token="{token}"',
            "Content-Type": "application/json",
        },
    )
    resp.raise_for_status()
    data = resp.json()

    result_parts = []
    msg = data.get("message") or {}
    for block in msg.get("content", []):
        if block.get("type") == "text":
            result_parts.append(block["text"])
        elif block.get("type") == "sql":
            result_parts.append(f"SQL: {block['statement']}")
            try:
                sql_results = session.sql(block["statement"]).collect()
                result_parts.append(json.dumps([row.as_dict() for row in sql_results[:20]], default=str))
            except Exception as e:
                result_parts.append(f"SQL execution error: {e}")
        elif block.get("type") == "result_table":
            result_parts.append(json.dumps(block.get("data", [])[:20], default=str))
    return result_parts

print("Cortex Analyst tool defined.")

from langchain_snowflake import ChatSnowflake
from langgraph.prebuilt import create_react_agent

llm = ChatSnowflake(
    session=session,
    model="claude-sonnet-4-6",
    temperature=0,
    max_tokens=2048,
)

SYSTEM_PROMPT = """
instructions:
  response: >
    Concise customer support analytics assistant. Be data-driven, use appropriate number formatting.
    ALWAYS cite case IDs (e.g., CASE-00016) from search results. For rankings/comparisons, show the
    COMPLETE list. Group duplicate search results by issue type with counts and representative case IDs.
    Note data limitations when results appear incomplete.
  orchestration: >
    Tool Selection: query_support_analytics for metrics, trends, counts, averages, comparisons.
    search_support_cases for specific case details, issue descriptions, resolutions, or topic searches.
    Use BOTH search and analytics tools when a question needs metrics AND case examples.

    search_support_cases: ALWAYS include CASE_ID from results. Group duplicate results by issue type
    with representative case IDs rather than repeating identical entries.

    query_support_analytics: For trends, request the FULL date range (data covers Dec 2025-Feb 2026).
    For rankings, return ALL items with values, not just the top result."""

tools = [search_support_cases, query_support_analytics]

graph = create_react_agent(
    llm,
    tools=tools,
    prompt=SYSTEM_PROMPT,
)

print(f"LangGraph agent compiled. Nodes: {list(graph.get_graph().nodes.keys())}")

# --- TruLens Setup ---
from trulens.apps.langgraph import TruGraph
from trulens.connectors.snowflake import SnowflakeConnector

tru_snowflake_connector = SnowflakeConnector(snowpark_session=session)

APP_NAME = "LANGGRAPH_CUSTOMER_SUPPORT_AGENT"
APP_VERSION = "ALIGNED_EVAL_V3"

try:
    session.sql(f'DROP EXTERNAL AGENT {APP_NAME}').collect()
except Exception:
    pass

tru_graph = TruGraph(
    graph,
    app_name=APP_NAME,
    app_version=APP_VERSION,
    connector=tru_snowflake_connector,
    main_method=graph.invoke
)

print(f"TruGraph registered: {APP_NAME} / {APP_VERSION}")

# --- Load Eval Data ---
queries_df = session.table("CUST_SUPPORT_DEMO.AGENTS.EVAL_DATA").to_pandas()
queries_df['query_json'] = queries_df['INPUT_QUERY'].apply(lambda x: {"messages": [("user", x)]})
queries_df['ground_truth_string'] = queries_df['GROUND_TRUTH_DATA'].apply(lambda x: json.loads(x).get('ground_truth_output'))
print(f"Evaluation dataset: {len(queries_df)} queries")

# --- Run Config ---
from trulens.core.run import Run, RunConfig

run_config = RunConfig(
    run_name="LANGGRAPH_ALIGNED_EVAL_V3",
    description="Aligned evaluation V3 - correctness, groundedness, coherence, logical_consistency",
    dataset_name="TEST_QUERIES_DF",
    source_type="DATAFRAME",
    label="LANGGRAPH_ALIGNED_V3",
    dataset_spec={
        "RECORD_ROOT.INPUT": "query_json",
        "RECORD_ROOT.GROUND_TRUTH_OUTPUT": "ground_truth_string",
    },
)

# --- Execute Agent Run ---
print("Starting agent invocations...")
run = tru_graph.add_run(run_config=run_config)
run.start(input_df=queries_df)
print("Agent invocations complete.")

# --- Compute Metrics ---
import logging
logging.basicConfig(level=logging.INFO)

from trulens.core import Metric, Selector
from trulens.providers.cortex import Cortex
from trulens.otel.semconv.trace import SpanAttributes

provider = Cortex(snowpark_session=session, model_engine="claude-sonnet-4-6")

logical_consistency_metric = Metric(
    name="logical_consistency",
    implementation=provider.logical_consistency_with_cot_reasons,
    metric_type="logical_consistency",
    description="Evaluates logical consistency of agent reasoning across the full execution trace",
    enable_trace_compression=True,
    selectors={
        "trace": Selector(trace_level=True),
    },
)

metric_list = [
    "correctness",
    "groundedness",
    "coherence",
    logical_consistency_metric,
]

# Wait for invocation to complete before computing metrics
print("Waiting for invocation to complete...")
while True:
    status = str(run.get_status())
    if "INVOCATION_COMPLETED" in status or "COMPLETED" in status or "PARTIALLY" in status or "CANCELLED" in status or "FAILED" in status:
        break
    print(f"  Invocation status: {status}")
    time.sleep(5)
print(f"Invocation done. Status: {run.get_status()}")

print("Starting metrics computation...")
try:
    result = run.compute_metrics(metric_list)
    print(f"compute_metrics returned: {result}")
except Exception as e:
    print(f"ERROR in compute_metrics: {e}")
    import traceback
    traceback.print_exc()

print("Polling for completion...")
max_polls = 200
for i in range(max_polls):
    status = str(run.get_status())
    if "COMPLETED" in status or "PARTIALLY_COMPLETED" in status or "CANCELLED" in status or "FAILED" in status:
        if "INVOCATION_COMPLETED" not in status:
            break
    print(f"  [{i}] Status: {status}")
    time.sleep(5)

print(f"Evaluation complete. Final status: {run.get_status()}")
print(f"\nRun Name: {run_config.run_name}")
print(f"App Name: {APP_NAME}")
print(f"App Version: {APP_VERSION}")
print("View results in Snowsight: AI & ML > Evaluations")
