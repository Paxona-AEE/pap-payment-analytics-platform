# Runbook

## Installation order

`run_all.sql` executes the project in this order:

1. Create `PaymentProjectDW` and the `dw`, `report`, `stg`, and `etl` schemas.
2. Create dimensions, then `dw.FactPaymentTransaction` and its foreign keys.
3. Insert reference and synthetic dimension data.
4. Generate 10,000 validated template payments and expand them to 1,000,000 production fact rows. (That part has been powered by Artifical Intelligence)
5. Create reporting views and stored procedures.
6. Create ETL control, staging, validation, and fact-load objects.
7. Create analytical indexes, window-query examples, the indexed view, roles, and health checks.

The test scripts are optional and must be run separately.

## SSMS execution (Recommended to Use!)

1. Open SSMS and connect with an account that can create databases.
2. Select **Query → SQLCMD Mode**.
3. Open `run_all.sql` from the repository root.
4. Execute the whole file.
5. Confirm that the final message says `PaymentProjectDW installation completed.`

If SQLCMD Mode is disabled, SSMS treats `:r` as invalid SQL.

## Command-line execution

```powershell
sqlcmd -S localhost\SQLEXPRESS -E -b -i run_all.sql
```
!!! Use `-U` and `-P` only when SQL authentication is required. Avoid committing credentials or connection strings to the repository.

## Verification

```sql
USE PaymentProjectDW;
GO

SELECT COUNT_BIG(*) AS FactRows
FROM dw.FactPaymentTransaction
WHERE SourceSystem = 'SyntheticGeneratorV1';

SELECT ProcessingStatus, COUNT_BIG(*) AS RowCount
FROM stg.PaymentTransactionRaw
GROUP BY ProcessingStatus;

SELECT TOP (20) *
FROM etl.ETLRunLog
ORDER BY ETLRunID DESC;
```

The first query should return `1000000` after completion.

## Common issues

### `Invalid object name`

-- The scripts were run out of order or against another database. Use `run_all.sql`, or follow the numbered folders and filenames.

### `There is already an object named ...`

-- Use the cleaned scripts in this repository rather than the original files. Tables, indexes, views, procedures, roles, and demo users are guarded or created with `CREATE OR ALTER` where appropriate.

### Indexed-view SET-option error

Connections that modify `dw.FactPaymentTransaction` after the indexed view exists must use:

```sql
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;
```

### Build stops during the one-million-row load (Powered by Artifical Intelligence)

Fix the reported error and rerun `run_all.sql`. The generator validates completed production copies and resumes only from a complete 10,000-row boundary. If a partial production batch exists, inspect it before deleting anything; do not blindly truncate the fact table.

### Existing older schema contains SCD columns

This repository defines a clean non-historized model and does not destructively migrate an older database. Create a fresh `PaymentProjectDW` database for the portfolio build, or migrate the old schema manually after taking a backup.
