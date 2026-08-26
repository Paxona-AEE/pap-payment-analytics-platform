USE PaymentProjectDW;
GO

CREATE OR ALTER VIEW report.vwMonthlyChannelPerformance
AS

SELECT

    dateDimension.CalendarYear,
    dateDimension.CalendarQuarter,
    dateDimension.MonthNumber,
    dateDimension.MonthName,

    MIN(dateDimension.FullDate)
        AS MonthStartDate,

    MAX(dateDimension.FullDate)
        AS MonthEndDate,

    fact.PaymentChannelKey,
    channel.PaymentChannelCode,

    COUNT_BIG(*)
        AS TransactionCount,

    SUM(
        CASE
            WHEN status.StatusCode = 'APPROVED'
            THEN CONVERT(BIGINT, 1)
            ELSE CONVERT(BIGINT, 0)
        END
    ) AS ApprovedTransactionCount,

    SUM(
        CASE
            WHEN status.StatusCode = 'DECLINED'
            THEN CONVERT(BIGINT, 1)
            ELSE CONVERT(BIGINT, 0)
        END
    ) AS DeclinedTransactionCount,

    SUM(
        CASE
            WHEN status.StatusCode = 'FAILED'
            THEN CONVERT(BIGINT, 1)
            ELSE CONVERT(BIGINT, 0)
        END
    ) AS FailedTransactionCount,


    CAST(100.0*SUM(
            CASE
                WHEN status.StatusCode = 'APPROVED'
                THEN CONVERT(BIGINT, 1)
                ELSE CONVERT(BIGINT, 0)
            END
        )
        /
        NULLIF
        (
            COUNT_BIG(*),
            0
        )

        AS DECIMAL(8,2)
    ) AS ApprovalRate,

    SUM(CONVERT(
            BIGINT,
            fact.IsFraud
        )
    ) AS FraudTransactionCount,

    CAST(100.0*SUM(CONVERT(
                BIGINT,
                fact.IsFraud
            )
        )
        /
        NULLIF(
            COUNT_BIG(*),
            0
        )

        AS DECIMAL(8,4)
    ) AS FraudRate,

    CAST(
        AVG(fact.FraudScore)
        AS DECIMAL(8,2)
    ) AS AverageFraudScore,

    SUM(fact.AmountTRY)
        AS TotalTransactionVolumeTRY,

    SUM(
        CASE
            WHEN status.StatusCode = 'APPROVED'
            THEN fact.AmountTRY
            ELSE CONVERT(DECIMAL(19,4), 0)
        END
    ) AS ApprovedTransactionVolumeTRY,

    CAST(
        AVG(fact.AmountTRY)
        AS DECIMAL(19,2)
    ) AS AverageTransactionAmountTRY,

    SUM(fact.FeeAmountTRY)
        AS TotalFeeAmountTRY,

    SUM(fact.MerchantCommissionTRY)
        AS TotalMerchantCommissionTRY,

    SUM(fact.TaxAmountTRY)
        AS TotalTaxAmountTRY,

    SUM(fact.CashbackAmountTRY)
        AS TotalCashbackCostTRY,

    CAST(SUM(fact.FeeAmountTRY+fact.MerchantCommissionTRY)

        AS DECIMAL(38,4)
    ) AS GrossRevenueTRY,

    CAST(
        SUM(fact.FeeAmountTRY+fact.MerchantCommissionTRY-fact.TaxAmountTRY-fact.CashbackAmountTRY)

        AS DECIMAL(38,4)
    ) AS NetRevenueTRY,

    SUM(CONVERT(
            BIGINT,
            fact.IsInternational
        )
    ) AS InternationalTransactionCount,

    SUM(CONVERT(BIGINT,
            fact.IsContactless
        )
    ) AS ContactlessTransactionCount,

    SUM(CONVERT(
            BIGINT,
            fact.IsRecurring
        )
    ) AS RecurringTransactionCount,

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

INNER JOIN dw.DimTransactionStatus AS status
    ON status.TransactionStatusKey =
       fact.TransactionStatusKey

GROUP BY
    dateDimension.CalendarYear,
    dateDimension.CalendarQuarter,
    dateDimension.MonthNumber,
    dateDimension.MonthName,

    fact.PaymentChannelKey,
    channel.PaymentChannelCode;
GO

--View Scheme

SELECT
    schemaData.name AS SchemaName,
    viewData.name AS ViewName,
    viewData.create_date AS CreateDate,
    viewData.modify_date AS ModifyDate

FROM sys.views AS viewData

INNER JOIN sys.schemas AS schemaData
    ON schemaData.schema_id =
       viewData.schema_id

WHERE schemaData.name = N'report'
  AND viewData.name =
      N'vwMonthlyChannelPerformance';
GO
