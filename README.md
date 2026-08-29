# Payment Analytics Platform

An end-to-end payment analytics project built with Microsoft SQL Server and Power BI. The project models a payment-processing data warehouse, generates one million synthetic payment transactions, implements an incremental staging-to-fact ETL pipeline, and presents the resulting business insights through an interactive Power BI dashboard.

> All customers, cards, merchants, devices, and transactions in this repository are synthetic. No real payment or personal data is included.

## Highlights

- Star schema centered on `dw.FactPaymentTransaction` and nine dimensions
- 25,000 synthetic customers, approximately 40,000 cards, 5,000 merchants, and 1,000,000 fact rows
- ETL batch log, run log, reject table, fact-load lineage, and validation snapshots
- Reporting views and parameterized stored procedures for payment, merchant, fraud, channel, and customer-segment analysis
- Window-function examples, covering indexes, and a schema-bound indexed view
- Database roles for report readers, ETL operators, and auditors
- Rerunnable object creation guards for a clean installation
- Power BI semantic model with reusable DAX measures and dedicated date intelligence
- Four dashboard pages covering executive, merchant, customer, card, fraud, and operational performance
- Synced slicers, bookmarks, report-page tooltips, conditional formatting, and payment-channel drill-through

## Architecture

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the data model and ETL flow.

## Power BI Dashboard

The Power BI layer transforms the SQL Server data warehouse into an interactive payment-performance reporting experience.

### Dashboard pages

| Page | Analytical focus |
|---|---|
| Executive Overview | Payment volume, net revenue, transaction activity, approval rate, and fraud rate |
| Merchant & Channel | Channel performance, merchant-category revenue, and operational comparisons |
| Customer & Card | Customer segments, card types, customer value, and payment-volume distribution |
| Fraud & Operations | Fraud trends, fraud reasons, authorization duration, and device-level risk |
| Payment Channel Detail | Drill-through analysis for an individually selected payment channel |

### Interactive features

- Synced date and category slicers
- Reset-filter bookmarks
- Report-page tooltips
- Payment-channel drill-through
- Current-year versus previous-year comparisons
- Conditional formatting and risk heatmaps
- Chronologically sorted English month labels

The downloadable Power BI Desktop file is distributed through the repository's GitHub Releases section.

## Requirements

- Microsoft SQL Server 2022 Developer or Express Edition
- SQL Server Management Studio (SSMS) or the `sqlcmd` command-line utility
- Permission to create a database and database objects
- Power BI Desktop for opening and exploring the dashboard

## Quick start

Clone or download the repository, open a terminal and run:

In SSMS, enable **Query → SQLCMD Mode**, open `run_all.sql` from the repository root, and execute it. The `:r` directives run every setup file in dependency order. The one-million-row generator can take several minutes depending on hardware.

For the cleanest result, run the project against a new `PaymentProjectDW` database. The scripts do not attempt to migrate an older SCD Type 2 version of the schema.

## Optional tests

Tests are intentionally excluded from `run_all.sql`:

1. Run `tests/01_End_to_End_ETL_Test.sql` to insert one valid staging row, validate it, load it into the fact table, and display its lineage.
2. Run `tests/02_Indexed_View_Performance_Test.sql` with the actual execution plan enabled to compare the expanded normal view with the indexed view using `NOEXPAND`.

## Example queries

```sql
USE PaymentProjectDW;
GO

EXEC report.usp_GetPaymentSummary
    @StartDate = '2025-01-01',
    @EndDate = '2025-12-31',
    @OnlyFraud = NULL;

EXEC report.usp_GetTopMerchantPerformance
    @StartDate = '2025-01-01',
    @EndDate = '2025-12-31',
    @TopN = 20,
    @SortMetric = 'VOLUME';
```

## Repository layout

```text
sql/01_schema       Database, schemas, dimensions, and fact table
sql/02_seed         Reference data and synthetic-data generators
sql/03_reporting    Reporting views and stored procedures
sql/04_etl          ETL control, staging, validation, and fact load
sql/05_analytics    Indexes, window queries, indexed view, security, health checks
tests               Optional performance tests
docs                Architecture and operating notes
run_all.sql         SQLCMD-mode installation point
power-bi             Power BI documentation and DAX reference
docs/screenshots     Dashboard page screenshots
```

## Design notes

- `TransactionID` is unique in the fact table, supporting incremental loads
- Unknown dimension members use surrogate key `0` so incomplete source records can be handled explicitly
- `SET XACT_ABORT ON` and `TRY...CATCH` to protect multi-step ETL transactions
- ETL procedures validate prerequisites and record success, failure, skipped runs, row counts, and error details

## Author

**Alper Efe Eker**

Built as an end-to-end portfolio project combining data engineering, analytical modeling, query optimization, and business intelligence.

Detailed execution guidance is in [docs/RUNBOOK.md](docs/RUNBOOK.md).
