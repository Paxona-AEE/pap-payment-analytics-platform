USE PaymentProjectDW;
GO

IF OBJECT_ID(N'dw.DimDate', N'U') IS NULL
BEGIN
CREATE TABLE dw.DimDate (

    DateKey INT NOT NULL,
    FullDate DATE NOT NULL,

    DayNumber TINYINT NOT NULL,
    DayOfWeekNumber TINYINT NOT NULL,
    DayName NVARCHAR(20) NOT NULL,

    WeekOfYear TINYINT NOT NULL,

    MonthNumber TINYINT NOT NULL,
    MonthName NVARCHAR(20) NOT NULL,

    CalendarQuarter TINYINT NOT NULL,
    CalendarYear SMALLINT NOT NULL,

    FiscalQuarter TINYINT NULL,
    FiscalYear SMALLINT NULL,

    IsWeekend BIT NOT NULL,
    IsMonthEnd BIT NOT NULL,
    IsQuarterEnd BIT NOT NULL,
    IsYearEnd BIT NOT NULL,

    CONSTRAINT PK_DimDate
        PRIMARY KEY (DateKey),

    CONSTRAINT UQ_DimDate_FullDate
        UNIQUE (FullDate),

    CONSTRAINT CK_DimDate_DayNumber
        CHECK (DayNumber BETWEEN 1 AND 31),

    CONSTRAINT CK_DimDate_DayOfWeek
        CHECK (DayOfWeekNumber BETWEEN 1 AND 7),

    CONSTRAINT CK_DimDate_MonthNumber
        CHECK (MonthNumber BETWEEN 1 AND 12),

    CONSTRAINT CK_DimDate_CalendarQuarter
        CHECK (CalendarQuarter BETWEEN 1 AND 4),

    CONSTRAINT CK_DimDate_FiscalQuarter
        CHECK (
            FiscalQuarter IS NULL
            OR FiscalQuarter BETWEEN 1 AND 4
        )
);
END;
GO
