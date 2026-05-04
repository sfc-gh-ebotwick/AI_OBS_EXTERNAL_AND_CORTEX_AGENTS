--------------------------------------------------------------------------------
-- AGENT COMPARISON: LANGGRAPH_CUSTOMER_SUPPORT_AGENT vs CORTEX_CUST_SUPPORT_AGENT
--------------------------------------------------------------------------------

-- 1) HIGH-LEVEL PERFORMANCE SCORECARD
--    Compares avg eval scores, latency, and volume side-by-side
WITH all_events AS (
    SELECT * FROM TABLE(SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS(
        'CUST_SUPPORT_DEMO', 'AGENTS', 'CORTEX_CUST_SUPPORT_AGENT', 'CORTEX AGENT'))
    UNION ALL
    SELECT * FROM TABLE(SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS(
        'CUST_SUPPORT_DEMO', 'AGENTS', 'LANGGRAPH_CUSTOMER_SUPPORT_AGENT', 'EXTERNAL AGENT'))
),
eval_scores AS (
    SELECT
        RECORD_ATTRIBUTES:"snow.ai.observability.object.name"::STRING AS AGENT_NAME,
        RECORD_ATTRIBUTES:"ai.observability.eval.metric_name"::STRING AS METRIC,
        RECORD_ATTRIBUTES:"ai.observability.eval_root.score"::FLOAT AS SCORE
    FROM all_events
    WHERE RECORD_ATTRIBUTES:"ai.observability.span_type"::STRING = 'eval_root'
      AND RECORD_ATTRIBUTES:"ai.observability.eval_root.score" IS NOT NULL
),
latencies AS (
    SELECT
        RECORD_ATTRIBUTES:"snow.ai.observability.object.name"::STRING AS AGENT_NAME,
        TIMESTAMPDIFF('millisecond', START_TIMESTAMP, TIMESTAMP) AS DURATION_MS
    FROM all_events
    WHERE RECORD_ATTRIBUTES:"ai.observability.span_type"::STRING = 'record_root'
)
SELECT
    COALESCE(e.AGENT_NAME, l.AGENT_NAME) AS AGENT_NAME,
    COUNT(DISTINCT e.METRIC) AS NUM_EVAL_METRICS,
    ROUND(AVG(e.SCORE), 4) AS AVG_EVAL_SCORE,
    ROUND(MIN(e.SCORE), 4) AS MIN_EVAL_SCORE,
    COUNT(DISTINCT l.DURATION_MS) AS NUM_INVOCATIONS,
    ROUND(AVG(l.DURATION_MS), 0) AS AVG_LATENCY_MS,
    ROUND(MEDIAN(l.DURATION_MS), 0) AS MEDIAN_LATENCY_MS,
    ROUND(MAX(l.DURATION_MS), 0) AS MAX_LATENCY_MS
FROM eval_scores e
FULL OUTER JOIN latencies l ON e.AGENT_NAME = l.AGENT_NAME
GROUP BY 1
ORDER BY 1;


-- 2) EVAL SCORE DISTRIBUTION BY METRIC
--    Shows how each agent scores across every evaluation metric
SELECT
    RECORD_ATTRIBUTES:"snow.ai.observability.object.name"::STRING AS AGENT_NAME,
    RECORD_ATTRIBUTES:"ai.observability.eval.metric_name"::STRING AS METRIC,
    COUNT(*) AS NUM_EVALS,
    ROUND(AVG(RECORD_ATTRIBUTES:"ai.observability.eval_root.score"::FLOAT), 4) AS AVG_SCORE,
    ROUND(MEDIAN(RECORD_ATTRIBUTES:"ai.observability.eval_root.score"::FLOAT), 4) AS MEDIAN_SCORE,
    ROUND(MIN(RECORD_ATTRIBUTES:"ai.observability.eval_root.score"::FLOAT), 4) AS MIN_SCORE,
    ROUND(MAX(RECORD_ATTRIBUTES:"ai.observability.eval_root.score"::FLOAT), 4) AS MAX_SCORE,
    ROUND(STDDEV(RECORD_ATTRIBUTES:"ai.observability.eval_root.score"::FLOAT), 4) AS STDDEV_SCORE,
    SUM(CASE WHEN RECORD_ATTRIBUTES:"ai.observability.eval_root.score"::FLOAT = 1 THEN 1 ELSE 0 END) AS PERFECT_SCORE_COUNT,
    ROUND(SUM(CASE WHEN RECORD_ATTRIBUTES:"ai.observability.eval_root.score"::FLOAT = 1 THEN 1 ELSE 0 END)
          / COUNT(*)::FLOAT * 100, 1) AS PERFECT_SCORE_PCT
FROM (
    SELECT * FROM TABLE(SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS(
        'CUST_SUPPORT_DEMO', 'AGENTS', 'CORTEX_CUST_SUPPORT_AGENT', 'CORTEX AGENT'))
    UNION ALL
    SELECT * FROM TABLE(SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS(
        'CUST_SUPPORT_DEMO', 'AGENTS', 'LANGGRAPH_CUSTOMER_SUPPORT_AGENT', 'EXTERNAL AGENT'))
)
WHERE RECORD_ATTRIBUTES:"ai.observability.span_type"::STRING = 'eval_root'
  AND RECORD_ATTRIBUTES:"ai.observability.eval_root.score" IS NOT NULL
GROUP BY 1, 2
ORDER BY 1, 2;


-- 3) END-TO-END LATENCY COMPARISON WITH PERCENTILES
--    Compares response time distributions across agents
SELECT
    RECORD_ATTRIBUTES:"snow.ai.observability.object.name"::STRING AS AGENT_NAME,
    COUNT(*) AS NUM_REQUESTS,
    ROUND(AVG(TIMESTAMPDIFF('millisecond', START_TIMESTAMP, TIMESTAMP)), 0) AS AVG_MS,
    ROUND(MEDIAN(TIMESTAMPDIFF('millisecond', START_TIMESTAMP, TIMESTAMP)), 0) AS P50_MS,
    ROUND(PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY TIMESTAMPDIFF('millisecond', START_TIMESTAMP, TIMESTAMP)), 0) AS P90_MS,
    ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY TIMESTAMPDIFF('millisecond', START_TIMESTAMP, TIMESTAMP)), 0) AS P95_MS,
    ROUND(MIN(TIMESTAMPDIFF('millisecond', START_TIMESTAMP, TIMESTAMP)), 0) AS MIN_MS,
    ROUND(MAX(TIMESTAMPDIFF('millisecond', START_TIMESTAMP, TIMESTAMP)), 0) AS MAX_MS
FROM (
    SELECT * FROM TABLE(SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS(
        'CUST_SUPPORT_DEMO', 'AGENTS', 'CORTEX_CUST_SUPPORT_AGENT', 'CORTEX AGENT'))
    UNION ALL
    SELECT * FROM TABLE(SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS(
        'CUST_SUPPORT_DEMO', 'AGENTS', 'LANGGRAPH_CUSTOMER_SUPPORT_AGENT', 'EXTERNAL AGENT'))
)
WHERE RECORD_ATTRIBUTES:"ai.observability.span_type"::STRING = 'record_root'
GROUP BY 1
ORDER BY 1;


-- 4) SPAN-LEVEL LATENCY BREAKDOWN
--    Shows time spent in each span type per agent (tool calls, retrieval, generation, etc.)
SELECT
    RECORD_ATTRIBUTES:"snow.ai.observability.object.name"::STRING AS AGENT_NAME,
    RECORD_ATTRIBUTES:"ai.observability.span_type"::STRING AS SPAN_TYPE,
    COUNT(*) AS SPAN_COUNT,
    ROUND(AVG(TIMESTAMPDIFF('millisecond', START_TIMESTAMP, TIMESTAMP)), 0) AS AVG_DURATION_MS,
    ROUND(MEDIAN(TIMESTAMPDIFF('millisecond', START_TIMESTAMP, TIMESTAMP)), 0) AS MEDIAN_DURATION_MS,
    ROUND(MAX(TIMESTAMPDIFF('millisecond', START_TIMESTAMP, TIMESTAMP)), 0) AS MAX_DURATION_MS
FROM (
    SELECT * FROM TABLE(SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS(
        'CUST_SUPPORT_DEMO', 'AGENTS', 'CORTEX_CUST_SUPPORT_AGENT', 'CORTEX AGENT'))
    UNION ALL
    SELECT * FROM TABLE(SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS(
        'CUST_SUPPORT_DEMO', 'AGENTS', 'LANGGRAPH_CUSTOMER_SUPPORT_AGENT', 'EXTERNAL AGENT'))
)
WHERE RECORD_TYPE = 'SPAN'
  AND RECORD_ATTRIBUTES:"ai.observability.span_type"::STRING IS NOT NULL
GROUP BY 1, 2
ORDER BY 1, AVG_DURATION_MS DESC;


-- 5) CORTEX AGENT TOOL USAGE & DURATION BREAKDOWN
--    Shows how the Cortex SUPPORT_AGENT uses its tools (search, analyst, planning)
SELECT
    'CORTEX_CUST_SUPPORT_AGENT' AS AGENT_NAME,
    CASE
        WHEN RECORD_ATTRIBUTES:"snow.ai.observability.agent.tool.cortex_search.name" IS NOT NULL THEN 'cortex_search'
        WHEN RECORD_ATTRIBUTES:"snow.ai.observability.agent.tool.cortex_analyst.semantic_model" IS NOT NULL THEN 'cortex_analyst'
        WHEN RECORD_ATTRIBUTES:"snow.ai.observability.agent.duration" IS NOT NULL THEN 'agent_orchestration'
    END AS TOOL_TYPE,
    COUNT(*) AS INVOCATIONS,
    ROUND(AVG(COALESCE(
        RECORD_ATTRIBUTES:"snow.ai.observability.agent.tool.cortex_search.duration"::NUMBER,
        RECORD_ATTRIBUTES:"snow.ai.observability.agent.tool.cortex_analyst.duration"::NUMBER,
        RECORD_ATTRIBUTES:"snow.ai.observability.agent.duration"::NUMBER
    )), 0) AS AVG_DURATION_MS,
    ROUND(MAX(COALESCE(
        RECORD_ATTRIBUTES:"snow.ai.observability.agent.tool.cortex_search.duration"::NUMBER,
        RECORD_ATTRIBUTES:"snow.ai.observability.agent.tool.cortex_analyst.duration"::NUMBER,
        RECORD_ATTRIBUTES:"snow.ai.observability.agent.duration"::NUMBER
    )), 0) AS MAX_DURATION_MS
FROM TABLE(SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS(
    'CUST_SUPPORT_DEMO', 'AGENTS', 'CORTEX_CUST_SUPPORT_AGENT', 'CORTEX AGENT'))
WHERE RECORD_TYPE = 'SPAN'
  AND (RECORD_ATTRIBUTES:"snow.ai.observability.agent.tool.cortex_search.name" IS NOT NULL
       OR RECORD_ATTRIBUTES:"snow.ai.observability.agent.tool.cortex_analyst.semantic_model" IS NOT NULL
       OR RECORD_ATTRIBUTES:"snow.ai.observability.agent.duration" IS NOT NULL)
GROUP BY TOOL_TYPE
ORDER BY AVG_DURATION_MS DESC;


-- 6) LANGGRAPH AGENT SPAN BREAKDOWN
--    Shows retrieval, MCP, generation span durations for the external agent

SELECT
    'LANGGRAPH_CUSTOMER_SUPPORT_AGENT' AS AGENT_NAME,
    RECORD_ATTRIBUTES:"ai.observability.span_type"::STRING AS SPAN_TYPE,
    COUNT(*) AS SPAN_COUNT,
    ROUND(AVG(TIMESTAMPDIFF('millisecond', START_TIMESTAMP, TIMESTAMP)), 0) AS AVG_DURATION_MS,
    ROUND(MAX(TIMESTAMPDIFF('millisecond', START_TIMESTAMP, TIMESTAMP)), 0) AS MAX_DURATION_MS,
    ROUND(SUM(TIMESTAMPDIFF('millisecond', START_TIMESTAMP, TIMESTAMP)), 0) AS TOTAL_DURATION_MS
FROM TABLE(SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS(
    'CUST_SUPPORT_DEMO', 'AGENTS', 'LANGGRAPH_CUSTOMER_SUPPORT_AGENT', 'EXTERNAL AGENT'))
WHERE RECORD_TYPE = 'SPAN'
  AND RECORD_ATTRIBUTES:"ai.observability.span_type"::STRING IN ('retrieval', 'tool', 'graph_node', 'MCP', 'generation', 'record_root', 'unknown')
GROUP BY SPAN_TYPE
ORDER BY AVG_DURATION_MS DESC;


SELECT         
REGEXP_SUBSTR(
    RECORD_ATTRIBUTES:"ai.observability.call.return"::STRING,
    'input_tokens.: (\\d+)', 1, 1, 'e'
)::NUMBER AS INPUT_TOKENS,

*     FROM TABLE(
    SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS(
    'CUST_SUPPORT_DEMO',
    'AGENTS',
    'LANGGRAPH_CUSTOMER_SUPPORT_AGENT',
    'EXTERNAL AGENT'
    ))
        WHERE RECORD_ATTRIBUTES:"ai.observability.span_type"::STRING = 'record_root';



-- 7) SIDE-BY-SIDE RESPONSE COMPARISON ON MATCHING INPUTS
--    Joins both agents' responses to the same user queries for qualitative review
WITH cortex_token_totals AS (
    SELECT
        RECORD_ATTRIBUTES:"ai.observability.record_id"::STRING AS RECORD_ID,
        SUM(RECORD_ATTRIBUTES:"snow.ai.observability.agent.planning.token_count.input"::NUMBER) AS PROMPT_TOKENS,
        SUM(RECORD_ATTRIBUTES:"snow.ai.observability.agent.planning.token_count.output"::NUMBER) AS COMPLETION_TOKENS,
        SUM(RECORD_ATTRIBUTES:"snow.ai.observability.agent.planning.token_count.total"::NUMBER) AS TOTAL_TOKENS
    FROM TABLE(
    SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS(
    'CUST_SUPPORT_DEMO',
    'AGENTS',
    'CORTEX_CUST_SUPPORT_AGENT',
    'CORTEX AGENT'
    ))
    -- WHERE RECORD_ATTRIBUTES:"snow.ai.observability.agent.planning.token_count.total" IS NOT NULL
    GROUP BY RECORD_ID
),
cortex_responses AS (
    SELECT
        r.RECORD_ATTRIBUTES:"ai.observability.record_root.input"::STRING AS USER_INPUT,
        r.RECORD_ATTRIBUTES:"ai.observability.record_root.output"::STRING AS AGENT_RESPONSE,
        TIMESTAMPDIFF('millisecond', r.START_TIMESTAMP, r.TIMESTAMP) AS LATENCY_MS,
        -- r.RECORD_ATTRIBUTES:"ai.observability.cost.num_prompt_tokens"::NUMBER AS PROMPT_TOKENS,
        -- r.RECORD_ATTRIBUTES:"ai.observability.cost.num_completion_tokens"::NUMBER AS COMPLETION_TOKENS,
        t.PROMPT_TOKENS,
        t.COMPLETION_TOKENS,
        t.TOTAL_TOKENS
    FROM TABLE(
    SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS(
    'CUST_SUPPORT_DEMO',
    'AGENTS',
    'CORTEX_CUST_SUPPORT_AGENT',
    'CORTEX AGENT'
    )) r
    LEFT JOIN cortex_token_totals t
        ON r.RECORD_ATTRIBUTES:"ai.observability.record_id"::STRING = t.RECORD_ID
    WHERE r.RECORD_ATTRIBUTES:"ai.observability.span_type"::STRING = 'record_root'
),
langgraph_token_extracted AS (
    SELECT
        r.RECORD_ID,
        TRY_PARSE_JSON(
            SUBSTR(
                REPLACE(REPLACE(f.VALUE::STRING, '''', '"'), 'True', 'true'),
                POSITION('{' IN REPLACE(REPLACE(f.VALUE::STRING, '''', '"'), 'True', 'true'))
            )
        ) AS USAGE
    FROM (
        SELECT
            RECORD_ATTRIBUTES:"ai.observability.record_id"::STRING AS RECORD_ID,
            RECORD_ATTRIBUTES:"ai.observability.call.return"::STRING AS CALL_RETURN
        FROM TABLE(
        SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS(
        'CUST_SUPPORT_DEMO',
        'AGENTS',
        'LANGGRAPH_CUSTOMER_SUPPORT_AGENT',
        'EXTERNAL AGENT'
        ))
        WHERE CALL_RETURN LIKE '%usage_metadata%'
            AND RECORD_ATTRIBUTES:"ai.observability.span_type"::STRING = 'graph_node'
    ) r,
    LATERAL FLATTEN(input => REGEXP_SUBSTR_ALL(r.CALL_RETURN, 'usage_metadata=\\{[^}]+\\}')) f
),
langgraph_token_totals AS (
    SELECT
        RECORD_ID,
        SUM(USAGE:"input_tokens"::NUMBER) AS PROMPT_TOKENS,
        SUM(USAGE:"output_tokens"::NUMBER) AS COMPLETION_TOKENS,
        SUM(USAGE:"total_tokens"::NUMBER) AS TOTAL_TOKENS
    FROM langgraph_token_extracted
    WHERE USAGE IS NOT NULL
    GROUP BY RECORD_ID
),
langgraph_responses AS (
    SELECT
        r.RECORD_ATTRIBUTES:"ai.observability.record_root.input"::STRING AS USER_INPUT,
        r.RECORD_ATTRIBUTES:"ai.observability.record_root.output"::STRING AS AGENT_RESPONSE,
        TIMESTAMPDIFF('millisecond', r.START_TIMESTAMP, r.TIMESTAMP) AS LATENCY_MS,
        t.PROMPT_TOKENS,
        t.COMPLETION_TOKENS,
        t.TOTAL_TOKENS
    FROM TABLE(
    SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS(
    'CUST_SUPPORT_DEMO',
    'AGENTS',
    'LANGGRAPH_CUSTOMER_SUPPORT_AGENT',
    'EXTERNAL AGENT'
    )) r
    LEFT JOIN langgraph_token_totals t
        ON r.RECORD_ATTRIBUTES:"ai.observability.record_id"::STRING = t.RECORD_ID
    WHERE r.RECORD_ATTRIBUTES:"ai.observability.span_type"::STRING = 'record_root'
)
SELECT
    c.USER_INPUT,
    LEFT(c.AGENT_RESPONSE, 200) AS CORTEX_RESPONSE_PREVIEW,
    LEFT(l.AGENT_RESPONSE, 200) AS LANGGRAPH_RESPONSE_PREVIEW,
    c.LATENCY_MS AS CORTEX_LATENCY_MS,
    l.LATENCY_MS AS LANGGRAPH_LATENCY_MS,
    ROUND(c.LATENCY_MS - l.LATENCY_MS, 0) AS LATENCY_DIFF_MS,
    ROUND((c.LATENCY_MS - l.LATENCY_MS) / NULLIF(l.LATENCY_MS, 0) * 100, 1) AS LATENCY_DIFF_PCT,
    c.PROMPT_TOKENS AS CORTEX_PROMPT_TOKENS,
    c.COMPLETION_TOKENS AS CORTEX_COMPLETION_TOKENS,
    c.TOTAL_TOKENS AS CORTEX_TOTAL_TOKENS,
    l.PROMPT_TOKENS AS LANGGRAPH_PROMPT_TOKENS,
    l.COMPLETION_TOKENS AS LANGGRAPH_COMPLETION_TOKENS,
    l.TOTAL_TOKENS AS LANGGRAPH_TOTAL_TOKENS,
    c.TOTAL_TOKENS - l.TOTAL_TOKENS AS TOKEN_DIFF,
    ROUND(( c.TOTAL_TOKENS - l.TOTAL_TOKENS) / NULLIF(l.TOTAL_TOKENS, 0) * 100, 1) AS TOKEN_DIFF_PCT,

FROM cortex_responses c
INNER JOIN langgraph_responses l
    ON c.USER_INPUT = l.USER_INPUT
ORDER BY ABS(LATENCY_DIFF_MS) DESC;

-- 7b)aggregate latency and token comparison
--    Joins both agents' responses to the same user queries for qualitative review
WITH cortex_token_totals AS (
    SELECT
        RECORD_ATTRIBUTES:"ai.observability.record_id"::STRING AS RECORD_ID,
        SUM(RECORD_ATTRIBUTES:"snow.ai.observability.agent.planning.token_count.input"::NUMBER) AS PROMPT_TOKENS,
        SUM(RECORD_ATTRIBUTES:"snow.ai.observability.agent.planning.token_count.output"::NUMBER) AS COMPLETION_TOKENS,
        SUM(RECORD_ATTRIBUTES:"snow.ai.observability.agent.planning.token_count.total"::NUMBER) AS TOTAL_TOKENS
    FROM TABLE(
    SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS(
    'CUST_SUPPORT_DEMO',
    'AGENTS',
    'CORTEX_CUST_SUPPORT_AGENT',
    'CORTEX AGENT'
    ))
    WHERE RECORD_ATTRIBUTES:"snow.ai.observability.agent.planning.token_count.total" IS NOT NULL
    GROUP BY RECORD_ID
),
cortex_responses AS (
    SELECT
        r.RECORD_ATTRIBUTES:"ai.observability.record_root.input"::STRING AS USER_INPUT,
        TIMESTAMPDIFF('millisecond', r.START_TIMESTAMP, r.TIMESTAMP) AS LATENCY_MS,
        t.PROMPT_TOKENS,
        t.COMPLETION_TOKENS,
        t.TOTAL_TOKENS
    FROM TABLE(
    SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS(
    'CUST_SUPPORT_DEMO',
    'AGENTS',
    'CORTEX_CUST_SUPPORT_AGENT',
    'CORTEX AGENT'
    )) r
    LEFT JOIN cortex_token_totals t
        ON r.RECORD_ATTRIBUTES:"ai.observability.record_id"::STRING = t.RECORD_ID
    WHERE r.RECORD_ATTRIBUTES:"ai.observability.span_type"::STRING = 'record_root'
),
langgraph_token_extracted AS (
    SELECT
        r.RECORD_ID,
        TRY_PARSE_JSON(
            SUBSTR(
                REPLACE(REPLACE(f.VALUE::STRING, '''', '"'), 'True', 'true'),
                POSITION('{' IN REPLACE(REPLACE(f.VALUE::STRING, '''', '"'), 'True', 'true'))
            )
        ) AS USAGE
    FROM (
        SELECT
            RECORD_ATTRIBUTES:"ai.observability.record_id"::STRING AS RECORD_ID,
            RECORD_ATTRIBUTES:"ai.observability.call.return"::STRING AS CALL_RETURN
        FROM TABLE(
        SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS(
        'CUST_SUPPORT_DEMO',
        'AGENTS',
        'LANGGRAPH_CUSTOMER_SUPPORT_AGENT',
        'EXTERNAL AGENT'
        ))
        WHERE CALL_RETURN LIKE '%usage_metadata%'
            AND RECORD_ATTRIBUTES:"ai.observability.span_type"::STRING = 'graph_node'
    ) r,
    LATERAL FLATTEN(input => REGEXP_SUBSTR_ALL(r.CALL_RETURN, 'usage_metadata=\\{[^}]+\\}')) f
),
langgraph_token_totals AS (
    SELECT
        RECORD_ID,
        SUM(USAGE:"input_tokens"::NUMBER) AS PROMPT_TOKENS,
        SUM(USAGE:"output_tokens"::NUMBER) AS COMPLETION_TOKENS,
        SUM(USAGE:"total_tokens"::NUMBER) AS TOTAL_TOKENS
    FROM langgraph_token_extracted
    WHERE USAGE IS NOT NULL
    GROUP BY RECORD_ID
),
langgraph_responses AS (
    SELECT
        r.RECORD_ATTRIBUTES:"ai.observability.record_root.input"::STRING AS USER_INPUT,
        TIMESTAMPDIFF('millisecond', r.START_TIMESTAMP, r.TIMESTAMP) AS LATENCY_MS,
        t.PROMPT_TOKENS,
        t.COMPLETION_TOKENS,
        t.TOTAL_TOKENS
    FROM TABLE(
    SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS(
    'CUST_SUPPORT_DEMO',
    'AGENTS',
    'LANGGRAPH_CUSTOMER_SUPPORT_AGENT',
    'EXTERNAL AGENT'
    )) r
    LEFT JOIN langgraph_token_totals t
        ON r.RECORD_ATTRIBUTES:"ai.observability.record_id"::STRING = t.RECORD_ID
    WHERE r.RECORD_ATTRIBUTES:"ai.observability.span_type"::STRING = 'record_root'
)
SELECT
    AVG(c.LATENCY_MS) AS CORTEX_LATENCY_MS,
    AVG(l.LATENCY_MS) AS LANGGRAPH_LATENCY_MS,
    AVG(ROUND(c.LATENCY_MS - l.LATENCY_MS, 0)) AS LATENCY_DIFF_MS,
    ROUND((AVG(c.LATENCY_MS) - AVG(l.LATENCY_MS)) / NULLIF(AVG(l.LATENCY_MS), 0) * 100, 1) AS LATENCY_DIFF_PCT,
    AVG(c.TOTAL_TOKENS) AS AVG_CORTEX_TOTAL_TOKENS,
    AVG(l.TOTAL_TOKENS) AS AVG_LANGGRAPH_TOTAL_TOKENS,
    AVG(c.PROMPT_TOKENS) AS AVG_CORTEX_PROMPT_TOKENS,
    AVG(l.PROMPT_TOKENS) AS AVG_LANGGRAPH_PROMPT_TOKENS,
    AVG(c.COMPLETION_TOKENS) AS AVG_CORTEX_COMPLETION_TOKENS,
    AVG(l.COMPLETION_TOKENS) AS AVG_LANGGRAPH_COMPLETION_TOKENS,
    ROUND((AVG(c.TOTAL_TOKENS) - AVG(l.TOTAL_TOKENS)) / NULLIF(AVG(l.TOTAL_TOKENS), 0) * 100, 1) AS TOKEN_DIFF_PCT
FROM cortex_responses c
INNER JOIN langgraph_responses l
    ON c.USER_INPUT = l.USER_INPUT;





-- 8) EVAL SCORE HEATMAP: SCORE BUCKETS BY AGENT AND METRIC
--    Bucketed view of eval score distributions for easy visual comparison
SELECT
    RECORD_ATTRIBUTES:"snow.ai.observability.object.name"::STRING AS AGENT_NAME,
    RECORD_ATTRIBUTES:"ai.observability.eval.metric_name"::STRING AS METRIC,
    CASE
        WHEN RECORD_ATTRIBUTES:"ai.observability.eval_root.score"::FLOAT = 1.0 THEN '1.0 (Perfect)'
        WHEN RECORD_ATTRIBUTES:"ai.observability.eval_root.score"::FLOAT >= 0.8 THEN '0.8-0.99'
        WHEN RECORD_ATTRIBUTES:"ai.observability.eval_root.score"::FLOAT >= 0.6 THEN '0.6-0.79'
        WHEN RECORD_ATTRIBUTES:"ai.observability.eval_root.score"::FLOAT >= 0.4 THEN '0.4-0.59'
        ELSE '< 0.4 (Poor)'
    END AS SCORE_BUCKET,
    COUNT(*) AS COUNT
FROM (
    SELECT * FROM TABLE(SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS(
        'CUST_SUPPORT_DEMO', 'AGENTS', 'CORTEX_CUST_SUPPORT_AGENT', 'CORTEX AGENT'))
    UNION ALL
    SELECT * FROM TABLE(SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS(
        'CUST_SUPPORT_DEMO', 'AGENTS', 'LANGGRAPH_CUSTOMER_SUPPORT_AGENT', 'EXTERNAL AGENT'))
)
WHERE RECORD_ATTRIBUTES:"ai.observability.span_type"::STRING = 'eval_root'
  AND RECORD_ATTRIBUTES:"ai.observability.eval_root.score" IS NOT NULL
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3;


-- 9) EVAL RUN COMPARISON ACROSS BATCH RUNS (LANGGRAPH)
--    Shows how the LangGraph agent's eval scores change across different batch runs
SELECT
    RECORD_ATTRIBUTES:"ai.observability.run.name"::STRING AS RUN_NAME,
    RECORD_ATTRIBUTES:"ai.observability.eval.metric_name"::STRING AS METRIC,
    COUNT(*) AS NUM_EVALS,
    ROUND(AVG(RECORD_ATTRIBUTES:"ai.observability.eval_root.score"::FLOAT), 4) AS AVG_SCORE,
    ROUND(MIN(RECORD_ATTRIBUTES:"ai.observability.eval_root.score"::FLOAT), 4) AS MIN_SCORE,
    SUM(CASE WHEN RECORD_ATTRIBUTES:"ai.observability.eval_root.score"::FLOAT = 1 THEN 1 ELSE 0 END) AS PERFECT_COUNT
FROM TABLE(SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS(
    'CUST_SUPPORT_DEMO', 'AGENTS', 'LANGGRAPH_CUSTOMER_SUPPORT_AGENT', 'EXTERNAL AGENT'))
WHERE RECORD_ATTRIBUTES:"ai.observability.span_type"::STRING = 'eval_root'
  AND RECORD_ATTRIBUTES:"ai.observability.eval_root.score" IS NOT NULL
GROUP BY 1, 2
ORDER BY 1, 2;


-- 10) EXECUTIVE SUMMARY: PER-QUERY LATENCY & EVAL SCORE BY AGENT
--     For each user query, shows both agents' latency and all eval scores in one row
--     Aggregates eval scores across ALL runs/record_ids so no metrics are missed
WITH roots AS (
    SELECT
        RECORD_ATTRIBUTES:"snow.ai.observability.object.name"::STRING AS AGENT_NAME,
        RECORD_ATTRIBUTES:"ai.observability.record_root.input"::STRING AS USER_QUERY,
        RECORD_ATTRIBUTES:"ai.observability.record_root.output"::STRING AS AGENT_OUTPUT,
        RECORD_ATTRIBUTES:"ai.observability.record_id"::STRING AS RECORD_ID,
        TIMESTAMPDIFF('millisecond', START_TIMESTAMP, TIMESTAMP) AS LATENCY_MS,
        ROW_NUMBER() OVER (PARTITION BY
            RECORD_ATTRIBUTES:"snow.ai.observability.object.name"::STRING,
            RECORD_ATTRIBUTES:"ai.observability.record_root.input"::STRING
            ORDER BY TIMESTAMP DESC) AS RN
    FROM (
        SELECT * FROM TABLE(SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS(
            'CUST_SUPPORT_DEMO', 'AGENTS', 'CORTEX_CUST_SUPPORT_AGENT', 'CORTEX AGENT'))
        UNION ALL
        SELECT * FROM TABLE(SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS(
            'CUST_SUPPORT_DEMO', 'AGENTS', 'LANGGRAPH_CUSTOMER_SUPPORT_AGENT', 'EXTERNAL AGENT'))
    )
    WHERE RECORD_ATTRIBUTES:"ai.observability.span_type"::STRING = 'record_root'
),
evals AS (
    SELECT
        RECORD_ATTRIBUTES:"snow.ai.observability.object.name"::STRING AS AGENT_NAME,
        RECORD_ATTRIBUTES:"ai.observability.eval.target_record_id"::STRING AS TARGET_RECORD_ID,
        RECORD_ATTRIBUTES:"ai.observability.eval.metric_name"::STRING AS METRIC,
        ROUND(RECORD_ATTRIBUTES:"ai.observability.eval_root.score"::FLOAT, 2)::NUMBER(5,2) AS SCORE
    FROM (
        SELECT * FROM TABLE(SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS(
            'CUST_SUPPORT_DEMO', 'AGENTS', 'CORTEX_CUST_SUPPORT_AGENT', 'CORTEX AGENT'))
        UNION ALL
        SELECT * FROM TABLE(SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS(
            'CUST_SUPPORT_DEMO', 'AGENTS', 'LANGGRAPH_CUSTOMER_SUPPORT_AGENT', 'EXTERNAL AGENT'))
    )
    WHERE RECORD_ATTRIBUTES:"ai.observability.span_type"::STRING = 'eval_root'
      AND RECORD_ATTRIBUTES:"ai.observability.eval_root.score" IS NOT NULL
),
query_evals AS (
    SELECT
        r.AGENT_NAME,
        r.USER_QUERY,
        e.METRIC,
        ROUND(AVG(e.SCORE), 2)::NUMBER(5,2) AS AVG_SCORE
    FROM roots r
    INNER JOIN evals e
        ON r.AGENT_NAME = e.AGENT_NAME AND r.RECORD_ID = e.TARGET_RECORD_ID
    GROUP BY 1, 2, 3
),
query_scores AS (
    SELECT
        AGENT_NAME,
        USER_QUERY,
        OBJECT_AGG(METRIC, AVG_SCORE::VARIANT) AS SCORES
    FROM query_evals
    GROUP BY 1, 2
),
query_latency AS (
    SELECT
        AGENT_NAME,
        USER_QUERY,
        AGENT_OUTPUT,
        ROUND(AVG(LATENCY_MS) OVER (PARTITION BY AGENT_NAME, USER_QUERY), 0) AS AVG_LATENCY_MS,
        RN
    FROM roots
),
combined AS (
    SELECT
        l.AGENT_NAME,
        l.USER_QUERY,
        l.AGENT_OUTPUT,
        l.AVG_LATENCY_MS,
        s.SCORES
    FROM query_latency l
    LEFT JOIN query_scores s ON l.AGENT_NAME = s.AGENT_NAME AND l.USER_QUERY = s.USER_QUERY
    WHERE l.RN = 1
),
cortex AS (
    SELECT * FROM combined WHERE AGENT_NAME = 'CORTEX_CUST_SUPPORT_AGENT'
),
langgraph AS (
    SELECT * FROM combined WHERE AGENT_NAME = 'LANGGRAPH_CUSTOMER_SUPPORT_AGENT'
)
SELECT
    COALESCE(c.USER_QUERY, l.USER_QUERY) AS USER_QUERY,
    c.AGENT_OUTPUT AS CORTEX_OUTPUT,
    l.AGENT_OUTPUT AS LANGGRAPH_OUTPUT,
    c.AVG_LATENCY_MS AS CORTEX_LATENCY_MS,
    l.AVG_LATENCY_MS AS LANGGRAPH_LATENCY_MS,
    c.SCORES AS CORTEX_EVAL_SCORES,
    l.SCORES AS LANGGRAPH_EVAL_SCORES
FROM cortex c
FULL OUTER JOIN langgraph l ON c.USER_QUERY = l.USER_QUERY
WHERE c.SCORES IS NOT NULL OR l.SCORES IS NOT NULL
ORDER BY COALESCE(c.USER_QUERY, l.USER_QUERY);


--------------------------------------------------------------------------------
-- 11) ALIGNED METRIC COMPARISON (NORMALIZED NAMES)
--     Maps answer_correctness -> correctness for apples-to-apples comparison
--     Filters to aligned eval runs only
--------------------------------------------------------------------------------
WITH all_events AS (
    SELECT * FROM TABLE(SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS(
        'CUST_SUPPORT_DEMO', 'AGENTS', 'CORTEX_CUST_SUPPORT_AGENT', 'CORTEX AGENT'))
    UNION ALL
    SELECT * FROM TABLE(SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS(
        'CUST_SUPPORT_DEMO', 'AGENTS', 'LANGGRAPH_CUSTOMER_SUPPORT_AGENT', 'EXTERNAL AGENT'))
),
normalized_scores AS (
    SELECT
        RECORD_ATTRIBUTES:"snow.ai.observability.object.name"::STRING AS AGENT_NAME,
        CASE
            WHEN RECORD_ATTRIBUTES:"ai.observability.eval.metric_name"::STRING = 'answer_correctness' THEN 'correctness'
            WHEN RECORD_ATTRIBUTES:"ai.observability.eval.metric_name"::STRING = 'logical_consistency' THEN 'logical_consistency'
            ELSE RECORD_ATTRIBUTES:"ai.observability.eval.metric_name"::STRING
        END AS NORMALIZED_METRIC,
        RECORD_ATTRIBUTES:"ai.observability.eval_root.score"::FLOAT AS SCORE,
        RECORD_ATTRIBUTES:"ai.observability.eval.target_record_id"::STRING AS TARGET_RECORD_ID
    FROM all_events
    WHERE RECORD_ATTRIBUTES:"ai.observability.span_type"::STRING = 'eval_root'
      AND RECORD_ATTRIBUTES:"ai.observability.eval_root.score" IS NOT NULL
)
SELECT
    NORMALIZED_METRIC,
    ROUND(AVG(CASE WHEN AGENT_NAME = 'CORTEX_CUST_SUPPORT_AGENT' THEN SCORE END), 4) AS CORTEX_AVG,
    ROUND(AVG(CASE WHEN AGENT_NAME = 'LANGGRAPH_CUSTOMER_SUPPORT_AGENT' THEN SCORE END), 4) AS LANGGRAPH_AVG,
    ROUND(AVG(CASE WHEN AGENT_NAME = 'CORTEX_CUST_SUPPORT_AGENT' THEN SCORE END)
        - AVG(CASE WHEN AGENT_NAME = 'LANGGRAPH_CUSTOMER_SUPPORT_AGENT' THEN SCORE END), 4) AS DELTA,
    CASE
        WHEN AVG(CASE WHEN AGENT_NAME = 'CORTEX_CUST_SUPPORT_AGENT' THEN SCORE END)
           > AVG(CASE WHEN AGENT_NAME = 'LANGGRAPH_CUSTOMER_SUPPORT_AGENT' THEN SCORE END) THEN 'CORTEX'
        WHEN AVG(CASE WHEN AGENT_NAME = 'CORTEX_CUST_SUPPORT_AGENT' THEN SCORE END)
           < AVG(CASE WHEN AGENT_NAME = 'LANGGRAPH_CUSTOMER_SUPPORT_AGENT' THEN SCORE END) THEN 'LANGGRAPH'
        ELSE 'TIE'
    END AS WINNER,
    COUNT(CASE WHEN AGENT_NAME = 'CORTEX_CUST_SUPPORT_AGENT' THEN 1 END) AS CORTEX_N,
    COUNT(CASE WHEN AGENT_NAME = 'LANGGRAPH_CUSTOMER_SUPPORT_AGENT' THEN 1 END) AS LANGGRAPH_N
FROM normalized_scores
GROUP BY NORMALIZED_METRIC
ORDER BY NORMALIZED_METRIC;


-- 12) PER-QUERY METRIC DELTA (WHO WINS EACH QUESTION?)
--     Shows which agent scored higher on each query for each metric
WITH roots AS (
    SELECT
        RECORD_ATTRIBUTES:"snow.ai.observability.object.name"::STRING AS AGENT_NAME,
        RECORD_ATTRIBUTES:"ai.observability.record_root.input"::STRING AS USER_QUERY,
        RECORD_ATTRIBUTES:"ai.observability.record_id"::STRING AS RECORD_ID
    FROM (
        SELECT * FROM TABLE(SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS(
            'CUST_SUPPORT_DEMO', 'AGENTS', 'CORTEX_CUST_SUPPORT_AGENT', 'CORTEX AGENT'))
        UNION ALL
        SELECT * FROM TABLE(SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS(
            'CUST_SUPPORT_DEMO', 'AGENTS', 'LANGGRAPH_CUSTOMER_SUPPORT_AGENT', 'EXTERNAL AGENT'))
    )
    WHERE RECORD_ATTRIBUTES:"ai.observability.span_type"::STRING = 'record_root'
),
evals AS (
    SELECT
        RECORD_ATTRIBUTES:"snow.ai.observability.object.name"::STRING AS AGENT_NAME,
        RECORD_ATTRIBUTES:"ai.observability.eval.target_record_id"::STRING AS TARGET_RECORD_ID,
        CASE
            WHEN RECORD_ATTRIBUTES:"ai.observability.eval.metric_name"::STRING = 'answer_correctness' THEN 'correctness'
            ELSE RECORD_ATTRIBUTES:"ai.observability.eval.metric_name"::STRING
        END AS METRIC,
        RECORD_ATTRIBUTES:"ai.observability.eval_root.score"::FLOAT AS SCORE
    FROM (
        SELECT * FROM TABLE(SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS(
            'CUST_SUPPORT_DEMO', 'AGENTS', 'CORTEX_CUST_SUPPORT_AGENT', 'CORTEX AGENT'))
        UNION ALL
        SELECT * FROM TABLE(SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS(
            'CUST_SUPPORT_DEMO', 'AGENTS', 'LANGGRAPH_CUSTOMER_SUPPORT_AGENT', 'EXTERNAL AGENT'))
    )
    WHERE RECORD_ATTRIBUTES:"ai.observability.span_type"::STRING = 'eval_root'
      AND RECORD_ATTRIBUTES:"ai.observability.eval_root.score" IS NOT NULL
),
joined AS (
    SELECT
        r.USER_QUERY,
        e.METRIC,
        r.AGENT_NAME,
        AVG(e.SCORE) AS SCORE
    FROM roots r
    INNER JOIN evals e ON r.AGENT_NAME = e.AGENT_NAME AND r.RECORD_ID = e.TARGET_RECORD_ID
    GROUP BY 1, 2, 3
),
pivoted AS (
    SELECT
        USER_QUERY,
        METRIC,
        MAX(CASE WHEN AGENT_NAME = 'CORTEX_CUST_SUPPORT_AGENT' THEN SCORE END) AS CORTEX_SCORE,
        MAX(CASE WHEN AGENT_NAME = 'LANGGRAPH_CUSTOMER_SUPPORT_AGENT' THEN SCORE END) AS LANGGRAPH_SCORE
    FROM joined
    GROUP BY 1, 2
)
SELECT
    USER_QUERY,
    METRIC,
    ROUND(CORTEX_SCORE, 3) AS CORTEX_SCORE,
    ROUND(LANGGRAPH_SCORE, 3) AS LANGGRAPH_SCORE,
    ROUND(CORTEX_SCORE - LANGGRAPH_SCORE, 3) AS DELTA,
    CASE
        WHEN CORTEX_SCORE > LANGGRAPH_SCORE THEN 'CORTEX'
        WHEN CORTEX_SCORE < LANGGRAPH_SCORE THEN 'LANGGRAPH'
        ELSE 'TIE'
    END AS WINNER
FROM pivoted
WHERE CORTEX_SCORE IS NOT NULL AND LANGGRAPH_SCORE IS NOT NULL
ORDER BY METRIC, DELTA DESC;


-- 13) WIN/LOSS/TIE SUMMARY BY METRIC
--     Counts how many queries each agent wins per metric
WITH roots AS (
    SELECT
        RECORD_ATTRIBUTES:"snow.ai.observability.object.name"::STRING AS AGENT_NAME,
        RECORD_ATTRIBUTES:"ai.observability.record_root.input"::STRING AS USER_QUERY,
        RECORD_ATTRIBUTES:"ai.observability.record_id"::STRING AS RECORD_ID
    FROM (
        SELECT * FROM TABLE(SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS(
            'CUST_SUPPORT_DEMO', 'AGENTS', 'CORTEX_CUST_SUPPORT_AGENT', 'CORTEX AGENT'))
        UNION ALL
        SELECT * FROM TABLE(SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS(
            'CUST_SUPPORT_DEMO', 'AGENTS', 'LANGGRAPH_CUSTOMER_SUPPORT_AGENT', 'EXTERNAL AGENT'))
    )
    WHERE RECORD_ATTRIBUTES:"ai.observability.span_type"::STRING = 'record_root'
),
evals AS (
    SELECT
        RECORD_ATTRIBUTES:"snow.ai.observability.object.name"::STRING AS AGENT_NAME,
        RECORD_ATTRIBUTES:"ai.observability.eval.target_record_id"::STRING AS TARGET_RECORD_ID,
        CASE
            WHEN RECORD_ATTRIBUTES:"ai.observability.eval.metric_name"::STRING = 'answer_correctness' THEN 'correctness'
            ELSE RECORD_ATTRIBUTES:"ai.observability.eval.metric_name"::STRING
        END AS METRIC,
        RECORD_ATTRIBUTES:"ai.observability.eval_root.score"::FLOAT AS SCORE
    FROM (
        SELECT * FROM TABLE(SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS(
            'CUST_SUPPORT_DEMO', 'AGENTS', 'CORTEX_CUST_SUPPORT_AGENT', 'CORTEX AGENT'))
        UNION ALL
        SELECT * FROM TABLE(SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS(
            'CUST_SUPPORT_DEMO', 'AGENTS', 'LANGGRAPH_CUSTOMER_SUPPORT_AGENT', 'EXTERNAL AGENT'))
    )
    WHERE RECORD_ATTRIBUTES:"ai.observability.span_type"::STRING = 'eval_root'
      AND RECORD_ATTRIBUTES:"ai.observability.eval_root.score" IS NOT NULL
),
joined AS (
    SELECT r.USER_QUERY, e.METRIC, r.AGENT_NAME, AVG(e.SCORE) AS SCORE
    FROM roots r
    INNER JOIN evals e ON r.AGENT_NAME = e.AGENT_NAME AND r.RECORD_ID = e.TARGET_RECORD_ID
    GROUP BY 1, 2, 3
),
pivoted AS (
    SELECT
        USER_QUERY, METRIC,
        MAX(CASE WHEN AGENT_NAME = 'CORTEX_CUST_SUPPORT_AGENT' THEN SCORE END) AS CORTEX_SCORE,
        MAX(CASE WHEN AGENT_NAME = 'LANGGRAPH_CUSTOMER_SUPPORT_AGENT' THEN SCORE END) AS LANGGRAPH_SCORE
    FROM joined
    GROUP BY 1, 2
),
winners AS (
    SELECT METRIC,
        CASE
            WHEN CORTEX_SCORE > LANGGRAPH_SCORE THEN 'CORTEX_WIN'
            WHEN CORTEX_SCORE < LANGGRAPH_SCORE THEN 'LANGGRAPH_WIN'
            ELSE 'TIE'
        END AS OUTCOME
    FROM pivoted
    WHERE CORTEX_SCORE IS NOT NULL AND LANGGRAPH_SCORE IS NOT NULL
)
SELECT
    METRIC,
    COUNT(CASE WHEN OUTCOME = 'CORTEX_WIN' THEN 1 END) AS CORTEX_WINS,
    COUNT(CASE WHEN OUTCOME = 'LANGGRAPH_WIN' THEN 1 END) AS LANGGRAPH_WINS,
    COUNT(CASE WHEN OUTCOME = 'TIE' THEN 1 END) AS TIES,
    COUNT(*) AS TOTAL_QUERIES
FROM winners
GROUP BY METRIC
ORDER BY METRIC;
