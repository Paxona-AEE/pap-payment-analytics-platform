CREATE TABLE dw.FactPaymentTransaction (

    PaymentTransactionKey BIGINT IDENTITY(1,1) NOT NULL,
    TransactionID VARCHAR(50) NOT NULL,
    TransactionReference VARCHAR(100) NULL,
    TransactionDateKey INT NOT NULL,
    AuthorizationDateKey INT NULL,
    SettlementDateKey INT NULL,
    CustomerKey INT NOT NULL,
    CardKey INT NOT NULL,
    MerchantKey INT NOT NULL,
    PaymentChannelKey SMALLINT NOT NULL,
    CurrencyKey SMALLINT NOT NULL,
    TransactionStatusKey TINYINT NOT NULL,
    DeviceKey INT NULL,
    FraudReasonKey SMALLINT NULL,
    TransactionTimestamp DATETIME2(3) NOT NULL,
    AuthorizationTimestamp DATETIME2(3) NULL,
    SettlementTimestamp DATETIME2(3) NULL,
    OriginalAmount DECIMAL(19,4) NOT NULL,
    ExchangeRateToTRY DECIMAL(19,8) NOT NULL,
    AmountTRY DECIMAL(19,4) NOT NULL,

    FeeAmountTRY DECIMAL(19,4) NOT NULL
        CONSTRAINT DF_FactPayment_FeeAmount
        DEFAULT (0),

    MerchantCommissionTRY DECIMAL(19,4) NOT NULL
        CONSTRAINT DF_FactPayment_Commission
        DEFAULT (0),

    TaxAmountTRY DECIMAL(19,4) NOT NULL
        CONSTRAINT DF_FactPayment_Tax
        DEFAULT (0),

    CashbackAmountTRY DECIMAL(19,4) NOT NULL
        CONSTRAINT DF_FactPayment_Cashback
        DEFAULT (0),

    InstallmentCount TINYINT NOT NULL
        CONSTRAINT DF_FactPayment_InstallmentCount
        DEFAULT (1),

    TransactionCount TINYINT NOT NULL
        CONSTRAINT DF_FactPayment_TransactionCount
        DEFAULT (1),

    AuthorizationDurationMs INT NULL,

    IsInternational BIT NOT NULL
        CONSTRAINT DF_FactPayment_IsInternational
        DEFAULT (0),

    IsContactless BIT NOT NULL
        CONSTRAINT DF_FactPayment_IsContactless
        DEFAULT (0),

    IsRecurring BIT NOT NULL
        CONSTRAINT DF_FactPayment_IsRecurring
        DEFAULT (0),

    Is3DSecure BIT NOT NULL
        CONSTRAINT DF_FactPayment_Is3DSecure
        DEFAULT (0),

    IsTokenized BIT NOT NULL
        CONSTRAINT DF_FactPayment_IsTokenized
        DEFAULT (0),

    IsFraud BIT NOT NULL
        CONSTRAINT DF_FactPayment_IsFraud
        DEFAULT (0),

    FraudScore DECIMAL(5,2) NULL,

    SourceSystem VARCHAR(50) NOT NULL
        CONSTRAINT DF_FactPayment_SourceSystem
        DEFAULT ('SyntheticGenerator'),

    LoadDateTime DATETIME2(0) NOT NULL
        CONSTRAINT DF_FactPayment_LoadDateTime
        DEFAULT (SYSDATETIME()),

    CONSTRAINT PK_FactPaymentTransaction
        PRIMARY KEY (PaymentTransactionKey),

    CONSTRAINT UQ_FactPaymentTransaction_TransactionID
        UNIQUE (TransactionID),

    CONSTRAINT FK_FactPayment_TransactionDate
        FOREIGN KEY (TransactionDateKey)
        REFERENCES dw.DimDate(DateKey),

    CONSTRAINT FK_FactPayment_AuthorizationDate
        FOREIGN KEY (AuthorizationDateKey)
        REFERENCES dw.DimDate(DateKey),

    CONSTRAINT FK_FactPayment_SettlementDate
        FOREIGN KEY (SettlementDateKey)
        REFERENCES dw.DimDate(DateKey),

    CONSTRAINT FK_FactPayment_Customer
        FOREIGN KEY (CustomerKey)
        REFERENCES dw.DimCustomer(CustomerKey),

    CONSTRAINT FK_FactPayment_Card
        FOREIGN KEY (CardKey)
        REFERENCES dw.DimCard(CardKey),

    CONSTRAINT FK_FactPayment_Merchant
        FOREIGN KEY (MerchantKey)
        REFERENCES dw.DimMerchant(MerchantKey),

    CONSTRAINT FK_FactPayment_Channel
        FOREIGN KEY (PaymentChannelKey)
        REFERENCES dw.DimPaymentChannel(PaymentChannelKey),

    CONSTRAINT FK_FactPayment_Currency
        FOREIGN KEY (CurrencyKey)
        REFERENCES dw.DimCurrency(CurrencyKey),

    CONSTRAINT FK_FactPayment_Status
        FOREIGN KEY (TransactionStatusKey)
        REFERENCES dw.DimTransactionStatus(TransactionStatusKey),

    CONSTRAINT FK_FactPayment_Device
        FOREIGN KEY (DeviceKey)
        REFERENCES dw.DimDevice(DeviceKey),

    CONSTRAINT FK_FactPayment_FraudReason
        FOREIGN KEY (FraudReasonKey)
        REFERENCES dw.DimFraudReason(FraudReasonKey),

    CONSTRAINT CK_FactPayment_OriginalAmount
        CHECK (OriginalAmount > 0),

    CONSTRAINT CK_FactPayment_ExchangeRate
        CHECK (ExchangeRateToTRY > 0),

    CONSTRAINT CK_FactPayment_AmountTRY
        CHECK (AmountTRY > 0),

    CONSTRAINT CK_FactPayment_FeeAmount
        CHECK (FeeAmountTRY >= 0),

    CONSTRAINT CK_FactPayment_Commission
        CHECK (MerchantCommissionTRY >= 0),

    CONSTRAINT CK_FactPayment_TaxAmount
        CHECK (TaxAmountTRY >= 0),

    CONSTRAINT CK_FactPayment_Cashback
        CHECK (CashbackAmountTRY >= 0),

    CONSTRAINT CK_FactPayment_InstallmentCount
        CHECK (InstallmentCount BETWEEN 1 AND 36),

    CONSTRAINT CK_FactPayment_TransactionCount
        CHECK (TransactionCount = 1),

    CONSTRAINT CK_FactPayment_AuthorizationDuration
        CHECK (
            AuthorizationDurationMs IS NULL
            OR AuthorizationDurationMs >= 0
        ),

    CONSTRAINT CK_FactPayment_FraudScore
        CHECK (
            FraudScore IS NULL
            OR FraudScore BETWEEN 0 AND 100
        ),

    CONSTRAINT CK_FactPayment_Timestamps
        CHECK (
            AuthorizationTimestamp IS NULL
            OR AuthorizationTimestamp >= TransactionTimestamp
        ),

    CONSTRAINT CK_FactPayment_SettlementTimestamp
        CHECK (
            SettlementTimestamp IS NULL
            OR AuthorizationTimestamp IS NULL
            OR SettlementTimestamp >= AuthorizationTimestamp
        )
);
GO