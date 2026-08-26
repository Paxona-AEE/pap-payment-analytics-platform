USE PaymentProjectDW;
GO

IF OBJECT_ID(N'dw.DimFraudReason', N'U') IS NULL
BEGIN
CREATE TABLE dw.DimFraudReason (

    FraudReasonKey SMALLINT IDENTITY(1,1) NOT NULL,
    FraudReasonCode VARCHAR(30) NOT NULL,
    FraudCategory VARCHAR(50) NOT NULL,
    FraudReasonName NVARCHAR(100) NOT NULL,
    SeverityLevel VARCHAR(20) NOT NULL,
    FraudReasonDescription NVARCHAR(300) NULL,

    IsActive BIT NOT NULL
        CONSTRAINT DF_DimFraudReason_IsActive
        DEFAULT (1),

    CONSTRAINT PK_DimFraudReason
        PRIMARY KEY (FraudReasonKey),

    CONSTRAINT UQ_DimFraudReason_Code
        UNIQUE (FraudReasonCode),

    CONSTRAINT CK_DimFraudReason_Severity
        CHECK (
            SeverityLevel IN (
                'None',
                'Low',
                'Medium',
                'High',
                'Critical'
            )
        )
);
END;
GO
