/* Load checks on Dataverse, through its SQL (TDS) endpoint: read-only SELECTs that cost no flow actions.
   Run in SSMS after every load. rp_sourcefile is confirmed (the OData query on it worked).
   Per-file counts (as in query 2) have been run; queries 1 and 3 have not.

-- 1. Same event twice. Must return no rows: the alternate key on rp_eventkey makes a second copy impossible,
--    so any row here means the key is missing or inactive.
SELECT rp_eventkey, COUNT(*) AS Copies
FROM rp_event
GROUP BY rp_eventkey
HAVING COUNT(*) > 1;

-- 2. Rows per loaded file. Compare with data/expected_rejections.csv (_Rows read minus all rejections, duplicates included)
--    and, once the Load Log table exists, with its Rows Read column.
SELECT rp_sourcefile AS SourceFile, COUNT(*) AS EventsLoaded
FROM rp_event
GROUP BY rp_sourcefile
ORDER BY rp_sourcefile;

-- 3. Events with no source file. Must return no rows: such a row cannot be traced to a load.
SELECT COUNT(*) AS WithoutSourceFile
FROM rp_event
WHERE rp_sourcefile IS NULL OR rp_sourcefile = N'';
