
SET NOCOUNT ON;

DECLARE @ApprovedStatusKey TINYINT;

SELECT
    @ApprovedStatusKey = TransactionStatusKey
FROM dw.DimTransactionStatus
WHERE StatusCode = 'APPROVED';

SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT
    dateDimension.CalendarYear,
    dateDimension.MonthNumber,
    dateDimension.MonthName,

    channel.PaymentChannelCode,
    channel.PaymentChannelName,

    COUNT_BIG(*) AS TransactionCount,

    SUM(
        CASE
            WHEN fact.TransactionStatusKey =
                 @ApprovedStatusKey
            THEN CONVERT(BIGINT, 1)
            ELSE CONVERT(BIGINT, 0)
        END
    ) AS ApprovedTransactionCount,

    CAST(100.0*SUM(
            CASE
                WHEN fact.TransactionStatusKey =
                     @ApprovedStatusKey
                THEN CONVERT(BIGINT, 1)
                ELSE CONVERT(BIGINT, 0)
            END
        )
        /
        NULLIF(COUNT_BIG(*), 0)

        AS DECIMAL(8,2)
    ) AS ApprovalRate,

    SUM(CONVERT(BIGINT, fact.IsFraud))
        AS FraudTransactionCount,

    CAST(100.0*SUM(CONVERT(BIGINT, fact.IsFraud))
        /
        NULLIF(COUNT_BIG(*), 0)

        AS DECIMAL(8,4)
    ) AS FraudRate,

    SUM(fact.AmountTRY)
        AS TotalTransactionVolumeTRY,

    CAST(AVG(fact.AmountTRY)AS DECIMAL(19,2)) AS AverageTransactionAmountTRY,

    SUM(fact.FeeAmountTRY)
        AS TotalFeeAmountTRY,

    SUM(fact.MerchantCommissionTRY)
        AS TotalMerchantCommissionTRY,

    SUM(fact.TaxAmountTRY)
        AS TotalTaxAmountTRY,

    SUM(fact.CashbackAmountTRY)
        AS TotalCashbackCostTRY,

    CAST(AVG(CONVERT(
                DECIMAL(19,2),
                fact.AuthorizationDurationMs
            )
        )
        AS DECIMAL(19,2)
    ) AS AverageAuthorizationDurationMs

FROM dw.FactPaymentTransaction AS fact

INNER JOIN dw.DimDate AS dateDimension
    ON dateDimension.DateKey =
       fact.TransactionDateKey

INNER JOIN dw.DimPaymentChannel AS channel
    ON channel.PaymentChannelKey =
       fact.PaymentChannelKey

WHERE fact.TransactionDateKey
      BETWEEN 20240101 AND 20261231

GROUP BY
    dateDimension.CalendarYear,
    dateDimension.MonthNumber,
    dateDimension.MonthName,

    channel.PaymentChannelCode,
    channel.PaymentChannelName

ORDER BY
    dateDimension.CalendarYear,
    dateDimension.MonthNumber,
    channel.PaymentChannelCode

OPTION (RECOMPILE);

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;

SET NOCOUNT OFF;
GO