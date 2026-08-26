CREATE TABLE dw.DimPaymentChannel (
    PaymentChannelKey SMALLINT IDENTITY(1,1) NOT NULL,

    PaymentChannelCode VARCHAR(20) NOT NULL,
    PaymentChannelName NVARCHAR(50) NOT NULL,

    ChannelGroup VARCHAR(30) NOT NULL,

    IsCardPresent BIT NOT NULL,

    ChannelDescription NVARCHAR(250) NULL,

    CONSTRAINT PK_DimPaymentChannel
        PRIMARY KEY (PaymentChannelKey),

    CONSTRAINT UQ_DimPaymentChannel_Code
        UNIQUE (PaymentChannelCode),

    CONSTRAINT CK_DimPaymentChannel_Group
        CHECK (
            ChannelGroup IN (
                'Physical',
                'Digital',
                'Recurring',
                'ATM',
                'Other'
            )
        )
);
GO