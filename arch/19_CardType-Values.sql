--New
BEGIN
    ALTER TABLE dw.DimCard
    ADD CardholderCustomerID VARCHAR(30) NULL;
END;
GO

--SCD Type 2 Error Again (Solution)

BEGIN
    ALTER TABLE dw.DimCard
    DROP CONSTRAINT UQ_DimCard_CardID;
END;
GO

BEGIN
    ALTER TABLE dw.DimCard
    ADD CONSTRAINT UQ_DimCard_Version
        UNIQUE(
            CardID,
            EffectiveStartDate
        );
END;
GO

BEGIN
    CREATE UNIQUE INDEX UX_DimCard_CurrentCardID
        ON dw.DimCard(CardID)
        WHERE IsCurrent = 1;
END;
GO

--Unknown for the CardType

BEGIN
    ALTER TABLE dw.DimCard
    DROP CONSTRAINT CK_DimCard_CardType;
END;
GO

ALTER TABLE dw.DimCard
ADD CONSTRAINT CK_DimCard_CardType
CHECK(
    CardType IN (
        'Unknown',
        'Credit',
        'Debit',
        'Prepaid'
    )
);
GO

--Setting the Unknown Values

IF NOT EXISTS (
    SELECT 1
    FROM dw.DimCard
    WHERE CardKey = 0
)
BEGIN
    SET IDENTITY_INSERT dw.DimCard ON;

    INSERT INTO dw.DimCard (
        CardKey,
        CardID,
        CardType,
        CardBrand,
        CardTier,
        LastFourDigits,
        IssueDate,
        ExpiryDate,
        CardStatus,
        IsVirtual,
        IsContactlessEnabled,
        CardCountry,
        EffectiveStartDate,
        EffectiveEndDate,
        IsCurrent,
        CardholderCustomerID
    )
    VALUES (
        0,
        'UNKNOWN',
        'Unknown',
        'Unknown',
        'Unknown',
        '0000',
        '19000101',
        '99991231',
        'Unknown',
        0,
        0,
        N'Bilinmiyor',
        '19000101',
        '99991231',
        1,
        'UNKNOWN'
    );

    SET IDENTITY_INSERT dw.DimCard OFF;
END;
GO


--Big Command

DECLARE @AsOfDate DATE = '20260630';

;WITH CurrentCustomers AS (
    SELECT
        CustomerID,
        CustomerSegment,
        Country,
        RegistrationDate,
        IsActive,

        ABS(
            CONVERT(
                BIGINT,
                CHECKSUM(
                    CONCAT(CustomerID, '|CARD_COUNT')
                )
            )
        ) % 100 AS CardCountBucket

    FROM dw.DimCustomer

    WHERE CustomerKey <> 0
      AND IsCurrent = 1
),
CustomerCardCounts AS
(
    SELECT
        CustomerID,
        CustomerSegment,
        Country,
        RegistrationDate,
        IsActive,

        CASE
            WHEN CustomerSegment = 'Standard'
            THEN
                CASE
                    WHEN CardCountBucket < 5  THEN 0
                    WHEN CardCountBucket < 75 THEN 1
                    WHEN CardCountBucket < 97 THEN 2
                    ELSE 3
                END

            WHEN CustomerSegment = 'Silver'
            THEN
                CASE
                    WHEN CardCountBucket < 2  THEN 0
                    WHEN CardCountBucket < 52 THEN 1
                    WHEN CardCountBucket < 87 THEN 2
                    WHEN CardCountBucket < 98 THEN 3
                    ELSE 4
                END

            WHEN CustomerSegment = 'Gold'
            THEN
                CASE
                    WHEN CardCountBucket < 30 THEN 1
                    WHEN CardCountBucket < 72 THEN 2
                    WHEN CardCountBucket < 92 THEN 3
                    WHEN CardCountBucket < 98 THEN 4
                    ELSE 5
                END

            WHEN CustomerSegment = 'Platinum'
            THEN
                CASE
                    WHEN CardCountBucket < 10 THEN 1
                    WHEN CardCountBucket < 45 THEN 2
                    WHEN CardCountBucket < 75 THEN 3
                    WHEN CardCountBucket < 95 THEN 4
                    ELSE 5
                END

            WHEN CustomerSegment = 'Corporate'
            THEN
                CASE
                    WHEN CardCountBucket < 10 THEN 1
                    WHEN CardCountBucket < 35 THEN 2
                    WHEN CardCountBucket < 65 THEN 3
                    WHEN CardCountBucket < 90 THEN 4
                    ELSE 5
                END

            ELSE 0
        END AS CardCount

    FROM CurrentCustomers
),
CardNumbers AS (
    SELECT
        customer.CustomerID,
        customer.CustomerSegment,
        customer.Country,
        customer.RegistrationDate,
        customer.IsActive,
        numbers.CardSequence,

        CONCAT('CARD',RIGHT(customer.CustomerID, 6),RIGHT('00' +CONVERT(
                    VARCHAR(2),
                    numbers.CardSequence
                ),
                2
            )
        ) AS CardID

    FROM CustomerCardCounts AS customer

    CROSS JOIN (
        VALUES
            (1),
            (2),
            (3),
            (4),
            (5)
    ) AS numbers(CardSequence)

    WHERE numbers.CardSequence <= customer.CardCount
),
CardSeeds AS (
    SELECT
        CardID,
        CustomerID,
        CustomerSegment,
        Country,
        RegistrationDate,
        IsActive,
        CardSequence,

        ABS(
            CONVERT(
                BIGINT,
                CHECKSUM(CONCAT(CardID, '|TYPE'))
            )
        ) % 100 AS CardTypeBucket,

        ABS(
            CONVERT(
                BIGINT,
                CHECKSUM(CONCAT(CardID, '|BRAND'))
            )
        ) % 100 AS BrandBucket,

        ABS(
            CONVERT(
                BIGINT,
                CHECKSUM(CONCAT(CardID, '|TIER'))
            )
        ) % 100 AS TierBucket,

        ABS(
            CONVERT(
                BIGINT,
                CHECKSUM(CONCAT(CardID, '|LAST4'))
            )
        ) % 10000 AS LastFourSeed,

        ABS(
            CONVERT(
                BIGINT,
                CHECKSUM(CONCAT(CardID, '|ISSUE_DATE'))
            )
        ) AS IssueDateSeed,

        ABS(
            CONVERT(
                BIGINT,
                CHECKSUM(CONCAT(CardID, '|EXPIRY'))
            )
        ) % 3 AS ExpiryYearSeed,

        ABS(
            CONVERT(
                BIGINT,
                CHECKSUM(CONCAT(CardID, '|STATUS'))
            )
        ) % 100 AS StatusBucket,

        ABS(
            CONVERT(
                BIGINT,
                CHECKSUM(CONCAT(CardID, '|VIRTUAL'))
            )
        ) % 100 AS VirtualBucket,

        ABS(
            CONVERT(
                BIGINT,
                CHECKSUM(CONCAT(CardID, '|CONTACTLESS'))
            )
        ) % 100 AS ContactlessBucket

    FROM CardNumbers
),
CardsWithIssueDate AS(
    SELECT
        *,

        DATEADD(DAY,CONVERT(INT,IssueDateSeed %(DATEDIFF(DAY,RegistrationDate,                     @AsOfDate) + 1
                )
            ),

            RegistrationDate
        ) AS IssueDate

    FROM CardSeeds
),
CardsWithType AS(
    SELECT
        *,

        CASE
            WHEN CustomerSegment = 'Standard'
            THEN
                CASE
                    WHEN CardTypeBucket < 58 THEN 'Debit'
                    WHEN CardTypeBucket < 90 THEN 'Credit'
                    ELSE 'Prepaid'
                END

            WHEN CustomerSegment = 'Silver'
            THEN
                CASE
                    WHEN CardTypeBucket < 45 THEN 'Debit'
                    WHEN CardTypeBucket < 91 THEN 'Credit'
                    ELSE 'Prepaid'
                END

            WHEN CustomerSegment = 'Gold'
            THEN
                CASE
                    WHEN CardTypeBucket < 35 THEN 'Debit'
                    WHEN CardTypeBucket < 95 THEN 'Credit'
                    ELSE 'Prepaid'
                END

            WHEN CustomerSegment = 'Platinum'
            THEN
                CASE
                    WHEN CardTypeBucket < 26 THEN 'Debit'
                    WHEN CardTypeBucket < 98 THEN 'Credit'
                    ELSE 'Prepaid'
                END

            WHEN CustomerSegment = 'Corporate'
            THEN
                CASE
                    WHEN CardTypeBucket < 28 THEN 'Debit'
                    WHEN CardTypeBucket < 96 THEN 'Credit'
                    ELSE 'Prepaid'
                END

            ELSE 'Debit'
        END AS CardType

    FROM CardsWithIssueDate
),
CardsWithExpiryDate AS(
    SELECT
        *,

        EOMONTH(
            DATEADD(YEAR,CONVERT(INT, 3 + ExpiryYearSeed),IssueDate)
        ) AS ExpiryDate

    FROM CardsWithType
),
CardsWithVirtualStatus AS (
    SELECT
        *,

        CASE
            WHEN CardType = 'Prepaid'
                 AND VirtualBucket < 45
            THEN 1

            WHEN CardType = 'Credit'
                 AND VirtualBucket < 14
            THEN 1

            WHEN CardType = 'Debit'
                 AND VirtualBucket < 7
            THEN 1

            ELSE 0
        END AS IsVirtual

    FROM CardsWithExpiryDate
),
FinalCards AS (
    SELECT
        CardID,
        CustomerID,
        CustomerSegment,
        Country,
        RegistrationDate,
        IsActive,
        CardType,
        IssueDate,
        ExpiryDate,
        IsVirtual,

        CASE
            WHEN CardType = 'Prepaid'
            THEN
                CASE
                    WHEN BrandBucket < 40 THEN 'Mastercard'
                    WHEN BrandBucket < 75 THEN 'Visa'
                    ELSE 'Troy'
                END

            WHEN CustomerSegment = 'Platinum'
            THEN
                CASE
                    WHEN BrandBucket < 44 THEN 'Mastercard'
                    WHEN BrandBucket < 84 THEN 'Visa'
                    WHEN BrandBucket < 94 THEN 'Troy'
                    ELSE 'American Express'
                END

            WHEN CustomerSegment = 'Corporate'
            THEN
                CASE
                    WHEN BrandBucket < 50 THEN 'Mastercard'
                    WHEN BrandBucket < 87 THEN 'Visa'
                    WHEN BrandBucket < 95 THEN 'Troy'
                    ELSE 'American Express'
                END

            ELSE
                CASE
                    WHEN BrandBucket < 46 THEN 'Mastercard'
                    WHEN BrandBucket < 88 THEN 'Visa'
                    WHEN BrandBucket < 98 THEN 'Troy'
                    ELSE 'American Express'
                END
        END AS CardBrand,

        CASE
            WHEN CustomerSegment = 'Corporate'
                 AND CardType = 'Credit'
            THEN 'Corporate Credit'

            WHEN CustomerSegment = 'Corporate'
                 AND CardType = 'Debit'
            THEN 'Business Debit'

            WHEN CustomerSegment = 'Corporate'
                 AND CardType = 'Prepaid'
            THEN 'Corporate Prepaid'

            WHEN CardType = 'Prepaid'
                 AND IsVirtual = 1
            THEN 'Virtual Prepaid'

            WHEN CardType = 'Prepaid'
            THEN 'Standard Prepaid'

            WHEN CardType = 'Credit'
                 AND CustomerSegment = 'Platinum'
                 AND TierBucket < 45
            THEN 'World Elite'

            WHEN CardType = 'Credit'
                 AND CustomerSegment = 'Platinum'
            THEN 'Platinum'

            WHEN CardType = 'Credit'
                 AND CustomerSegment = 'Gold'
                 AND TierBucket < 55
            THEN 'World'

            WHEN CardType = 'Credit'
                 AND CustomerSegment = 'Gold'
            THEN 'Gold'

            WHEN CardType = 'Credit'
                 AND CustomerSegment = 'Silver'
                 AND TierBucket < 20
            THEN 'Gold'

            WHEN CardType = 'Credit'
            THEN 'Classic'

            WHEN CardType = 'Debit'
                 AND CustomerSegment = 'Platinum'
            THEN 'Platinum Debit'

            WHEN CardType = 'Debit'
                 AND CustomerSegment = 'Gold'
            THEN 'Gold Debit'

            ELSE 'Standard Debit'
        END AS CardTier,

        RIGHT('0000' +CONVERT(VARCHAR(4),LastFourSeed),
            4
        ) AS LastFourDigits,

        CASE
            WHEN ExpiryDate < @AsOfDate
            THEN 'Expired'

            WHEN IsActive = 0
            THEN
                CASE
                    WHEN StatusBucket < 10 THEN 'Active'
                    WHEN StatusBucket < 65 THEN 'Cancelled'
                    WHEN StatusBucket < 85 THEN 'Blocked'
                    ELSE 'Suspended'
                END

            ELSE
                CASE
                    WHEN StatusBucket < 91 THEN 'Active'
                    WHEN StatusBucket < 95 THEN 'Blocked'
                    WHEN StatusBucket < 98 THEN 'Suspended'
                    ELSE 'Cancelled'
                END
        END AS CardStatus,

        CASE
            WHEN IsVirtual = 1
            THEN 0

            WHEN IssueDate >= '20220101'
                 AND ContactlessBucket < 96
            THEN 1

            WHEN IssueDate >= '20200101'
                 AND ContactlessBucket < 91
            THEN 1

            WHEN IssueDate < '20200101'
                 AND ContactlessBucket < 78
            THEN 1

            ELSE 0
        END AS IsContactlessEnabled

    FROM CardsWithVirtualStatus
)
INSERT INTO dw.DimCard (
    CardID,
    CardType,
    CardBrand,
    CardTier,
    LastFourDigits,
    IssueDate,
    ExpiryDate,
    CardStatus,
    IsVirtual,
    IsContactlessEnabled,
    CardCountry,
    EffectiveStartDate,
    EffectiveEndDate,
    IsCurrent,
    CardholderCustomerID
)
SELECT
    source.CardID,
    source.CardType,
    source.CardBrand,
    source.CardTier,
    source.LastFourDigits,
    source.IssueDate,
    source.ExpiryDate,
    source.CardStatus,
    source.IsVirtual,
    source.IsContactlessEnabled,
    source.Country,
    source.IssueDate,
    CAST('99991231' AS DATE),
    1,
    source.CustomerID

FROM FinalCards AS source

WHERE NOT EXISTS (
    SELECT 1
    FROM dw.DimCard AS target
    WHERE target.CardID = source.CardID
);
GO

--Validate

SELECT
    COUNT(*) AS TotalCardRowCount,

    COUNT(
        CASE
            WHEN CardKey <> 0 THEN 1
        END
    ) AS RealCardCount,

    COUNT (
        CASE
            WHEN CardKey <> 0
             AND IsCurrent = 1
            THEN 1
        END
    ) AS CurrentCardCount,

    MIN(IssueDate) AS FirstIssueDate,
    MAX(IssueDate) AS LastIssueDate

FROM dw.DimCard;
GO



