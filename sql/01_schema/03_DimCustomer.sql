USE PaymentProjectDW;
GO

IF OBJECT_ID(N'dw.DimCustomer', N'U') IS NULL
BEGIN
CREATE TABLE dw.DimCustomer (
    CustomerKey INT IDENTITY(1,1) NOT NULL,
    CustomerID VARCHAR(30) NOT NULL,

    FullName NVARCHAR(150) NOT NULL,
    BirthDate DATE NULL,

    CustomerSegment VARCHAR(30) NOT NULL,
    IncomeBand VARCHAR(30) NULL,
    RiskLevel VARCHAR(20) NULL,

    RegistrationDate DATE NOT NULL,

    City NVARCHAR(100) NULL,
    StateProvince NVARCHAR(100) NULL,
    Country NVARCHAR(100) NOT NULL,
    PostalCode VARCHAR(20) NULL,

    IsActive BIT NOT NULL
        CONSTRAINT DF_DimCustomer_IsActive
        DEFAULT (1),

    CONSTRAINT PK_DimCustomer
        PRIMARY KEY (CustomerKey),

    CONSTRAINT UQ_DimCustomer_CustomerID
        UNIQUE (CustomerID),

    CONSTRAINT CK_DimCustomer_Segment
        CHECK (
            CustomerSegment IN (
                'Unknown',
                'Standard',
                'Silver',
                'Gold',
                'Platinum',
                'Corporate'
            )
        ),

    CONSTRAINT CK_DimCustomer_RiskLevel
        CHECK (
            RiskLevel IS NULL
            OR RiskLevel IN (
                'Low',
                'Medium',
                'High',
                'Critical'
            )
        )
);
END;
GO
