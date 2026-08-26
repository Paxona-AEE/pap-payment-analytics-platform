
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
GO

SELECT
    dateDimension.CalendarYear,
    dateDimension.MonthNumber,
    dateDimension.MonthName,

    channel.PaymentChannelCode,
    channel.PaymentChannelName,

    COUNT_BIG(*) AS TransactionCount,

    SUM(CASE
            WHEN status.StatusCode = 'APPROVED'
            THEN CONVERT(BIGINT, 1)
            ELSE CONVERT(BIGINT, 0)
        END
    ) AS ApprovedTransactionCount,

    CAST(100.0*SUM(
            CASE
                WHEN status.StatusCode = 'APPROVED'
                THEN CONVERT(BIGINT, 1)
                ELSE CONVERT(BIGINT, 0)
            END
        )
        /
        NULLIF(COUNT_BIG(*), 0)

        AS DECIMAL(8,2)
    ) AS ApprovalRate,

    SUM(CONVERT(
            BIGINT,
            fact.IsFraud
        )
    ) AS FraudTransactionCount,

    CAST(100.0*SUM(CONVERT(BIGINT,fact.IsFraud))
        /
        NULLIF(COUNT_BIG(*), 0)

        AS DECIMAL(8,4)
    ) AS FraudRate,

    SUM(fact.AmountTRY)
        AS TotalTransactionVolumeTRY,

    CAST(AVG(fact.AmountTRY)AS DECIMAL(19,2)) AS AverageTransactionAmountTRY

FROM dw.FactPaymentTransaction AS fact

INNER JOIN dw.DimDate AS dateDimension
    ON dateDimension.DateKey =
       fact.TransactionDateKey

INNER JOIN dw.DimPaymentChannel AS channel
    ON channel.PaymentChannelKey =
       fact.PaymentChannelKey

INNER JOIN dw.DimTransactionStatus AS status
    ON status.TransactionStatusKey =
       fact.TransactionStatusKey

WHERE fact.TransactionDateKey
      BETWEEN 20250101 AND 20261231

  AND channel.PaymentChannelCode = 'ECOMMERCE'

GROUP BY
    dateDimension.CalendarYear,
    dateDimension.MonthNumber,
    dateDimension.MonthName,

    channel.PaymentChannelCode,
    channel.PaymentChannelName

ORDER BY
    dateDimension.CalendarYear,
    dateDimension.MonthNumber;
GO

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO



--SQL Server parse and compile time: 
--   CPU time = 0 ms, elapsed time = 0 ms.

--(18 rows affected)
--Table 'Worktable'. Scan count 0, logical reads 0, physical reads 0, page server reads 0, read-ahead reads 0, page server read-ahead reads 0, lob logical reads 0, lob physical reads 0, lob page server reads 0, lob read-ahead reads 0, lob page server read-ahead reads 0.
--Table 'DimDate'. Scan count 1, logical reads 7, physical reads 0, page server reads 0, read-ahead reads 0, page server read-ahead reads 0, lob logical reads 0, lob physical reads 0, lob page server reads 0, lob read-ahead reads 0, lob page server read-ahead reads 0.
--Table 'Workfile'. Scan count 0, logical reads 0, physical reads 0, page server reads 0, read-ahead reads 0, page server read-ahead reads 0, lob logical reads 0, lob physical reads 0, lob page server reads 0, lob read-ahead reads 0, lob page server read-ahead reads 0.
--Table 'FactPaymentTransaction'. Scan count 1, logical reads 28710, physical reads 0, page server reads 0, read-ahead reads 0, page server read-ahead reads 0, lob logical reads 0, lob physical reads 0, lob page server reads 0, lob read-ahead reads 0, lob page server read-ahead reads 0.
--Table 'DimTransactionStatus'. Scan count 1, logical reads 2, physical reads 0, page server reads 0, read-ahead reads 0, page server read-ahead reads 0, lob logical reads 0, lob physical reads 0, lob page server reads 0, lob read-ahead reads 0, lob page server read-ahead reads 0.
--Table 'DimPaymentChannel'. Scan count 0, logical reads 4, physical reads 0, page server reads 0, read-ahead reads 0, page server read-ahead reads 0, lob logical reads 0, lob physical reads 0, lob page server reads 0, lob read-ahead reads 0, lob page server read-ahead reads 0.

-- SQL Server Execution Times:
--   CPU time = 406 ms,  elapsed time = 432 ms.
--SQL Server parse and compile time: 
--CPU time = 0 ms, elapsed time = 0 ms.
--SQL Server Execution Times:
--   CPU time = 0 ms,  elapsed time = 0 ms.

--Completion time: 2026-07-17T12:52:02.1780618+03:00
