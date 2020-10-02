@derived_cohort_table_create

DELETE FROM @cohort_database_schema.@cohort_table
WHERE cohort_definition_id IN (SELECT cohort_id FROM #DERIVED_COHORT_XREF)
;

INSERT INTO @cohort_database_schema.@cohort_table (
  cohort_definition_id,
  subject_id,
  cohort_start_date,
  cohort_end_date
)
SELECT 
  x.cohort_id,
  c.subject_id,
  c.cohort_start_date,
  c.cohort_end_date
FROM (
  SELECT 
    cst.cohort_definition_id,
    cst.subject_id,
    cst.cohort_start_date,
    cst.cohort_end_date,
    ROW_NUMBER() OVER (PARTITION BY cohort_definition_id, subject_id, cohort_start_date) rn
  FROM @cohort_database_schema.@cohort_table cst
  JOIN @cdm_database_schema.observation_period OP on cst.subject_id = OP.person_id 
    and cst.cohort_start_date >=  OP.observation_period_start_date 
    and cst.cohort_start_date <= op.observation_period_end_date
  WHERE DATEADD(day,365,OP.OBSERVATION_PERIOD_START_DATE) <= cst.cohort_start_date 
) c
INNER JOIN #DERIVED_COHORT_XREF x ON x.target_id = c.cohort_definition_id
WHERE c.rn = 1
;

@derived_cohort_table_drop