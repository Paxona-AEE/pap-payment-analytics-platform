;/****** Object:  StoredProcedure [report].[usp_GetPaymentSummary]    Script Date: 17.07.2026 21:23:14 ******/

CREATE PROCEDURE [report].[usp_GetPaymentSummary] (
    @StartDate              DATE         = NULL,    --Open to null process --That kind of parameters
    @EndDate                DATE         = NULL,
    @PaymentChannelCode     VARCHAR(50)  = NULL,
    @MerchantCategory       VARCHAR(100) = NULL,
    @CustomerSegment        VARCHAR(50)  = NULL,
    @TransactionStatusCode  VARCHAR(50)  = NULL,
    @OnlyFraud              BIT          = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY

        DECLARE
            @EffectiveStartDate DATE,
            @EffectiveEndDate   DATE,
            @StartDateKey       INT,
            @EndDateKey         INT;

        SELECT
            @EffectiveStartDate =
                COALESCE(           --Select anything but null?
                    @StartDate,
                    MIN(dateDimension.FullDate)
                ),

            @EffectiveEndDate =
                COALESCE(
                    @EndDate,
                    MAX(dateDimension.FullDate)
                )

        FROM dw.FactPaymentTransaction AS fact

        INNER JOIN dw.DimDate AS dateDimension
            ON dateDimension.DateKey =
               fact.TransactionDateKey;

--Every throw should be higher than the 50000, resounding

        SET @StartDateKey =
            CONVERT(
                INT,
                CONVERT(
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

        DROP TABLE IF EXISTS #FilteredPayment;

        SELECT
            fact.PaymentTransactionKey,

            fact.TransactionDateKey,

            dateDimension.FullDate
                AS TransactionDate,

            dateDimension.CalendarYear,
            dateDimension.CalendarQuarter,
            dateDimension.MonthNumber,
            dateDimension.MonthName,

            fact.CustomerKey,
            customer.CustomerSegment,

            fact.CardKey,

            fact.MerchantKey,
            merchant.MerchantCategory,

            fact.PaymentChannelKey,
            channel.PaymentChannelCode,

            fact.TransactionStatusKey,

            status.StatusCode
                AS TransactionStatusCode,

            CONVERT(
                BIT,        --Another true or false statement
                CASE
                    WHEN status.StatusCode = 'APPROVED'
                    THEN 1
                    ELSE 0
                END
            ) AS IsApproved,

            fact.AmountTRY,
            fact.FeeAmountTRY,
            fact.MerchantCommissionTRY,
            fact.TaxAmountTRY,
            fact.CashbackAmountTRY,

            fact.AuthorizationDurationMs,

            fact.IsInternational,
            fact.IsContactless,
            fact.IsRecurring,

            fact.IsFraud,
            fact.FraudScore

        INTO #FilteredPayment

        FROM dw.FactPaymentTransaction AS fact

        INNER JOIN dw.DimDate AS dateDimension
            ON dateDimension.DateKey =
               fact.TransactionDateKey

        INNER JOIN dw.DimCustomer AS customer
            ON customer.CustomerKey =
               fact.CustomerKey

        INNER JOIN dw.DimMerchant AS merchant
            ON merchant.MerchantKey =
               fact.MerchantKey

        INNER JOIN dw.DimPaymentChannel AS channel
            ON channel.PaymentChannelKey =
               fact.PaymentChannelKey

        INNER JOIN dw.DimTransactionStatus AS status
            ON status.TransactionStatusKey =
               fact.TransactionStatusKey

        WHERE fact.TransactionDateKey
              BETWEEN @StartDateKey AND @EndDateKey

          AND(
              @PaymentChannelCode IS NULL
              OR channel.PaymentChannelCode =
                 @PaymentChannelCode
          )

          AND(
              @MerchantCategory IS NULL
              OR merchant.MerchantCategory =
                 @MerchantCategory
          )

          AND(
              @CustomerSegment IS NULL
              OR customer.CustomerSegment =
                 @CustomerSegment
          )

          AND(
              @TransactionStatusCode IS NULL
              OR status.StatusCode =
                 @TransactionStatusCode
          )

          AND(
              @OnlyFraud IS NULL
              OR fact.IsFraud = @OnlyFraud
          )


        CREATE CLUSTERED INDEX
            CX_FilteredPayment_TransactionDateKey

        ON #FilteredPayment
        (
            TransactionDateKey
        );



--Resolution

        SELECT
            @EffectiveStartDate
                AS EffectiveStartDate,

            @EffectiveEndDate
                AS EffectiveEndDate,

            @PaymentChannelCode
                AS PaymentChannelFilter,

            @MerchantCategory
                AS MerchantCategoryFilter,

            @CustomerSegment
                AS CustomerSegmentFilter,

            @TransactionStatusCode
                AS TransactionStatusFilter,

            @OnlyFraud
                AS OnlyFraudFilter,

            COUNT_BIG(*)
                AS TransactionCount,

            COUNT
            (
                DISTINCT CustomerKey
            ) AS DistinctCustomerCount,

            COUNT
            (
                DISTINCT CardKey
            ) AS DistinctCardCount,

            COUNT
            (
                DISTINCT MerchantKey
            ) AS DistinctMerchantCount,

            SUM
            (
                CONVERT
                (
                    BIGINT,
                    IsApproved
                )
            ) AS ApprovedTransactionCount,

            CAST
            (
                100.0
                *
                SUM
                (
                    CONVERT
                    (
                        BIGINT,
                        IsApproved
                    )
                )
                /
                NULLIF
                (
                    COUNT_BIG(*),
                    0
                )

                AS DECIMAL(8,2)
            ) AS ApprovalRate,

            SUM
            (
                CONVERT
                (
                    BIGINT,
                    IsFraud
                )
            ) AS FraudTransactionCount,

            CAST
            (
                100.0
                *
                SUM
                (
                    CONVERT
                    (
                        BIGINT,
                        IsFraud
                    )
                )
                /
                NULLIF
                (
                    COUNT_BIG(*),
                    0
                )

                AS DECIMAL(8,4)
            ) AS FraudRate,

            SUM(AmountTRY)
                AS TotalTransactionVolumeTRY,

            CAST
            (
                AVG(AmountTRY)
                AS DECIMAL(19,2)
            ) AS AverageTransactionAmountTRY,

            SUM(FeeAmountTRY)
                AS TotalFeeAmountTRY,

            SUM(MerchantCommissionTRY)
                AS TotalMerchantCommissionTRY,

            SUM(TaxAmountTRY)
                AS TotalTaxAmountTRY,

            SUM(CashbackAmountTRY)
                AS TotalCashbackCostTRY,

            CAST
            (
                SUM
                (
                    FeeAmountTRY
                    +
                    MerchantCommissionTRY
                )

                AS DECIMAL(38,4)
            ) AS GrossRevenueTRY,

            CAST
            (
                SUM
                (
                    FeeAmountTRY
                    +
                    MerchantCommissionTRY
                    -
                    TaxAmountTRY
                    -
                    CashbackAmountTRY
                )

                AS DECIMAL(38,4)
            ) AS NetRevenueTRY,

            CAST
            (
                SUM
                (
                    COALESCE
                    (
                        CONVERT
                        (
                            DECIMAL(38,2),
                            AuthorizationDurationMs
                        ),
                        0
                    )
                )
                /
                NULLIF
                (
                    SUM
                    (
                        CASE
                            WHEN AuthorizationDurationMs
                                 IS NOT NULL
                            THEN CONVERT
                                 (
                                     DECIMAL(38,2),
                                     1
                                 )

                            ELSE CONVERT
                                 (
                                     DECIMAL(38,2),
                                     0
                                 )
                        END
                    ),
                    0
                )

                AS DECIMAL(19,2)
            ) AS AverageAuthorizationDurationMs

        FROM #FilteredPayment;
END TRY
BEGIN CATCH

        SELECT
            ERROR_NUMBER() AS ErrorNumber,
            ERROR_LINE() AS ErrorLine,
            ERROR_PROCEDURE() AS ErrorProcedure,
            ERROR_MESSAGE() AS ErrorMessage;

        THROW;

    END CATCH;
END;
GO