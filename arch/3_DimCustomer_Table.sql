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

    EffectiveStartDate DATE NOT NULL
        CONSTRAINT DF_DimCustomer_EffectiveStartDate  --Unique constraints with defaults, #manage the nulls#
        DEFAULT ('19000101'),

    EffectiveEndDate DATE NOT NULL
        CONSTRAINT DF_DimCustomer_EffectiveEndDate
        DEFAULT ('99991231'),

    IsCurrent BIT NOT NULL
        CONSTRAINT DF_DimCustomer_IsCurrent
        DEFAULT (1),

    CONSTRAINT PK_DimCustomer
        PRIMARY KEY (CustomerKey),

    CONSTRAINT UQ_DimCustomer_CustomerID
        UNIQUE (CustomerID),

    CONSTRAINT CK_DimCustomer_Segment
        CHECK (
            CustomerSegment IN (
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
        ),

    CONSTRAINT CK_DimCustomer_EffectiveDates
        CHECK (EffectiveEndDate >= EffectiveStartDate)
);
GO