IF SCHEMA_ID(N'report') IS NULL
BEGIN
    EXEC(N'CREATE SCHEMA report AUTHORIZATION dbo;');
END;
GO

CREATE OR ALTER VIEW report.vwPaymentTransactionDetail
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

    fact.AuthorizationDateKey,

    authorizationDate.FullDate
        AS AuthorizationDate,

    fact.SettlementDateKey,

    settlementDate.FullDate
        AS SettlementDate,

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

    card.IssueDate
        AS CardIssueDate,

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

    CONVERT
    (
        BIT,
        CASE
            WHEN status.StatusCode = 'APPROVED'
            THEN 1
            ELSE 0
        END
    ) AS IsApproved,

    fact.DeviceKey,
    fact.FraudReasonKey,
    fraudReason.FraudReasonCode,

    fact.OriginalAmount,
    fact.ExchangeRateToTRY,
    fact.AmountTRY,

    fact.FeeAmountTRY,
    fact.MerchantCommissionTRY,
    fact.TaxAmountTRY,
    fact.CashbackAmountTRY,

    CAST(fact.FeeAmountTRY+fact.MerchantCommissionTRY

        AS DECIMAL(19,4)
    ) AS GrossRevenueTRY,

    CAST(fact.FeeAmountTRY+fact.MerchantCommissionTRY-fact.TaxAmountTRY-fact.CashbackAmountTRY

        AS DECIMAL(19,4)
    ) AS NetRevenueTRY,

    fact.InstallmentCount,
    fact.TransactionCount,

    fact.IsInternational,
    fact.IsContactless,
    fact.IsRecurring,
    fact.Is3DSecure,
    fact.IsTokenized,

    fact.IsFraud,
    fact.FraudScore,

    fact.SourceSystem,
    fact.LoadDateTime

FROM dw.FactPaymentTransaction AS fact

INNER JOIN dw.DimDate AS transactionDate
    ON transactionDate.DateKey =
       fact.TransactionDateKey

LEFT JOIN dw.DimDate AS authorizationDate
    ON authorizationDate.DateKey =
       fact.AuthorizationDateKey

LEFT JOIN dw.DimDate AS settlementDate
    ON settlementDate.DateKey =
       fact.SettlementDateKey

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

LEFT JOIN dw.DimFraudReason AS fraudReason
    ON fraudReason.FraudReasonKey =
       fact.FraudReasonKey;
GO

--Check Up

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
      N'vwPaymentTransactionDetail';
GO
