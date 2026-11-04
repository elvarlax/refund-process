# Weekly load with a dataflow and two cloud flows

Status: the **load** is built and verified. All 18 files (W35 to W52) were loaded by the dataflow `LoadWeeklyFiles` and the counts in Dataverse
match `data/expected_rejections.csv` for every one of them (see `TESTS.md`). The **automation** (cloud flows `StartWeeklyLoad` and `FinishWeeklyLoad`)
ran end to end: a new file in `incoming` started the dataflow and the file was moved afterwards. Counts checked with SQL on
Dataverse: Event 19,180 and Rejected Event 126 after W40 and a small test file (`TESTS.md`).

## Design

```
OneDrive  RefundProcess/incoming
   │  new file AP_Refunds_EventLog_*.csv
   ▼
Cloud flow StartWeeklyLoad ── name check ──► refresh dataflow LoadWeeklyFiles
                                                   │  reads every file in incoming
                                                   ▼
                                  EventsValid ──► Event (upsert on rp_eventkey)
                                  EventsInvalid ► Rejected Event
                                                   │
Cloud flow FinishWeeklyLoad ◄── "dataflow refresh completes"
   ├─ Refresh Status = Success ─► every file in incoming  → processed
   └─ otherwise                 ─► every file in incoming  → failed
```

- **Dataflow** (Power Platform dataflow, Standard V2, in the solution `Refund Process`): reads, validates and loads in one refresh. No row-by-row
  actions, so a load costs a handful of flow actions however many rows the files have.
- **Cloud flows** only orchestrate: start the refresh, then move the files. Two flows because *Refresh a dataflow* does not wait for the refresh
  to finish; the trigger *When a dataflow refresh completes* does.
- **Folders:** `incoming` (waiting), `processed` (loaded), `failed` (rejected by the name check, or the refresh failed).

## The dataflow `LoadWeeklyFiles`

Four queries. The OneDrive site URL contains a user name and is not stored in Git: use a placeholder here and an environment variable
(`rp_OneDriveSiteURL`, created in the solution with an empty default value and no current value; no flow or dataflow reads it yet) in the solution.

| Query | Role | Loaded to |
|---|---|---|
| `RawEvents` | Reads every `AP_Refunds_EventLog_*.csv` under `/RefundProcess/incoming/`, adds `SourceFile` (the file name) | Not loaded |
| `Events` | Removes identical lines, normalises `dd.mm.yyyy` timestamps to `yyyy-MM-dd HH:mm:ss`, builds `EventKey` (`CaseId\|Activity\|Start`), adds `Reason` | Not loaded |
| `EventsValid` | `Reason` empty, one row per `EventKey`, typed columns | Table `Event`, key `rp_eventkey` (upsert) |
| `EventsInvalid` | `Reason` not empty, with `RawEventData` and a generated id | Table `Rejected Event` |

Quality rules, in this order: CaseId missing, unknown activity, unreadable timestamp,
end before start, `InvoiceValue` not a number. Rows with `dd.mm.yyyy hh:mm` are fixed, not rejected. The 13 valid activities are written in the
`Steps` list of the `Events` query (a lookup against the `Step` table is a later improvement).

Settings that matter:

- *Load to existing table*; for `Event` the primary key is the alternate key `Event Key (rp_eventkey)`, so a re-run updates rows instead of adding them.
- **Delete rows that no longer exist** stays unchecked on both tables.
- Do not detect data types, and remove the automatic *Changed column type* step: automatic typing changed timestamps and CaseId.
- Dataverse stores no fractions of a second, so timestamps are cut at 19 characters.
- `Text.NewGuid()` is evaluated once per query, so every row would get the same id. `EventsInvalid` builds the id as the first 24 characters of one
  GUID plus a 12-digit row index. The id is therefore **new on every refresh**.

## Known limits (read before re-running)

- **Rejected Event is not idempotent.** Event is (alternate key); Rejected Event is not, because its id is generated. Refreshing twice while the
  same file is still in `incoming` doubles that file's rejected rows. This is why files must leave `incoming` after every refresh.
- **The dataflow reads every file in `incoming`, not only the one that triggered the run.** `FinishWeeklyLoad` therefore moves all of them.
- **A broken file fails the whole refresh** (missing column, empty or not a CSV), not just that file. The planned fix is a check in
  `StartWeeklyLoad` before the refresh (name, not empty, header line); not built.
- **Recovery after a failed refresh:** delete that file's rows in `Rejected Event` (Source File Name), then refresh again. Event needs no cleanup.
- A file that arrives while a refresh is running may be moved by `FinishWeeklyLoad` before it was read. Not handled; load files one batch at a time.
- Scale: this fits tens of thousands of rows. For millions of rows a dataflow is the wrong tool (Fabric, Azure Data Factory or SQL bulk load).

## The cloud flows

### `StartWeeklyLoad`

| Step | Detail |
|---|---|
| Trigger | OneDrive for Business, *When a file is created*, folder `/RefundProcess/incoming` |
| `FileName` (Compose) | `base64ToString(triggerOutputs()?['headers/x-ms-file-name-encoded'])`. **The trigger's *File name* token is base64-encoded**; compare against this Compose, never against the token |
| `File name is valid` (Condition) | `and(startsWith(outputs('FileName'), 'AP_Refunds_EventLog_'), endsWith(outputs('FileName'), '.csv'))` is equal to `true` |
| If yes | *Refresh a dataflow* (Power Query Dataflows connector): environment, `LoadWeeklyFiles` |
| If no | *Move or rename a file* to `/RefundProcess/failed/` + `FileName` output |

Lessons from building it:

- Two text boxes with *starts with* / *ends with* compared wrongly; one expression in the left box and `true` on the right worked.
- Renaming an action that other actions refer to produced `InvalidTemplate` ("repetition action 'Apply_to_each' ... not defined"). Fix:
  delete and recreate the inner action; rename only after a successful save.
- A moved file does not fire *When a file is created*; upload a new copy.

### `FinishWeeklyLoad`

| Step | Detail |
|---|---|
| Trigger | Power Query Dataflows, *When a dataflow refresh completes*, environment, `LoadWeeklyFiles` |
| `List incoming files` | OneDrive, *List files in folder*, `/RefundProcess/incoming` |
| `Dataflow refresh succeeded` | Condition: **Refresh Status** is equal to `Success` (seen: on success the files moved to `processed`) |
| If yes | For each file: *Move or rename a file* (`Id`) to `/RefundProcess/processed/` + `Name` |
| If no | The same, to `/RefundProcess/failed/` |

The loop is over files, not rows: about three actions per run for one file.

## Environment setup that the flows depend on

Two things blocked the first runs. Both are environment settings, not flow logic.

1. **Connector policy.** The environment belongs to the default environment group, whose advanced connector policy is managed by Microsoft and is a
   strict allow list. *Refresh a dataflow* failed at runtime with *Request blocked due to data loss prevention (DLP) or advanced connector policies*
   for the connector `dataflows`. Fix: in the Microsoft 365 admin center (*Apps → Settings → Environment groups*) open the default group, choose
   *Edit this rule* on *Connectors and MCP servers*, add **Power Query Dataflows** (all actions on) and publish the rules (environment history shows
   *Update Managed Environment Settings*). The change took effect after the runtime had refreshed its copy of the policy; the error message includes
   a *Last refresh* time that shows which policy version the runtime saw. The admin center states that changes can take up to 24 hours.
2. **Group and Dataflow must be picked from the dropdowns.** Typed or stale values (the environment name and the dataflow name) produced
   `InvalidRefreshRequest` with a request URL that contained names. After clearing both fields and choosing the values from the list, the call worked.
   Do this in both flows: the action *Refresh a dataflow* in `StartWeeklyLoad` and the trigger *When a dataflow refresh completes* in `FinishWeeklyLoad`.

If the connector is ever blocked again, the load still runs by hand: put the files in `incoming`, refresh the dataflow once, then move the files to
`processed`.

## Error handling (built in both flows, failure paths not tested)

Goal: a failed load is visible and recoverable without opening the run history. Built in the same two flows, no new flow.

### `FinishWeeklyLoad`

| Step | Detail |
|---|---|
| `Process files` (Scope) | Contains `List incoming files`, the condition `Dataflow refresh succeeded` and both loops (the structure was checked on a screenshot) |
| `Handle failure` (Scope) | *Configure run after* on `Process files`: **has failed** and **has timed out** (not *is successful*). Contains the notification and `Fail the run` |
| Notification | One message (Office 365 Outlook *Send an email (V2)* or a Teams message) with the dataflow name, the refresh status and the run link: `concat(workflow()['tags']['flowDisplayName'], ' failed: ', workflow()['run']['name'])` |
| `Fail the run` (Terminate) | Status **Failed**, code `LoadFailed`, message = the notification text. Without it the run shows *Succeeded* after `Handle failure` has handled the error |

Also send the notification in the branch where *Refresh Status* is not `Success` (files moved to `failed`): that is a failed load, not a failed flow.

### `StartWeeklyLoad`

| Step | Detail |
|---|---|
| `Process files` (Scope) | Inside the *True* branch of `File name is valid`. Contains `Refresh LoadWeeklyFiles` |
| `Handle failure` (Scope) | Next to `Process files` in the same branch. Run after `Process files`: **has failed** and **has timed out** (not *is successful*, not *is skipped*). Contains `Send an email (V2)` (subject `concat(workflow()['tags']['flowDisplayName'], ' failed: ', workflow()['run']['name'])`, body with the file name) and `Terminate` (Failed, code `LoadFailed`) |
| `File name is valid` (Condition) | Changed from one formula to two rows with **And**: `outputs('FileName')` *starts with* `AP_Refunds_EventLog_` and `outputs('FileName')` *ends with* `.csv`. Not retested after the change (same logic as the formula `and(startsWith(...), endsWith(...))` that was tested before) |
| `File name is valid` = false | `Move file to failed`, with the retry policy below. An invalid file name is not a flow failure, so it does not use `Handle failure` |

Status as built: the failure path has **not** been run (no refresh was made to fail). The design above also said that `Handle failure` moves the file to `failed`; the built version only notifies and fails the run, so a file whose refresh failed stays in `incoming`. Moving it is a possible next step.

### Retries

On each *Move or rename a file* action: *Settings → Retry policy → Exponential interval*, count 3, interval `PT10S` (built on `Move file to failed` in `StartWeeklyLoad`, seen in the settings; set on the two *Move* actions in the `FinishWeeklyLoad` loops, reported by the owner, settings not seen). Moves fail on throttling and short outages; a retry
fixes those. Do not add a retry to the *Refresh a dataflow* action: a refresh that is started twice reads the files twice (see "Known limits").

### Checks

- The notification connector must be allowed by the connector policy of the environment group (see "Environment setup"). If it is not, use *Terminate* only and rely on the run history.
- Test: make the move fail (a path that does not exist) and check that `Handle failure` runs, the notification arrives and the run shows *Failed* (`TESTS.md`).

## Checks after every load

Read-only queries on the Dataverse SQL endpoint (they cost no flow actions):

```sql
SELECT rp_sourcefile, COUNT(*) AS Total FROM rp_event GROUP BY rp_sourcefile ORDER BY rp_sourcefile;
SELECT rp_sourcefilename, rp_errorreason, COUNT(*) AS Total FROM rp_rejectedevent
GROUP BY rp_sourcefilename, rp_errorreason ORDER BY 1, 2;
```

Compare with `data/expected_rejections.csv` (valid = rows read − duplicates − rejected). Expected after W35 to W52 (all 18 files): 19,176 rows in Event and
125 in Rejected Event.
