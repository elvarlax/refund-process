# OData query against the Dataverse Web API

Status: **all four queries run, JSON seen.** `rp_rejectedevents` with `$top` and `$select` returned three rows with `rp_errorreason` and `rp_sourcefilename` plus the row id and the ETag (the ids are not copied here). The environment URL is a placeholder (`<org>`); the real one is not stored in Git.

Dataverse exposes its tables as an OData v4 service. The same data that `dataverse_sql/load_checks.sql` reads over SQL can be read as JSON over REST.

## 1 · Find the names

- Table `Rejected Event` has the logical name `rp_rejectedevent`. The **entity set name** (used in the URL) is `rp_rejectedevents` (confirmed: the request below worked).
- The service document is at `https://<org>.crm4.dynamics.com/api/data/v9.2/` (the `crm4` part is the region of this environment, Europe; other regions use another number, so copy the host from your own environment) and `.../$metadata` lists every table and column.

## 2 · Queries

Run in a browser tab where you are signed in to the environment (a GET in the address bar uses the signed-in session). The result is JSON.

| Purpose | Request | Expected |
|---|---|---|
| Five rejected rows with their reason | `/api/data/v9.2/rp_rejectedevents?$select=rp_sourcefilename,rp_errorreason&$top=5` | 5 objects with the two columns. **Run (a variant with `$top=3`), worked** |
| Count of rows with an unknown activity | `/api/data/v9.2/rp_rejectedevents?$filter=rp_errorreason eq 'Unknown activity'&$count=true&$select=rp_errorreason` | `@odata.count` = 25 (after W35 to W52). **Run, `@odata.count` = 25** |
| Rows per reason | `/api/data/v9.2/rp_rejectedevents?$apply=groupby((rp_errorreason),aggregate($count as total))` | 35, 36, 29 and 25 rows for the four reasons (125 in total). **Run, `$apply` works: 35, 36, 29, 25** |
| One file | `/api/data/v9.2/rp_events?$filter=rp_sourcefile eq 'AP_Refunds_EventLog_2022-W36.csv'&$count=true&$select=rp_eventkey` | `@odata.count` = 1213. **Run, `@odata.count` = 1213** |

Notes: Dataverse returns at most 5,000 rows per page and then gives `@odata.nextLink`; follow it. `$apply` (grouping) worked on `rp_rejectedevents`; it is not supported for every table feature, so if it returns an error on another table, use the FetchXML aggregate or the SQL endpoint.

## 3 · The same filter in a flow

In a cloud flow the Dataverse action *List rows* takes the OData syntax directly: **Filter rows** `rp_errorreason eq 'Unknown activity'`, **Select columns**
`rp_sourcefilename,rp_errorreason`. The count is `length(outputs('List_rows')?['body/value'])`.

## 4 · Not covered

A custom connector (an OpenAPI description of these calls, with authentication by Microsoft Entra ID) is planned, not built.
