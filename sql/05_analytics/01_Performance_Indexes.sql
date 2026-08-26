USE PaymentProjectDW;
GO

SET NOCOUNT ON;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dw.FactPaymentTransaction')
      AND name = N'IX_FactPaymentTransaction_TransactionDateKey_Covering'
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_FactPaymentTransaction_TransactionDateKey_Covering
        ON dw.FactPaymentTransaction (TransactionDateKey)
        INCLUDE (AmountTRY, MerchantCommissionTRY, CashbackAmountTRY);
END;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dw.FactPaymentTransaction')
      AND name = N'IX_FactPaymentTransaction_Channel_Date_Covering'
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_FactPaymentTransaction_Channel_Date_Covering
        ON dw.FactPaymentTransaction (PaymentChannelKey, TransactionDateKey)
        INCLUDE (TransactionStatusKey, IsFraud, AmountTRY);
END;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dw.FactPaymentTransaction')
      AND name = N'IX_FactPaymentTransaction_Merchant_Date_Covering'
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_FactPaymentTransaction_Merchant_Date_Covering
        ON dw.FactPaymentTransaction (MerchantKey, TransactionDateKey)
        INCLUDE (TransactionStatusKey, IsFraud, AmountTRY, MerchantCommissionTRY);
END;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dw.FactPaymentTransaction')
      AND name = N'NCCI_FactPaymentTransaction_Analytics'
)
BEGIN
    CREATE NONCLUSTERED COLUMNSTORE INDEX NCCI_FactPaymentTransaction_Analytics
        ON dw.FactPaymentTransaction (
            TransactionDateKey, CustomerKey, CardKey, MerchantKey,
            PaymentChannelKey, CurrencyKey, TransactionStatusKey,
            DeviceKey, FraudReasonKey, AmountTRY, FeeAmountTRY,
            MerchantCommissionTRY, TaxAmountTRY, CashbackAmountTRY,
            AuthorizationDurationMs, IsInternational, IsContactless,
            IsRecurring, IsFraud, FraudScore
        );
END;
GO

SET NOCOUNT OFF;
GO
