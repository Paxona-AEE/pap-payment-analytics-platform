/*
    -- PaymentProjectDW - Payment Transaction Staging --0

    PURPOSE
      - Receive raw payment transaction rows
      - Preserve source batch and row lineage
      - Support validation, rejection and Fact loading

    NOTES
      - Staging deliberately accepts incomplete or invalid business data
      - The payment ETL procedure will validate and classify those rows later
      - Demo data is commented out at the bottom and is not executed during setup
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO


IF SCHEMA_ID(N'stg') IS NULL
BEGIN
    EXEC(N'CREATE SCHEMA stg AUTHORIZATION dbo;');
END;
GO

------------------------------------------------------------
-- RAW PAYMENT TRANSACTION TABLE

IF OBJECT_ID(N'stg.PaymentTransactionRaw', N'U') IS NULL
BEGIN
    CREATE TABLE stg.PaymentTransactionRaw
    (
        StagingRowID BIGINT IDENTITY(1,1) NOT NULL,

        SourceBatchCode VARCHAR(50) NOT NULL,
        SourceRowNumber INT NOT NULL,
        SourceFileName NVARCHAR(260) NULL,

        SourceTransactionID VARCHAR(50) NULL,
        CustomerCode VARCHAR(50) NULL,
        CardCode VARCHAR(50) NULL,
        MerchantCode VARCHAR(50) NULL,

        TransactionTimestamp DATETIME2(3) NULL,
        OriginalAmount DECIMAL(19,4) NULL,
        CurrencyCode CHAR(3) NULL,
        PaymentChannelCode VARCHAR(50) NULL,
        TransactionStatusCode VARCHAR(50) NULL,
        IsFraud BIT NULL,

        ProcessingStatus VARCHAR(20) NOT NULL
            CONSTRAINT DF_PaymentTransactionRaw_Status
            DEFAULT ('NEW'),

        RejectReason NVARCHAR(1000) NULL,
        ETLBatchID UNIQUEIDENTIFIER NULL,

        ReceivedDateTime DATETIME2(3) NOT NULL
            CONSTRAINT DF_PaymentTransactionRaw_Received
            DEFAULT (SYSDATETIME()),

        ProcessedDateTime DATETIME2(3) NULL,

        CONSTRAINT PK_PaymentTransactionRaw
            PRIMARY KEY CLUSTERED (StagingRowID),

        CONSTRAINT UQ_PaymentTransactionRaw_Batch_Row
            UNIQUE
            (
                SourceBatchCode,
                SourceRowNumber
            ),

        CONSTRAINT CK_PaymentTransactionRaw_RowNumber
            CHECK (SourceRowNumber > 0),

        CONSTRAINT CK_PaymentTransactionRaw_Status
            CHECK
            (
                ProcessingStatus IN
                (
                    'NEW',
                    'VALID',
                    'REJECTED',
                    'LOADED'
                )
            )
    );
END;
GO

------------------------------------------------------------
-- BATCH PROCESSING INDEX

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'stg.PaymentTransactionRaw')
      AND name = N'IX_PaymentTransactionRaw_Batch_Status'
)
BEGIN
    CREATE NONCLUSTERED INDEX
        IX_PaymentTransactionRaw_Batch_Status
    ON stg.PaymentTransactionRaw
    (
        SourceBatchCode,
        ProcessingStatus
    )
    INCLUDE
    (
        SourceRowNumber,
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
    );
END;
GO

------------------------------------------------------------
-- INSTALLATION CHECK

SELECT
    schemaData.name AS SchemaName,
    tableData.name AS TableName,
    indexData.name AS BatchIndexName
FROM sys.tables AS tableData
INNER JOIN sys.schemas AS schemaData
    ON schemaData.schema_id = tableData.schema_id
LEFT JOIN sys.indexes AS indexData
    ON indexData.object_id = tableData.object_id
   AND indexData.name = N'IX_PaymentTransactionRaw_Batch_Status'
WHERE schemaData.name = N'stg'
  AND tableData.name = N'PaymentTransactionRaw';
GO

/*
================================================================
OPTIONAL DEMO DATA - RUN ONLY IN A DISPOSABLE TEST DATABASE
================================================================

The first batch contains structurally complete rows. CustomerCode,
CardCode and MerchantCode must also exist in the corresponding
dimensions for these rows to pass the later ETL lookup validation.

The second batch intentionally contains invalid values so that the
reject-handling logic can be tested.

DELETE FROM stg.PaymentTransactionRaw
WHERE SourceBatchCode IN
(
    'SRC-20260718-001',
    'SRC-20260718-002'
);
GO

------------------------------------------------------------
-- DEMO BATCH 1: STRUCTURALLY COMPLETE ROWS
------------------------------------------------------------

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
    'SRC-20260718-001', 1, N'payment_20260718_part1.csv',
    'SRC-TX-1001', 'CUST-001', 'CARD-001', 'MERCH-001',
    '2026-07-18T09:10:00', 1250.0000, 'TRY',
    'ECOMMERCE', 'APPROVED', 0
),
(
    'SRC-20260718-001', 2, N'payment_20260718_part1.csv',
    'SRC-TX-1002', 'CUST-002', 'CARD-002', 'MERCH-002',
    '2026-07-18T09:15:00', 890.5000, 'TRY',
    'POS', 'APPROVED', 0
),
(
    'SRC-20260718-001', 3, N'payment_20260718_part1.csv',
    'SRC-TX-1003', 'CUST-003', 'CARD-003', 'MERCH-003',
    '2026-07-18T09:20:00', 4200.0000, 'TRY',
    'ECOMMERCE', 'DECLINED', 0
),
(
    'SRC-20260718-001', 4, N'payment_20260718_part1.csv',
    'SRC-TX-1004', 'CUST-004', 'CARD-004', 'MERCH-004',
    '2026-07-18T09:25:00', 350.7500, 'EUR',
    'MOBILE', 'APPROVED', 0
),
(
    'SRC-20260718-001', 5, N'payment_20260718_part1.csv',
    'SRC-TX-1005', 'CUST-005', 'CARD-005', 'MERCH-005',
    '2026-07-18T09:30:00', 9800.0000, 'TRY',
    'ECOMMERCE', 'APPROVED', 1
);
GO

------------------------------------------------------------
-- DEMO BATCH 2: INTENTIONALLY INVALID ROWS
------------------------------------------------------------

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
    'SRC-20260718-002', 1, N'payment_20260718_part2.csv',
    'SRC-TX-2001', 'CUST-006', 'CARD-006', 'MERCH-006',
    '2026-07-18T10:00:00', 750.0000, 'TRY',
    'POS', 'APPROVED', 0
),
(
    'SRC-20260718-002', 2, N'payment_20260718_part2.csv',
    'SRC-TX-2002', 'CUST-007', 'CARD-007', 'MERCH-007',
    '2026-07-18T10:05:00', -500.0000, 'TRY',
    'ECOMMERCE', 'APPROVED', 0
),
(
    'SRC-20260718-002', 3, N'payment_20260718_part2.csv',
    NULL, 'CUST-008', 'CARD-008', 'MERCH-008',
    '2026-07-18T10:10:00', 1400.0000, 'TRY',
    'MOBILE', 'APPROVED', 0
),
(
    'SRC-20260718-002', 4, N'payment_20260718_part2.csv',
    'SRC-TX-1002', 'CUST-009', 'CARD-009', 'MERCH-009',
    '2026-07-18T10:15:00', 2100.0000, 'TRY',
    'POS', 'APPROVED', 0
),
(
    'SRC-20260718-002', 5, N'payment_20260718_part2.csv',
    'SRC-TX-2005', 'CUST-010', 'CARD-010', 'MERCH-010',
    '2026-07-18T10:20:00', 3200.0000, 'ABC',
    'ECOMMERCE', 'APPROVED', 0
);
GO

------------------------------------------------------------
-- DEMO BATCH SUMMARY
------------------------------------------------------------

SELECT
    SourceBatchCode,
    MIN(SourceFileName) AS SourceFileName,
    COUNT_BIG(*) AS TotalRowCount,
    SUM
    (
        CASE
            WHEN ProcessingStatus = 'NEW' THEN 1
            ELSE 0
        END
    ) AS NewRowCount,
    MIN(ReceivedDateTime) AS FirstReceivedDateTime,
    MAX(ReceivedDateTime) AS LastReceivedDateTime
FROM stg.PaymentTransactionRaw
WHERE SourceBatchCode IN
(
    'SRC-20260718-001',
    'SRC-20260718-002'
)
GROUP BY SourceBatchCode
ORDER BY SourceBatchCode;
GO

*/

SET NOCOUNT OFF;
GO