-- ============================================================
-- CUST_SUPPORT_DEMO: Customer Support Agentic AI Demo Setup
-- ============================================================

-- 1. Database, Schema and grants

CREATE OR REPLACE DATABASE CUST_SUPPORT_DEMO;
CREATE SCHEMA CUST_SUPPORT_DEMO.AGENTS;
USE DATABASE CUST_SUPPORT_DEMO;
USE SCHEMA CUST_SUPPORT_DEMO.AGENTS;
USE WAREHOUSE COMPUTE_WH;

-- Create new role
CREATE OR REPLACE ROLE EVAL_ROLE;

-- Set current user (or change if running on behalf of a coworker)
SET AGENT_EVAL_USER = CURRENT_USER();

-- Grant role to user
GRANT ROLE EVAL_ROLE to USER IDENTIFIER($AGENT_EVAL_USER);

-- Usage on DB and Schema
GRANT USAGE ON DATABASE CUST_SUPPORT_DEMO TO ROLE EVAL_ROLE;
GRANT USAGE ON SCHEMA CUST_SUPPORT_DEMO.AGENTS TO ROLE EVAL_ROLE;
GRANT CREATE TABLE ON SCHEMA CUST_SUPPORT_DEMO.AGENTS TO ROLE EVAL_ROLE;
GRANT CREATE STAGE ON SCHEMA CUST_SUPPORT_DEMO.AGENTS TO ROLE EVAL_ROLE;


-- Specialized db/application roles
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE EVAL_ROLE;
GRANT APPLICATION ROLE SNOWFLAKE.AI_OBSERVABILITY_EVENTS_LOOKUP TO ROLE EVAL_ROLE;

-- Create Datasets
GRANT CREATE FILE FORMAT ON SCHEMA CUST_SUPPORT_DEMO.AGENTS TO ROLE EVAL_ROLE;
GRANT CREATE DATASET ON SCHEMA CUST_SUPPORT_DEMO.AGENTS TO ROLE EVAL_ROLE;

-- Create and execute tasks
GRANT CREATE TASK ON SCHEMA CUST_SUPPORT_DEMO.AGENTS TO ROLE EVAL_ROLE;
GRANT EXECUTE TASK ON ACCOUNT TO ROLE EVAL_ROLE;

-- Run evaluations
GRANT MONITOR ON FUTURE AGENTS IN SCHEMA CUST_SUPPORT_DEMO.AGENTS TO ROLE EVAL_ROLE;

-- Warehouse usage on COMPUTE_WH and on User's defualt WH (which is used for eval tasks)
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE EVAL_ROLE;

-- Git setup
GRANT CREATE API INTEGRATION ON ACCOUNT TO ROLE EVAL_ROLE;
GRANT CREATE GIT REPOSITORY ON SCHEMA CUST_SUPPORT_DEMO.AGENTS TO ROLE EVAL_ROLE;

-- Service and Agent creation
GRANT CREATE SEMANTIC VIEW ON SCHEMA CUST_SUPPORT_DEMO.AGENTS TO ROLE EVAL_ROLE;
GRANT CREATE CORTEX SEARCH SERVICE ON SCHEMA CUST_SUPPORT_DEMO.AGENTS TO ROLE EVAL_ROLE;
GRANT CREATE PROCEDURE ON SCHEMA CUST_SUPPORT_DEMO.AGENTS TO ROLE EVAL_ROLE;
GRANT CREATE AGENT ON SCHEMA CUST_SUPPORT_DEMO.AGENTS TO ROLE EVAL_ROLE;

USE ROLE EVAL_ROLE;


-- 2. Git Setup 

-- Create API integration for GitHub (public repo, no secrets needed)
CREATE OR REPLACE API INTEGRATION AGENT_OBS_DEMO_GIT_API_INTEGRATION
    API_PROVIDER = git_https_api
    API_ALLOWED_PREFIXES = ('https://github.com/sfc-gh-ebotwick/')
    ALLOWED_AUTHENTICATION_SECRETS = ALL
    ENABLED = TRUE;

-- Clone the GitHub repository
CREATE OR REPLACE GIT REPOSITORY AGENT_OBS_DEMO_GIT_REPO
    API_INTEGRATION = AGENT_OBS_DEMO_GIT_API_INTEGRATION
    GIT_CREDENTIALS = SANDBOX.PUBLIC.ELLIOTT_GIT_PAT_03_26 -- UPDATE TO PUBLIC REPO 
    ORIGIN = 'https://github.com/sfc-gh-ebotwick/AI_OBS_EXTERNAL_AND_CORTEX_AGENTS.git';

-- Fetch latest from GitHub
ALTER GIT REPOSITORY AGENT_OBS_DEMO_GIT_REPO FETCH;


-- 3. Tables
CREATE OR REPLACE TABLE SUPPORT_CASES (
    CASE_ID VARCHAR(20),
    CUSTOMER_ID VARCHAR(20),
    CASE_DATE DATE,
    PRODUCT VARCHAR(100),
    ISSUE_CATEGORY VARCHAR(100),
    ISSUE_SUMMARY VARCHAR(5000),
    RESOLUTION_SUMMARY VARCHAR(5000),
    REP_NAME VARCHAR(100),
    STATUS VARCHAR(50),
    PRIORITY VARCHAR(20)
);

CREATE OR REPLACE TABLE CASE_METRICS (
    CASE_ID VARCHAR(20),
    CUSTOMER_ID VARCHAR(20),
    CASE_DATE DATE,
    PRODUCT VARCHAR(100),
    ISSUE_CATEGORY VARCHAR(100),
    PRIORITY VARCHAR(20),
    FIRST_RESPONSE_TIME_MINS INTEGER,
    RESOLUTION_TIME_HOURS FLOAT,
    NUM_INTERACTIONS INTEGER,
    CSAT_SCORE FLOAT,
    ESCALATED INTEGER
);

CREATE OR REPLACE TABLE DAILY_SUPPORT_METRICS (
    METRIC_DATE DATE,
    TOTAL_CASES INTEGER,
    CASES_RESOLVED INTEGER,
    CASES_ESCALATED INTEGER,
    AVG_RESOLUTION_TIME_HOURS FLOAT,
    AVG_CSAT_SCORE FLOAT,
    AVG_FIRST_RESPONSE_MINS FLOAT
);

CREATE OR REPLACE TABLE REP_PERFORMANCE (
    REP_NAME VARCHAR(100),
    WEEK_START DATE,
    CASES_HANDLED INTEGER,
    CASES_RESOLVED INTEGER,
    AVG_RESOLUTION_TIME_HOURS FLOAT,
    AVG_CSAT_SCORE FLOAT,
    ESCALATION_RATE FLOAT
);

CREATE OR REPLACE TABLE EVAL_DATA (
    INPUT_QUERY TEXT,
    GROUND_TRUTH_DATA VARIANT);

-- 4. Load CSV data from git repo

-- First create a file format to use when reading data from github
CREATE OR REPLACE FILE FORMAT SUPPORT_AGENT_CSV_FORMAT
  TYPE = 'CSV'
  FIELD_DELIMITER = ','
  SKIP_HEADER = 1
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  COMPRESSION = 'AUTO';

-- Support Cases
INSERT INTO SUPPORT_CASES (CASE_ID, CUSTOMER_ID, CASE_DATE, PRODUCT, ISSUE_CATEGORY, ISSUE_SUMMARY, RESOLUTION_SUMMARY, REP_NAME, STATUS, PRIORITY)
SELECT $1, $2, $3, $4, $5, $6, $7, $8, $9, $10
FROM @AGENT_OBS_DEMO_GIT_REPO/branches/main/data/support_cases.csv (FILE_FORMAT=>SUPPORT_AGENT_CSV_FORMAT);

-- Case Metrics
INSERT INTO CASE_METRICS (CASE_ID, CUSTOMER_ID, CASE_DATE, PRODUCT, ISSUE_CATEGORY, PRIORITY, FIRST_RESPONSE_TIME_MINS, RESOLUTION_TIME_HOURS, NUM_INTERACTIONS, CSAT_SCORE, ESCALATED)
SELECT $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11
FROM @AGENT_OBS_DEMO_GIT_REPO/branches/main/data/case_metrics.csv (FILE_FORMAT=>SUPPORT_AGENT_CSV_FORMAT);

-- Daily Support metrics
INSERT INTO DAILY_SUPPORT_METRICS (METRIC_DATE, TOTAL_CASES, CASES_RESOLVED, CASES_ESCALATED, AVG_RESOLUTION_TIME_HOURS, AVG_CSAT_SCORE, AVG_FIRST_RESPONSE_MINS)
SELECT $1, $2, $3, $4, $5, $6, $7
FROM @AGENT_OBS_DEMO_GIT_REPO/branches/main/data/daily_support_metrics.csv (FILE_FORMAT=>SUPPORT_AGENT_CSV_FORMAT);

-- Rep performance
INSERT INTO REP_PERFORMANCE (REP_NAME, WEEK_START, CASES_HANDLED, CASES_RESOLVED, AVG_RESOLUTION_TIME_HOURS, AVG_CSAT_SCORE, ESCALATION_RATE)
SELECT $1, $2, $3, $4, $5, $6, $7
FROM @AGENT_OBS_DEMO_GIT_REPO/branches/main/data/support_rep_performance.csv (FILE_FORMAT=>SUPPORT_AGENT_CSV_FORMAT);

-- Eval data
INSERT INTO EVAL_DATA (INPUT_QUERY, GROUND_TRUTH)
SELECT $1, PARSE_JSON($2)
FROM @AGENT_OBS_DEMO_GIT_REPO/branches/main/data/eval_data.csv (FILE_FORMAT=>SUPPORT_AGENT_CSV_FORMAT);

-- 4b. Validate data

SELECT * FROM SUPPORT_CASES;

SELECT * FROM CASE_METRICS;

SELECT * FROM DAILY_SUPPORT_METRICS;

SELECT * FROM REP_PERFORMANCE;

SELECT * FROM EVAL_DATA;

-- 5. Semantic View (for Cortex Analyst structured data queries)
CALL SYSTEM$CREATE_SEMANTIC_VIEW_FROM_YAML(
    'CUST_SUPPORT_DEMO.AGENTS',
    $$
name: SUPPORT_ANALYTICS
description: >
  Semantic view for customer support analytics. Contains case-level metrics,
  daily aggregated support metrics, and agent performance data.

tables:
  - name: CASE_METRICS
    description: Per-case quantitative metrics including response times, resolution times, customer satisfaction scores, and escalation flags.
    base_table:
      database: CUST_SUPPORT_DEMO
      schema: AGENTS
      table: CASE_METRICS
    primary_key:
      columns:
        - CASE_ID
    dimensions:
      - name: CASE_ID
        description: Unique identifier for each support case
        expr: CASE_ID
        data_type: VARCHAR
        unique: true
      - name: CUSTOMER_ID
        synonyms:
          - customer
          - account
        description: Unique identifier for the customer who opened the case
        expr: CUSTOMER_ID
        data_type: VARCHAR
      - name: PRODUCT
        synonyms:
          - product name
          - application
        description: The product the support case is related to
        expr: PRODUCT
        data_type: VARCHAR
        is_enum: true
        sample_values:
          - CloudStore Platform
          - DataSync Pro
          - SecureVault
          - AnalyticsHub
          - API Gateway
      - name: ISSUE_CATEGORY
        synonyms:
          - category
          - issue type
          - problem type
        description: Category classification of the support issue
        expr: ISSUE_CATEGORY
        data_type: VARCHAR
        is_enum: true
        sample_values:
          - Login/Authentication
          - Performance
          - Billing
          - Data Loss
          - Integration
          - Feature Request
          - Configuration
          - Security
      - name: PRIORITY
        synonyms:
          - severity
          - urgency
        description: Priority level of the support case
        expr: PRIORITY
        data_type: VARCHAR
        is_enum: true
        sample_values:
          - Low
          - Medium
          - High
          - Critical
    time_dimensions:
      - name: CASE_DATE
        synonyms:
          - date
          - opened date
          - created date
        description: The date the support case was created
        expr: CASE_DATE
        data_type: DATE
    facts:
      - name: FIRST_RESPONSE_TIME_MINS
        synonyms:
          - first response time
          - initial response time
          - FRT
        description: Time in minutes from case creation to first rep response
        expr: FIRST_RESPONSE_TIME_MINS
        data_type: NUMBER
      - name: RESOLUTION_TIME_HOURS
        synonyms:
          - resolution time
          - time to resolve
          - TTR
        description: Time in hours from case creation to resolution
        expr: RESOLUTION_TIME_HOURS
        data_type: FLOAT
      - name: NUM_INTERACTIONS
        synonyms:
          - interactions
          - touchpoints
          - number of contacts
        description: Total number of interactions between rep and customer for this case
        expr: NUM_INTERACTIONS
        data_type: NUMBER
      - name: CSAT_SCORE
        synonyms:
          - satisfaction score
          - customer satisfaction
          - CSAT
        description: Customer satisfaction score on a 1-5 scale where 5 is highest
        expr: CSAT_SCORE
        data_type: FLOAT
      - name: ESCALATED_FLAG
        synonyms:
          - escalated
          - was escalated
        description: Flag indicating whether the case was escalated (1=yes, 0=no)
        expr: ESCALATED
        data_type: NUMBER
    metrics:
      - name: TOTAL_CASES
        synonyms:
          - case count
          - number of cases
          - case volume
        description: Total number of support cases
        expr: COUNT(CASE_METRICS.CASE_ID)
      - name: AVG_FIRST_RESPONSE_TIME
        synonyms:
          - average first response
          - mean FRT
        description: Average first response time in minutes across cases
        expr: AVG(CASE_METRICS.FIRST_RESPONSE_TIME_MINS)
      - name: AVG_RESOLUTION_TIME
        synonyms:
          - average resolution time
          - mean resolution time
          - mean TTR
        description: Average resolution time in hours across cases
        expr: AVG(CASE_METRICS.RESOLUTION_TIME_HOURS)
      - name: AVG_CSAT
        synonyms:
          - average satisfaction
          - average CSAT score
          - mean CSAT
        description: Average customer satisfaction score (1-5 scale)
        expr: AVG(CASE_METRICS.CSAT_SCORE)
      - name: ESCALATION_RATE
        synonyms:
          - escalation percentage
          - pct escalated
        description: Percentage of cases that were escalated
        expr: AVG(CASE_METRICS.ESCALATED_FLAG)
      - name: AVG_INTERACTIONS
        synonyms:
          - average interactions
          - mean touchpoints
        description: Average number of interactions per case
        expr: AVG(CASE_METRICS.NUM_INTERACTIONS)

  - name: DAILY_SUPPORT_METRICS
    description: Daily aggregated support metrics showing volume, resolution, and quality trends over time.
    base_table:
      database: CUST_SUPPORT_DEMO
      schema: AGENTS
      table: DAILY_SUPPORT_METRICS
    primary_key:
      columns:
        - METRIC_DATE
    time_dimensions:
      - name: METRIC_DATE
        synonyms:
          - date
          - day
          - report date
        description: The calendar date for the aggregated metrics
        expr: METRIC_DATE
        data_type: DATE
    facts:
      - name: TOTAL_CASES
        synonyms:
          - daily cases
          - case volume
        description: Total number of cases received on this date
        expr: TOTAL_CASES
        data_type: NUMBER
      - name: CASES_RESOLVED
        synonyms:
          - resolved cases
          - cases closed
        description: Number of cases resolved on this date
        expr: CASES_RESOLVED
        data_type: NUMBER
      - name: CASES_ESCALATED
        synonyms:
          - escalated cases
        description: Number of cases escalated on this date
        expr: CASES_ESCALATED
        data_type: NUMBER
      - name: AVG_RESOLUTION_TIME_HOURS
        description: Average resolution time in hours for this date
        expr: AVG_RESOLUTION_TIME_HOURS
        data_type: FLOAT
      - name: AVG_CSAT_SCORE
        description: Average CSAT score for this date
        expr: AVG_CSAT_SCORE
        data_type: FLOAT
      - name: AVG_FIRST_RESPONSE_MINS
        description: Average first response time in minutes for this date
        expr: AVG_FIRST_RESPONSE_MINS
        data_type: FLOAT
    metrics:
      - name: SUM_DAILY_CASES
        synonyms:
          - total daily cases
        description: Sum of all daily case counts
        expr: SUM(DAILY_SUPPORT_METRICS.TOTAL_CASES)
      - name: SUM_DAILY_RESOLVED
        synonyms:
          - total resolved
        description: Sum of all daily resolved case counts
        expr: SUM(DAILY_SUPPORT_METRICS.CASES_RESOLVED)
      - name: DAILY_AVG_CSAT
        synonyms:
          - average daily CSAT
        description: Average of the daily CSAT scores
        expr: AVG(DAILY_SUPPORT_METRICS.AVG_CSAT_SCORE)
      - name: DAILY_AVG_RESOLUTION_TIME
        description: Average of the daily resolution times in hours
        expr: AVG(DAILY_SUPPORT_METRICS.AVG_RESOLUTION_TIME_HOURS)

  - name: REP_PERFORMANCE
    description: Weekly rep performance metrics including cases handled, resolution rates, satisfaction, and escalation rates.
    base_table:
      database: CUST_SUPPORT_DEMO
      schema: AGENTS
      table: REP_PERFORMANCE
    dimensions:
      - name: REP_NAME
        synonyms:
          - rep
          - support rep
          - agent
          - representative
        description: Name of the support rep
        expr: REP_NAME
        data_type: VARCHAR
    time_dimensions:
      - name: WEEK_START
        synonyms:
          - week
          - week beginning
          - week of
        description: Start date of the performance week
        expr: WEEK_START
        data_type: DATE
    facts:
      - name: CASES_HANDLED
        synonyms:
          - cases worked
          - tickets handled
        description: Number of cases handled by the rep in the week
        expr: CASES_HANDLED
        data_type: NUMBER
      - name: CASES_RESOLVED
        synonyms:
          - cases closed
          - tickets resolved
        description: Number of cases resolved by the rep in the week
        expr: CASES_RESOLVED
        data_type: NUMBER
      - name: AVG_RESOLUTION_TIME_HOURS
        description: Average resolution time in hours for the rep that week
        expr: AVG_RESOLUTION_TIME_HOURS
        data_type: FLOAT
      - name: AVG_CSAT_SCORE
        description: Average CSAT score for the rep that week
        expr: AVG_CSAT_SCORE
        data_type: FLOAT
      - name: ESCALATION_RATE
        description: Fraction of cases escalated by the rep that week
        expr: ESCALATION_RATE
        data_type: FLOAT
    metrics:
      - name: TOTAL_REP_CASES
        synonyms:
          - total handled
        description: Total cases handled by rep
        expr: SUM(REP_PERFORMANCE.CASES_HANDLED)
      - name: TOTAL_REP_RESOLVED
        description: Total cases resolved by rep
        expr: SUM(REP_PERFORMANCE.CASES_RESOLVED)
      - name: REP_AVG_CSAT
        synonyms:
          - rep satisfaction
        description: Average CSAT across all weeks for the rep
        expr: AVG(REP_PERFORMANCE.AVG_CSAT_SCORE)
      - name: REP_AVG_RESOLUTION_TIME
        description: Average resolution time across all weeks for the rep
        expr: AVG(REP_PERFORMANCE.AVG_RESOLUTION_TIME_HOURS)
      - name: REP_AVG_ESCALATION_RATE
        synonyms:
          - rep escalation rate
        description: Average escalation rate across all weeks for the rep
        expr: AVG(REP_PERFORMANCE.ESCALATION_RATE)

verified_queries:
  - name: total_cases_by_product
    question: How many support cases were there for each product?
    use_as_onboarding_question: true
    sql: |
      SELECT PRODUCT, COUNT(*) AS TOTAL_CASES
      FROM CUST_SUPPORT_DEMO.AGENTS.CASE_METRICS
      GROUP BY PRODUCT
      ORDER BY TOTAL_CASES DESC
  - name: avg_csat_by_category
    question: What is the average CSAT score by issue category?
    use_as_onboarding_question: true
    sql: |
      SELECT ISSUE_CATEGORY, AVG(CSAT_SCORE) AS AVG_CSAT
      FROM CUST_SUPPORT_DEMO.AGENTS.CASE_METRICS
      GROUP BY ISSUE_CATEGORY
      ORDER BY AVG_CSAT DESC
  - name: top_reps_by_volume
    question: Which reps handled the most cases?
    use_as_onboarding_question: true
    sql: |
      SELECT REP_NAME, SUM(CASES_HANDLED) AS TOTAL_CASES
      FROM CUST_SUPPORT_DEMO.AGENTS.REP_PERFORMANCE
      GROUP BY REP_NAME
      ORDER BY TOTAL_CASES DESC
  - name: escalation_rate_by_priority
    question: What is the escalation rate for each priority level?
    sql: |
      SELECT PRIORITY, AVG(ESCALATED) AS ESCALATION_RATE
      FROM CUST_SUPPORT_DEMO.AGENTS.CASE_METRICS
      GROUP BY PRIORITY
      ORDER BY ESCALATION_RATE DESC
  - name: daily_trend
    question: Show me the daily trend of total cases and average CSAT
    sql: |
      SELECT METRIC_DATE, TOTAL_CASES, AVG_CSAT_SCORE
      FROM CUST_SUPPORT_DEMO.AGENTS.DAILY_SUPPORT_METRICS
      ORDER BY METRIC_DATE
$$
);

-- 6. Cortex Search Service (for unstructured case detail lookups)
CREATE OR REPLACE CORTEX SEARCH SERVICE CASE_SEARCH_SERVICE
    ON ISSUE_SUMMARY
    ATTRIBUTES CASE_ID, CUSTOMER_ID, PRODUCT, ISSUE_CATEGORY, PRIORITY, STATUS, REP_NAME
    WAREHOUSE = COMPUTE_WH
    TARGET_LAG = '1 hour'
    AS (
        SELECT
            CASE_ID,
            CUSTOMER_ID,
            CASE_DATE,
            PRODUCT,
            ISSUE_CATEGORY,
            ISSUE_SUMMARY || ' Resolution: ' || RESOLUTION_SUMMARY AS ISSUE_SUMMARY,
            RESOLUTION_SUMMARY,
            REP_NAME,
            STATUS,
            PRIORITY
        FROM CUST_SUPPORT_DEMO.AGENTS.SUPPORT_CASES
    );

-- 7. Cortex Agent (ties Analyst + Search together)
CREATE OR REPLACE AGENT SUPPORT_AGENT
    COMMENT = 'Customer Support AI Agent - answers questions about support metrics, case details, and support rep performance'
    FROM SPECIFICATION $$
models:
  orchestration: auto
instructions:
  response: >
    You are a helpful customer support analytics assistant. Answer questions about support case
    metrics, rep performance, daily trends, and specific case details. Be concise and data-driven.
    When presenting numbers, use appropriate formatting. When asked about specific cases or issues,
    search the case database for relevant details.
  orchestration: >
    For quantitative questions about metrics, trends, counts, averages, or comparisons, use the
    SupportAnalytics tool to query structured data. For questions about specific case details,
    issue descriptions, resolution steps, or searching for cases by topic, use the CaseSearch tool.
    If a question involves both metrics and case details, use both tools.
  sample_questions:
    - question: "What is the average CSAT score by product?"
      answer: "I'll query the support analytics data to get average CSAT scores broken down by product."
    - question: "Find cases related to authentication issues"
      answer: "I'll search the case database for cases involving authentication problems."
    - question: "Which rep has the best resolution time?"
      answer: "I'll look at the rep performance data to find who has the fastest average resolution times."
    - question: "Show me the trend of daily escalations"
      answer: "I'll query the daily support metrics to show the escalation trend over time."
tools:
  - tool_spec:
      type: "cortex_analyst_text_to_sql"
      name: "SupportAnalytics"
      description: >
        Use this tool for quantitative questions about support metrics. This includes case counts,
        average CSAT scores, resolution times, first response times, escalation rates, rep
        performance comparisons, daily/weekly trends, and breakdowns by product, category, priority,
        or rep. Use this for any question that requires aggregation, filtering, or numerical analysis.
  - tool_spec:
      type: "cortex_search"
      name: "CaseSearch"
      description: >
        Use this tool to search for specific support case details, issue descriptions, and resolution
        summaries. Use this when the user asks about specific issues, wants to find cases by topic
        or keyword, needs resolution steps for a type of problem, or asks about what happened in
        specific cases. This searches the full text of issue and resolution summaries.
tool_resources:
  SupportAnalytics:
    semantic_view: "CUST_SUPPORT_DEMO.AGENTS.SUPPORT_ANALYTICS"
    execution_environment:
      query_timeout: 299
      type: warehouse
      warehouse: COMPUTE_WH
  CaseSearch:
    name: "CUST_SUPPORT_DEMO.AGENTS.CASE_SEARCH_SERVICE"
    max_results: "5"
    execution_environment:
      query_timeout: 299
      type: warehouse
      warehouse: COMPUTE_WH
$$;

-- 7. Run Evaluations

-- GRANT EXECUTE TASK ON ACCOUNT TO ROLE ACCOUNTADMIN;
-- GRANT MONITOR ON FUTURE AGENTS IN SCHEMA CUST_SUPPORT_DEMO.AGENTS TO ROLE ACCOUNTADMIN;
-- GRANT CREATE DATASET ON SCHEMA CUST_SUPPORT_DEMO.AGENTS TO ROLE ACCOUNTADMIN;

-- -- Create and execute tasks
-- GRANT CREATE TASK ON SCHEMA CUST_SUPPORT_DEMO.AGENTS TO ROLE ACCOUNTADMIN;

SELECT * FROM CUST_SUPPORT_DEMO.AGENTS.EVAL_DATA;

-- First we will create a dataset to use for evaluating our agent
CALL SYSTEM$CREATE_EVALUATION_DATASET(
    'Cortex Agent',
    'CUST_SUPPORT_DEMO.AGENTS.EVAL_DATA',
    'CUST_SUPPORT_DEMO.AGENTS.AGENTS_AGENT_EVAL_DATASET',
    OBJECT_CONSTRUCT('query_text', 'INPUT_QUERY', 'expected_tools', 'GROUND_TRUTH_DATA'));



-- Confirm dataset creation
SHOW DATASETS IN SCHEMA CUST_SUPPORT_DEMO.AGENTS;
-- Next we will create a stage to store our evaluation config file
CREATE OR REPLACE STAGE CUST_SUPPORT_DEMO.AGENTS.EVAL_CONFIG_STAGE
  DIRECTORY = (ENABLE = TRUE)
  COMMENT = 'Internal stage to host evaluation config files';

-- Upload the support_agent_eval_config.yaml file to the stage
COPY FILES INTO @CUST_SUPPORT_DEMO.AGENTS.EVAL_CONFIG_STAGE
FROM @AGENT_OBS_DEMO_GIT_REPO/branches/main/
FILES = ('support_agent_eval_config.yaml');

-- Confirm yaml was uploaded
LS @CUST_SUPPORT_DEMO.AGENTS.EVAL_CONFIG_STAGE;


USE SCHEMA CUST_SUPPORT_DEMO.AGENTS;

-- Kickoff evaluation run using yaml config
CALL EXECUTE_AI_EVALUATION(
  'START',
  OBJECT_CONSTRUCT('run_name', 'SUPPORT_AGENT_CORTEX_EVAL_RUN_V3'),
  '@CUST_SUPPORT_DEMO.AGENTS.EVAL_CONFIG_STAGE/support_agent_eval_config.yaml'
);

-- Check run status
CALL EXECUTE_AI_EVALUATION(
  'STATUS',
  OBJECT_CONSTRUCT('run_name', 'SUPPORT_AGENT_CORTEX_EVAL_RUN_V2'),
  '@CUST_SUPPORT_DEMO.AGENTS.EVAL_CONFIG_STAGE/support_agent_eval_config.yaml'
);

SHOW GRANTS TO ROLE EVAL_ROLE;