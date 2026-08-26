USE PaymentProjectDW;
GO

CREATE OR ALTER VIEW report.vwFraudTransactionDetail
AS
SELECT

    fact.PaymentTransactionKey,
    fact.TransactionID,
    fact.TransactionReference,

    fact.TransactionDateKey,

    transactionDate.FullDate
        AS TransactionDate,

    transactionDate.CalendarYear,
    transactionDate.CalendarQuarter,
    transactionDate.MonthNumber,
    transactionDate.MonthName,
    transactionDate.WeekOfYear,
    transactionDate.DayName,
    transactionDate.IsWeekend,

    fact.TransactionTimestamp,
    fact.AuthorizationTimestamp,
    fact.SettlementTimestamp,
    fact.AuthorizationDurationMs,

    fact.CustomerKey,
    customer.CustomerID,
    customer.CustomerSegment,

    customer.RiskLevel
        AS CustomerRiskLevel,

    customer.Country
        AS CustomerCountry,

    customer.RegistrationDate
        AS CustomerRegistrationDate,

    fact.CardKey,
    card.CardID,
    card.CardType,
    card.CardBrand,
    card.CardTier,

    card.IsVirtual
        AS IsVirtualCard,

    card.IsContactlessEnabled,
    card.CardCountry,

    fact.MerchantKey,
    merchant.MerchantID,
    merchant.MerchantName,
    merchant.MerchantCategory,
    merchant.MerchantSubcategory,
    merchant.MerchantCategoryCode,
    merchant.MerchantSize,
    merchant.MerchantRiskLevel,

    merchant.Country
        AS MerchantCountry,

    merchant.IsOnlineMerchant,

    fact.PaymentChannelKey,
    channel.PaymentChannelCode,

    fact.CurrencyKey,
    currency.CurrencyCode,

    fact.TransactionStatusKey,

    status.StatusCode
        AS TransactionStatusCode,

    fact.DeviceKey,
    fact.FraudReasonKey,
    fraudReason.FraudReasonCode,

    fact.IsFraud,
    fact.FraudScore,

    CASE
        WHEN fact.FraudScore >= 90
        THEN 'Critical'

        WHEN fact.FraudScore >= 80
        THEN 'High'

        WHEN fact.FraudScore >= 70
        THEN 'Medium'

        ELSE 'Low'
    END AS FraudSeverity,

    fact.OriginalAmount,
    fact.ExchangeRateToTRY,
    fact.AmountTRY,

    fact.FeeAmountTRY,
    fact.MerchantCommissionTRY,
    fact.TaxAmountTRY,
    fact.CashbackAmountTRY,

    fact.InstallmentCount,
    fact.IsInternational,
    fact.IsContactless,
    fact.IsRecurring,
    fact.Is3DSecure,
    fact.IsTokenized,

    fact.SourceSystem,
    fact.LoadDateTime

FROM dw.FactPaymentTransaction AS fact

INNER JOIN dw.DimDate AS transactionDate
    ON transactionDate.DateKey =
       fact.TransactionDateKey

INNER JOIN dw.DimCustomer AS customer
    ON customer.CustomerKey =
       fact.CustomerKey

INNER JOIN dw.DimCard AS card
    ON card.CardKey =
       fact.CardKey

INNER JOIN dw.DimMerchant AS merchant
    ON merchant.MerchantKey =
       fact.MerchantKey

INNER JOIN dw.DimPaymentChannel AS channel
    ON channel.PaymentChannelKey =
       fact.PaymentChannelKey

INNER JOIN dw.DimCurrency AS currency
    ON currency.CurrencyKey =
       fact.CurrencyKey

INNER JOIN dw.DimTransactionStatus AS status
    ON status.TransactionStatusKey =
       fact.TransactionStatusKey

INNER JOIN dw.DimFraudReason AS fraudReason
    ON fraudReason.FraudReasonKey =
       fact.FraudReasonKey

WHERE fact.IsFraud = 1;
GO

--View

SELECT
    schemaData.name AS SchemaName,
    viewData.name AS ViewName,
    viewData.create_date AS CreateDate,
    viewData.modify_date AS ModifyDate

FROM sys.views AS viewData

INNER JOIN sys.schemas AS schemaData
    ON schemaData.schema_id =
       viewData.schema_id

WHERE schemaData.name = N'report'
  AND viewData.name =
      N'vwFraudTransactionDetail';
GO
