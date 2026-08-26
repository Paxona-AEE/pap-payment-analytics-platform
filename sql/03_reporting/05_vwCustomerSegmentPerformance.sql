USE PaymentProjectDW;
GO

CREATE OR ALTER VIEW report.vwCustomerSegmentPerformance
AS
SELECT
    customer.CustomerSegment,

    COUNT(
        DISTINCT fact.CustomerKey
    ) AS DistinctCustomerCount,

    COUNT(
        DISTINCT fact.CardKey
    ) AS DistinctCardCount,

    MIN(dateDimension.FullDate)
        AS FirstTransactionDate,

    MAX(dateDimension.FullDate)
        AS LastTransactionDate,

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

    SUM(
        CASE
            WHEN status.StatusCode = 'REFUNDED'
            THEN CONVERT(BIGINT, 1)
            ELSE CONVERT(BIGINT, 0)
        END
    ) AS RefundedTransactionCount,


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

    SUM(fact.AmountTRY)
        AS TotalTransactionVolumeTRY,

    SUM(
        CASE
            WHEN status.StatusCode = 'APPROVED'
            THEN fact.AmountTRY
            ELSE CONVERT(DECIMAL(19,4), 0)
        END
    ) AS ApprovedTransactionVolumeTRY,

    CAST(AVG(fact.AmountTRY)AS DECIMAL(19,2)) AS AverageTransactionAmountTRY,

    MIN(fact.AmountTRY)
        AS MinimumTransactionAmountTRY,

    MAX(fact.AmountTRY)
        AS MaximumTransactionAmountTRY,

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

    CAST(SUM(fact.FeeAmountTRY+fact.MerchantCommissionTRY-fact.TaxAmountTRY-fact.CashbackAmountTRY)

        AS DECIMAL(38,4)
    ) AS NetRevenueTRY,

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
        NULLIF
        (
            COUNT_BIG(*),
            0
        )

        AS DECIMAL(8,4)
    ) AS FraudRate,

    CAST(
        AVG(fact.FraudScore)
        AS DECIMAL(8,2)
    ) AS AverageFraudScore,

    SUM(CONVERT(
            BIGINT,
            fact.IsInternational
        )
    ) AS InternationalTransactionCount,

    CAST(100.0*SUM(CONVERT(
                BIGINT,
                fact.IsInternational
            )
        )
        /
        NULLIF
        (
            COUNT_BIG(*),
            0
        )

        AS DECIMAL(8,2)
    ) AS InternationalTransactionRate,

    SUM(CONVERT(
            BIGINT,
            fact.IsContactless
        )
    ) AS ContactlessTransactionCount,

    SUM(CONVERT(
            BIGINT,
            fact.IsRecurring
        )
    ) AS RecurringTransactionCount,

    SUM(CONVERT(
            BIGINT,
            fact.Is3DSecure
        )
    ) AS Secure3DTransactionCount,

    CAST(100.0*SUM(
            CONVERT
            (
                BIGINT,
                fact.Is3DSecure
            )
        )
        /
        NULLIF
        (
            COUNT_BIG(*),
            0
        )

        AS DECIMAL(8,2)
    ) AS Secure3DTransactionRate,

    SUM(CONVERT(
            BIGINT,
            fact.IsTokenized
        )
    ) AS TokenizedTransactionCount,

    SUM(
        CASE
            WHEN fact.InstallmentCount > 1
            THEN CONVERT(BIGINT, 1)
            ELSE CONVERT(BIGINT, 0)
        END
    ) AS InstallmentTransactionCount,

    CAST(100.0*SUM(
            CASE
                WHEN fact.InstallmentCount > 1
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
    ) AS InstallmentTransactionRate,

    CAST(AVG(CONVERT(
                DECIMAL(10,2),
                fact.InstallmentCount
            )
        )

        AS DECIMAL(10,2)
    ) AS AverageInstallmentCount,


    CAST(AVG(CONVERT(
                DECIMAL(19,2),
                fact.AuthorizationDurationMs
            )
        )

        AS DECIMAL(19,2)
    ) AS AverageAuthorizationDurationMs

FROM dw.FactPaymentTransaction AS fact

INNER JOIN dw.DimCustomer AS customer
    ON customer.CustomerKey =
       fact.CustomerKey

INNER JOIN dw.DimTransactionStatus AS status
    ON status.TransactionStatusKey =
       fact.TransactionStatusKey

INNER JOIN dw.DimDate AS dateDimension
    ON dateDimension.DateKey =
       fact.TransactionDateKey

GROUP BY
    customer.CustomerSegment;
GO

--View

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
      N'vwCustomerSegmentPerformance';
GO
