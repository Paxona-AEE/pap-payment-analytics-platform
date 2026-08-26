USE PaymentProjectDW;
GO

;WITH DateSeries AS (
    -- Let's start with 2020, might be best choice
    SELECT CAST('20200101' AS DATE) AS FullDate

    UNION ALL

    -- CTE With 1 Dayy +
    SELECT DATEADD(DAY, 1, FullDate)
    FROM DateSeries
    WHERE FullDate < '20261231'
)
INSERT INTO dw.DimDate (
    DateKey,
    FullDate,

    DayNumber,
    DayOfWeekNumber,
    DayName,

    WeekOfYear,

    MonthNumber,
    MonthName,

    CalendarQuarter,
    CalendarYear,

    FiscalQuarter,
    FiscalYear,

    IsWeekend,
    IsMonthEnd,
    IsQuarterEnd,
    IsYearEnd
)
SELECT
    -- 2026-07-16, 20260716
    CONVERT (
        INT,
        CONVERT (
            CHAR(8),
            FullDate,
            112
        )
    ) AS DateKey,

    FullDate,

    DAY(FullDate) AS DayNumber,
    -- Pazartesi = 1 Salı = 2 ... Pazar = 7 STRAT
    (
        DATEDIFF (
            DAY,
            '19000101',
            FullDate
        ) % 7
    ) + 1 AS DayOfWeekNumber,

    CASE
        WHEN
            (
                DATEDIFF(DAY, '19000101', FullDate) % 7 --Modulo --Modulo
            ) + 1 = 1 THEN N'Pazartesi'

        WHEN
            (
                DATEDIFF(DAY, '19000101', FullDate) % 7
            ) + 1 = 2 THEN N'Salı'

        WHEN
            (
                DATEDIFF(DAY, '19000101', FullDate) % 7
            ) + 1 = 3 THEN N'Çarşamba'

        WHEN
            (
                DATEDIFF(DAY, '19000101', FullDate) % 7
            ) + 1 = 4 THEN N'Perşembe'

        WHEN
            (
                DATEDIFF(DAY, '19000101', FullDate) % 7
            ) + 1 = 5 THEN N'Cuma'

        WHEN
            (
                DATEDIFF(DAY, '19000101', FullDate) % 7
            ) + 1 = 6 THEN N'Cumartesi'

        WHEN
            (
                DATEDIFF(DAY, '19000101', FullDate) % 7
            ) + 1 = 7 THEN N'Pazar'
    END AS DayName,

    DATEPART(ISO_WEEK, FullDate) AS WeekOfYear,

    MONTH(FullDate) AS MonthNumber,

    CASE MONTH(FullDate)
        WHEN 1  THEN N'Ocak'
        WHEN 2  THEN N'Şubat'
        WHEN 3  THEN N'Mart'
        WHEN 4  THEN N'Nisan'
        WHEN 5  THEN N'Mayıs'
        WHEN 6  THEN N'Haziran'
        WHEN 7  THEN N'Temmuz'
        WHEN 8  THEN N'Ağustos'
        WHEN 9  THEN N'Eylül'
        WHEN 10 THEN N'Ekim'
        WHEN 11 THEN N'Kasım'
        WHEN 12 THEN N'Aralık'
    END AS MonthName,

    DATEPART(QUARTER, FullDate) AS CalendarQuarter,

    YEAR(FullDate) AS CalendarYear,

    -- Şimdilik mali çeyrek takvim çeyreğiyle aynı --
    DATEPART(QUARTER, FullDate) AS FiscalQuarter,

    -- Şimdilik mali yıl takvim yılıyla aynı --
    YEAR(FullDate) AS FiscalYear,

    CASE
        WHEN
            (
                DATEDIFF(DAY, '19000101', FullDate) % 7
            ) + 1 IN (6, 7)
        THEN 1
        ELSE 0
    END AS IsWeekend,

    CASE
        WHEN FullDate = EOMONTH(FullDate)
        THEN 1
        ELSE 0
    END AS IsMonthEnd,

    CASE
        WHEN
            FullDate = EOMONTH(FullDate)
            AND MONTH(FullDate) IN (3, 6, 9, 12)
        THEN 1
        ELSE 0
    END AS IsQuarterEnd,

    CASE
        WHEN MONTH(FullDate) = 12
             AND DAY(FullDate) = 31
        THEN 1
        ELSE 0
    END AS IsYearEnd

FROM DateSeries AS d

-- Keep the load rerunnable by inserting only missing dates.
WHERE NOT EXISTS
(
    SELECT 1
    FROM dw.DimDate AS existing
    WHERE existing.DateKey =
        CONVERT
        (
            INT,
            CONVERT
            (
                CHAR(8),
                d.FullDate,
                112
            )
        )
)

OPTION (MAXRECURSION 0);
GO
