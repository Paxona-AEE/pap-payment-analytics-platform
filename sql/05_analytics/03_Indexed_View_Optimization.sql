/*
    PaymentProjectDW - Merchant Daily Payment Summary
      - A normal reporting view
      - A schema-bound indexed view
      - A unique clustered index on the indexed view

    The script is safe to run more than once.
*/

USE PaymentProjectDW;
GO

------------------------------------------------------------
-- REQUIRED SET OPTIONS FOR INDEXED VIEWS
------------------------------------------------------------

SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;
GO

IF OBJECT_ID(N'dw.FactPaymentTransaction', N'U') IS NULL
BEGIN
    THROW 59001,
          'dw.FactPaymentTransaction tablosu bulunamadi.',
          1;
END;
GO

IF SCHEMA_ID(N'report') IS NULL
BEGIN
    EXEC(N'CREATE SCHEMA report AUTHORIZATION dbo;');
END;
GO

------------------------------------------------------------
-- NORMAL REPORTING VIEW
------------------------------------------------------------

CREATE OR ALTER VIEW report.vw_MerchantDailyPaymentSummary
AS
SELECT
    fact.TransactionDateKey,
    fact.MerchantKey,
    COUNT_BIG(*) AS TransactionCount,
    SUM(fact.AmountTRY) AS TotalAmountTRY
FROM dw.FactPaymentTransaction AS fact
GROUP BY
    fact.TransactionDateKey,
    fact.MerchantKey;
GO

------------------------------------------------------------
-- SCHEMA-BOUND VIEW
------------------------------------------------------------

IF OBJECT_ID
   (
       N'dw.vw_MerchantDailyPaymentSummaryIndexed',
       N'V'
   ) IS NULL
BEGIN
    EXEC
    (
        N'CREATE VIEW dw.vw_MerchantDailyPaymentSummaryIndexed
          WITH SCHEMABINDING
          AS
          SELECT
              fact.TransactionDateKey,
              fact.MerchantKey,
              COUNT_BIG(*) AS TransactionCount,
              SUM(fact.AmountTRY) AS TotalAmountTRY
          FROM dw.FactPaymentTransaction AS fact
          GROUP BY
              fact.TransactionDateKey,
              fact.MerchantKey;'
    );
END;
GO

IF OBJECTPROPERTYEX
   (
       OBJECT_ID(N'dw.vw_MerchantDailyPaymentSummaryIndexed'),
       N'IsSchemaBound'
   ) <> 1
BEGIN
    THROW 59002,
          'Mevcut indexed-view adindaki view SCHEMABINDING ile olusturulmamis.',
          1;
END;
GO

------------------------------------------------------------
-- UNIQUE CLUSTERED INDEX
------------------------------------------------------------

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE object_id =
          OBJECT_ID(N'dw.vw_MerchantDailyPaymentSummaryIndexed')
      AND name =
          N'CIX_MerchantDailyPaymentSummaryIndexed'
)
BEGIN
    CREATE UNIQUE CLUSTERED INDEX
        CIX_MerchantDailyPaymentSummaryIndexed
    ON dw.vw_MerchantDailyPaymentSummaryIndexed
    (
        TransactionDateKey,
        MerchantKey
    );
END;
GO

------------------------------------------------------------
-- INSTALLATION CHECK
------------------------------------------------------------

SELECT
    schemaData.name AS SchemaName,
    viewData.name AS ViewName,
    indexData.name AS IndexName,
    indexData.type_desc AS IndexType
FROM sys.views AS viewData
INNER JOIN sys.schemas AS schemaData
    ON schemaData.schema_id = viewData.schema_id
LEFT JOIN sys.indexes AS indexData
    ON indexData.object_id = viewData.object_id
   AND indexData.index_id > 0
WHERE viewData.object_id IN
      (
          OBJECT_ID(N'report.vw_MerchantDailyPaymentSummary'),
          OBJECT_ID(N'dw.vw_MerchantDailyPaymentSummaryIndexed')
      )
ORDER BY
    schemaData.name,
    viewData.name,
    indexData.index_id;
GO

/*
    Important:
    Connections that later INSERT, UPDATE or DELETE rows in
    dw.FactPaymentTransaction must use the required indexed-view SET options.
*/
