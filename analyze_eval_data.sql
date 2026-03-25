SELECT *
FROM TABLE(SNOWFLAKE.LOCAL.GET_AI_EVALUATION_DATA(
    'CUST_SUPPORT_DEMO',
    'SUPPORT',
    'SUPPORT_AGENT',
    'cortex agent',
    'a'
));



SELECT * FROM TABLE(
    SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS(
    'CUST_SUPPORT_DEMO',
    'SUPPORT',
    'SUPPORT_AGENT',
    'cortex agent'
    ) );
-- WHERE RECORD_ATTRIBUTES:"snow.ai.observability.run.name" = 'a';