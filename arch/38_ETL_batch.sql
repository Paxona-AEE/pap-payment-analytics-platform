SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF OBJECT_ID(N'dw.FactPaymentTransaction', N'U') IS NULL
BEGIN
    THROW 54000,
          'dw.FactPaymentTransaction tablosu bulunamadi.',
          1;
END;
GO

IF OBJECT_ID(N'dw.DimTransactionStatus', N'U') IS NULL
BEGIN
    THROW 54001,
          'dw.DimTransactionStatus tablosu bulunamadi.',
          1;
END;
GO

IF SCHEMA_ID(N'etl') IS NULL
BEGIN
    EXEC(N'CREATE SCHEMA etl AUTHORIZATION dbo;');
END;
GO

-- ETL BATCH CONTROL TABLE

IF OBJECT_ID(N'etl.ETLBatch', N'U') IS NULL
BEGIN
    CREATE TABLE etl.ETLBatch
    (
        BatchID UNIQUEIDENTIFIER NOT NULL,
        BatchName NVARCHAR(200) NOT NULL,
        SourceSystem VARCHAR(100) NOT NULL,

        BatchStatus VARCHAR(20) NOT NULL
            CONSTRAINT DF_ETLBatch_BatchStatus
            DEFAULT ('PENDING'),

        AttemptCount INT NOT NULL
            CONSTRAINT DF_ETLBatch_AttemptCount
            DEFAULT (0),

        CreatedDateTime DATETIME2(3) NOT NULL
            CONSTRAINT DF_ETLBatch_CreatedDateTime
            DEFAULT (SYSDATETIME()),

        StartedDateTime DATETIME2(3) NULL,
        CompletedDateTime DATETIME2(3) NULL,
        CurrentSessionID INT NULL,

        LastErrorNumber INT NULL,
        LastErrorMessage NVARCHAR(4000) NULL,

        CONSTRAINT PK_ETLBatch
            PRIMARY KEY CLUSTERED (BatchID),

        CONSTRAINT CK_ETLBatch_Status
            CHECK
            (
                BatchStatus IN
                (
                    'PENDING',
                    'RUNNING',
                    'SUCCEEDED',
                    'FAILED'
                )
            ),

        CONSTRAINT CK_ETLBatch_AttemptCount
            CHECK (AttemptCount >= 0)
    );
END;
GO

-- ETL RUN LOG TABLE

IF OBJECT_ID(N'etl.ETLRunLog', N'U') IS NULL
BEGIN
    CREATE TABLE etl.ETLRunLog
    (
        ETLRunID BIGINT IDENTITY(1,1) NOT NULL,
        BatchID UNIQUEIDENTIFIER NOT NULL,
        ProcedureName SYSNAME NOT NULL,
        RunStatus VARCHAR(20) NOT NULL,

        StartDateTime DATETIME2(3) NOT NULL
            CONSTRAINT DF_ETLRunLog_StartDateTime
            DEFAULT (SYSDATETIME()),

        EndDateTime DATETIME2(3) NULL,

        RowsRead BIGINT NOT NULL
            CONSTRAINT DF_ETLRunLog_RowsRead
            DEFAULT (0),

        RowsInserted BIGINT NOT NULL
            CONSTRAINT DF_ETLRunLog_RowsInserted
            DEFAULT (0),

        RowsUpdated BIGINT NOT NULL
            CONSTRAINT DF_ETLRunLog_RowsUpdated
            DEFAULT (0),

        RowsRejected BIGINT NOT NULL
            CONSTRAINT DF_ETLRunLog_RowsRejected
            DEFAULT (0),

        ErrorNumber INT NULL,
        ErrorSeverity INT NULL,
        ErrorState INT NULL,
        ErrorLine INT NULL,
        ErrorProcedure NVARCHAR(256) NULL,
        ErrorMessage NVARCHAR(4000) NULL,

        HostName NVARCHAR(128) NULL,
        ApplicationName NVARCHAR(128) NULL,
        LoginName SYSNAME NULL,
        SessionID INT NOT NULL,

        CONSTRAINT PK_ETLRunLog
            PRIMARY KEY CLUSTERED (ETLRunID),

        CONSTRAINT FK_ETLRunLog_ETLBatch
            FOREIGN KEY (BatchID)
            REFERENCES etl.ETLBatch(BatchID),

        CONSTRAINT CK_ETLRunLog_Status
            CHECK
            (
                RunStatus IN
                (
                    'RUNNING',
                    'SUCCEEDED',
                    'FAILED',
                    'SKIPPED'
                )
            ),

        CONSTRAINT CK_ETLRunLog_RowCounts
            CHECK
            (
                RowsRead >= 0
                AND RowsInserted >= 0
                AND RowsUpdated >= 0
                AND RowsRejected >= 0
            )
    );
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'etl.ETLRunLog')
      AND name = N'IX_ETLRunLog_BatchID_StartDateTime'
)
BEGIN
    CREATE NONCLUSTERED INDEX
        IX_ETLRunLog_BatchID_StartDateTime
    ON etl.ETLRunLog
    (
        BatchID,
        StartDateTime DESC
    )
    INCLUDE
    (
        RunStatus,
        EndDateTime,
        RowsRead,
        RowsInserted,
        ErrorNumber
    );
END;
GO


-- FACT VALIDATION SNAPSHOT TABLE

IF OBJECT_ID(N'etl.FactValidationSnapshot', N'U') IS NULL
BEGIN
    CREATE TABLE etl.FactValidationSnapshot
    (
        FactValidationSnapshotID BIGINT IDENTITY(1,1) NOT NULL,
        BatchID UNIQUEIDENTIFIER NOT NULL,

        SnapshotDateTime DATETIME2(3) NOT NULL
            CONSTRAINT DF_FactValidationSnapshot_SnapshotDateTime
            DEFAULT (SYSDATETIME()),

        MinimumTransactionDateKey INT NULL,
        MaximumTransactionDateKey INT NULL,

        FactRowCount BIGINT NOT NULL,
        ApprovedTransactionCount BIGINT NOT NULL,
        FraudTransactionCount BIGINT NOT NULL,

        TotalTransactionVolumeTRY DECIMAL(38,4) NOT NULL,
        NetRevenueTRY DECIMAL(38,4) NOT NULL,

        CONSTRAINT PK_FactValidationSnapshot
            PRIMARY KEY CLUSTERED (FactValidationSnapshotID),

        CONSTRAINT UQ_FactValidationSnapshot_BatchID
            UNIQUE (BatchID),

        CONSTRAINT FK_FactValidationSnapshot_ETLBatch
            FOREIGN KEY (BatchID)
            REFERENCES etl.ETLBatch(BatchID),

        CONSTRAINT CK_FactValidationSnapshot_Counts
            CHECK
            (
                FactRowCount >= 0
                AND ApprovedTransactionCount >= 0
                AND FraudTransactionCount >= 0
                AND ApprovedTransactionCount <= FactRowCount
                AND FraudTransactionCount <= FactRowCount
            )
    );
END;
GO


-- FACT VALIDATION PROCEDURE

CREATE OR ALTER PROCEDURE etl.usp_CaptureFactValidationSnapshot
(
    @BatchID UNIQUEIDENTIFIER = NULL OUTPUT,
    @BatchName NVARCHAR(200) = N'Fact validation snapshot',
    @SourceSystem VARCHAR(100) = 'PaymentProjectDW',
    @SimulateFailure BIT = 0
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

        @RunID BIGINT = NULL,

        @ExistingBatchName NVARCHAR(200),
        @ExistingSourceSystem VARCHAR(100),
        @ExistingStatus VARCHAR(20),
        @ExistingSessionID INT,

        @ApprovedStatusKey TINYINT,

        @MinimumTransactionDateKey INT,
        @MaximumTransactionDateKey INT,

        @FactRowCount BIGINT = 0,
        @ApprovedTransactionCount BIGINT = 0,
        @FraudTransactionCount BIGINT = 0,

        @TotalTransactionVolumeTRY DECIMAL(38,4) = 0,
        @NetRevenueTRY DECIMAL(38,4) = 0;

    SET @BatchID = COALESCE(@BatchID, NEWID());
    SET @BatchName = NULLIF(LTRIM(RTRIM(@BatchName)), N'');
    SET @SourceSystem = NULLIF(LTRIM(RTRIM(@SourceSystem)), '');
    SET @SimulateFailure = COALESCE(@SimulateFailure, 0);

    IF @BatchName IS NULL
    BEGIN
        THROW 54010,
              'BatchName bos birakilamaz.',
              1;
    END;

    IF @SourceSystem IS NULL
    BEGIN
        THROW 54011,
              'SourceSystem bos birakilamaz.',
              1;
    END;

    SELECT
        @ApprovedStatusKey = TransactionStatusKey
    FROM dw.DimTransactionStatus
    WHERE StatusCode = 'APPROVED';

    IF @ApprovedStatusKey IS NULL
    BEGIN
        THROW 54012,
              'APPROVED transaction status key bulunamadi.',
              1;
    END;


    -- REGISTER OR REUSE THE BATCH

    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT
            @ExistingBatchName = BatchName,
            @ExistingSourceSystem = SourceSystem,
            @ExistingStatus = BatchStatus,
            @ExistingSessionID = CurrentSessionID
        FROM etl.ETLBatch WITH (UPDLOCK, HOLDLOCK)
        WHERE BatchID = @BatchID;

        IF @ExistingStatus IS NULL
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
                @BatchID,
                @BatchName,
                @SourceSystem,
                'PENDING'
            );

            SET @ExistingStatus = 'PENDING';
        END
        ELSE IF @ExistingBatchName <> @BatchName
             OR @ExistingSourceSystem <> @SourceSystem
        BEGIN
            THROW 54013,
                  'BatchID daha once farkli BatchName veya SourceSystem ile kullanildi.',
                  1;
        END;

        IF @ExistingStatus = 'SUCCEEDED'
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
                @BatchID,
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
                'Batch daha once basariyla tamamlandigi icin tekrar calistirilmadi.';

            SELECT snapshot.*
            FROM etl.FactValidationSnapshot AS snapshot
            WHERE snapshot.BatchID = @BatchID;

            RETURN;
        END;

        IF @ExistingStatus = 'RUNNING'
           AND
           (
               @ExistingSessionID IS NULL
               OR @ExistingSessionID <> @@SPID
           )
        BEGIN
            THROW 54014,
                  'Ayni BatchID baska bir SQL Server session tarafindan calistiriliyor.',
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
        WHERE BatchID = @BatchID;

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
            @BatchID,
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


    -- CAPTURE THE VALIDATION SNAPSHOT

    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT
            @MinimumTransactionDateKey =
                MIN(fact.TransactionDateKey),

            @MaximumTransactionDateKey =
                MAX(fact.TransactionDateKey),

            @FactRowCount =
                COUNT_BIG(*),

            @ApprovedTransactionCount =
                COALESCE
                (
                    SUM
                    (
                        CASE
                            WHEN fact.TransactionStatusKey = @ApprovedStatusKey
                            THEN CONVERT(BIGINT, 1)
                            ELSE CONVERT(BIGINT, 0)
                        END
                    ),
                    0
                ),

            @FraudTransactionCount =
                COALESCE
                (
                    SUM(CONVERT(BIGINT, fact.IsFraud)),
                    0
                ),

            @TotalTransactionVolumeTRY =
                COALESCE
                (
                    SUM(CONVERT(DECIMAL(38,4), fact.AmountTRY)),
                    CONVERT(DECIMAL(38,4), 0)
                ),

            @NetRevenueTRY =
                COALESCE
                (
                    SUM
                    (
                        CONVERT
                        (
                            DECIMAL(38,4),
                            fact.FeeAmountTRY
                            + fact.MerchantCommissionTRY
                            - fact.TaxAmountTRY
                            - fact.CashbackAmountTRY
                        )
                    ),
                    CONVERT(DECIMAL(38,4), 0)
                )
        FROM dw.FactPaymentTransaction AS fact;

        IF @SimulateFailure = 1
        BEGIN
            THROW 54015,
                  'Kontrollu ETL hatasi olusturuldu.',
                  1;
        END;

        INSERT INTO etl.FactValidationSnapshot
        (
            BatchID,
            MinimumTransactionDateKey,
            MaximumTransactionDateKey,
            FactRowCount,
            ApprovedTransactionCount,
            FraudTransactionCount,
            TotalTransactionVolumeTRY,
            NetRevenueTRY
        )
        VALUES
        (
            @BatchID,
            @MinimumTransactionDateKey,
            @MaximumTransactionDateKey,
            @FactRowCount,
            @ApprovedTransactionCount,
            @FraudTransactionCount,
            @TotalTransactionVolumeTRY,
            @NetRevenueTRY
        );

        UPDATE etl.ETLBatch
        SET
            BatchStatus = 'SUCCEEDED',
            CompletedDateTime = SYSDATETIME(),
            CurrentSessionID = NULL,
            LastErrorNumber = NULL,
            LastErrorMessage = NULL
        WHERE BatchID = @BatchID;

        UPDATE etl.ETLRunLog
        SET
            RunStatus = 'SUCCEEDED',
            EndDateTime = SYSDATETIME(),
            RowsRead = @FactRowCount,
            RowsInserted = 1,
            RowsUpdated = 0,
            RowsRejected = 0
        WHERE ETLRunID = @RunID;

        COMMIT TRANSACTION;

        PRINT 'Fact validation snapshot basariyla olusturuldu.';

        SELECT snapshot.*
        FROM etl.FactValidationSnapshot AS snapshot
        WHERE snapshot.BatchID = @BatchID;
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
        WHERE BatchID = @BatchID;

        IF @RunID IS NOT NULL
        BEGIN
            UPDATE etl.ETLRunLog
            SET
                RunStatus = 'FAILED',
                EndDateTime = SYSDATETIME(),
                RowsRead = COALESCE(@FactRowCount, 0),
                RowsInserted = 0,
                RowsUpdated = 0,
                RowsRejected = 0,
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


-- INSTALLATION CHECK

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
          N'ETLBatch',
          N'ETLRunLog',
          N'FactValidationSnapshot',
          N'usp_CaptureFactValidationSnapshot'
      )
ORDER BY objectData.type_desc, objectData.name;
GO

/*
    Optional idempotency test:

    DECLARE @DemoBatchID UNIQUEIDENTIFIER = NEWID();

    EXEC etl.usp_CaptureFactValidationSnapshot
        @BatchID = @DemoBatchID OUTPUT,
        @BatchName = N'Fact validation demo',
        @SourceSystem = 'PaymentProjectDW',
        @SimulateFailure = 0;

    EXEC etl.usp_CaptureFactValidationSnapshot
        @BatchID = @DemoBatchID OUTPUT,
        @BatchName = N'Fact validation demo',
        @SourceSystem = 'PaymentProjectDW',
        @SimulateFailure = 0;
*/

SET NOCOUNT OFF;
GO