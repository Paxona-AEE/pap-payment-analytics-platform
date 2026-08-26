USE PaymentProjectDW;
GO

IF OBJECT_ID(N'dw.DimMerchant', N'U') IS NULL
BEGIN
CREATE TABLE dw.DimMerchant (
    MerchantKey INT IDENTITY(1,1) NOT NULL,
    MerchantID VARCHAR(30) NOT NULL,

    MerchantName NVARCHAR(150) NOT NULL,

    MerchantCategory VARCHAR(100) NOT NULL,
    MerchantSubcategory VARCHAR(100) NULL,
    MerchantCategoryCode CHAR(4) NULL,

    MerchantSize VARCHAR(20) NULL,

    OnboardingDate DATE NOT NULL,

    City NVARCHAR(100) NULL,
    StateProvince NVARCHAR(100) NULL,
    Country NVARCHAR(100) NOT NULL,
    PostalCode VARCHAR(20) NULL,

    IsOnlineMerchant BIT NOT NULL
        CONSTRAINT DF_DimMerchant_IsOnline
        DEFAULT (0),

    MerchantRiskLevel VARCHAR(20) NULL,

    IsActive BIT NOT NULL
        CONSTRAINT DF_DimMerchant_IsActive
        DEFAULT (1),

    CONSTRAINT PK_DimMerchant
        PRIMARY KEY (MerchantKey),

    CONSTRAINT UQ_DimMerchant_MerchantID
        UNIQUE (MerchantID),

    CONSTRAINT CK_DimMerchant_Size
        CHECK
        (
            MerchantSize IS NULL
            OR MerchantSize IN
            (
                'Micro',
                'Small',
                'Medium',
                'Large',
                'Enterprise'
            )
        ),

    CONSTRAINT CK_DimMerchant_RiskLevel
        CHECK (
            MerchantRiskLevel IS NULL
            OR MerchantRiskLevel IN
            (
                'Low',
                'Medium',
                'High',
                'Critical'
            )
        )
);
END;
GO
