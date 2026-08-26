--Clustered Index

SET NOCOUNT ON;
BEGIN
    EXEC(
        N'
        CREATE NONCLUSTERED INDEX
            IX_FactPaymentTransaction_Channel_Date_Covering

        ON dw.FactPaymentTransaction(
            PaymentChannelKey,
            TransactionDateKey
        )

        INCLUDE(
            TransactionStatusKey,  --Secondary importance
            IsFraud,
            AmountTRY
        );
        '
    );
END


-- Test

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