/* Flags on Dataverse, through its SQL (TDS) endpoint. Read-only SELECT statements, written for the subset that endpoint supports:
   no CTE (WITH), no OVER, no window, ranking or analytic functions (Microsoft Learn: "How Dataverse SQL differs from Transact-SQL").
   GROUP BY, HAVING, UNION, joins and nested queries are supported.
   Run in SSMS connected to the Dataverse environment (Entra ID authentication).

   Rule 3 (cycle time above P90) needs PERCENTILE_CONT, which the endpoint
   does not have: query 2 below returns cycle days per case, and the P90 comparison is done in DAX (powerbi/flags_and_kpi.dax).
   The previous step is found with nested queries instead of LAG. Not yet run on the Dataverse endpoint. Dataverse stores no fractions of a second,
   so a borderline case can differ. */

-- 1. Rule 1 (2+ rejections) and rule 2 (wait before approval over 24 hours). Value = rejections, or hours.
SELECT rp_caseidentifier AS CaseId, N'Rejected 2+ times' AS Reason, CONVERT(decimal(12,2), COUNT(*)) AS Value
FROM rp_event
WHERE rp_activityname = N'Reject Invoice'
GROUP BY rp_caseidentifier
HAVING COUNT(*) >= 2
UNION ALL
SELECT w.CaseId, N'Wait before approval > 24 h', CONVERT(decimal(12,2), MAX(w.WaitSeconds) / 3600.0)
FROM (
    SELECT a.rp_caseidentifier AS CaseId,
           DATEDIFF(SECOND,
                    (SELECT MAX(p.rp_endtimestamp) FROM rp_event AS p
                     WHERE p.rp_caseidentifier = a.rp_caseidentifier
                       AND p.rp_starttimestamp = (SELECT MAX(x.rp_starttimestamp) FROM rp_event AS x
                                                  WHERE x.rp_caseidentifier = a.rp_caseidentifier
                                                    AND x.rp_starttimestamp < a.rp_starttimestamp)),
                    a.rp_starttimestamp) AS WaitSeconds
    FROM rp_event AS a
    WHERE a.rp_activityname = N'Approve Invoice'
) AS w
WHERE w.WaitSeconds IS NOT NULL
GROUP BY w.CaseId
HAVING MAX(w.WaitSeconds) > 24 * 3600;

-- 2. Cycle days per case, and whether the case has an approval (the path). The P90 per path is computed in DAX.
SELECT c.CaseId, c.CycleDays, IIF(ap.CaseId IS NULL, N'Payment check', N'Approval') AS ProcessPath
FROM (
    SELECT rp_caseidentifier AS CaseId,
           DATEDIFF(SECOND, MIN(rp_starttimestamp), MAX(rp_endtimestamp)) / 86400.0 AS CycleDays
    FROM rp_event
    GROUP BY rp_caseidentifier
) AS c
LEFT JOIN (
    SELECT DISTINCT rp_caseidentifier AS CaseId FROM rp_event WHERE rp_activityname = N'Approve Invoice'
) AS ap ON ap.CaseId = c.CaseId;
