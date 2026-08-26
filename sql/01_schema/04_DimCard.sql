USE PaymentProjectDW;
GO

IF OBJECT_ID(N'dw.DimCard', N'U') IS NULL
BEGIN
CREATE TABLE dw.DimCard (

    CardKey INT IDENTITY(1,1) NOT NULL,
    CardID VARCHAR(30) NOT NULL,
    CardType VARCHAR(20) NOT NULL,
    CardBrand VARCHAR(30) NOT NULL,
    CardTier VARCHAR(30) NULL,
    LastFourDigits CHAR(4) NULL,
    IssueDate DATE NOT NULL,
    ExpiryDate DATE NOT NULL,
    CardStatus VARCHAR(20) NOT NULL,
    CardholderCustomerID VARCHAR(30) NULL,

    IsVirtual BIT NOT NULL
        CONSTRAINT DF_DimCard_IsVirtual
        DEFAULT (0),

    IsContactlessEnabled BIT NOT NULL
        CONSTRAINT DF_DimCard_IsContactless
        DEFAULT (1),

    CardCountry NVARCHAR(100) NULL,

    CONSTRAINT PK_DimCard
        PRIMARY KEY (CardKey),

    CONSTRAINT UQ_DimCard_CardID
        UNIQUE (CardID),

    CONSTRAINT CK_DimCard_CardType
        CHECK (
            CardType IN (
                'Unknown',
                'Credit',
                'Debit',
                'Prepaid'
            )
        ),

    CONSTRAINT CK_DimCard_CardStatus
        CHECK (
            CardStatus IN (
                'Unknown',
                'Active',
                'Blocked',
                'Expired',
                'Cancelled',
                'Suspended'
            )
        ),

    CONSTRAINT CK_DimCard_ExpiryDate
        CHECK (ExpiryDate > IssueDate)
);
END;
GO
