--Starting to test for the optimization!

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



--SQL Server parse and compile time: 
--   CPU time = 15 ms, elapsed time = 30 ms.

--(30 rows affected)
--Table 'Worktable'. Scan count 0, logical reads 0, physical reads 0, page server reads 0, read-ahead reads 0, page server read-ahead reads 0, lob logical reads 0, lob physical reads 0, lob page server reads 0, lob read-ahead reads 0, lob page server read-ahead reads 0.
--Table 'DimDate'. Scan count 1, logical reads 10, physical reads 0, page server reads 0, read-ahead reads 0, page server read-ahead reads 0, lob logical reads 0, lob physical reads 0, lob page server reads 0, lob read-ahead reads 0, lob page server read-ahead reads 0.
--Table 'Workfile'. Scan count 0, logical reads 0, physical reads 0, page server reads 0, read-ahead reads 0, page server read-ahead reads 0, lob logical reads 0, lob physical reads 0, lob page server reads 0, lob read-ahead reads 0, lob page server read-ahead reads 0.
--Table 'FactPaymentTransaction'. Scan count 1, logical reads 28710, physical reads 0, page server reads 0, read-ahead reads 0, page server read-ahead reads 0, lob logical reads 0, lob physical reads 0, lob page server reads 0, lob read-ahead reads 0, lob page server read-ahead reads 0.

-- SQL Server Execution Times:
--   CPU time = 1172 ms,  elapsed time = 1204 ms.
--SQL Server parse and compile time: 
--   CPU time = 0 ms, elapsed time = 0 ms.

 --SQL Server Execution Times:
 --  CPU time = 0 ms,  elapsed time = 0 ms.

--Completion time: 2026-07-17T12:14:50.8211665+03:00
