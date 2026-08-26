USE PaymentProjectDW;
GO

IF OBJECT_ID(N'dw.DimCurrency', N'U') IS NULL
BEGIN
CREATE TABLE dw.DimCurrency (
    CurrencyKey SMALLINT IDENTITY(1,1) NOT NULL,

    CurrencyCode CHAR(3) NOT NULL,
    CurrencyName NVARCHAR(50) NOT NULL,
    CurrencySymbol NVARCHAR(10) NULL,

    DecimalPlaces TINYINT NOT NULL
        CONSTRAINT DF_DimCurrency_DecimalPlaces
        DEFAULT (2),

    IsActive BIT NOT NULL
        CONSTRAINT DF_DimCurrency_IsActive
        DEFAULT (1),

    CONSTRAINT PK_DimCurrency
        PRIMARY KEY (CurrencyKey),

    CONSTRAINT UQ_DimCurrency_Code
        UNIQUE (CurrencyCode),

    CONSTRAINT CK_DimCurrency_DecimalPlaces
        CHECK (DecimalPlaces BETWEEN 0 AND 4)
);
END;
GO
