/*
    -- PaymentProjectDW - Payment Staging Validation --0

    PURPOSE
      - Validate raw payment rows before Fact loading
      - Mark rows as VALID or REJECTED
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO


IF SCHEMA_ID(N'etl') IS NULL
BEGIN
    EXEC(N'CREATE SCHEMA etl AUTHORIZATION dbo;');
END;
GO

IF OBJECT_ID(N'stg.PaymentTransactionRaw', N'U') IS NULL
   OR OBJECT_ID(N'etl.ETLBatch', N'U') IS NULL
   OR OBJECT_ID(N'etl.ETLRunLog', N'U') IS NULL
   OR OBJECT_ID(N'dw.DimDate', N'U') IS NULL
   OR OBJECT_ID(N'dw.DimCustomer', N'U') IS NULL
   OR OBJECT_ID(N'dw.DimCard', N'U') IS NULL
   OR OBJECT_ID(N'dw.DimMerchant', N'U') IS NULL
   OR OBJECT_ID(N'dw.DimCurrency', N'U') IS NULL
   OR OBJECT_ID(N'dw.DimPaymentChannel', N'U') IS NULL
   OR OBJECT_ID(N'dw.DimTransactionStatus', N'U') IS NULL
   OR OBJECT_ID(N'dw.FactPaymentTransaction', N'U') IS NULL
BEGIN
    THROW 56000,
          'Payment validation icin gerekli staging, ETL veya DW nesnelerinden biri bulunamadi.',
          1;
END;
GO

------------------------------------------------------------
-- REJECT TABLE
------------------------------------------------------------

IF OBJECT_ID(N'etl.PaymentTransactionReject', N'U') IS NULL
BEGIN
    CREATE TABLE etl.PaymentTransactionReject
    (
        RejectID BIGINT IDENTITY(1,1) NOT NULL,
        StagingRowID BIGINT NOT NULL,
        SourceBatchCode VARCHAR(50) NOT NULL,
        SourceTransactionID VARCHAR(50) NULL,
        RejectReason NVARCHAR(2000) NOT NULL,
        ETLBatchID UNIQUEIDENTIFIER NOT NULL,

        RejectedDateTime DATETIME2(3) NOT NULL
            CONSTRAINT DF_PaymentTransactionReject_RejectedDateTime
            DEFAULT (SYSDATETIME()),

        CONSTRAINT PK_PaymentTransactionReject
            PRIMARY KEY CLUSTERED (RejectID),

        CONSTRAINT FK_PaymentTransactionReject_Staging
            FOREIGN KEY (StagingRowID)
            REFERENCES stg.PaymentTransactionRaw(StagingRowID),

        CONSTRAINT FK_PaymentTransactionReject_ETLBatch
            FOREIGN KEY (ETLBatchID)
            REFERENCES etl.ETLBatch(BatchID),

        CONSTRAINT UQ_PaymentTransactionReject_Run_Row
            UNIQUE
            (
                ETLBatchID,
                StagingRowID
            )
    );
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'etl.PaymentTransactionReject')
      AND name = N'IX_PaymentTransactionReject_SourceBatchCode'
)
BEGIN
    CREATE NONCLUSTERED INDEX
        IX_PaymentTransactionReject_SourceBatchCode
    ON etl.PaymentTransactionReject
    (
        SourceBatchCode,
        RejectedDateTime DESC
    )
    INCLUDE
    (
        StagingRowID,
        SourceTransactionID,
        RejectReason,
        ETLBatchID
    );
END;
GO

------------------------------------------------------------
-- VALIDATION PROCEDURE
------------------------------------------------------------

CREATE OR ALTER PROCEDURE etl.usp_ValidatePaymentTransactionBatch
(
    @SourceBatchCode VARCHAR(50),
    @ETLBatchID UNIQUEIDENTIFIER = NULL OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE
        @ProcedureName SYSNAME =
            CONCAT
            (
                OBJECT_SCHEMA_NAME(@@PROCID),
                N'.',
                OBJECT_NAME(@@PROCID)
            ),

        @BatchName NVARCHAR(200),
        @ExpectedSourceSystem VARCHAR(100) = 'stg.PaymentTransactionRaw',

        @ExistingBatchName NVARCHAR(200),
        @ExistingSourceSystem VARCHAR(100),
        @ExistingBatchStatus VARCHAR(20),
        @ExistingSessionID INT,

        @RunID BIGINT = NULL,
        @RowsRead BIGINT = 0,
        @RowsValid BIGINT = 0,
        @RowsRejected BIGINT = 0;

    SET @SourceBatchCode =
        NULLIF(LTRIM(RTRIM(@SourceBatchCode)), '');

    IF @SourceBatchCode IS NULL
    BEGIN
        THROW 56001,
              'SourceBatchCode bos birakilamaz.',
              1;
    END;

    IF NOT EXISTS
    (
        SELECT 1
        FROM stg.PaymentTransactionRaw
        WHERE SourceBatchCode = @SourceBatchCode
    )
    BEGIN
        THROW 56002,
              'Belirtilen SourceBatchCode staging tablosunda bulunamadi.',
              1;
    END;

    SET @ETLBatchID = COALESCE(@ETLBatchID, NEWID());
    SET @BatchName = CONCAT(N'Validate source batch: ', @SourceBatchCode);

    --------------------------------------------------------
    -- 3.1. REGISTER OR REUSE THE BATCH
    --------------------------------------------------------

    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT
            @ExistingBatchName = BatchName,
            @ExistingSourceSystem = SourceSystem,
            @ExistingBatchStatus = BatchStatus,
            @ExistingSessionID = CurrentSessionID
        FROM etl.ETLBatch WITH (UPDLOCK, HOLDLOCK)
        WHERE BatchID = @ETLBatchID;

        IF @ExistingBatchStatus IS NULL
        BEGIN
            INSERT INTO etl.ETLBatch
            (
                BatchID,
                BatchName,
                SourceSystem,
                BatchStatus
            )
            VALUES
            (
                @ETLBatchID,
                @BatchName,
                @ExpectedSourceSystem,
                'PENDING'
            );

            SET @ExistingBatchStatus = 'PENDING';
        END
        ELSE IF @ExistingBatchName <> @BatchName
             OR @ExistingSourceSystem <> @ExpectedSourceSystem
        BEGIN
            THROW 56003,
                  'ETLBatchID daha once farkli bir source batch icin kullanildi.',
                  1;
        END;

        IF @ExistingBatchStatus = 'SUCCEEDED'
        BEGIN
            INSERT INTO etl.ETLRunLog
            (
                BatchID,
                ProcedureName,
                RunStatus,
                StartDateTime,
                EndDateTime,
                HostName,
                ApplicationName,
                LoginName,
                SessionID
            )
            VALUES
            (
                @ETLBatchID,
                @ProcedureName,
                'SKIPPED',
                SYSDATETIME(),
                SYSDATETIME(),
                HOST_NAME(),
                APP_NAME(),
                ORIGINAL_LOGIN(),
                @@SPID
            );

            COMMIT TRANSACTION;

            PRINT
                'ETLBatchID daha once tamamlandigi icin validation tekrar calistirilmadi.';

            SELECT
                StagingRowID,
                SourceRowNumber,
                SourceTransactionID,
                ProcessingStatus,
                RejectReason,
                ETLBatchID
            FROM stg.PaymentTransactionRaw
            WHERE SourceBatchCode = @SourceBatchCode
            ORDER BY SourceRowNumber;

            RETURN;
        END;

        IF @ExistingBatchStatus = 'RUNNING'
           AND
           (
               @ExistingSessionID IS NULL
               OR @ExistingSessionID <> @@SPID
           )
        BEGIN
            THROW 56004,
                  'Bu ETLBatchID baska bir SQL Server session tarafindan calistiriliyor.',
                  1;
        END;

        UPDATE etl.ETLBatch
        SET
            BatchStatus = 'RUNNING',
            AttemptCount = AttemptCount + 1,
            StartedDateTime = SYSDATETIME(),
            CompletedDateTime = NULL,
            CurrentSessionID = @@SPID,
            LastErrorNumber = NULL,
            LastErrorMessage = NULL
        WHERE BatchID = @ETLBatchID;

        INSERT INTO etl.ETLRunLog
        (
            BatchID,
            ProcedureName,
            RunStatus,
            HostName,
            ApplicationName,
            LoginName,
            SessionID
        )
        VALUES
        (
            @ETLBatchID,
            @ProcedureName,
            'RUNNING',
            HOST_NAME(),
            APP_NAME(),
            ORIGINAL_LOGIN(),
            @@SPID
        );

        SET @RunID = CONVERT(BIGINT, SCOPE_IDENTITY());

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
        BEGIN
            ROLLBACK TRANSACTION;
        END;

        THROW;
    END CATCH;

    --------------------------------------------------------
    -- VALIDATE NEW STAGING ROWS
    --------------------------------------------------------

    BEGIN TRY
        BEGIN TRANSACTION;

        DROP TABLE IF EXISTS #ValidationResult;

        SELECT
            raw.StagingRowID,

            RejectReason =
                NULLIF
                (
                    CONCAT_WS
                    (
                        N'; ',

                        CASE
                            WHEN NULLIF(LTRIM(RTRIM(raw.SourceTransactionID)), '') IS NULL
                            THEN N'SourceTransactionID zorunludur'
                        END,

                        CASE
                            WHEN NULLIF(LTRIM(RTRIM(raw.CustomerCode)), '') IS NULL
                            THEN N'CustomerCode zorunludur'
                        END,

                        CASE
                            WHEN NULLIF(LTRIM(RTRIM(raw.CustomerCode)), '') IS NOT NULL
                                 AND NOT EXISTS
                                 (
                                     SELECT 1
                                     FROM dw.DimCustomer AS customer
                                     WHERE customer.CustomerID =
                                           LTRIM(RTRIM(raw.CustomerCode))
                                       AND customer.CustomerKey <> 0
                                 )
                            THEN N'CustomerCode DimCustomer icinde bulunamadi'
                        END,

                        CASE
                            WHEN NULLIF(LTRIM(RTRIM(raw.CardCode)), '') IS NULL
                            THEN N'CardCode zorunludur'
                        END,

                        CASE
                            WHEN NULLIF(LTRIM(RTRIM(raw.CardCode)), '') IS NOT NULL
                                 AND NOT EXISTS
                                 (
                                     SELECT 1
                                     FROM dw.DimCard AS card
                                     WHERE card.CardID =
                                           LTRIM(RTRIM(raw.CardCode))
                                       AND card.CardKey <> 0
                                 )
                            THEN N'CardCode DimCard icinde bulunamadi'
                        END,

                        CASE
                            WHEN NULLIF(LTRIM(RTRIM(raw.MerchantCode)), '') IS NULL
                            THEN N'MerchantCode zorunludur'
                        END,

                        CASE
                            WHEN NULLIF(LTRIM(RTRIM(raw.MerchantCode)), '') IS NOT NULL
                                 AND NOT EXISTS
                                 (
                                     SELECT 1
                                     FROM dw.DimMerchant AS merchant
                                     WHERE merchant.MerchantID =
                                           LTRIM(RTRIM(raw.MerchantCode))
                                       AND merchant.MerchantKey <> 0
                                 )
                            THEN N'MerchantCode DimMerchant icinde bulunamadi'
                        END,

                        CASE
                            WHEN raw.TransactionTimestamp IS NULL
                            THEN N'TransactionTimestamp zorunludur'
                        END,

                        CASE
                            WHEN raw.TransactionTimestamp IS NOT NULL
                                 AND NOT EXISTS
                                 (
                                     SELECT 1
                                     FROM dw.DimDate AS dateDimension
                                     WHERE dateDimension.FullDate =
                                           CONVERT(DATE, raw.TransactionTimestamp)
                                 )
                            THEN N'Islem tarihi DimDate icinde bulunamadi'
                        END,

                        CASE
                            WHEN raw.OriginalAmount IS NULL
                            THEN N'OriginalAmount zorunludur'

                            WHEN raw.OriginalAmount <= 0
                            THEN N'OriginalAmount sifirdan buyuk olmalidir'
                        END,

                        CASE
                            WHEN NULLIF(LTRIM(RTRIM(raw.CurrencyCode)), '') IS NULL
                            THEN N'CurrencyCode zorunludur'

                            WHEN NOT EXISTS
                                 (
                                     SELECT 1
                                     FROM dw.DimCurrency AS currency
                                     WHERE currency.CurrencyCode =
                                           UPPER(LTRIM(RTRIM(raw.CurrencyCode)))
                                 )
                            THEN N'CurrencyCode DimCurrency icinde bulunamadi'
                        END,

                        CASE
                            WHEN NULLIF(LTRIM(RTRIM(raw.PaymentChannelCode)), '') IS NULL
                            THEN N'PaymentChannelCode zorunludur'

                            WHEN NOT EXISTS
                                 (
                                     SELECT 1
                                     FROM dw.DimPaymentChannel AS channel
                                     WHERE channel.PaymentChannelCode =
                                           UPPER(LTRIM(RTRIM(raw.PaymentChannelCode)))
                                 )
                            THEN N'PaymentChannelCode gecersizdir'
                        END,

                        CASE
                            WHEN NULLIF(LTRIM(RTRIM(raw.TransactionStatusCode)), '') IS NULL
                            THEN N'TransactionStatusCode zorunludur'

                            WHEN NOT EXISTS
                                 (
                                     SELECT 1
                                     FROM dw.DimTransactionStatus AS statusData
                                     WHERE statusData.StatusCode =
                                           UPPER(LTRIM(RTRIM(raw.TransactionStatusCode)))
                                 )
                            THEN N'TransactionStatusCode gecersizdir'
                        END,

                        CASE
                            WHEN raw.IsFraud IS NULL
                            THEN N'IsFraud zorunludur'
                        END,

                        CASE
                            WHEN NULLIF(LTRIM(RTRIM(raw.SourceTransactionID)), '') IS NOT NULL
                                 AND EXISTS
                                 (
                                     SELECT 1
                                     FROM stg.PaymentTransactionRaw AS earlierRaw
                                     WHERE LTRIM(RTRIM(earlierRaw.SourceTransactionID)) =
                                           LTRIM(RTRIM(raw.SourceTransactionID))
                                       AND earlierRaw.StagingRowID < raw.StagingRowID
                                 )
                            THEN N'SourceTransactionID staging icinde duplicate'
                        END,

                        CASE
                            WHEN NULLIF(LTRIM(RTRIM(raw.SourceTransactionID)), '') IS NOT NULL
                                 AND EXISTS
                                 (
                                     SELECT 1
                                     FROM dw.FactPaymentTransaction AS existingFact
                                     WHERE existingFact.TransactionID =
                                           LTRIM(RTRIM(raw.SourceTransactionID))
                                 )
                            THEN N'SourceTransactionID Fact tablosunda zaten mevcut'
                        END
                    ),
                    N''
                )
        INTO #ValidationResult
        FROM stg.PaymentTransactionRaw AS raw
        WHERE raw.SourceBatchCode = @SourceBatchCode
          AND raw.ProcessingStatus = 'NEW';

        SELECT
            @RowsRead = COUNT_BIG(*),

            @RowsValid =
                COALESCE
                (
                    SUM
                    (
                        CASE
                            WHEN RejectReason IS NULL THEN CONVERT(BIGINT, 1)
                            ELSE CONVERT(BIGINT, 0)
                        END
                    ),
                    0
                ),

            @RowsRejected =
                COALESCE
                (
                    SUM
                    (
                        CASE
                            WHEN RejectReason IS NOT NULL THEN CONVERT(BIGINT, 1)
                            ELSE CONVERT(BIGINT, 0)
                        END
                    ),
                    0
                )
        FROM #ValidationResult;

        IF @RowsRead = 0
        BEGIN
            THROW 56005,
                  'Source batch icinde NEW durumunda staging satiri bulunamadi.',
                  1;
        END;

        UPDATE raw
        SET
            raw.ProcessingStatus =
                CASE
                    WHEN validation.RejectReason IS NULL THEN 'VALID'
                    ELSE 'REJECTED'
                END,

            raw.RejectReason = validation.RejectReason,
            raw.ETLBatchID = @ETLBatchID,
            raw.ProcessedDateTime = SYSDATETIME()
        FROM stg.PaymentTransactionRaw AS raw
        INNER JOIN #ValidationResult AS validation
            ON validation.StagingRowID = raw.StagingRowID;

        INSERT INTO etl.PaymentTransactionReject
        (
            StagingRowID,
            SourceBatchCode,
            SourceTransactionID,
            RejectReason,
            ETLBatchID
        )
        SELECT
            raw.StagingRowID,
            raw.SourceBatchCode,
            raw.SourceTransactionID,
            validation.RejectReason,
            @ETLBatchID
        FROM #ValidationResult AS validation
        INNER JOIN stg.PaymentTransactionRaw AS raw
            ON raw.StagingRowID = validation.StagingRowID
        WHERE validation.RejectReason IS NOT NULL;

        UPDATE etl.ETLBatch
        SET
            BatchStatus = 'SUCCEEDED',
            CompletedDateTime = SYSDATETIME(),
            CurrentSessionID = NULL,
            LastErrorNumber = NULL,
            LastErrorMessage = NULL
        WHERE BatchID = @ETLBatchID;

        UPDATE etl.ETLRunLog
        SET
            RunStatus = 'SUCCEEDED',
            EndDateTime = SYSDATETIME(),
            RowsRead = @RowsRead,
            RowsInserted = @RowsRejected,
            RowsUpdated = @RowsRead,
            RowsRejected = @RowsRejected
        WHERE ETLRunID = @RunID;

        COMMIT TRANSACTION;

        SELECT
            @SourceBatchCode AS SourceBatchCode,
            @ETLBatchID AS ETLBatchID,
            @RowsRead AS RowsRead,
            @RowsValid AS RowsValid,
            @RowsRejected AS RowsRejected,
            'SUCCEEDED' AS ValidationStatus;

        SELECT
            StagingRowID,
            SourceRowNumber,
            SourceTransactionID,
            OriginalAmount,
            CurrencyCode,
            PaymentChannelCode,
            TransactionStatusCode,
            ProcessingStatus,
            RejectReason,
            ETLBatchID,
            ProcessedDateTime
        FROM stg.PaymentTransactionRaw
        WHERE SourceBatchCode = @SourceBatchCode
        ORDER BY SourceRowNumber;
    END TRY
    BEGIN CATCH
        DECLARE
            @ErrorNumber INT = ERROR_NUMBER(),
            @ErrorSeverity INT = ERROR_SEVERITY(),
            @ErrorState INT = ERROR_STATE(),
            @ErrorLine INT = ERROR_LINE(),
            @ErrorProcedure NVARCHAR(256) = ERROR_PROCEDURE(),
            @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();

        IF XACT_STATE() <> 0
        BEGIN
            ROLLBACK TRANSACTION;
        END;

        UPDATE etl.ETLBatch
        SET
            BatchStatus = 'FAILED',
            CompletedDateTime = SYSDATETIME(),
            CurrentSessionID = NULL,
            LastErrorNumber = @ErrorNumber,
            LastErrorMessage = @ErrorMessage
        WHERE BatchID = @ETLBatchID;

        IF @RunID IS NOT NULL
        BEGIN
            UPDATE etl.ETLRunLog
            SET
                RunStatus = 'FAILED',
                EndDateTime = SYSDATETIME(),
                RowsRead = COALESCE(@RowsRead, 0),
                RowsInserted = 0,
                RowsUpdated = 0,
                RowsRejected = COALESCE(@RowsRejected, 0),
                ErrorNumber = @ErrorNumber,
                ErrorSeverity = @ErrorSeverity,
                ErrorState = @ErrorState,
                ErrorLine = @ErrorLine,
                ErrorProcedure = @ErrorProcedure,
                ErrorMessage = @ErrorMessage
            WHERE ETLRunID = @RunID;
        END;

        THROW;
    END CATCH;
END;
GO

------------------------------------------------------------
-- INSTALLATION CHECK
------------------------------------------------------------

SELECT
    schemaData.name AS SchemaName,
    objectData.name AS ObjectName,
    objectData.type_desc AS ObjectType
FROM sys.objects AS objectData
INNER JOIN sys.schemas AS schemaData
    ON schemaData.schema_id = objectData.schema_id
WHERE schemaData.name = N'etl'
  AND objectData.name IN
      (
          N'PaymentTransactionReject',
          N'usp_ValidatePaymentTransactionBatch'
      )
ORDER BY objectData.type_desc, objectData.name;
GO

/*
    Optional validation test:

    DECLARE @ValidationBatchID UNIQUEIDENTIFIER = NEWID();

    EXEC etl.usp_ValidatePaymentTransactionBatch
        @SourceBatchCode = 'SRC-20260718-001',
        @ETLBatchID = @ValidationBatchID OUTPUT;

    SELECT
        SourceBatchCode,
        ProcessingStatus,
        COUNT_BIG(*) AS RowCount
    FROM stg.PaymentTransactionRaw
    WHERE SourceBatchCode = 'SRC-20260718-001'
    GROUP BY SourceBatchCode, ProcessingStatus;
*/

SET NOCOUNT OFF;
GO