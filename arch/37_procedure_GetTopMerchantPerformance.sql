
SET NOCOUNT ON;
GO

-- TOP MERCHANT PERFORMANCE STORED PROCEDURE

IF SCHEMA_ID(N'report') IS NULL
BEGIN
    THROW 53101,
          'report şeması bulunamadı.',
          1;
END;
GO

CREATE OR ALTER PROCEDURE report.usp_GetTopMerchantPerformance(
    @StartDate           DATE          = NULL,
    @EndDate             DATE          = NULL,
    @MerchantCategory    VARCHAR(100)  = NULL,
    @MerchantCountry     NVARCHAR(100) = NULL,
    @MerchantRiskLevel   VARCHAR(50)   = NULL,
    @OnlyOnlineMerchant  BIT           = NULL,
    @TopN                INT           = 20,
    @SortMetric          VARCHAR(30)   = 'VOLUME'
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY


        DECLARE
            @MinimumFactDateKey INT,
            @MaximumFactDateKey INT,

            @EffectiveStartDate DATE,
            @EffectiveEndDate   DATE,

            @StartDateKey INT,
            @EndDateKey   INT,

            @ApprovedStatusKey TINYINT;

        -- PARAMETRELERE STANDART

        SET @SortMetric =
            UPPER(
                LTRIM(
                    RTRIM(@SortMetric)
                )
            );

        SET @MerchantCategory =
            NULLIF(
                LTRIM(
                    RTRIM(@MerchantCategory)
                ),
                ''
            );

        SET @MerchantCountry =
            NULLIF(
                LTRIM(
                    RTRIM(@MerchantCountry)
                ),
                N''
            );

        SET @MerchantRiskLevel =
            NULLIF
            (
                LTRIM
                (
                    RTRIM(@MerchantRiskLevel)
                ),
                ''
            );

        -- TARİH ARALIĞI

        SELECT
            @MinimumFactDateKey =
                MIN(TransactionDateKey),

            @MaximumFactDateKey =
                MAX(TransactionDateKey)

        FROM dw.FactPaymentTransaction;

        IF @MinimumFactDateKey IS NULL
           OR @MaximumFactDateKey IS NULL
        BEGIN
            THROW 53102,
                  'FactPaymentTransaction tablosunda işlem bulunamadı.',
                  1;
        END;

        SET @EffectiveStartDate =
            COALESCE
            (
                @StartDate,

                CONVERT
                (
                    DATE,
                    CONVERT
                    (
                        CHAR(8),
                        @MinimumFactDateKey
                    ),
                    112
                )
            );

        SET @EffectiveEndDate =
            COALESCE(
                @EndDate,

                CONVERT(
                    DATE,
                    CONVERT(
                        CHAR(8),
                        @MaximumFactDateKey
                    ),
                    112
                )
            );

        --TARİH DOĞRULAMASI

        IF @EffectiveStartDate > @EffectiveEndDate
        BEGIN
            THROW 53103,
                  'StartDate, EndDate değerinden sonra olamaz.',
                  1;
        END;

        SET @StartDateKey =
            CONVERT
            (
                INT,
                CONVERT
                (
                    CHAR(8),
                    @EffectiveStartDate,
                    112
                )
            );

        SET @EndDateKey =
            CONVERT(
                INT,
                CONVERT(
                    CHAR(8),
                    @EffectiveEndDate,
                    112
                )
            );

        --TOP N DOĞRULAMASI

        IF @TopN IS NULL
           OR @TopN NOT BETWEEN 1 AND 100
        BEGIN
            THROW 53104,
                  'TopN değeri 1 ile 100 arasında olmalıdır.',
                  1;
        END;

        -- SORT METRIC DOĞRULAMASI

        IF @SortMetric NOT IN
        (
            'VOLUME',
            'TRANSACTION_COUNT',
            'NET_REVENUE',
            'FRAUD_RATE',
            'APPROVAL_RATE'
        )
        BEGIN
            THROW 53105,
                  'Geçersiz SortMetric. VOLUME, TRANSACTION_COUNT, NET_REVENUE, FRAUD_RATE veya APPROVAL_RATE kullanılmalıdır.',
                  1;
        END;

        -- MERCHANT FİLTRELERİNİ DOĞRULAMA

        IF @MerchantCategory IS NOT NULL
           AND NOT EXISTS
           (
               SELECT 1
               FROM dw.DimMerchant
               WHERE MerchantCategory = @MerchantCategory
                 AND MerchantKey <> 0
           )
        BEGIN
            THROW 53106,
                  'Geçersiz MerchantCategory değeri.',
                  1;
        END;

        IF @MerchantCountry IS NOT NULL
           AND NOT EXISTS
           (
               SELECT 1
               FROM dw.DimMerchant
               WHERE Country = @MerchantCountry
                 AND MerchantKey <> 0
           )
        BEGIN
            THROW 53107,
                  'Geçersiz MerchantCountry değeri.',
                  1;
        END;

        IF @MerchantRiskLevel IS NOT NULL
           AND NOT EXISTS
           (
               SELECT 1
               FROM dw.DimMerchant
               WHERE MerchantRiskLevel = @MerchantRiskLevel
                 AND MerchantKey <> 0
           )
        BEGIN
            THROW 53108,
                  'Geçersiz MerchantRiskLevel değeri.',
                  1;
        END;

        -- APPROVED STATUS KEY

        SELECT
            @ApprovedStatusKey = TransactionStatusKey
        FROM dw.DimTransactionStatus
        WHERE StatusCode = 'APPROVED';

        IF @ApprovedStatusKey IS NULL
        BEGIN
            THROW 53109,
                  'APPROVED status key bulunamadı.',
                  1;
        END;

        -- MERCHANT ÖZET TABLOSU

        DROP TABLE IF EXISTS #MerchantSummary;

        SELECT
            ------------------------------------------------
            -- MERCHANT ATTRIBUTES
            ------------------------------------------------

            merchant.MerchantKey,
            merchant.MerchantID,
            merchant.MerchantName,
            merchant.MerchantCategory,
            merchant.MerchantSubcategory,
            merchant.MerchantSize,
            merchant.MerchantRiskLevel,

            merchant.Country
                AS MerchantCountry,

            merchant.IsOnlineMerchant,
            merchant.OnboardingDate,

            ------------------------------------------------
            -- TRANSACTION COUNTS
            ------------------------------------------------

            COUNT_BIG(*)
                AS TransactionCount,

            SUM
            (
                CASE
                    WHEN fact.TransactionStatusKey =
                         @ApprovedStatusKey
                    THEN CONVERT(BIGINT, 1)
                    ELSE CONVERT(BIGINT, 0)
                END
            ) AS ApprovedTransactionCount,

            SUM
            (
                CASE
                    WHEN fact.IsFraud = 1
                    THEN CONVERT(BIGINT, 1)
                    ELSE CONVERT(BIGINT, 0)
                END
            ) AS FraudTransactionCount,

            ------------------------------------------------
            -- TRANSACTION AMOUNTS
            ------------------------------------------------

            SUM(fact.AmountTRY)
                AS TotalTransactionVolumeTRY,

            SUM
            (
                CASE
                    WHEN fact.TransactionStatusKey =
                         @ApprovedStatusKey
                    THEN fact.AmountTRY
                    ELSE CONVERT(DECIMAL(19,4), 0)
                END
            ) AS ApprovedTransactionVolumeTRY,

            CAST
            (
                AVG(fact.AmountTRY)
                AS DECIMAL(19,2)
            ) AS AverageTransactionAmountTRY,

            MAX(fact.AmountTRY)
                AS MaximumTransactionAmountTRY,

            ------------------------------------------------
            -- REVENUE
            ------------------------------------------------

            SUM(fact.FeeAmountTRY)
                AS TotalFeeAmountTRY,

            SUM(fact.MerchantCommissionTRY)
                AS TotalMerchantCommissionTRY,

            SUM(fact.TaxAmountTRY)
                AS TotalTaxAmountTRY,

            SUM(fact.CashbackAmountTRY)
                AS TotalCashbackCostTRY,

            CAST
            (
                SUM
                (
                    fact.FeeAmountTRY
                    +
                    fact.MerchantCommissionTRY
                )
                AS DECIMAL(38,4)
            ) AS GrossRevenueTRY,

            CAST(
                SUM(
                    fact.FeeAmountTRY
                    +
                    fact.MerchantCommissionTRY
                    -
                    fact.TaxAmountTRY
                    -
                    fact.CashbackAmountTRY
                )
                AS DECIMAL(38,4)
            ) AS NetRevenueTRY,

            ------------------------------------------------
            -- FRAUD SCORE
            ------------------------------------------------

            CAST
            (
                AVG(fact.FraudScore)
                AS DECIMAL(8,2)
            ) AS AverageFraudScore,

            ------------------------------------------------
            -- AUTHORIZATION DURATION
            ------------------------------------------------

            CAST(
                SUM(
                    COALESCE(
                        CONVERT(
                            DECIMAL(38,2),
                            fact.AuthorizationDurationMs
                        ),
                        0
                    )
                )
                /
                NULLIF(
                    SUM(
                        CASE
                            WHEN fact.AuthorizationDurationMs
                                 IS NOT NULL
                            THEN CONVERT(DECIMAL(38,2), 1)
                            ELSE CONVERT(DECIMAL(38,2), 0)
                        END
                    ),
                    0
                )
                AS DECIMAL(19,2)
            ) AS AverageAuthorizationDurationMs,

            ------------------------------------------------
            -- SECURITY / CHANNEL FLAGS
            ------------------------------------------------

            SUM
            (
                CONVERT
                (
                    BIGINT,
                    fact.IsInternational
                )
            ) AS InternationalTransactionCount,

            SUM(
                CONVERT(
                    BIGINT,
                    fact.IsContactless
                )
            ) AS ContactlessTransactionCount,

            SUM(
                CONVERT(
                    BIGINT,
                    fact.IsRecurring
                )
            ) AS RecurringTransactionCount

        INTO #MerchantSummary

        FROM dw.FactPaymentTransaction AS fact

        INNER JOIN dw.DimMerchant AS merchant
            ON merchant.MerchantKey =
               fact.MerchantKey

        WHERE fact.TransactionDateKey
              BETWEEN @StartDateKey AND @EndDateKey

          AND merchant.IsCurrent = 1

          AND(
              @MerchantCategory IS NULL
              OR merchant.MerchantCategory =
                 @MerchantCategory
          )

          AND(
              @MerchantCountry IS NULL
              OR merchant.Country =
                 @MerchantCountry
          )

          AND(
              @MerchantRiskLevel IS NULL
              OR merchant.MerchantRiskLevel =
                 @MerchantRiskLevel
          )

          AND(
              @OnlyOnlineMerchant IS NULL
              OR merchant.IsOnlineMerchant =
                 @OnlyOnlineMerchant
          )

        GROUP BY
            merchant.MerchantKey,
            merchant.MerchantID,
            merchant.MerchantName,
            merchant.MerchantCategory,
            merchant.MerchantSubcategory,
            merchant.MerchantSize,
            merchant.MerchantRiskLevel,
            merchant.Country,
            merchant.IsOnlineMerchant,
            merchant.OnboardingDate

        OPTION (RECOMPILE);

        -- TEMP TABLE INDEX

        CREATE UNIQUE CLUSTERED INDEX
            CX_MerchantSummary_MerchantKey

        ON #MerchantSummary
        (
            MerchantKey
        );

        -- RESULT SET 1
        -- FİLTRE

        SELECT
            @EffectiveStartDate
                AS EffectiveStartDate,

            @EffectiveEndDate
                AS EffectiveEndDate,

            @MerchantCategory
                AS MerchantCategoryFilter,

            @MerchantCountry
                AS MerchantCountryFilter,

            @MerchantRiskLevel
                AS MerchantRiskLevelFilter,

            @OnlyOnlineMerchant
                AS OnlyOnlineMerchantFilter,

            @TopN
                AS TopN,

            @SortMetric
                AS SortMetric,

            COUNT_BIG(*)
                AS MatchingMerchantCount,

            COALESCE
            (
                SUM(TransactionCount),
                0
            ) AS TransactionCount,

            COALESCE
            (
                SUM(ApprovedTransactionCount),
                0
            ) AS ApprovedTransactionCount,

            COALESCE
            (
                SUM(FraudTransactionCount),
                0
            ) AS FraudTransactionCount,

            COALESCE
            (
                SUM(TotalTransactionVolumeTRY),
                CONVERT(DECIMAL(38,4), 0)
            ) AS TotalTransactionVolumeTRY,

            COALESCE
            (
                SUM(NetRevenueTRY),
                CONVERT(DECIMAL(38,4), 0)
            ) AS NetRevenueTRY

        FROM #MerchantSummary;

        -- RESULT SET 2
        -- TOP MERCHANT 

        ;WITH CalculatedMerchant AS
        (
            SELECT
                summary.*,

                CAST
                (
                    100.0
                    *
                    summary.ApprovedTransactionCount
                    /
                    NULLIF
                    (
                        summary.TransactionCount,
                        0
                    )
                    AS DECIMAL(8,2)
                ) AS ApprovalRate,

                CAST
                (
                    100.0
                    *
                    summary.FraudTransactionCount
                    /
                    NULLIF
                    (
                        summary.TransactionCount,
                        0
                    )
                    AS DECIMAL(8,4)
                ) AS FraudRate,

                CAST
                (
                    100.0
                    *
                    summary.InternationalTransactionCount
                    /
                    NULLIF
                    (
                        summary.TransactionCount,
                        0
                    )
                    AS DECIMAL(8,2)
                ) AS InternationalTransactionRate

            FROM #MerchantSummary AS summary
        )
        SELECT TOP (@TopN)
            MerchantKey,
            MerchantID,
            MerchantName,
            MerchantCategory,
            MerchantSubcategory,
            MerchantSize,
            MerchantRiskLevel,
            MerchantCountry,
            IsOnlineMerchant,
            OnboardingDate,

            TransactionCount,
            ApprovedTransactionCount,
            ApprovalRate,

            FraudTransactionCount,
            FraudRate,
            AverageFraudScore,

            TotalTransactionVolumeTRY,
            ApprovedTransactionVolumeTRY,
            AverageTransactionAmountTRY,
            MaximumTransactionAmountTRY,

            GrossRevenueTRY,
            NetRevenueTRY,

            InternationalTransactionCount,
            InternationalTransactionRate,
            ContactlessTransactionCount,
            RecurringTransactionCount,

            AverageAuthorizationDurationMs,

            @SortMetric AS SortMetricUsed

        FROM CalculatedMerchant

        ORDER BY
            CASE
                WHEN @SortMetric = 'VOLUME'
                THEN TotalTransactionVolumeTRY
            END DESC,

            CASE
                WHEN @SortMetric = 'TRANSACTION_COUNT'
                THEN TransactionCount
            END DESC,

            CASE
                WHEN @SortMetric = 'NET_REVENUE'
                THEN NetRevenueTRY
            END DESC,

            CASE
                WHEN @SortMetric = 'FRAUD_RATE'
                THEN FraudRate
            END DESC,

            CASE
                WHEN @SortMetric = 'APPROVAL_RATE'
                THEN ApprovalRate
            END DESC,

            MerchantKey;

    END TRY

    BEGIN CATCH

        DECLARE
            @ErrorNumber    INT            = ERROR_NUMBER(),
            @ErrorMessage   NVARCHAR(4000) = ERROR_MESSAGE(),
            @ErrorProcedure NVARCHAR(200)  = ERROR_PROCEDURE(),
            @ErrorLine      INT            = ERROR_LINE();

        PRINT CONCAT
        (
            'Hata numarası: ',
            @ErrorNumber
        );

        PRINT CONCAT
        (
            'Procedure: ',
            COALESCE
            (
                @ErrorProcedure,
                'Bilinmiyor'
            )
        );

        PRINT CONCAT
        (
            'Hata satırı: ',
            @ErrorLine
        );

        PRINT CONCAT
        (
            'Hata mesajı: ',
            @ErrorMessage
        );

        THROW;

    END CATCH;
END;
GO

------------------------------------------------------------
-- PROCEDURE
------------------------------------------------------------

SELECT
    schemaData.name AS SchemaName,
    procedureData.name AS ProcedureName,
    procedureData.create_date AS CreateDate,
    procedureData.modify_date AS ModifyDate

FROM sys.procedures AS procedureData

INNER JOIN sys.schemas AS schemaData
    ON schemaData.schema_id =
       procedureData.schema_id

WHERE schemaData.name = N'report'
  AND procedureData.name =
      N'usp_GetTopMerchantPerformance';
GO

-- TEST
-- 2025 YILI, HACME GÖRE TOP 20 MERCHANT
------------------------------------------------------------

EXEC report.usp_GetTopMerchantPerformance
    @StartDate = '20250101',
    @EndDate = '20251231',
    @TopN = 20,
    @SortMetric = 'VOLUME';
GO

SET NOCOUNT OFF;
GO