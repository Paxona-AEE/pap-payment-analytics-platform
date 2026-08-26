DECLARE
    @SourceBatchCode VARCHAR(50) =
        CONCAT('DEMO-', RIGHT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 12)),

    @TransactionID VARCHAR(50) =
        CONCAT('DEMO-TX-', RIGHT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 12)),

    @CustomerCode VARCHAR(50),
    @CardCode VARCHAR(50),
    @MerchantCode VARCHAR(50),

    @TransactionDate DATE,
    @TransactionTimestamp DATETIME2(3),

    @ValidationBatchID UNIQUEIDENTIFIER = NEWID(),
    @LoadBatchID UNIQUEIDENTIFIER = NEWID();


SELECT TOP (1)
    @CustomerCode = CustomerID
FROM dw.DimCustomer
WHERE CustomerKey <> 0
ORDER BY CustomerKey;


SELECT TOP (1)
    @CardCode = CardID
FROM dw.DimCard
WHERE CardKey <> 0
ORDER BY CardKey;


SELECT TOP (1)
    @MerchantCode = MerchantID
FROM dw.DimMerchant
WHERE MerchantKey <> 0
ORDER BY MerchantKey;


SELECT
    @TransactionDate = MAX(FullDate)
FROM dw.DimDate
WHERE FullDate <= CONVERT(DATE, SYSDATETIME());


SET @TransactionTimestamp =
    DATEADD(
        HOUR,
        10,
        CONVERT(DATETIME2(3), @TransactionDate)
    );


INSERT INTO stg.PaymentTransactionRaw
(
    SourceBatchCode,
    SourceRowNumber,
    SourceFileName,
    SourceTransactionID,
    CustomerCode,
    CardCode,
    MerchantCode,
    TransactionTimestamp,
    OriginalAmount,
    CurrencyCode,
    PaymentChannelCode,
    TransactionStatusCode,
    IsFraud
)
VALUES
(
    @SourceBatchCode,
    1,
    N'end_to_end_test.csv',
    @TransactionID,
    @CustomerCode,
    @CardCode,
    @MerchantCode,
    @TransactionTimestamp,
    1250.0000,
    'TRY',
    'ECOMMERCE',
    'APPROVED',
    0
);


EXEC etl.usp_ValidatePaymentTransactionBatch
    @SourceBatchCode = @SourceBatchCode,
    @ETLBatchID = @ValidationBatchID OUTPUT;


EXEC etl.usp_LoadPaymentTransactionBatch
    @SourceBatchCode = @SourceBatchCode,
    @LoadETLBatchID = @LoadBatchID OUTPUT;


SELECT
    raw.SourceBatchCode,
    raw.SourceTransactionID,
    raw.ProcessingStatus,
    raw.RejectReason,

    fact.PaymentTransactionKey,
    fact.TransactionID,
    fact.AmountTRY,
    fact.SourceSystem

FROM stg.PaymentTransactionRaw AS raw

LEFT JOIN etl.PaymentTransactionLoadMap AS loadMap
    ON loadMap.StagingRowID = raw.StagingRowID

LEFT JOIN dw.FactPaymentTransaction AS fact
    ON fact.PaymentTransactionKey =
       loadMap.PaymentTransactionKey

WHERE raw.SourceBatchCode = @SourceBatchCode;