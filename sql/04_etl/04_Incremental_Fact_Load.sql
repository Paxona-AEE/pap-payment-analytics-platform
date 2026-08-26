/*
    PaymentProjectDW - Incremental Payment Fact Load
      - Load VALID staging rows into dw.FactPaymentTransaction
      - Reject transaction IDs that already exist in the Fact table
      - Preserve staging-to-Fact lineage
      - Record batch and run-level metrics
*/

USE PaymentProjectDW;
GO

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
   OR OBJECT_ID(N'etl.PaymentTransactionReject', N'U') IS NULL
   OR OBJECT_ID(N'dw.DimDate', N'U') IS NULL
   OR OBJECT_ID(N'dw.DimCustomer', N'U') IS NULL
   OR OBJECT_ID(N'dw.DimCard', N'U') IS NULL
   OR OBJECT_ID(N'dw.DimMerchant', N'U') IS NULL
   OR OBJECT_ID(N'dw.DimCurrency', N'U') IS NULL
   OR OBJECT_ID(N'dw.DimPaymentChannel', N'U') IS NULL
   OR OBJECT_ID(N'dw.DimTransactionStatus', N'U') IS NULL
   OR OBJECT_ID(N'dw.FactPaymentTransaction', N'U') IS NULL
BEGIN
    THROW 57001,
          'Fact load icin gerekli staging, ETL veya DW nesnelerinden biri bulunamadi.',
          1;
END;
GO

IF COL_LENGTH(N'dw.DimCustomer', N'CustomerID') IS NULL
   OR COL_LENGTH(N'dw.DimCard', N'CardID') IS NULL
   OR COL_LENGTH(N'dw.DimMerchant', N'MerchantID') IS NULL
BEGIN
    THROW 57002,
          'Dimension business-code kolonlarindan biri bulunamadi.',
          1;
END;
GO

------------------------------------------------------------
-- STAGING LOAD-METADATA COLUMNS
------------------------------------------------------------

IF COL_LENGTH(N'stg.PaymentTransactionRaw', N'LoadETLBatchID') IS NULL
BEGIN
    ALTER TABLE stg.PaymentTransactionRaw
    ADD LoadETLBatchID UNIQUEIDENTIFIER NULL;
END;
GO

IF COL_LENGTH(N'stg.PaymentTransactionRaw', N'LoadedDateTime') IS NULL
BEGIN
    ALTER TABLE stg.PaymentTransactionRaw
    ADD LoadedDateTime DATETIME2(3) NULL;
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.foreign_key_columns AS foreignKeyColumn
    WHERE foreignKeyColumn.parent_object_id =
          OBJECT_ID(N'stg.PaymentTransactionRaw')
      AND foreignKeyColumn.parent_column_id =
          COLUMNPROPERTY
          (
              OBJECT_ID(N'stg.PaymentTransactionRaw'),
              N'LoadETLBatchID',
              'ColumnId'
          )
      AND foreignKeyColumn.referenced_object_id =
          OBJECT_ID(N'etl.ETLBatch')
)
BEGIN
    ALTER TABLE stg.PaymentTransactionRaw
    ADD CONSTRAINT FK_PaymentTransactionRaw_LoadETLBatch
        FOREIGN KEY (LoadETLBatchID)
        REFERENCES etl.ETLBatch(BatchID);
END;
GO

------------------------------------------------------------
-- STAGING-TO-FACT LINEAGE TABLE
------------------------------------------------------------

IF OBJECT_ID(N'etl.PaymentTransactionLoadMap', N'U') IS NULL
BEGIN
    CREATE TABLE etl.PaymentTransactionLoadMap
    (
        PaymentTransactionLoadMapID BIGINT IDENTITY(1,1) NOT NULL,
        StagingRowID BIGINT NOT NULL,
        PaymentTransactionKey BIGINT NOT NULL,
        SourceBatchCode VARCHAR(50) NOT NULL,
        LoadETLBatchID UNIQUEIDENTIFIER NOT NULL,

        LoadedDateTime DATETIME2(3) NOT NULL
            CONSTRAINT DF_PaymentTransactionLoadMap_Loaded
            DEFAULT (SYSDATETIME()),

        CONSTRAINT PK_PaymentTransactionLoadMap
            PRIMARY KEY CLUSTERED (PaymentTransactionLoadMapID),

        CONSTRAINT UQ_PaymentTransactionLoadMap_StagingRow
            UNIQUE (StagingRowID),

        CONSTRAINT UQ_PaymentTransactionLoadMap_FactKey
            UNIQUE (PaymentTransactionKey),

        CONSTRAINT FK_PaymentTransactionLoadMap_Staging
            FOREIGN KEY (StagingRowID)
            REFERENCES stg.PaymentTransactionRaw(StagingRowID),

        CONSTRAINT FK_PaymentTransactionLoadMap_Fact
            FOREIGN KEY (PaymentTransactionKey)
            REFERENCES dw.FactPaymentTransaction(PaymentTransactionKey),

        CONSTRAINT FK_PaymentTransactionLoadMap_Batch
            FOREIGN KEY (LoadETLBatchID)
            REFERENCES etl.ETLBatch(BatchID)
    );
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'etl.PaymentTransactionLoadMap')
      AND name = N'IX_PaymentTransactionLoadMap_SourceBatch'
)
BEGIN
    CREATE NONCLUSTERED INDEX
        IX_PaymentTransactionLoadMap_SourceBatch
    ON etl.PaymentTransactionLoadMap
    (
        SourceBatchCode,
        LoadedDateTime DESC
    )
    INCLUDE
    (
        StagingRowID,
        PaymentTransactionKey,
        LoadETLBatchID
    );
END;
GO

------------------------------------------------------------
-- FACT LOAD PROCEDURE
------------------------------------------------------------

CREATE OR ALTER PROCEDURE etl.usp_LoadPaymentTransactionBatch
(
    @SourceBatchCode VARCHAR(50),
    @LoadETLBatchID UNIQUEIDENTIFIER = NULL OUTPUT
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
        @RowsCandidate BIGINT = 0,
        @RowsInserted BIGINT = 0,
        @RowsRejected BIGINT = 0;

    SET @SourceBatchCode =
        NULLIF(LTRIM(RTRIM(@SourceBatchCode)), '');

    IF @SourceBatchCode IS NULL
    BEGIN
        THROW 57010,
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
        THROW 57011,
              'Belirtilen SourceBatchCode staging tablosunda bulunamadi.',
              1;
    END;

    IF EXISTS
    (
        SELECT 1
        FROM stg.PaymentTransactionRaw
        WHERE SourceBatchCode = @SourceBatchCode
          AND ProcessingStatus = 'NEW'
    )
    BEGIN
        THROW 57012,
              'Source batch icinde NEW satirlar var. Once validation procedure calistirilmalidir.',
              1;
    END;

    SET @LoadETLBatchID = COALESCE(@LoadETLBatchID, NEWID());
    SET @BatchName = CONCAT(N'Load source batch: ', @SourceBatchCode);

    --------------------------------------------------------
    -- REGISTER OR REUSE THE LOAD BATCH
    --------------------------------------------------------

    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT
            @ExistingBatchName = BatchName,
            @ExistingSourceSystem = SourceSystem,
            @ExistingBatchStatus = BatchStatus,
            @ExistingSessionID = CurrentSessionID
        FROM etl.ETLBatch WITH (UPDLOCK, HOLDLOCK)
        WHERE BatchID = @LoadETLBatchID;

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
                @LoadETLBatchID,
                @BatchName,
                @ExpectedSourceSystem,
                'PENDING'
            );

            SET @ExistingBatchStatus = 'PENDING';
        END
        ELSE IF @ExistingBatchName <> @BatchName
             OR @ExistingSourceSystem <> @ExpectedSourceSystem
        BEGIN
            THROW 57013,
                  'LoadETLBatchID daha once farkli bir source batch icin kullanildi.',
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
                @LoadETLBatchID,
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

            SELECT
                SourceBatchCode,
                StagingRowID,
                PaymentTransactionKey,
                LoadETLBatchID,
                LoadedDateTime
            FROM etl.PaymentTransactionLoadMap
            WHERE LoadETLBatchID = @LoadETLBatchID
            ORDER BY StagingRowID;

            RETURN;
        END;

        IF @ExistingBatchStatus = 'RUNNING'
           AND
           (
               @ExistingSessionID IS NULL
               OR @ExistingSessionID <> @@SPID
           )
        BEGIN
            THROW 57014,
                  'Bu LoadETLBatchID baska bir SQL Server session tarafindan calistiriliyor.',
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
        WHERE BatchID = @LoadETLBatchID;

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
            @LoadETLBatchID,
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
    -- 4.2. LOAD VALID ROWS
    --------------------------------------------------------

    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT
            @RowsRead = COUNT_BIG(*)
        FROM stg.PaymentTransactionRaw AS raw WITH (UPDLOCK, HOLDLOCK)
        WHERE raw.SourceBatchCode = @SourceBatchCode
          AND raw.ProcessingStatus = 'VALID'
          AND NOT EXISTS
              (
                  SELECT 1
                  FROM etl.PaymentTransactionLoadMap AS existingMap
                  WHERE existingMap.StagingRowID = raw.StagingRowID
              );

        ----------------------------------------------------
        -- FACT DUPLICATES DETECTED AFTER VALIDATION
        ----------------------------------------------------

        DROP TABLE IF EXISTS #LoadDuplicate;

        SELECT
            raw.StagingRowID,
            raw.SourceTransactionID
        INTO #LoadDuplicate
        FROM stg.PaymentTransactionRaw AS raw
        WHERE raw.SourceBatchCode = @SourceBatchCode
          AND raw.ProcessingStatus = 'VALID'
          AND EXISTS
              (
                  SELECT 1
                  FROM dw.FactPaymentTransaction AS existingFact
                  WHERE existingFact.TransactionID =
                        LTRIM(RTRIM(raw.SourceTransactionID))
              )
          AND NOT EXISTS
              (
                  SELECT 1
                  FROM etl.PaymentTransactionLoadMap AS existingMap
                  WHERE existingMap.StagingRowID = raw.StagingRowID
              );

        SELECT @RowsRejected = COUNT_BIG(*)
        FROM #LoadDuplicate;

        UPDATE raw
        SET
            raw.ProcessingStatus = 'REJECTED',
            raw.RejectReason =
                CASE
                    WHEN raw.RejectReason IS NULL
                    THEN N'SourceTransactionID fact tablosunda zaten mevcut'
                    ELSE CONCAT
                         (
                             raw.RejectReason,
                             N'; SourceTransactionID fact tablosunda zaten mevcut'
                         )
                END,
            raw.ProcessedDateTime = SYSDATETIME()
        FROM stg.PaymentTransactionRaw AS raw
        INNER JOIN #LoadDuplicate AS duplicateData
            ON duplicateData.StagingRowID = raw.StagingRowID;

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
            raw.RejectReason,
            @LoadETLBatchID
        FROM stg.PaymentTransactionRaw AS raw
        INNER JOIN #LoadDuplicate AS duplicateData
            ON duplicateData.StagingRowID = raw.StagingRowID
        WHERE NOT EXISTS
              (
                  SELECT 1
                  FROM etl.PaymentTransactionReject AS existingReject
                  WHERE existingReject.ETLBatchID = @LoadETLBatchID
                    AND existingReject.StagingRowID = raw.StagingRowID
              );

        ----------------------------------------------------
        -- LOAD CANDIDATES
        ----------------------------------------------------

        DROP TABLE IF EXISTS #LoadCandidate;

        SELECT
            raw.StagingRowID,
            raw.SourceBatchCode,
            raw.SourceRowNumber,
            LTRIM(RTRIM(raw.SourceTransactionID)) AS SourceTransactionID,
            raw.TransactionTimestamp,
            raw.OriginalAmount,

            currency.CurrencyCode,
            channel.PaymentChannelCode,
            statusData.StatusCode AS TransactionStatusCode,
            raw.IsFraud,

            dateDimension.DateKey AS TransactionDateKey,
            customerLookup.CustomerKey,
            cardLookup.CardKey,
            merchantLookup.MerchantKey,
            channel.PaymentChannelKey,
            currency.CurrencyKey,
            statusData.TransactionStatusKey,

            CAST
            (
                CASE currency.CurrencyCode
                    WHEN 'TRY' THEN 1.00000000
                    WHEN 'USD' THEN 32.00000000
                    WHEN 'EUR' THEN 35.00000000
                    WHEN 'GBP' THEN 41.00000000
                    ELSE 1.00000000
                END
                AS DECIMAL(19,8)
            ) AS ExchangeRateToTRY
        INTO #LoadCandidate
        FROM stg.PaymentTransactionRaw AS raw
        INNER JOIN dw.DimDate AS dateDimension
            ON dateDimension.FullDate = CONVERT(DATE, raw.TransactionTimestamp)
        INNER JOIN dw.DimCurrency AS currency
            ON currency.CurrencyCode =
               UPPER(LTRIM(RTRIM(raw.CurrencyCode)))
        INNER JOIN dw.DimPaymentChannel AS channel
            ON channel.PaymentChannelCode =
               UPPER(LTRIM(RTRIM(raw.PaymentChannelCode)))
        INNER JOIN dw.DimTransactionStatus AS statusData
            ON statusData.StatusCode =
               UPPER(LTRIM(RTRIM(raw.TransactionStatusCode)))

        -- Deterministic business-code lookup. No temporal columns are used.
        CROSS APPLY
        (
            SELECT TOP (1)
                customer.CustomerKey
            FROM dw.DimCustomer AS customer
            WHERE customer.CustomerID = LTRIM(RTRIM(raw.CustomerCode))
              AND customer.CustomerKey <> 0
            ORDER BY customer.CustomerKey DESC
        ) AS customerLookup

        CROSS APPLY
        (
            SELECT TOP (1)
                card.CardKey
            FROM dw.DimCard AS card
            WHERE card.CardID = LTRIM(RTRIM(raw.CardCode))
              AND card.CardKey <> 0
            ORDER BY card.CardKey DESC
        ) AS cardLookup

        CROSS APPLY
        (
            SELECT TOP (1)
                merchant.MerchantKey
            FROM dw.DimMerchant AS merchant
            WHERE merchant.MerchantID = LTRIM(RTRIM(raw.MerchantCode))
              AND merchant.MerchantKey <> 0
            ORDER BY merchant.MerchantKey DESC
        ) AS merchantLookup

        WHERE raw.SourceBatchCode = @SourceBatchCode
          AND raw.ProcessingStatus = 'VALID'
          AND NOT EXISTS
              (
                  SELECT 1
                  FROM etl.PaymentTransactionLoadMap AS existingMap
                  WHERE existingMap.StagingRowID = raw.StagingRowID
              )
          AND NOT EXISTS
              (
                  SELECT 1
                  FROM dw.FactPaymentTransaction AS existingFact
                  WHERE existingFact.TransactionID =
                        LTRIM(RTRIM(raw.SourceTransactionID))
              );

        SELECT @RowsCandidate = COUNT_BIG(*)
        FROM #LoadCandidate;

        IF @RowsCandidate <> @RowsRead - @RowsRejected
        BEGIN
            THROW 57015,
                  'VALID satirlardan biri dimension anahtarina donusturulemedi. Validation tekrar calistirilmalidir.',
                  1;
        END;

        ----------------------------------------------------
        -- FACT INSERT
        ----------------------------------------------------

        DROP TABLE IF EXISTS #InsertedFact;

        CREATE TABLE #InsertedFact
        (
            PaymentTransactionKey BIGINT NOT NULL,
            TransactionID VARCHAR(50) NOT NULL
        );

        INSERT INTO dw.FactPaymentTransaction
        (
            TransactionID,
            TransactionReference,
            TransactionDateKey,
            AuthorizationDateKey,
            SettlementDateKey,
            CustomerKey,
            CardKey,
            MerchantKey,
            PaymentChannelKey,
            CurrencyKey,
            TransactionStatusKey,
            DeviceKey,
            FraudReasonKey,
            TransactionTimestamp,
            AuthorizationTimestamp,
            SettlementTimestamp,
            OriginalAmount,
            ExchangeRateToTRY,
            AmountTRY,
            FeeAmountTRY,
            MerchantCommissionTRY,
            TaxAmountTRY,
            CashbackAmountTRY,
            InstallmentCount,
            TransactionCount,
            AuthorizationDurationMs,
            IsInternational,
            IsContactless,
            IsRecurring,
            Is3DSecure,
            IsTokenized,
            IsFraud,
            FraudScore,
            SourceSystem
        )
        OUTPUT
            inserted.PaymentTransactionKey,
            inserted.TransactionID
        INTO #InsertedFact
        (
            PaymentTransactionKey,
            TransactionID
        )
        SELECT
            candidate.SourceTransactionID,
            CONCAT
            (
                'STG-',
                candidate.SourceBatchCode,
                '-',
                candidate.SourceRowNumber
            ),
            candidate.TransactionDateKey,
            CASE
                WHEN candidate.TransactionStatusCode = 'APPROVED'
                THEN candidate.TransactionDateKey
            END,
            CASE
                WHEN candidate.TransactionStatusCode = 'APPROVED'
                THEN candidate.TransactionDateKey
            END,
            candidate.CustomerKey,
            candidate.CardKey,
            candidate.MerchantKey,
            candidate.PaymentChannelKey,
            candidate.CurrencyKey,
            candidate.TransactionStatusKey,
            NULL,
            NULL,
            candidate.TransactionTimestamp,
            CASE
                WHEN candidate.TransactionStatusCode = 'APPROVED'
                THEN DATEADD(MILLISECOND, 750, candidate.TransactionTimestamp)
            END,
            CASE
                WHEN candidate.TransactionStatusCode = 'APPROVED'
                THEN DATEADD(MINUTE, 30, candidate.TransactionTimestamp)
            END,
            candidate.OriginalAmount,
            candidate.ExchangeRateToTRY,
            CAST
            (
                candidate.OriginalAmount * candidate.ExchangeRateToTRY
                AS DECIMAL(19,4)
            ),
            CAST
            (
                candidate.OriginalAmount * candidate.ExchangeRateToTRY * 0.0100
                AS DECIMAL(19,4)
            ),
            CAST
            (
                candidate.OriginalAmount * candidate.ExchangeRateToTRY * 0.0200
                AS DECIMAL(19,4)
            ),
            CAST
            (
                candidate.OriginalAmount * candidate.ExchangeRateToTRY * 0.0050
                AS DECIMAL(19,4)
            ),
            CONVERT(DECIMAL(19,4), 0),
            1,
            1,
            CASE
                WHEN candidate.TransactionStatusCode = 'APPROVED' THEN 750
            END,
            CASE
                WHEN candidate.CurrencyCode <> 'TRY' THEN 1 ELSE 0
            END,
            0,
            0,
            CASE
                WHEN candidate.PaymentChannelCode = 'ECOMMERCE' THEN 1 ELSE 0
            END,
            0,
            candidate.IsFraud,
            CASE
                WHEN candidate.IsFraud = 1
                THEN CONVERT(DECIMAL(5,2), 90.00)
                ELSE CONVERT(DECIMAL(5,2), 10.00)
            END,
            'StagingBatch'
        FROM #LoadCandidate AS candidate;

        SET @RowsInserted = @@ROWCOUNT;

        IF @RowsInserted <> @RowsCandidate
        BEGIN
            THROW 57016,
                  'Fact insert satir sayisi load candidate sayisi ile eslesmedi.',
                  1;
        END;

        ----------------------------------------------------
        -- LINEAGE AND STAGING STATUS
        ----------------------------------------------------

        INSERT INTO etl.PaymentTransactionLoadMap
        (
            StagingRowID,
            PaymentTransactionKey,
            SourceBatchCode,
            LoadETLBatchID
        )
        SELECT
            candidate.StagingRowID,
            insertedFact.PaymentTransactionKey,
            candidate.SourceBatchCode,
            @LoadETLBatchID
        FROM #LoadCandidate AS candidate
        INNER JOIN #InsertedFact AS insertedFact
            ON insertedFact.TransactionID = candidate.SourceTransactionID;

        UPDATE raw
        SET
            raw.ProcessingStatus = 'LOADED',
            raw.LoadETLBatchID = @LoadETLBatchID,
            raw.LoadedDateTime = SYSDATETIME(),
            raw.ProcessedDateTime = SYSDATETIME()
        FROM stg.PaymentTransactionRaw AS raw
        INNER JOIN etl.PaymentTransactionLoadMap AS mapData
            ON mapData.StagingRowID = raw.StagingRowID
        WHERE mapData.LoadETLBatchID = @LoadETLBatchID;

        UPDATE etl.ETLBatch
        SET
            BatchStatus = 'SUCCEEDED',
            CompletedDateTime = SYSDATETIME(),
            CurrentSessionID = NULL,
            LastErrorNumber = NULL,
            LastErrorMessage = NULL
        WHERE BatchID = @LoadETLBatchID;

        UPDATE etl.ETLRunLog
        SET
            RunStatus = 'SUCCEEDED',
            EndDateTime = SYSDATETIME(),
            RowsRead = @RowsRead,
            RowsInserted = @RowsInserted,
            RowsUpdated = @RowsInserted,
            RowsRejected = @RowsRejected
        WHERE ETLRunID = @RunID;

        COMMIT TRANSACTION;

        SELECT
            @SourceBatchCode AS SourceBatchCode,
            @LoadETLBatchID AS LoadETLBatchID,
            @RowsRead AS ValidRowsRead,
            @RowsInserted AS FactRowsInserted,
            @RowsRejected AS LoadRowsRejected,
            'SUCCEEDED' AS LoadStatus;

        SELECT
            raw.StagingRowID,
            raw.SourceRowNumber,
            raw.SourceTransactionID,
            raw.ProcessingStatus,
            mapData.PaymentTransactionKey,
            fact.TransactionID,
            fact.TransactionDateKey,
            fact.CustomerKey,
            fact.CardKey,
            fact.MerchantKey,
            fact.AmountTRY,
            fact.IsFraud,
            raw.LoadETLBatchID,
            raw.LoadedDateTime
        FROM stg.PaymentTransactionRaw AS raw
        INNER JOIN etl.PaymentTransactionLoadMap AS mapData
            ON mapData.StagingRowID = raw.StagingRowID
        INNER JOIN dw.FactPaymentTransaction AS fact
            ON fact.PaymentTransactionKey = mapData.PaymentTransactionKey
        WHERE mapData.LoadETLBatchID = @LoadETLBatchID
        ORDER BY raw.SourceRowNumber;
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
        WHERE BatchID = @LoadETLBatchID;

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
          N'PaymentTransactionLoadMap',
          N'usp_LoadPaymentTransactionBatch'
      )
ORDER BY objectData.type_desc, objectData.name;
GO

/*
    Optional load test. Run only after validation has marked rows VALID/REJECTED.

    DECLARE @LoadBatchID UNIQUEIDENTIFIER = NEWID();

    EXEC etl.usp_LoadPaymentTransactionBatch
        @SourceBatchCode = 'SRC-20260718-001',
        @LoadETLBatchID = @LoadBatchID OUTPUT;

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
