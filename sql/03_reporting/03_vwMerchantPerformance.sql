USE PaymentProjectDW;
GO

SET NOCOUNT ON;
GO

CREATE OR ALTER VIEW report.vwMerchantPerformance
AS
SELECT

    fact.MerchantKey,

    merchant.MerchantID,
    merchant.MerchantName,
    merchant.MerchantCategory,
    merchant.MerchantSubcategory,
    merchant.MerchantCategoryCode,
    merchant.MerchantSize,
    merchant.MerchantRiskLevel,

    merchant.Country
        AS MerchantCountry,

    merchant.IsOnlineMerchant,
    merchant.IsActive
        AS MerchantIsActive,

    merchant.OnboardingDate,

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

    --------------------------------------------------------
    -- TRANSACTION VOLUME
    --------------------------------------------------------

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

    MAX(fact.AmountTRY)
        AS MaximumTransactionAmountTRY,

    MIN(fact.AmountTRY)
        AS MinimumTransactionAmountTRY,

    --------------------------------------------------------
    -- REVENUE VE COST
    --------------------------------------------------------

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

    --------------------------------------------------------
    -- FRAUD METRICS
    --------------------------------------------------------

    SUM(
        CONVERT(
            BIGINT,
            fact.IsFraud
        )
    ) AS FraudTransactionCount,

    CAST(100.0*SUM(
            CONVERT(
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

    --------------------------------------------------------
    -- CHANNEL-RELATED FLAGS
    --------------------------------------------------------

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
    ) AS RecurringTransactionCount

FROM dw.FactPaymentTransaction AS fact

INNER JOIN dw.DimMerchant AS merchant
    ON merchant.MerchantKey =
       fact.MerchantKey

INNER JOIN dw.DimTransactionStatus AS status
    ON status.TransactionStatusKey =
       fact.TransactionStatusKey

INNER JOIN dw.DimDate AS dateDimension
    ON dateDimension.DateKey =
       fact.TransactionDateKey

GROUP BY
    fact.MerchantKey,

    merchant.MerchantID,
    merchant.MerchantName,
    merchant.MerchantCategory,
    merchant.MerchantSubcategory,
    merchant.MerchantCategoryCode,
    merchant.MerchantSize,
    merchant.MerchantRiskLevel,
    merchant.Country,
    merchant.IsOnlineMerchant,
    merchant.IsActive,
    merchant.OnboardingDate;
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
      N'vwMerchantPerformance';
GO
