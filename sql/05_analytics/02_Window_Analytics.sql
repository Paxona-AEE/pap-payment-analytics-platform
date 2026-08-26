USE PaymentProjectDW;
GO

SET NOCOUNT ON;
GO

------------------------------------------------------------
-- MERCHANT TOPLAM HACİMLERİ
------------------------------------------------------------

;WITH MerchantVolume AS(
    SELECT
        merchant.MerchantKey,
        merchant.MerchantName,
        merchant.MerchantCategory,

        COUNT_BIG(*) AS TransactionCount,

        SUM(fact.AmountTRY) AS TotalAmountTRY

    FROM dw.FactPaymentTransaction AS fact

    INNER JOIN dw.DimMerchant AS merchant
        ON merchant.MerchantKey = fact.MerchantKey

    GROUP BY
        merchant.MerchantKey,
        merchant.MerchantName,
        merchant.MerchantCategory
)
SELECT
    MerchantKey,
    MerchantName,
    MerchantCategory,

    TransactionCount,
    TotalAmountTRY,

    ROW_NUMBER() OVER(
        ORDER BY TotalAmountTRY DESC
    ) AS VolumeRowNumber,

    RANK() OVER(
        ORDER BY TotalAmountTRY DESC
    ) AS VolumeRank,

    DENSE_RANK() OVER(
        ORDER BY TotalAmountTRY DESC
    ) AS VolumeDenseRank

FROM MerchantVolume

ORDER BY TotalAmountTRY DESC;
GO




--Category Merchants

;WITH MerchantVolume AS
(
    SELECT
        merchant.MerchantKey,
        merchant.MerchantName,
        merchant.MerchantCategory,

        COUNT_BIG(*) AS TransactionCount,

        SUM(fact.AmountTRY) AS TotalAmountTRY

    FROM dw.FactPaymentTransaction AS fact

    INNER JOIN dw.DimMerchant AS merchant
        ON merchant.MerchantKey =
           fact.MerchantKey

    GROUP BY
        merchant.MerchantKey,
        merchant.MerchantName,
        merchant.MerchantCategory
),
RankedMerchant AS
(
    SELECT
        MerchantKey,
        MerchantName,
        MerchantCategory,

        TransactionCount,
        TotalAmountTRY,

        DENSE_RANK() OVER
        (
            PARTITION BY MerchantCategory --3/3 Works Well
            ORDER BY TotalAmountTRY DESC
        ) AS CategoryVolumeRank

    FROM MerchantVolume
)
SELECT
    MerchantKey,
    MerchantName,
    MerchantCategory,

    TransactionCount,
    TotalAmountTRY,
    CategoryVolumeRank

FROM RankedMerchant

WHERE CategoryVolumeRank <= 3 --From Every Sector

ORDER BY
    MerchantCategory,
    CategoryVolumeRank,
    MerchantName;
GO



--Monthly Volume

;WITH MonthlyVolume AS
(
    SELECT
        dateData.CalendarYear,
        dateData.MonthNumber,

        MIN(dateData.MonthName) AS MonthName,

        COUNT_BIG(*) AS TransactionCount,

        SUM(fact.AmountTRY) AS MonthlyAmountTRY

    FROM dw.FactPaymentTransaction AS fact

    INNER JOIN dw.DimDate AS dateData
        ON dateData.DateKey =
           fact.TransactionDateKey

    GROUP BY
        dateData.CalendarYear,
        dateData.MonthNumber
)
SELECT
    CalendarYear,
    MonthNumber,
    MonthName,

    TransactionCount,
    MonthlyAmountTRY,

    --------------------------------------------------------
    -- BAŞLANGIÇTAN BU AYA KADAR BİRİKEN HACİM
    --------------------------------------------------------

    SUM(MonthlyAmountTRY) OVER
    (
        ORDER BY
            CalendarYear,
            MonthNumber

        ROWS BETWEEN
            UNBOUNDED PRECEDING
            AND CURRENT ROW     --Continuous update
    ) AS RunningTotalAmountTRY

FROM MonthlyVolume

ORDER BY
    CalendarYear,
    MonthNumber;
GO



--YTD Running,

;WITH MonthlyVolume AS
(
    SELECT
        dateData.CalendarYear,
        dateData.MonthNumber,

        MIN(dateData.MonthName) AS MonthName,

        SUM(fact.AmountTRY) AS MonthlyAmountTRY

    FROM dw.FactPaymentTransaction AS fact

    INNER JOIN dw.DimDate AS dateData
        ON dateData.DateKey =
           fact.TransactionDateKey

    GROUP BY
        dateData.CalendarYear,
        dateData.MonthNumber
)
SELECT
    CalendarYear,
    MonthNumber,
    MonthName,
    MonthlyAmountTRY,

    SUM(MonthlyAmountTRY) OVER
    (
        PARTITION BY CalendarYear --YTD Driver

        ORDER BY MonthNumber

        ROWS BETWEEN
            UNBOUNDED PRECEDING
            AND CURRENT ROW
    ) AS YearToDateAmountTRY

FROM MonthlyVolume

ORDER BY
    CalendarYear,
    MonthNumber;
GO


--Passed the LAG() and LEAD(), hard to model in this case. One earlier value, one late value

--Jan+Feb+March

------------------------------------------------------------
-- 3 AYLIK HAREKETLİ ORTALAMA
------------------------------------------------------------

;WITH MonthlyVolume AS(
    SELECT
        dateData.CalendarYear,
        dateData.MonthNumber,

        MIN(dateData.MonthName)
            AS MonthName,

        SUM(fact.AmountTRY)
            AS MonthlyAmountTRY

    FROM dw.FactPaymentTransaction AS fact

    INNER JOIN dw.DimDate AS dateData
        ON dateData.DateKey = fact.TransactionDateKey

    GROUP BY
        dateData.CalendarYear,
        dateData.MonthNumber
    )

SELECT
    CalendarYear,
    MonthNumber,
    MonthName,

    MonthlyAmountTRY,

    AVG(MonthlyAmountTRY)

    OVER(
        ORDER BY
            CalendarYear,
            MonthNumber

        ROWS BETWEEN
            2 PRECEDING
            AND CURRENT ROW
    ) AS ThreeMonthMovingAverageTRY

FROM MonthlyVolume

ORDER BY
    CalendarYear,
    MonthNumber;
GO

--Three Part Category Dimension

------------------------------------------------------------
-- KATEGORİ İÇİNDE MERCHANT PAYI
------------------------------------------------------------

;WITH MerchantVolume AS
(
    SELECT
        merchant.MerchantKey,
        merchant.MerchantName,
        merchant.MerchantCategory,

        SUM(fact.AmountTRY)
            AS TotalAmountTRY

    FROM dw.FactPaymentTransaction AS fact

    INNER JOIN dw.DimMerchant AS merchant
        ON merchant.MerchantKey =
           fact.MerchantKey

    GROUP BY
        merchant.MerchantKey,
        merchant.MerchantName,
        merchant.MerchantCategory
)
SELECT
    MerchantKey,
    MerchantName,
    MerchantCategory,

    TotalAmountTRY,

    SUM(TotalAmountTRY) OVER
    (
        PARTITION BY MerchantCategory
    ) AS CategoryTotalAmountTRY,

    CAST
    (
        100.0 * TotalAmountTRY
        /
        NULLIF
        (
            SUM(TotalAmountTRY) OVER
            (
                PARTITION BY MerchantCategory
            ),
            0
        )

        AS DECIMAL(10,4)
    ) AS CategoryVolumeSharePercent

FROM MerchantVolume

ORDER BY
    MerchantCategory,
    TotalAmountTRY DESC;
GO



------------------------------------------------------------
-- MÜŞTERİNİN ÖNCEKİ İŞLEMİYLE KARŞILAŞTIRMA
------------------------------------------------------------

;WITH CustomerTransactions AS
(
    SELECT
        fact.PaymentTransactionKey,
        fact.TransactionID,
        fact.CustomerKey,

        customer.CustomerID,

        fact.TransactionTimestamp,
        fact.AmountTRY,

        LAG(fact.TransactionTimestamp) OVER
        (
            PARTITION BY fact.CustomerKey

            ORDER BY
                fact.TransactionTimestamp,
                fact.PaymentTransactionKey
        ) AS PreviousTransactionTimestamp,

        LAG(fact.AmountTRY) OVER
        (
            PARTITION BY fact.CustomerKey

            ORDER BY
                fact.TransactionTimestamp,
                fact.PaymentTransactionKey
        ) AS PreviousTransactionAmountTRY

    FROM dw.FactPaymentTransaction AS fact

    INNER JOIN dw.DimCustomer AS customer
        ON customer.CustomerKey =
           fact.CustomerKey

    WHERE fact.CustomerKey <> 0
)
SELECT TOP (1000)
    PaymentTransactionKey,
    TransactionID,

    CustomerKey,
    CustomerID,

    TransactionTimestamp,
    AmountTRY,

    PreviousTransactionTimestamp,
    PreviousTransactionAmountTRY,

    AmountTRY -
    PreviousTransactionAmountTRY
        AS ChangeFromPreviousTransactionTRY

FROM CustomerTransactions

ORDER BY
    CustomerKey,
    TransactionTimestamp,
    PaymentTransactionKey;
GO



;WITH CustomerTransactions AS
(
    SELECT
        fact.PaymentTransactionKey,
        fact.TransactionID,
        fact.CustomerKey,

        customer.CustomerID,

        fact.TransactionTimestamp,
        fact.AmountTRY,

        LAG(fact.TransactionTimestamp) OVER
        (
            PARTITION BY fact.CustomerKey

            ORDER BY
                fact.TransactionTimestamp,
                fact.PaymentTransactionKey
        ) AS PreviousTransactionTimestamp

    FROM dw.FactPaymentTransaction AS fact

    INNER JOIN dw.DimCustomer AS customer
        ON customer.CustomerKey =
           fact.CustomerKey

    WHERE fact.CustomerKey <> 0
)
SELECT TOP (1000)
    PaymentTransactionKey,
    TransactionID,

    CustomerKey,
    CustomerID,

    PreviousTransactionTimestamp,
    TransactionTimestamp,

    DATEDIFF(
        DAY,
        PreviousTransactionTimestamp,
        TransactionTimestamp
    ) AS DaysSincePreviousTransaction,

    AmountTRY

FROM CustomerTransactions

ORDER BY
    CustomerKey,
    TransactionTimestamp,
    PaymentTransactionKey;
GO


------------------------------------------------------------
-- NTILE İLE MÜŞTERİ SEGMENTASYONU
------------------------------------------------------------

;WITH CustomerVolume AS
(
    SELECT
        fact.CustomerKey,

        customer.CustomerID,

        COUNT_BIG(*)
            AS TransactionCount,

        SUM(fact.AmountTRY)
            AS TotalAmountTRY

    FROM dw.FactPaymentTransaction AS fact

    INNER JOIN dw.DimCustomer AS customer
        ON customer.CustomerKey =
           fact.CustomerKey

    WHERE fact.CustomerKey <> 0

    GROUP BY
        fact.CustomerKey,
        customer.CustomerID
),
CustomerQuartile AS
(
    SELECT
        CustomerKey,
        CustomerID,

        TransactionCount,
        TotalAmountTRY,

        NTILE(4) OVER  --Good for partition
        (
            ORDER BY TotalAmountTRY DESC
        ) AS SpendingQuartile

    FROM CustomerVolume
)
SELECT
    CustomerKey,
    CustomerID,

    TransactionCount,
    TotalAmountTRY,

    SpendingQuartile,

    CASE SpendingQuartile
        WHEN 1 THEN 'Highest Spending Group'
        WHEN 2 THEN 'High Spending Group'
        WHEN 3 THEN 'Medium Spending Group'
        WHEN 4 THEN 'Lower Spending Group'
    END AS SpendingGroup

FROM CustomerQuartile

ORDER BY
    SpendingQuartile,
    TotalAmountTRY DESC;
GO
