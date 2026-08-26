USE PaymentProjectDW;
GO

-- Create the unknown merchant member.

IF NOT EXISTS (
    SELECT 1
    FROM dw.DimMerchant
    WHERE MerchantKey = 0
)
BEGIN
    SET IDENTITY_INSERT dw.DimMerchant ON;

    INSERT INTO dw.DimMerchant (
        MerchantKey,
        MerchantID,
        MerchantName,
        MerchantCategory,
        MerchantSubcategory,
        MerchantCategoryCode,
        MerchantSize,
        OnboardingDate,
        City,
        StateProvince,
        Country,
        PostalCode,
        IsOnlineMerchant,
        MerchantRiskLevel,
        IsActive
    )
    VALUES
    (
        0,
        'UNKNOWN',
        N'Bilinmeyen Merchant',
        'Unknown',
        'Unknown',
        '0000',
        NULL,
        '19000101',
        NULL,
        NULL,
        N'Bilinmiyor',
        NULL,
        0,
        NULL,
        0
    );

    SET IDENTITY_INSERT dw.DimMerchant OFF;
END;
GO


-- Generate deterministic synthetic merchant profiles.

DECLARE @TargetMerchantCount INT = 5000;
DECLARE @OnboardingStartDate DATE = '20150101';
DECLARE @OnboardingEndDate DATE = '20260630';

DECLARE @OnboardingDayCount INT =DATEDIFF(DAY,@OnboardingStartDate,@OnboardingEndDate) + 1;

;WITH NumberSeries AS(SELECT TOP (@TargetMerchantCount)
        ROW_NUMBER() OVER ( ORDER BY a.object_id, b.object_id) AS MerchantNumber

    FROM sys.all_objects AS a
    CROSS JOIN sys.all_objects AS b
),
MerchantSeeds AS(
    SELECT
        MerchantNumber,

        ABS(CONVERT(BIGINT,CHECKSUM(CONCAT(MerchantNumber, '|CATEGORY'))
            )
        ) AS CategorySeed,

        ABS(
            CONVERT(
                BIGINT,
                CHECKSUM(
                    CONCAT(MerchantNumber, '|SIZE'))
            )
        ) AS SizeSeed,

        ABS(
            CONVERT(
                BIGINT,
                CHECKSUM(CONCAT(MerchantNumber, '|RISK'))
            )
        ) AS RiskSeed,

        ABS(
            CONVERT(
                BIGINT,
                CHECKSUM(CONCAT(MerchantNumber, '|LOCATION'))
            )
        ) AS LocationSeed,

        ABS(
            CONVERT(
                BIGINT,
                CHECKSUM(
                    CONCAT(MerchantNumber, '|ONLINE')
                )
            )
        ) AS OnlineSeed,

        ABS(
            CONVERT(
                BIGINT,
                CHECKSUM(
                    CONCAT(MerchantNumber, '|ACTIVE')
                )
            )
        ) AS ActiveSeed,

        ABS(
            CONVERT(
                BIGINT,
                CHECKSUM(
                    CONCAT(MerchantNumber, '|ONBOARDING')
                )
            )
        ) AS OnboardingSeed,

        ABS(
            CONVERT(
                BIGINT,
                CHECKSUM(
                    CONCAT(MerchantNumber, '|NAME1')
                )
            )
        ) AS NameSeed1,

        ABS(
            CONVERT(
                BIGINT,
                CHECKSUM(
                    CONCAT(MerchantNumber, '|NAME2')
                )
            )
        ) AS NameSeed2,

        ABS(
            CONVERT(
                BIGINT,
                CHECKSUM(
                    CONCAT(MerchantNumber, '|NAME3')
                )
            )
        ) AS NameSeed3,

        ABS(
            CONVERT(
                BIGINT,
                CHECKSUM(
                    CONCAT(MerchantNumber, '|POSTAL')
                )
            )
        ) AS PostalSeed

    FROM NumberSeries
),
MerchantBase AS(
    SELECT
        MerchantNumber,

        CategorySeed % 100 AS CategoryBucket,
        SizeSeed % 100 AS SizeBucket,
        RiskSeed % 100 AS RiskBucket,
        LocationSeed % 100 AS LocationBucket,
        OnlineSeed % 100 AS OnlineBucket,
        ActiveSeed % 100 AS ActiveBucket,

        NameSeed1,
        NameSeed2,
        NameSeed3,
        PostalSeed,

        DATEADD(DAY,CONVERT(INT,OnboardingSeed % @OnboardingDayCount),
            @OnboardingStartDate
        ) AS OnboardingDate

    FROM MerchantSeeds
),
CategoryPool AS(
    SELECT
        BucketStart,
        BucketEnd,
        MerchantCategory,
        MerchantSubcategory,
        MerchantCategoryCode,
        OnlineProbability

    FROM
    (
        VALUES
            (0,  9,  'Grocery',              'Supermarket',             '5411', 15),
            (10, 14, 'Grocery',              'Convenience Store',       '5499', 10),

            (15, 23, 'Restaurant',           'Restaurant',              '5812', 20),
            (24, 28, 'Restaurant',           'Fast Food',               '5814', 25),

            (29, 36, 'Fashion',              'Clothing Store',          '5651', 50),

            (37, 42, 'Electronics',          'Electronics Store',       '5732', 55),

            (43, 48, 'Transportation',       'Taxi and Ride Sharing',   '4121', 65),

            (49, 53, 'Fuel',                 'Fuel Station',            '5541', 10),

            (54, 59, 'Utilities',            'Utility Services',        '4900', 75),

            (60, 64, 'Travel',               'Airline',                 '4511', 80),

            (65, 68, 'Accommodation',        'Hotel',                   '7011', 55),

            (69, 73, 'Healthcare',           'Pharmacy',                '5912', 25),
            (74, 77, 'Healthcare',           'Medical Services',        '8099', 30),

            (78, 82, 'Entertainment',        'Digital Entertainment',   '5815', 90),

            (83, 86, 'Education',            'Education Services',      '8299', 70),

            (87, 90, 'Financial Services',   'Financial Services',      '6012', 85),

            (91, 94, 'Home and Living',      'Home Improvement',        '5200', 30),

            (95, 97, 'Beauty and Personal Care',
                                              'Beauty Services',         '7230', 35),

            (98, 99, 'Other',                'Miscellaneous Retail',    '5999', 25)

    ) AS categories(
        BucketStart,
        BucketEnd,
        MerchantCategory,
        MerchantSubcategory,
        MerchantCategoryCode,
        OnlineProbability
    )
),
LocationPool AS(
    SELECT
        BucketStart,
        BucketEnd,
        Country,
        StateProvince,
        City,
        PostalPrefix

    FROM(
        VALUES
            (0,  31, N'Türkiye', N'İstanbul',   N'İstanbul',   34),
            (32, 43, N'Türkiye', N'Ankara',     N'Ankara',      6),
            (44, 53, N'Türkiye', N'İzmir',      N'İzmir',      35),
            (54, 59, N'Türkiye', N'Bursa',      N'Bursa',      16),
            (60, 65, N'Türkiye', N'Antalya',    N'Antalya',     7),
            (66, 70, N'Türkiye', N'Kocaeli',    N'Kocaeli',    41),
            (71, 74, N'Türkiye', N'Konya',      N'Konya',      42),
            (75, 78, N'Türkiye', N'Adana',      N'Adana',       1),
            (79, 81, N'Türkiye', N'Gaziantep',  N'Gaziantep',  27),
            (82, 84, N'Türkiye', N'Mersin',     N'Mersin',     33),
            (85, 86, N'Türkiye', N'Kayseri',    N'Kayseri',    38),
            (87, 88, N'Türkiye', N'Samsun',     N'Samsun',     55),
            (89, 89, N'Türkiye', N'Trabzon',    N'Trabzon',    61),
            (90, 90, N'Türkiye', N'Eskişehir',  N'Eskişehir',  26),
            (91, 91, N'Türkiye', N'Diyarbakır', N'Diyarbakır', 21),
            (92, 92, N'Türkiye', N'Tekirdağ',   N'Tekirdağ',   59),

            (93, 94, N'Almanya', N'Berlin', N'Berlin', 10),

            (95, 95, N'Birleşik Krallık',
                     N'İngiltere',
                     N'Londra',
                     NULL),

            (96, 96, N'Hollanda',
                     N'Kuzey Hollanda',
                     N'Amsterdam',
                     NULL),

            (97, 97, N'ABD',
                     N'New York',
                     N'New York',
                     10),

            (98, 98, N'Birleşik Arap Emirlikleri',
                     N'Dubai',
                     N'Dubai',
                     NULL),

            (99, 99, N'Fransa',
                     N'Île-de-France',
                     N'Paris',
                     75)) AS locations(
        BucketStart,
        BucketEnd,
        Country,
        StateProvince,
        City,
        PostalPrefix
    )
),
MerchantProfiles AS(
    SELECT
        merchant.MerchantNumber,
        merchant.SizeBucket,
        merchant.RiskBucket,
        merchant.OnlineBucket,
        merchant.ActiveBucket,
        merchant.NameSeed1,
        merchant.NameSeed2,
        merchant.NameSeed3,
        merchant.PostalSeed,
        merchant.OnboardingDate,

        category.MerchantCategory,
        category.MerchantSubcategory,
        category.MerchantCategoryCode,
        category.OnlineProbability,

        location.Country,
        location.StateProvince,
        location.City,
        location.PostalPrefix,

        CASE
            WHEN merchant.SizeBucket < 38 THEN 'Micro'
            WHEN merchant.SizeBucket < 68 THEN 'Small'
            WHEN merchant.SizeBucket < 86 THEN 'Medium'
            WHEN merchant.SizeBucket < 96 THEN 'Large'
            ELSE 'Enterprise'
        END AS MerchantSize,

        CASE
            WHEN merchant.OnlineBucket < category.OnlineProbability
            THEN 1
            ELSE 0
        END AS IsOnlineMerchant

    FROM MerchantBase AS merchant

    INNER JOIN CategoryPool AS category
        ON merchant.CategoryBucket
           BETWEEN category.BucketStart AND category.BucketEnd

    INNER JOIN LocationPool AS location
        ON merchant.LocationBucket
           BETWEEN location.BucketStart AND location.BucketEnd
),
FinalMerchants AS(
    SELECT
        MerchantNumber,

        CONCAT('MERC',RIGHT('000000'+CONVERT(VARCHAR(6),MerchantNumber),
                6
            )
        ) AS MerchantID,

        CONCAT(
            CHOOSE(CONVERT(INT, NameSeed1 % 20) + 1,
                N'Atlas',
                N'Nova',
                N'Pera',
                N'Mavi',
                N'Kuzey',
                N'Doruk',
                N'Eksen',
                N'Rota',
                N'Armoni',
                N'Vadi',
                N'Lale',
                N'Orion',
                N'Delta',
                N'Mercan',
                N'Bosphorus',
                N'Vega',
                N'Avrasya',
                N'Zenith',
                N'Lotus',
                N'Anka'
            ),
            N' ',
            CHOOSE(CONVERT(INT, NameSeed2 % 20) + 1,
                N'Ada',
                N'Park',
                N'Merkez',
                N'Kent',
                N'Plaza',
                N'Global',
                N'Prime',
                N'Plus',
                N'Royal',
                N'Select',
                N'One',
                N'Point',
                N'Line',
                N'House',
                N'Bridge',
                N'Corner',
                N'Zone',
                N'Life',
                N'World',
                N'Pro'
            ),
            N' ',CHOOSE(CONVERT(INT, NameSeed3 % 6) + 1,
                N'Ticaret',
                N'Grup',
                N'Hizmetleri',
                N'Mağazacılık',
                N'İşletmeleri',
                N'A.Ş.'
            )
        ) AS MerchantName,

        MerchantCategory,
        MerchantSubcategory,
        MerchantCategoryCode,
        MerchantSize,
        OnboardingDate,
        City,
        StateProvince,
        Country,
        PostalPrefix,
        PostalSeed,
        IsOnlineMerchant,

        CASE
            WHEN MerchantCategory IN(
                'Financial Services',
                'Travel')
            THEN
                CASE
                    WHEN RiskBucket < 55 THEN 'Low'
                    WHEN RiskBucket < 85 THEN 'Medium'
                    WHEN RiskBucket < 97 THEN 'High'
                    ELSE 'Critical'
                END

            WHEN IsOnlineMerchant = 1
            THEN
                CASE
                    WHEN RiskBucket < 62 THEN 'Low'
                    WHEN RiskBucket < 87 THEN 'Medium'
                    WHEN RiskBucket < 97 THEN 'High'
                    ELSE 'Critical'
                END

            ELSE
                CASE
                    WHEN RiskBucket < 75 THEN 'Low'
                    WHEN RiskBucket < 94 THEN 'Medium'
                    WHEN RiskBucket < 99 THEN 'High'
                    ELSE 'Critical'
                END
        END AS MerchantRiskLevel,

        CASE
            WHEN ActiveBucket < 94
            THEN 1
            ELSE 0
        END AS IsActive

    FROM MerchantProfiles
)
INSERT INTO dw.DimMerchant(
    MerchantID,
    MerchantName,
    MerchantCategory,
    MerchantSubcategory,
    MerchantCategoryCode,
    MerchantSize,
    OnboardingDate,
    City,
    StateProvince,
    Country,
    PostalCode,
    IsOnlineMerchant,
    MerchantRiskLevel,
    IsActive
)
SELECT
    source.MerchantID,
    source.MerchantName,
    source.MerchantCategory,
    source.MerchantSubcategory,
    source.MerchantCategoryCode,
    source.MerchantSize,
    source.OnboardingDate,
    source.City,
    source.StateProvince,
    source.Country,

    CASE
        WHEN source.Country = N'Türkiye'
        THEN
            RIGHT('00000'+CONVERT(VARCHAR(5),(source.PostalPrefix * 1000)+CONVERT(INT,source.PostalSeed % 1000)
                ),
                5
            )

        WHEN source.Country IN(N'Almanya',N'ABD',N'Fransa')
        THEN
            RIGHT('00000'+CONVERT(VARCHAR(5),10000+CONVERT(INT,source.PostalSeed % 90000)),
                5
            )

        WHEN source.Country = N'Birleşik Krallık'
        THEN
            CONCAT('UK-',RIGHT('0000'+CONVERT(VARCHAR(4),source.PostalSeed % 10000),
                    4
                )
            )

        WHEN source.Country = N'Hollanda'
        THEN
            CONCAT('NL-',RIGHT('0000'+CONVERT(VARCHAR(4),source.PostalSeed % 10000),
                    4
                )
            )

        ELSE NULL
    END AS PostalCode,

    source.IsOnlineMerchant,
    source.MerchantRiskLevel,
    source.IsActive

FROM FinalMerchants AS source

WHERE NOT EXISTS
(
    SELECT 1
    FROM dw.DimMerchant AS target
    WHERE target.MerchantID = source.MerchantID
);
GO
