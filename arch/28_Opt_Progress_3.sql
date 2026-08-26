

SET NOCOUNT ON;
BEGIN
    EXEC
    (
        N'
        CREATE NONCLUSTERED INDEX
            IX_FactPaymentTransaction_Merchant_Date_Covering

        ON dw.FactPaymentTransaction(
            MerchantKey,
            TransactionDateKey
        )

        INCLUDE(
            TransactionStatusKey,
            IsFraud,
            AmountTRY,
            MerchantCommissionTRY
        );
        '
    );
END


--Test (3X This Time?)


SET STATISTICS IO ON;
SET STATISTICS TIME ON;
GO

SELECT TOP (20)
    merchant.MerchantID,
    merchant.MerchantName,
    merchant.MerchantCategory,
    merchant.MerchantSize,
    merchant.MerchantRiskLevel,

    COUNT_BIG(*) AS TransactionCount,

    SUM(
        CASE
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

    SUM(fact.AmountTRY)
        AS TotalTransactionVolumeTRY,

    CAST
    (
        AVG(fact.AmountTRY)
        AS DECIMAL(19,2)
    ) AS AverageTransactionAmountTRY,

    SUM(fact.MerchantCommissionTRY)
        AS TotalMerchantCommissionTRY,

    SUM
    (
        CONVERT
        (
            BIGINT,
            fact.IsFraud
        )
    ) AS FraudTransactionCount

FROM dw.FactPaymentTransaction AS fact

INNER JOIN dw.DimMerchant AS merchant
    ON merchant.MerchantKey =
       fact.MerchantKey

INNER JOIN dw.DimTransactionStatus AS status
    ON status.TransactionStatusKey =
       fact.TransactionStatusKey

WHERE fact.TransactionDateKey
      BETWEEN 20250101 AND 20261231

  AND merchant.MerchantCategory = 'Electronics'

  AND merchant.IsCurrent = 1

GROUP BY
    merchant.MerchantID,
    merchant.MerchantName,
    merchant.MerchantCategory,
    merchant.MerchantSize,
    merchant.MerchantRiskLevel

ORDER BY
    TotalTransactionVolumeTRY DESC;
GO

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO