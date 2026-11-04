# Flows and Power Platform setup

Everything runs in a Power Platform Developer environment (not *Default*). The data is in Dataverse; the flows are cloud flows in the solution
`Refund Process` with the prefix `rp`. Design and reasoning are in `README.md` ("Design decisions").

## Setup

1. **Developer Plan:** aka.ms/PowerAppsDevPlan; choose the developer environment at the top right of make.powerapps.com. Limits: 750 flow runs per month, 2 GB in Dataverse. Dataflows work in the developer environment (verified). An unmanaged developer environment is suspended on 15 December 2026.
2. **Solution:** `Refund Process` with the publisher prefix `rp`. All tables, flows and apps are created inside it, so they are included in the export.
3. **Connections:** four connection references in the solution: Dataverse, OneDrive for Business, Power Query Dataflows and Office 365 Outlook.
4. **Secrets:** no passwords or keys in the flows themselves. URLs and settings go into environment variables and connections into connection references (the solution has four), so the solution can move between environments.

**Export:** with `pac solution export` and `pac solution unpack` into `solution/RefundProcess` (see README, ALM). The zip file is not stored in Git. Data (rows) is not included, only the structure.
Check screenshots and the export before adding them to Git (email addresses, tenant and environment IDs).

## The flows

| Flow | Trigger | Role | Status |
|---|---|---|---|
| Dataflow `LoadWeeklyFiles` | Manual refresh (or `StartWeeklyLoad`) | Reads every `AP_Refunds_EventLog_*.csv` in OneDrive `incoming`, applies the quality rules, upserts `Event` and writes `Rejected Event`. See `docs/dataflow_load.md` | Built; 18 files loaded, counts verified |
| `StartWeeklyLoad` | New file in `incoming` | Checks the file name, then refreshes the dataflow; a wrong name goes to `failed` | Built; end-to-end run verified |
| `FinishWeeklyLoad` | Dataflow refresh completes | On success moves every file in `incoming` to `processed`, otherwise to `failed` | Built; triggered by the dataflow refresh in the same run |
| `ResetFile` | Manual | Deletes Event and Rejected Event rows for one file. Whole table: Bulk deletion in the admin center | Planned |
| `GetExchangeRates` | Manual or daily | Fetches the USD→ISK rate over HTTP and writes one row per day to Dataverse | Planned |
| `SetReviewedOn` | Dataverse: `Rejected Event` row modified (column Review Status) | Writes Reviewed On and Reviewed By when a reviewer changes the status. See `docs/review_app.md` | Built, partly tested: `Resolved` fills Reviewed On and Reviewed By, `Open` clears them. Not tested in bulk or with a second user |
| Approvals and notification | Dataverse event | Sends a flagged case to an approver and records the decision | Planned |

## Requirements for the load flow

- Accepts files named `AP_Refunds_EventLog_*.csv`; any other name is moved to `failed` before anything is loaded.
- Quality rules in this order: CaseId missing, unknown activity, unreadable timestamp, end before start, `InvoiceValue` not a number. Rows with `dd.mm.yyyy hh:mm` are fixed, not rejected. A rejected row goes to `Rejected Event` with its reason.
- Duplicates within a file (identical lines) are removed before the lines are parsed, and counted as "Duplicates Removed".
- Re-running a finished file changes nothing in `Event` (alternate key on `rp_eventkey`). `Rejected Event` is not idempotent: finished files must leave `incoming` (see `docs/dataflow_load.md`).
- Failures show in the run history of the flows and the refresh history of the dataflow, not only in a notification.
- A load costs a handful of flow actions however many files and rows it has, because the dataflow does the work.

## Testing

See `TESTS.md` (section "Power Platform"). Check every load with `dataverse_sql/load_checks.sql` and compare with `data/expected_rejections.csv`.

## Exchange rates (planned)

Source: the USD mid rate of the Central Bank of Iceland (series 4055). Which API to use is not decided.
The flow must fetch rates for the whole period (2022-07-01 to 2023-01-14) once, then daily from "today minus a few days",
and use the last rate on or before the event's date when a rate is missing (weekends and holidays).

## Apps and agent

- **Model-driven app** `Refund Rejected Review`: built, see `docs/review_app.md`.
- **Canvas app** `Case Decision` (decision on a flagged case): planned.
- **Copilot Studio** agent `Refund Rejected Assistant`: in progress, see `docs/copilot_agent.md`.
