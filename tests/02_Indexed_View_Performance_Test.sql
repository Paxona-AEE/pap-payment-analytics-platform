USE PaymentProjectDW;
GO

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

SELECT
    @StartDateKey = MIN(TransactionDateKey),
    @EndDateKey = MAX(TransactionDateKey)
FROM dw.FactPaymentTransaction;

IF @StartDateKey IS NULL OR @EndDateKey IS NULL
BEGIN
    PRINT 'FactPaymentTransaction is empty; performance test skipped.';
END
ELSE
BEGIN
    PRINT '---------- NORMAL VIEW ----------';

    SELECT TOP (100)
        summary.TransactionDateKey,
        summary.MerchantKey,
        summary.TransactionCount,
        summary.TotalAmountTRY
    FROM report.vw_MerchantDailyPaymentSummary AS summary
    WHERE summary.TransactionDateKey BETWEEN @StartDateKey AND @EndDateKey
    ORDER BY summary.TransactionDateKey, summary.MerchantKey
    OPTION (RECOMPILE, EXPAND VIEWS);

    PRINT '---------- INDEXED VIEW ----------';

    SELECT TOP (100)
        summary.TransactionDateKey,
        summary.MerchantKey,
        summary.TransactionCount,
        summary.TotalAmountTRY
    FROM dw.vw_MerchantDailyPaymentSummaryIndexed AS summary WITH (NOEXPAND)
    WHERE summary.TransactionDateKey BETWEEN @StartDateKey AND @EndDateKey
    ORDER BY summary.TransactionDateKey, summary.MerchantKey
    OPTION (RECOMPILE);
END;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO
