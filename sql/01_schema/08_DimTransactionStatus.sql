USE PaymentProjectDW;
GO

IF OBJECT_ID(N'dw.DimTransactionStatus', N'U') IS NULL
BEGIN
CREATE TABLE dw.DimTransactionStatus(
    TransactionStatusKey TINYINT IDENTITY(1,1) NOT NULL,

    StatusCode VARCHAR(20) NOT NULL,
    StatusName NVARCHAR(50) NOT NULL,

    StatusGroup VARCHAR(30) NOT NULL,

    IsSuccessful BIT NOT NULL,
    IsFinalStatus BIT NOT NULL,

    StatusDescription NVARCHAR(250) NULL,

    CONSTRAINT PK_DimTransactionStatus
        PRIMARY KEY (TransactionStatusKey),

    CONSTRAINT UQ_DimTransactionStatus_Code
        UNIQUE (StatusCode),

    CONSTRAINT CK_DimTransactionStatus_Group
        CHECK (
            StatusGroup IN (
                'Unknown',
                'Successful',
                'Pending',
                'Failed',
                'Cancelled',
                'Reversed'
            )
        )
);
END;
GO
