import streamlit as st
from snowflake.snowpark.context import get_active_session
import pandas as pd
import json
import altair as alt

st.set_page_config(page_title="Agent Observability Dashboard", layout="wide")

session = get_active_session()

CORTEX_AGENT = ("CUST_SUPPORT_DEMO", "AGENTS", "CORTEX_CUST_SUPPORT_AGENT", "CORTEX AGENT")
LANGGRAPH_AGENT = ("CUST_SUPPORT_DEMO", "AGENTS", "LANGGRAPH_CUSTOMER_SUPPORT_AGENT", "EXTERNAL AGENT")

AGENT_LABELS = {
    "CORTEX_CUST_SUPPORT_AGENT": "Cortex Agent",
    "LANGGRAPH_CUSTOMER_SUPPORT_AGENT": "LangGraph Agent",
}

BOTH_AGENTS_SQL = f"""(
    SELECT * FROM TABLE(SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS(
        '{CORTEX_AGENT[0]}', '{CORTEX_AGENT[1]}', '{CORTEX_AGENT[2]}', '{CORTEX_AGENT[3]}'))
    UNION ALL
    SELECT * FROM TABLE(SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS(
        '{LANGGRAPH_AGENT[0]}', '{LANGGRAPH_AGENT[1]}', '{LANGGRAPH_AGENT[2]}', '{LANGGRAPH_AGENT[3]}'))
)"""

CORTEX_EVENTS_SQL = f"""TABLE(SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS(
    '{CORTEX_AGENT[0]}', '{CORTEX_AGENT[1]}', '{CORTEX_AGENT[2]}', '{CORTEX_AGENT[3]}'))"""

LANGGRAPH_EVENTS_SQL = f"""TABLE(SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS(
    '{LANGGRAPH_AGENT[0]}', '{LANGGRAPH_AGENT[1]}', '{LANGGRAPH_AGENT[2]}', '{LANGGRAPH_AGENT[3]}'))"""

METRIC_NORMALIZE = "REPLACE(RECORD_ATTRIBUTES:\"ai.observability.eval.metric_name\"::STRING, 'answer_correctness', 'correctness')"


@st.cache_data(ttl=300)
def run_query(sql):
    return session.sql(sql).to_pandas()


def parse_scores(val):
    if val is None or (isinstance(val, float) and pd.isna(val)):
        return {}
    if isinstance(val, str):
        try:
            return json.loads(val)
        except Exception:
            return {}
    return val


def label_col(df):
    df["LABEL"] = df["AGENT_NAME"].map(AGENT_LABELS)
    return df


st.title("AI Agent Observability Dashboard")
st.caption("Comparing **Cortex Agent** vs **LangGraph Agent** via Snowflake AI Observability")

exec_df = run_query(f"""
    WITH roots AS (
        SELECT
            RECORD_ATTRIBUTES:"snow.ai.observability.object.name"::STRING AS AGENT_NAME,
            RECORD_ATTRIBUTES:"ai.observability.record_root.input"::STRING AS USER_QUERY,
            RECORD_ATTRIBUTES:"ai.observability.record_root.output"::STRING AS AGENT_OUTPUT,
            RECORD_ATTRIBUTES:"ai.observability.record_id"::STRING AS RECORD_ID,
            TRACE:"trace_id"::STRING AS TRACE_ID,
            TIMESTAMPDIFF('millisecond', START_TIMESTAMP, TIMESTAMP) AS LATENCY_MS,
            ROW_NUMBER() OVER (PARTITION BY
                RECORD_ATTRIBUTES:"snow.ai.observability.object.name"::STRING,
                RECORD_ATTRIBUTES:"ai.observability.record_root.input"::STRING
                ORDER BY TIMESTAMP DESC) AS RN
        FROM {BOTH_AGENTS_SQL}
        WHERE RECORD_ATTRIBUTES:"ai.observability.span_type"::STRING = 'record_root'
    ),
    evals AS (
        SELECT
            RECORD_ATTRIBUTES:"snow.ai.observability.object.name"::STRING AS AGENT_NAME,
            RECORD_ATTRIBUTES:"ai.observability.eval.target_record_id"::STRING AS TARGET_RECORD_ID,
            {METRIC_NORMALIZE} AS METRIC,
            ROUND(RECORD_ATTRIBUTES:"ai.observability.eval_root.score"::FLOAT, 2)::NUMBER(5,2) AS SCORE
        FROM {BOTH_AGENTS_SQL}
        WHERE RECORD_ATTRIBUTES:"ai.observability.span_type"::STRING = 'eval_root'
          AND RECORD_ATTRIBUTES:"ai.observability.eval_root.score" IS NOT NULL
    ),
    query_evals AS (
        SELECT r.AGENT_NAME, r.USER_QUERY, e.METRIC,
               ROUND(AVG(e.SCORE), 2)::NUMBER(5,2) AS AVG_SCORE
        FROM roots r
        INNER JOIN evals e ON r.AGENT_NAME = e.AGENT_NAME AND r.RECORD_ID = e.TARGET_RECORD_ID
        GROUP BY 1, 2, 3
    ),
    query_scores AS (
        SELECT AGENT_NAME, USER_QUERY, OBJECT_AGG(METRIC, AVG_SCORE::VARIANT) AS SCORES
        FROM query_evals GROUP BY 1, 2
    ),
    query_latency AS (
        SELECT AGENT_NAME, USER_QUERY, AGENT_OUTPUT, TRACE_ID,
               ROUND(AVG(LATENCY_MS) OVER (PARTITION BY AGENT_NAME, USER_QUERY), 0) AS AVG_LATENCY_MS, RN
        FROM roots
    ),
    combined AS (
        SELECT l.AGENT_NAME, l.USER_QUERY, l.AGENT_OUTPUT, l.AVG_LATENCY_MS, l.TRACE_ID, s.SCORES
        FROM query_latency l
        LEFT JOIN query_scores s ON l.AGENT_NAME = s.AGENT_NAME AND l.USER_QUERY = s.USER_QUERY
        WHERE l.RN = 1
    ),
    cortex AS (SELECT * FROM combined WHERE AGENT_NAME = '{CORTEX_AGENT[2]}'),
    langgraph AS (SELECT * FROM combined WHERE AGENT_NAME = '{LANGGRAPH_AGENT[2]}')
    SELECT
        COALESCE(c.USER_QUERY, l.USER_QUERY) AS USER_QUERY,
        c.AVG_LATENCY_MS AS CORTEX_LATENCY_MS,
        l.AVG_LATENCY_MS AS LANGGRAPH_LATENCY_MS,
        c.SCORES AS CORTEX_EVAL_SCORES,
        l.SCORES AS LANGGRAPH_EVAL_SCORES,
        c.AGENT_OUTPUT AS CORTEX_OUTPUT,
        l.AGENT_OUTPUT AS LANGGRAPH_OUTPUT,
        c.TRACE_ID AS CORTEX_TRACE_ID,
        l.TRACE_ID AS LANGGRAPH_TRACE_ID
    FROM cortex c
    FULL OUTER JOIN langgraph l ON c.USER_QUERY = l.USER_QUERY
    WHERE c.SCORES IS NOT NULL OR l.SCORES IS NOT NULL
    ORDER BY COALESCE(c.USER_QUERY, l.USER_QUERY)
""")

tab_summary, tab_eval, tab_latency, tab_responses = st.tabs([
    "Executive Summary",
    "Eval Comparison",
    "Latency & Spans",
    "Responses & Traces"
])

with tab_summary:
    scorecard_df = run_query(f"""
        WITH eval_scores AS (
            SELECT
                RECORD_ATTRIBUTES:"snow.ai.observability.object.name"::STRING AS AGENT_NAME,
                RECORD_ATTRIBUTES:"ai.observability.eval_root.score"::FLOAT AS SCORE
            FROM {BOTH_AGENTS_SQL}
            WHERE RECORD_ATTRIBUTES:"ai.observability.span_type"::STRING = 'eval_root'
              AND RECORD_ATTRIBUTES:"ai.observability.eval_root.score" IS NOT NULL
        ),
        latencies AS (
            SELECT
                RECORD_ATTRIBUTES:"snow.ai.observability.object.name"::STRING AS AGENT_NAME,
                TIMESTAMPDIFF('millisecond', START_TIMESTAMP, TIMESTAMP) AS DURATION_MS
            FROM {BOTH_AGENTS_SQL}
            WHERE RECORD_ATTRIBUTES:"ai.observability.span_type"::STRING = 'record_root'
        )
        SELECT
            COALESCE(e.AGENT_NAME, l.AGENT_NAME) AS AGENT_NAME,
            ROUND(AVG(e.SCORE), 3) AS AVG_EVAL_SCORE,
            ROUND(MIN(e.SCORE), 3) AS MIN_EVAL_SCORE,
            ROUND(AVG(l.DURATION_MS), 0) AS AVG_LATENCY_MS,
            ROUND(MEDIAN(l.DURATION_MS), 0) AS MEDIAN_LATENCY_MS,
            COUNT(DISTINCT l.DURATION_MS) AS NUM_INVOCATIONS
        FROM eval_scores e
        FULL OUTER JOIN latencies l ON e.AGENT_NAME = l.AGENT_NAME
        GROUP BY 1 ORDER BY 1
    """)

    cols = st.columns(2)
    for i, row in scorecard_df.iterrows():
        label = AGENT_LABELS.get(row["AGENT_NAME"], row["AGENT_NAME"])
        with cols[i]:
            st.subheader(label)
            m1, m2, m3, m4 = st.columns(4)
            m1.metric("Avg Score", f"{row['AVG_EVAL_SCORE']:.2f}")
            m2.metric("Min Score", f"{row['MIN_EVAL_SCORE']:.2f}")
            m3.metric("Avg Latency", f"{row['AVG_LATENCY_MS']:.0f} ms")
            m4.metric("Invocations", f"{row['NUM_INVOCATIONS']:.0f}")

    st.markdown("##### Per-Query Breakdown")
    summary_rows = []
    for _, row in exec_df.iterrows():
        c_scores = parse_scores(row.get("CORTEX_EVAL_SCORES"))
        l_scores = parse_scores(row.get("LANGGRAPH_EVAL_SCORES"))
        summary_rows.append({
            "Query": row["USER_QUERY"],
            "Cortex ms": row.get("CORTEX_LATENCY_MS"),
            "LangGraph ms": row.get("LANGGRAPH_LATENCY_MS"),
            **{f"C: {k}": v for k, v in c_scores.items()},
            **{f"LG: {k}": v for k, v in l_scores.items()},
        })
    st.dataframe(pd.DataFrame(summary_rows), use_container_width=True, height=400)

with tab_eval:
    eval_detail_df = label_col(run_query(f"""
        SELECT
            RECORD_ATTRIBUTES:"snow.ai.observability.object.name"::STRING AS AGENT_NAME,
            {METRIC_NORMALIZE} AS METRIC,
            ROUND(AVG(RECORD_ATTRIBUTES:"ai.observability.eval_root.score"::FLOAT), 3) AS AVG_SCORE,
            ROUND(MEDIAN(RECORD_ATTRIBUTES:"ai.observability.eval_root.score"::FLOAT), 3) AS MEDIAN_SCORE,
            ROUND(MIN(RECORD_ATTRIBUTES:"ai.observability.eval_root.score"::FLOAT), 3) AS MIN_SCORE,
            COUNT(*) AS NUM_EVALS,
            ROUND(SUM(CASE WHEN RECORD_ATTRIBUTES:"ai.observability.eval_root.score"::FLOAT = 1 THEN 1 ELSE 0 END)
                  / COUNT(*)::FLOAT * 100, 1) AS PERFECT_PCT
        FROM {BOTH_AGENTS_SQL}
        WHERE RECORD_ATTRIBUTES:"ai.observability.span_type"::STRING = 'eval_root'
          AND RECORD_ATTRIBUTES:"ai.observability.eval_root.score" IS NOT NULL
        GROUP BY 1, 2 ORDER BY 1, 2
    """))

    left, right = st.columns(2)
    with left:
        st.markdown("##### Average Score by Metric")
        bar = alt.Chart(eval_detail_df).mark_bar(cornerRadiusTopLeft=3, cornerRadiusTopRight=3).encode(
            x=alt.X("METRIC:N", title=None, axis=alt.Axis(labelAngle=-30)),
            y=alt.Y("AVG_SCORE:Q", title="Avg Score", scale=alt.Scale(domain=[0, 1.05])),
            color=alt.Color("LABEL:N", title="Agent", scale=alt.Scale(scheme="tableau10")),
            xOffset="LABEL:N",
            tooltip=["LABEL", "METRIC", "AVG_SCORE", "MEDIAN_SCORE", "MIN_SCORE", "PERFECT_PCT"]
        ).properties(height=300)
        st.altair_chart(bar, use_container_width=True)

    with right:
        st.markdown("##### Perfect Score Rate (%)")
        perf_bar = alt.Chart(eval_detail_df).mark_bar(cornerRadiusTopLeft=3, cornerRadiusTopRight=3).encode(
            x=alt.X("METRIC:N", title=None, axis=alt.Axis(labelAngle=-30)),
            y=alt.Y("PERFECT_PCT:Q", title="% Perfect (1.0)", scale=alt.Scale(domain=[0, 105])),
            color=alt.Color("LABEL:N", title="Agent", scale=alt.Scale(scheme="tableau10")),
            xOffset="LABEL:N",
            tooltip=["LABEL", "METRIC", "PERFECT_PCT", "NUM_EVALS"]
        ).properties(height=300)
        st.altair_chart(perf_bar, use_container_width=True)

    st.markdown("##### Score Distribution Heatmap")
    bucket_df = label_col(run_query(f"""
        SELECT
            RECORD_ATTRIBUTES:"snow.ai.observability.object.name"::STRING AS AGENT_NAME,
            {METRIC_NORMALIZE} AS METRIC,
            CASE
                WHEN RECORD_ATTRIBUTES:"ai.observability.eval_root.score"::FLOAT = 1.0 THEN '1.0 Perfect'
                WHEN RECORD_ATTRIBUTES:"ai.observability.eval_root.score"::FLOAT >= 0.8 THEN '0.8 - 0.99'
                WHEN RECORD_ATTRIBUTES:"ai.observability.eval_root.score"::FLOAT >= 0.6 THEN '0.6 - 0.79'
                WHEN RECORD_ATTRIBUTES:"ai.observability.eval_root.score"::FLOAT >= 0.4 THEN '0.4 - 0.59'
                ELSE '< 0.4'
            END AS SCORE_BUCKET,
            COUNT(*) AS CNT
        FROM {BOTH_AGENTS_SQL}
        WHERE RECORD_ATTRIBUTES:"ai.observability.span_type"::STRING = 'eval_root'
          AND RECORD_ATTRIBUTES:"ai.observability.eval_root.score" IS NOT NULL
        GROUP BY 1, 2, 3
    """))
    bucket_df["FACET"] = bucket_df["LABEL"] + " / " + bucket_df["METRIC"]
    bucket_order = ["1.0 Perfect", "0.8 - 0.99", "0.6 - 0.79", "0.4 - 0.59", "< 0.4"]
    heatmap = alt.Chart(bucket_df).mark_rect(cornerRadius=2).encode(
        x=alt.X("SCORE_BUCKET:N", title=None, sort=bucket_order),
        y=alt.Y("FACET:N", title=None),
        color=alt.Color("CNT:Q", title="Count", scale=alt.Scale(scheme="blues")),
        tooltip=["LABEL", "METRIC", "SCORE_BUCKET", "CNT"]
    ).properties(height=250)
    text = heatmap.mark_text(fontSize=11).encode(text="CNT:Q", color=alt.value("black"))
    st.altair_chart(heatmap + text, use_container_width=True)

    st.markdown("##### Metric Details")
    st.dataframe(
        eval_detail_df[["LABEL", "METRIC", "AVG_SCORE", "MEDIAN_SCORE", "MIN_SCORE", "NUM_EVALS", "PERFECT_PCT"]].rename(
            columns={"LABEL": "Agent", "PERFECT_PCT": "Perfect %"}
        ), use_container_width=True
    )

with tab_latency:
    latency_df = label_col(run_query(f"""
        SELECT
            RECORD_ATTRIBUTES:"snow.ai.observability.object.name"::STRING AS AGENT_NAME,
            RECORD_ATTRIBUTES:"ai.observability.record_root.input"::STRING AS USER_QUERY,
            TIMESTAMPDIFF('millisecond', START_TIMESTAMP, TIMESTAMP) AS LATENCY_MS
        FROM {BOTH_AGENTS_SQL}
        WHERE RECORD_ATTRIBUTES:"ai.observability.span_type"::STRING = 'record_root'
    """))

    left, right = st.columns(2)
    with left:
        st.markdown("##### Latency Distribution")
        box = alt.Chart(latency_df).mark_boxplot(extent="min-max", size=40).encode(
            x=alt.X("LABEL:N", title=None),
            y=alt.Y("LATENCY_MS:Q", title="Latency (ms)"),
            color=alt.Color("LABEL:N", title="Agent", scale=alt.Scale(scheme="tableau10")),
        ).properties(height=300)
        st.altair_chart(box, use_container_width=True)

    with right:
        st.markdown("##### Per-Query Latency Comparison")
        latency_pivot = latency_df.groupby(["USER_QUERY", "LABEL"])["LATENCY_MS"].mean().reset_index()
        scatter = alt.Chart(latency_pivot).mark_circle(size=80).encode(
            x=alt.X("USER_QUERY:N", title=None, axis=alt.Axis(labelAngle=-35, labelLimit=200)),
            y=alt.Y("LATENCY_MS:Q", title="Avg Latency (ms)"),
            color=alt.Color("LABEL:N", title="Agent", scale=alt.Scale(scheme="tableau10")),
            tooltip=["USER_QUERY", "LABEL", "LATENCY_MS"]
        ).properties(height=300)
        st.altair_chart(scatter, use_container_width=True)

    st.markdown("##### Span-Level Duration Breakdown")
    span_df = label_col(run_query(f"""
        SELECT
            RECORD_ATTRIBUTES:"snow.ai.observability.object.name"::STRING AS AGENT_NAME,
            RECORD_ATTRIBUTES:"ai.observability.span_type"::STRING AS SPAN_TYPE,
            COUNT(*) AS SPAN_COUNT,
            ROUND(AVG(TIMESTAMPDIFF('millisecond', START_TIMESTAMP, TIMESTAMP)), 0) AS AVG_DURATION_MS,
            ROUND(MAX(TIMESTAMPDIFF('millisecond', START_TIMESTAMP, TIMESTAMP)), 0) AS MAX_DURATION_MS
        FROM {BOTH_AGENTS_SQL}
        WHERE RECORD_TYPE = 'SPAN'
          AND RECORD_ATTRIBUTES:"ai.observability.span_type"::STRING IS NOT NULL
          AND RECORD_ATTRIBUTES:"ai.observability.span_type"::STRING NOT IN ('eval', 'eval_root')
        GROUP BY 1, 2 ORDER BY 1, AVG_DURATION_MS DESC
    """))

    cl, cr = st.columns(2)
    for col, agent_label in zip([cl, cr], ["Cortex Agent", "LangGraph Agent"]):
        with col:
            st.markdown(f"**{agent_label}**")
            agent_spans = span_df[span_df["LABEL"] == agent_label].sort_values("AVG_DURATION_MS", ascending=True)
            hbar = alt.Chart(agent_spans).mark_bar(cornerRadiusTopRight=3, cornerRadiusBottomRight=3).encode(
                x=alt.X("AVG_DURATION_MS:Q", title="Avg Duration (ms)"),
                y=alt.Y("SPAN_TYPE:N", title=None, sort="-x"),
                color=alt.value("#4c78a8" if agent_label == "Cortex Agent" else "#f58518"),
                tooltip=["SPAN_TYPE", "SPAN_COUNT", "AVG_DURATION_MS", "MAX_DURATION_MS"]
            ).properties(height=max(len(agent_spans) * 28, 120))
            st.altair_chart(hbar, use_container_width=True)

    st.markdown("##### Cortex Agent Tool Durations")
    tool_df = run_query(f"""
        SELECT
            CASE
                WHEN RECORD_ATTRIBUTES:"snow.ai.observability.agent.tool.cortex_search.name" IS NOT NULL THEN 'Cortex Search'
                WHEN RECORD_ATTRIBUTES:"snow.ai.observability.agent.tool.cortex_analyst.semantic_model" IS NOT NULL THEN 'Cortex Analyst'
                WHEN RECORD_ATTRIBUTES:"snow.ai.observability.agent.duration" IS NOT NULL THEN 'Agent Orchestration'
            END AS TOOL,
            COUNT(*) AS CALLS,
            ROUND(AVG(COALESCE(
                RECORD_ATTRIBUTES:"snow.ai.observability.agent.tool.cortex_search.duration"::NUMBER,
                RECORD_ATTRIBUTES:"snow.ai.observability.agent.tool.cortex_analyst.duration"::NUMBER,
                RECORD_ATTRIBUTES:"snow.ai.observability.agent.duration"::NUMBER
            )), 0) AS AVG_MS,
            ROUND(MAX(COALESCE(
                RECORD_ATTRIBUTES:"snow.ai.observability.agent.tool.cortex_search.duration"::NUMBER,
                RECORD_ATTRIBUTES:"snow.ai.observability.agent.tool.cortex_analyst.duration"::NUMBER,
                RECORD_ATTRIBUTES:"snow.ai.observability.agent.duration"::NUMBER
            )), 0) AS MAX_MS
        FROM {CORTEX_EVENTS_SQL}
        WHERE RECORD_TYPE = 'SPAN'
          AND (RECORD_ATTRIBUTES:"snow.ai.observability.agent.tool.cortex_search.name" IS NOT NULL
               OR RECORD_ATTRIBUTES:"snow.ai.observability.agent.tool.cortex_analyst.semantic_model" IS NOT NULL
               OR RECORD_ATTRIBUTES:"snow.ai.observability.agent.duration" IS NOT NULL)
        GROUP BY TOOL ORDER BY AVG_MS DESC
    """)
    st.dataframe(tool_df, use_container_width=True)

with tab_responses:
    queries = exec_df["USER_QUERY"].dropna().unique().tolist()
    selected_query = st.selectbox("Select a query:", queries, label_visibility="collapsed",
                                  help="Pick a user query to compare agent responses and execution traces")

    if selected_query:
        match = exec_df[exec_df["USER_QUERY"] == selected_query].iloc[0]

        st.markdown(f"**Query:** {selected_query}")

        c1, c2 = st.columns(2)
        with c1:
            st.markdown("#### Cortex Agent")
            cortex_lat = match.get("CORTEX_LATENCY_MS")
            c_scores = parse_scores(match.get("CORTEX_EVAL_SCORES"))
            pills = " &nbsp; ".join([f"`{k}: {v}`" for k, v in c_scores.items()]) if c_scores else ""
            if cortex_lat and not pd.isna(cortex_lat):
                st.caption(f"Latency: {cortex_lat:.0f} ms &nbsp;|&nbsp; {pills}")
            cortex_out = match.get("CORTEX_OUTPUT")
            with st.container(height=300):
                st.markdown(cortex_out if cortex_out and not (isinstance(cortex_out, float) and pd.isna(cortex_out)) else "_No response_")

        with c2:
            st.markdown("#### LangGraph Agent")
            lg_lat = match.get("LANGGRAPH_LATENCY_MS")
            l_scores = parse_scores(match.get("LANGGRAPH_EVAL_SCORES"))
            pills = " &nbsp; ".join([f"`{k}: {v}`" for k, v in l_scores.items()]) if l_scores else ""
            if lg_lat and not pd.isna(lg_lat):
                st.caption(f"Latency: {lg_lat:.0f} ms &nbsp;|&nbsp; {pills}")
            lg_out = match.get("LANGGRAPH_OUTPUT")
            with st.container(height=300):
                st.markdown(lg_out if lg_out and not (isinstance(lg_out, float) and pd.isna(lg_out)) else "_No response_")

        st.markdown("##### Execution Traces")
        t1, t2 = st.columns(2)

        cortex_trace_id = match.get("CORTEX_TRACE_ID")
        lg_trace_id = match.get("LANGGRAPH_TRACE_ID")

        with t1:
            if cortex_trace_id and not (isinstance(cortex_trace_id, float) and pd.isna(cortex_trace_id)):
                trace_df = run_query(f"""
                    SELECT
                        COALESCE(
                            RECORD_ATTRIBUTES:"snow.ai.observability.agent.tool.cortex_search.name"::STRING,
                            RECORD_ATTRIBUTES:"snow.ai.observability.agent.tool.cortex_analyst.semantic_model"::STRING,
                            RECORD_ATTRIBUTES:"ai.observability.span_type"::STRING,
                            'orchestration'
                        ) AS STEP,
                        RECORD_ATTRIBUTES:"snow.ai.observability.agent.tool.cortex_search.query"::STRING AS SEARCH_QUERY,
                        RECORD_ATTRIBUTES:"snow.ai.observability.agent.tool.cortex_analyst.sql_query"::STRING AS ANALYST_SQL,
                        RECORD_ATTRIBUTES:"snow.ai.observability.agent.tool.cortex_search.status"::STRING AS STATUS,
                        TIMESTAMPDIFF('millisecond', START_TIMESTAMP, TIMESTAMP) AS DURATION_MS,
                        START_TIMESTAMP
                    FROM {CORTEX_EVENTS_SQL}
                    WHERE TRACE:"trace_id"::STRING = '{cortex_trace_id}'
                      AND RECORD_TYPE = 'SPAN'
                    ORDER BY START_TIMESTAMP
                """)
                for _, span in trace_df.iterrows():
                    step = span["STEP"]
                    dur = span["DURATION_MS"]
                    detail = span.get("SEARCH_QUERY") or span.get("ANALYST_SQL") or ""
                    if isinstance(detail, float) and pd.isna(detail):
                        detail = ""
                    detail_preview = detail[:120] + "..." if len(str(detail)) > 120 else detail
                    with st.expander(f"{step} — {dur} ms"):
                        if detail_preview:
                            st.code(detail_preview, language="sql" if "SELECT" in str(detail).upper() else "text")
            else:
                st.caption("No trace available")

        with t2:
            if lg_trace_id and not (isinstance(lg_trace_id, float) and pd.isna(lg_trace_id)):
                lg_trace_df = run_query(f"""
                    SELECT
                        COALESCE(
                            RECORD_ATTRIBUTES:"ai.observability.span_type"::STRING,
                            RECORD_ATTRIBUTES:"ai.observability.call.function"::STRING,
                            'step'
                        ) AS STEP,
                        RECORD_ATTRIBUTES:"ai.observability.retrieval.query_text"::STRING AS RETRIEVAL_QUERY,
                        RECORD_ATTRIBUTES:"ai.observability.call.function"::STRING AS FUNCTION_CALL,
                        LEFT(RECORD_ATTRIBUTES:"ai.observability.call.return"::STRING, 500) AS CALL_RETURN,
                        TIMESTAMPDIFF('millisecond', START_TIMESTAMP, TIMESTAMP) AS DURATION_MS,
                        START_TIMESTAMP
                    FROM {LANGGRAPH_EVENTS_SQL}
                    WHERE TRACE:"trace_id"::STRING = '{lg_trace_id}'
                      AND RECORD_TYPE = 'SPAN'
                      AND RECORD_ATTRIBUTES:"ai.observability.span_type"::STRING NOT IN ('eval', 'eval_root')
                    ORDER BY START_TIMESTAMP
                """)
                for _, span in lg_trace_df.iterrows():
                    step = span["STEP"]
                    dur = span["DURATION_MS"]
                    detail = span.get("RETRIEVAL_QUERY") or span.get("FUNCTION_CALL") or ""
                    if isinstance(detail, float) and pd.isna(detail):
                        detail = ""
                    ret = span.get("CALL_RETURN") or ""
                    if isinstance(ret, float) and pd.isna(ret):
                        ret = ""
                    with st.expander(f"{step} — {dur} ms"):
                        if detail:
                            st.text(str(detail))
                        if ret:
                            st.code(str(ret)[:300], language="text")
            else:
                st.caption("No trace available")
