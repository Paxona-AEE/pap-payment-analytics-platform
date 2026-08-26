
SET NOCOUNT ON;

BEGIN
	CREATE NONCLUSTERED INDEX 
		IX_FactPaymentTransaction_TransactionDateKey_Covering 
		ON dw.FactPaymentTransaction ( TransactionDateKey )
		INCLUDE (
        AmountTRY,
        MerchantCommissionTRY,
        CashbackAmountTRY
    );
END;
GO          --Covering index, check the included parts


--Starting to test for the optimization! (AGAIN)

GO

SET STATISTICS IO ON;
SET STATISTICS TIME ON;
GO

SELECT
	dateDimension.CalendarYear,
	dateDimension.MonthNumber,
	dateDimension.MonthName,

	COUNT_BIG(*) AS TransactionCount,

	SUM(fact.AmountTRY)
	AS TotalTransactionVolumeTRY,

	CAST(AVG(fact.AmountTRY)
	AS DECIMAL(19,2))
	AS AverageTransactionAmountTRY,

	SUM(fact.MerchantCommissionTRY)
	AS TotalMerchantCommissionTRY,

	SUM(fact.CashbackAmountTRY)
	AS TotalCashbackCostTRY

FROM dw.FactPaymentTransaction AS fact

INNER JOIN dw.DimDate AS dateDimension					--Avoided using alias, it will make everything more complex
	ON dateDimension.DateKey = fact.TransactionDateKey

WHERE fact.TransactionDateKey
      BETWEEN 20240101 AND 20261231

GROUP BY
    dateDimension.CalendarYear,
    dateDimension.MonthNumber,
    dateDimension.MonthName

ORDER BY
    dateDimension.CalendarYear,
    dateDimension.MonthNumber;
GO

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO