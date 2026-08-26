CREATE VIEW dw.vw_MerchantDailyPaymentSummaryIndexed
WITH SCHEMABINDING
AS
SELECT
    fact.TransactionDateKey,
    fact.MerchantKey,

    COUNT_BIG(*) AS TransactionCount,

    SUM(
        ISNULL(
            fact.AmountTRY,
            CONVERT(DECIMAL(19,4), 0))
    ) AS TotalAmountTRY

FROM dw.FactPaymentTransaction AS fact

GROUP BY
    fact.TransactionDateKey,
    fact.MerchantKey;
GO

---Second Scheme---

CREATE UNIQUE CLUSTERED INDEX
    CIX_MerchantDailyPaymentSummaryIndexed

ON dw.vw_MerchantDailyPaymentSummaryIndexed(
    TransactionDateKey,
    MerchantKey
);
GO

--Added to a disk, slight improvement!

--More seeks, better the situation
--Less scans for optimization

SELECT
    viewData.name AS ViewName,
    indexData.name AS IndexName,
    indexData.type_desc AS IndexType

FROM sys.views AS viewData

LEFT JOIN sys.indexes AS indexData
    ON indexData.object_id =
       viewData.object_id

   AND indexData.index_id > 0

WHERE viewData.object_id IN(
OBJECT_ID(
        N'report.vw_MerchantDailyPaymentSummary'
    ),

    OBJECT_ID
    (
        N'dw.vw_MerchantDailyPaymentSummaryIndexed'
    )
);
GO


IF OBJECT_ID(
    N'dw.vw_MerchantDailyPaymentSummaryIndexed',
    N'V'
) IS NULL
BEGIN
    EXEC(N'
        CREATE VIEW dw.vw_MerchantDailyPaymentSummaryIndexed
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
            fact.MerchantKey;
    ');
END;
GO


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


IF SCHEMA_ID(N'report') IS NULL
BEGIN
    EXEC(N'CREATE SCHEMA report AUTHORIZATION dbo;');
END;
GO

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
--Comparisons



SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;
GO

SET STATISTICS IO ON;
SET STATISTICS TIME ON;
GO

DECLARE
    @StartDateKey INT,
    @EndDateKey INT;

------------------------------------------------------------
-- FACT TABLOSUNDAKİ TARİH ARALIĞI
------------------------------------------------------------

SELECT
    @StartDateKey =
        MIN(TransactionDateKey),

    @EndDateKey =
        MAX(TransactionDateKey)

FROM dw.FactPaymentTransaction;

------------------------------------------------------------
-- TEST 1: NORMAL VIEW
------------------------------------------------------------

PRINT
    '---------- NORMAL VIEW ----------';

SELECT
    summary.TransactionDateKey,
    summary.MerchantKey,

    summary.TransactionCount,
    summary.TotalAmountTRY

FROM report.vw_MerchantDailyPaymentSummary
     AS summary

WHERE summary.TransactionDateKey
      BETWEEN @StartDateKey AND @EndDateKey

ORDER BY
    summary.TransactionDateKey,
    summary.MerchantKey

OPTION(
    RECOMPILE,
    EXPAND VIEWS  --It blocks the path for the indexed view!
);

------------------------------------------------------------
-- TEST 2: INDEXED VIEW
------------------------------------------------------------

PRINT
    '---------- INDEXED VIEW ----------';

SELECT
    summary.TransactionDateKey,
    summary.MerchantKey,

    summary.TransactionCount,
    summary.TotalAmountTRY

FROM dw.vw_MerchantDailyPaymentSummaryIndexed
     AS summary WITH (NOEXPAND)

WHERE summary.TransactionDateKey
      BETWEEN @StartDateKey AND @EndDateKey

ORDER BY
    summary.TransactionDateKey,
    summary.MerchantKey

OPTION(
    RECOMPILE
);

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO


