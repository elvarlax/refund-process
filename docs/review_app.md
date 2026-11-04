# Model-driven app `Refund Rejected Review`

Status: **Built.** This page was the build description; results are in `TESTS.md`.

| Part | Status |
|---|---|
| Review columns, three views, main form, app published | Built |
| Business rule `Ignored requires a note` | Built; tested on the form and in bulk edit (both blocked). Editable grid and Excel import not tested |
| 125 existing rows set to `Open` (bulk edit) | Done |
| Flow `SetReviewedOn` | Built; tested on a few rows (`Resolved` fills, `Open` clears). Run count per change not checked; no error handling |
| Roles `Refund Reviewer` and `Refund Admin` | Built; not tested with a second user. App not yet shared with the roles |
| Default `Open` on rows created by the dataflow | Not tested |

The sections below are kept as the build description. Names marked *verify* were checked during the build.

Purpose: a rejected row is not just counted, a person decides what happens to it. A reviewer opens the app, sees the open rows with the reason and
the raw line, and marks each row **Resolved** (cause fixed at the source, file reloaded) or **Ignored** (with a written reason). Who decided, and
when, is stored on the row.

Out of scope: correcting the raw line in the app and sending it through validation again. The correction belongs in the source file, which is then
loaded like any other weekly file.

Scope in numbers: 125 rejected rows after W35 to W52 (35 CaseId missing, 36 end before start, 29 `InvoiceValue` not a number, 25 unknown activity).

## 1 · Names to verify first

Logical names are generated from the display name and the publisher prefix `rp_`. Read the real ones from Dataverse (read-only, SQL endpoint):

```sql
SELECT TOP 1 * FROM rp_rejectedevent;
SELECT TOP 1 * FROM rp_event;
SELECT TOP 1 * FROM rp_step;
```

| Existing | Logical name | Status |
|---|---|---|
| Table Rejected Event | `rp_rejectedevent` | Confirmed (used in the load checks) |
| Source File Name | `rp_sourcefilename` | Confirmed |
| Error Reason | `rp_errorreason` | Confirmed |
| Raw Event Data | `rp_raweventdata` | Confirmed |
| Primary key (GUID, written by the dataflow) | `rp_rejectedeventid` | Confirmed. The table has no `rp_name` column: *verify* which text column is the primary name column (needed for the lookup display and the grid) |
| Standard columns | `statecode`, `statuscode` (Active / Inactive), `ownerid`, `createdon`, `modifiedby` | Exist. `statuscode` is not used for review: it only knows Active and Inactive, so the review has its own column `rp_reviewstatus` |
| Table Event | `rp_event`, key `rp_eventkey`, `rp_sourcefile` | Confirmed |
| Table Step | `rp_step` | *Verify* |

If a name differs, change it here and in the SQL in `dataverse_sql/load_checks.sql`, not in the table.

## 2 · New columns on `Rejected Event`

Create in the solution `Refund Process`: Tables → Rejected Event → Columns → New column. Type the display name, then **open *Advanced options* and
check that the schema name is exactly as below** (it cannot be changed afterwards).

| Display name | Schema / logical name | Type | Settings |
|---|---|---|---|
| Review Status | `rp_reviewstatus` | Choice (new, local choice) | Choices: **Open** (default), **In review**, **Resolved**, **Ignored**. Required: Optional (see section 3) |
| Review Note | `rp_reviewnote` | Multiple lines of text (plain), max length 1000 | Required: Optional (the business rule in section 6 requires it for `Ignored`) |
| Reviewed On | `rp_reviewedon` | Date and time, format *Date and time*, behavior *User local* | Filled by the flow `SetReviewedOn`, read-only on the form |
| Reviewed By | `rp_reviewedby` | Lookup to User | Filled by the flow `SetReviewedOn`, read-only on the form |

Dataverse assigns the numeric values of the choices from the publisher's option value prefix. Comparing labels was the plan, but the label came back
empty in the flow trigger, so `SetReviewedOn` compares the option number (section 7).

Columns the load fills (not changed): `rp_sourcefilename`, `rp_errorreason`, `rp_raweventdata`. The dataflow maps only these four columns, so it
does not touch the review columns when it creates rows.

## 3 · Rows that already exist

New rows get `Open` from the column's default value. *Verify:* load a small test file and check that `rp_reviewstatus` is `Open` on its rejected rows
(see `TESTS.md`). If the default is not applied to rows the dataflow creates, a view that filters on `Open` shows nothing.

The 125 existing rows have no status. Set them once, **before the flow in section 7 is turned on**:

1. Open the app (section 8), view *All rejected rows*, select all rows, *Bulk edit* → Review Status = Open.
2. Check with `SELECT rp_reviewstatus, COUNT(*) FROM rp_rejectedevent GROUP BY rp_reviewstatus;` → all rows `Open`.

## 4 · Views on `Rejected Event`

| View | Filter | Columns (in order) | Sort |
|---|---|---|---|
| **Open rows** (default) | Review Status equals Open, or equals In review | Source File Name, Error Reason, Raw Event Data, Review Status, Review Note, Created On | Source File Name, then Created On |
| **Resolved and ignored** | Review Status equals Resolved, or equals Ignored | Source File Name, Error Reason, Review Status, Review Note, Reviewed By, Reviewed On | Reviewed On, newest first |
| **All rejected rows** | none | Source File Name, Error Reason, Review Status, Created On | Source File Name |

Turn on the **editable grid** for *Open rows* (Views → the view → Components → Add component → Editable grid), so the status and note can be set in
the list. Bulk edit (select rows → *Bulk edit*) is for setting the same status on many rows, for example `Ignored` with one note on every row with
a missing CaseId.

Optional: a chart *Rejected rows by reason* (column chart, count of rows by Error Reason, filter Review Status = Open) and a dashboard with the chart
and the view *Open rows*.

## 5 · Main form

| Section | Fields | Read-only |
|---|---|---|
| Source | Source File Name, Error Reason, Raw Event Data | All three |
| Review | Review Status, Review Note | No |
| Audit | Reviewed By, Reviewed On | Both |

Read-only on the form is not security (a user with Write can still change the column through the API). It stops mistakes in the app. Real protection
of the source columns would be a column security profile; not planned.

## 6 · Business rule: `Ignored` needs a note

Table `Rejected Event` → Business rules → New. **Scope: Entity** (a rule with scope *Entity* is also evaluated outside forms; *verify*, see test).

- Name: `Ignored requires a note`
- Condition: `Review Status` **equals** `Ignored` **and** `Review Note` **does not contain data**
- If true, action: **Show error message** on `Review Note`: "Write why this row is ignored."
- Activate (Save, then *Activate*) and publish.

Optional second rule `Ignored note is required on the form`: condition Review Status equals Ignored, action **Set business required** on `Review Note`,
so the form shows the asterisk. The first rule is the one that blocks.

## 7 · Cloud flow `SetReviewedOn`

A business rule cannot write the current time or the current user, so a small flow does. It is in the solution and uses the Dataverse
connection reference (seen in the export).

| Step | Detail |
|---|---|
| Trigger | Dataverse, *When a row is added, modified or deleted*. Change type **Modified**, table **Rejected Event**, scope **Organization**, **Select columns** `rp_reviewstatus` |
| `NewStatus` (Compose) | `triggerOutputs()?['body/rp_reviewstatus']` (the option **number**). The first version used the `@OData.Community.Display.V1.FormattedValue` label; in this trigger it came back empty, so the `Open` check was never true and the fields were not cleared |
| `Reviewer` (Compose) | `triggerOutputs()?['body/_modifiedby_value']` (read from the trigger, not after the flow has updated the row) |
| Update a row | Table Rejected Event, Row ID from the trigger. `Reviewed On` = `if(equals(outputs('NewStatus'),126220000),null,utcNow())`. `Reviewed By` = `if(equals(outputs('NewStatus'),126220000),null,concat('systemusers(',outputs('Reviewer'),')'))` |

Option numbers seen in run history: `Open` = 126220000, `Resolved` = 126220002 (taken from one run each; `Ignored` and the fourth option not read yet). The number is fixed in the flow: if an option of Review Status is added or renumbered, update the flow.

Why it does not loop: *Select columns* limits the trigger to changes of `rp_reviewstatus`, and the flow only writes `rp_reviewedon` and `rp_reviewedby`.
Turn the flow on only after the rows in section 3 have been set to `Open`, or the bulk edit starts 125 runs. A bulk edit of 20 rows later starts 20 runs, which is fine.

This flow has no error handling (no Scope or failure notification); a failed run is only visible in run history.

## 8 · The app

Solution → New → App → Model-driven app, name `Refund Rejected Review`, unique name `rp_RefundRejectedReview`.

| Navigation | Page | Views shown |
|---|---|---|
| Review → **Rejected rows** | Table `Rejected Event` | Open rows, Resolved and ignored, All rejected rows |
| Reference → **Events** | Table `Event` | One view of the columns used for context (Case Id, Activity Name, Start Timestamp, Source File), read-only through the role |

Save, **Publish**, **Play**. Add every component (app, table, columns, views, form, business rule, flow, roles) to the solution `Refund Process`.

## 9 · Security roles

Create both roles by **copying *Basic User*** (Environment → Settings → Users + permissions → Security roles → *Copy role*), so that the minimum
privileges needed to open a model-driven app (read user, app access) are there, then change the three tables. Level: **Organization** for every
privilege that is granted (there is one business unit).

| Table | Refund Reviewer | Refund Admin |
|---|---|---|
| Rejected Event | Read, Write | Create, Read, Write, Delete, Append, Append To |
| Event | Read | Create, Read, Write, Delete, Append, Append To |
| Step | Read | Create, Read, Write, Delete, Append, Append To |

Rules behind the table:

- A reviewer decides, does not load or delete data: no Create or Delete on any table, no Write on `Event` or `Step`.
- An admin maintains the data model and clears test data. The dataflow runs as the person who owns it, so `Refund Admin` is not what makes the load work.
- Share the app `Refund Rejected Review` with both roles (app → Share).

Assign: Environment → Settings → Users + permissions → Users → *Manage roles*.

How it is tested without a second person: **Check access** on a user shows the effective privileges on a table or a record. With a second account
(for example a test user in the tenant with a Developer Plan or a Power Apps license), sign in as that user for the real test.

## 10 · Known limits

- Reviewing before `Rejected Event` is idempotent is fragile: a refresh with the same file in `incoming` creates the rejected rows again with status
  `Open` and no review. The planned fix (a fixed key per file name and line number, as an alternate key) comes before real review work.
- The business rule blocks `Ignored` without a note in the app. Whether it blocks the same change from an Excel import or the API is a test (`TESTS.md`), not an assumption.
- There is no way to correct a raw line in the app. The correction is a new file in the source system.
