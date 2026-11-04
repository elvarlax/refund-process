# Tests

Tick a test when it passes.
Screenshots of results (run history, refresh history) go in `docs/screenshots/`.

## SQL on Dataverse (SSMS)

Read-only queries run in SSMS against the Dataverse SQL (TDS) endpoint.

| ✓ | Part | Test | Expected |
|---|---|---|---|
| ☐ | `dataverse_sql/flags.sql` | Run on Dataverse | 247 cases with 2+ rejections and 139 with a wait over 24 h before approval (weekly files); P90 in DAX |

## Power Platform

These tests cover Dataverse and the bulk load. The expected numbers are computed outside the repository from `data/weekly/` and
`data/expected_rejections.csv`, not measured in Power Automate. The test file `AP_Refunds_EventLog_TEST-small.csv` is not in Git.

| ✓ | Layer | Part | Test | Expected |
|---|---|---|---|---|
| ☑ | 1 | Dataflow | W35 to W39 and W41 to W52 loaded with `LoadWeeklyFiles` | Event rows per file and Rejected Event rows per file equal `data/expected_rejections.csv` for all 17 files (confirmed with SQL on Dataverse: 18,021 and 120 in total, without W40) |
| ☐ | 1 | Dataflow | Refresh run again with the files still in `incoming` | Event unchanged (upsert); Rejected Event doubles for those files: known limit, see `docs/dataflow_load.md` |
| ☑ | 1 | Flows | W40 and a small test file (`AP_Refunds_EventLog_2022-W53.csv`: 4 valid rows, 1 duplicate, 1 unknown activity) dropped in `incoming` with both cloud flows on | `StartWeeklyLoad` refreshes the dataflow, `FinishWeeklyLoad` moves the files to `processed`. Confirmed with SQL on Dataverse: Event 19,180 (W40 1,155, W53 4), Rejected Event 126 (W40 5, W53 1 Unknown activity), no doubled rows. The W53 test rows are deleted afterwards (Source File = the test file) |
| ☐ | 1 | Flows | A move that fails in `FinishWeeklyLoad` (a path that does not exist) | `Handle failure` runs, a notification arrives, the run shows *Failed*; retry tried 3 times before |
| ☑ | 1 | Flows | `StartWeeklyLoad` after the condition and error-handling changes: `AP_Refunds_EventLog_2022-W54.csv` dropped in `incoming` | Seen in run history: condition true, `Process files` and `Refresh LoadWeeklyFiles` succeeded, `Handle failure` and `Move file to failed` skipped. Dataflow refresh details (seen): `EventsValid` 3 created, `EventsInvalid` 1 created, 0 updated, 0 failed. Row counts seen with SQL against Dataverse: Event 19,176 → 19,179 (3 rows with the W54 source file), Rejected Event 125 → 126 (1 row). `FinishWeeklyLoad` run and the `processed` folder not checked yet. The W54 rows were deleted afterwards, so the counts are back at 19,176 and 125 |
| ☐ | 1 | Flows | `StartWeeklyLoad`: a file with an invalid name (for example `report.csv`) dropped in `incoming` | The condition is false, the file moves to `failed`, no refresh starts (condition rewritten, not retested since) |
| ☐ | 1 | Flows | `StartWeeklyLoad`: the refresh action fails (dataflow name changed on purpose) | `Handle failure` runs: the email arrives, the run shows *Failed* (`LoadFailed`); the file stays in `incoming` |
| ☐ | 2 | Copilot Studio | Test set in `docs/copilot_agent.md` (9 questions) | Not run |
| ☑ | 2 | OData | Four queries in `docs/odata_example.md` | Run in the browser: 25, 35/36/29/25 and 1213 as listed; `$apply` works (JSON seen) |
| ☑ | 1 | Dataflow | W35 and W36 loaded | W35: 950 valid, 8 rejected; W36: 1,213 valid, 8 rejected (duplicates removed, not rejected) |
| ☑ | 1 | Flow | Flow checker (Power Automate) on `StartWeeklyLoad`, `FinishWeeklyLoad` and `SetReviewedOn` (after the error-handling changes) | Errors 0, warnings 0 in all three (screenshots seen). `SetReviewedOn` has no error handling yet |
| ☑ | 1 | Solution | Solution checker on `Refund Process` (run after the flow changes) | Issues found 0 (Critical 0, High 0, Medium 0, Low 0). The overview also says that 1 environment variable needs a value: `rp_OneDriveSiteURL` has no default on purpose, so a value is asked for at import |
| ☐ | 1 | Dataverse | `dataverse_sql/load_checks.sql`, query 1 | No duplicate `rp_eventkey` |
| ☐ | 1 | Dataverse | Test file removed with Bulk deletion (`Source File` = name) | 0 rows for the file |
| ☐ | 2 | Model-driven app | Load a small test file with rejected rows | The rejected rows have Review Status `Open` without the dataflow mapping the column (default value applied) |
| ☐ | 2 | Model-driven app | Open `Refund Rejected Review` → Rejected rows → *Open rows* | Only `Open` and `In review` rows, sorted by Source File Name; source columns read-only |
| ☑ | 2 | Model-driven app | Backfill: select all in *All rejected rows*, bulk edit Review Status = Open; `SELECT rp_reviewstatus, COUNT(*) FROM rp_rejectedevent GROUP BY rp_reviewstatus;` | All rows `Open` |
| ☑ | 2 | Business rule | Set a row to `Ignored` with an empty Review Note on the form | Error "Write why this row is ignored."; the row is not saved |
| ☐ | 2 | Business rule | The same change in the editable grid, in a bulk edit, and through an Excel import | Blocked in each, or documented as not blocked (then fixed or accepted). Bulk edit: blocked. Editable grid and Excel import: not tested |
| ☐ | 2 | Business rule | Set a row to `Ignored` with a note | Saved |
| ☑ | 2 | Flow | Change Review Status to `Resolved` on one row | Reviewed On and Reviewed By filled (seen on two rows; the run count was not checked) |
| ☑ | 2 | Flow | Set the row back to `Open` | Reviewed On and Reviewed By empty (seen on two rows; first version failed: the formatted-value label was empty; fixed by comparing the option number) |
| ☐ | 2 | Flow | Check run history for the same row | Exactly 2 runs, both Succeeded, no self-trigger (not checked yet) |
| ☐ | 2 | Security | *Check access* for a user with `Refund Reviewer` | Read and Write on Rejected Event, Read on Event and Step, no Create and no Delete |
| ☐ | 2 | Security | A user with `Refund Reviewer` tries to delete a row, and to open the app without any role | Delete not possible; no access to the app without a role |
| ☐ | 2 | Security | A user with `Refund Admin` | Can create, change and delete on the three tables |
| ☐ | 2 | Model-driven app | After a refresh with a file already reviewed (see `docs/dataflow_load.md`, known limits) | Documents the duplicate `Open` rows until Rejected Event is idempotent |
| ☐ | 3 | Power BI | Numbers in Power BI compared with `dataverse_sql/flags.sql` | Same numbers |
