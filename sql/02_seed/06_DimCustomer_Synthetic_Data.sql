USE PaymentProjectDW;
GO

-- Create the unknown customer member.

IF NOT EXISTS (
    SELECT 1
    FROM dw.DimCustomer
    WHERE CustomerKey = 0
)
BEGIN
    SET IDENTITY_INSERT dw.DimCustomer ON;

    INSERT INTO dw.DimCustomer (
        CustomerKey,
        CustomerID,
        FullName,
        BirthDate,
        CustomerSegment,
        IncomeBand,
        RiskLevel,
        RegistrationDate,
        City,
        StateProvince,
        Country,
        PostalCode,
        IsActive
    )
    VALUES (
        0,
        'UNKNOWN',
        N'Bilinmeyen Müşteri',
        NULL,
        'Unknown',
        'Unknown',
        NULL,
        '19000101',
        NULL,
        NULL,
        N'Bilinmiyor',
        NULL,
        0
    );

    SET IDENTITY_INSERT dw.DimCustomer OFF;
END;
GO


-- Generate deterministic synthetic customer profiles.

DECLARE @TargetCustomerCount INT = 25000;

DECLARE @RegistrationStartDate DATE = '20180101';
DECLARE @RegistrationEndDate DATE = '20260630';

DECLARE @RegistrationDayCount INT = DATEDIFF (
        DAY,
        @RegistrationStartDate,
        @RegistrationEndDate
    ) + 1;

;WITH NumberSeries AS (
    SELECT TOP (@TargetCustomerCount)
        ROW_NUMBER() OVER (
            ORDER BY
                a.object_id,
                b.object_id
        ) AS CustomerNumber
    FROM sys.all_objects AS a
    CROSS JOIN sys.all_objects AS b
),
CustomerSeeds AS (
    SELECT
        CustomerNumber,

        ABS ( --Absolute Value
            CONVERT (
                BIGINT, --Prevent: Arithmetic Overflow
                CHECKSUM ( --INT
                    CONCAT(CustomerNumber, '|SEGMENT') --ARRAY
                )
            )
        ) AS SegmentSeed,

        ABS (
            CONVERT (
                BIGINT,
                CHECKSUM
                (
                    CONCAT(CustomerNumber, '|INCOME')
                )
            )
        ) AS IncomeSeed,

        ABS (
            CONVERT (
                BIGINT,
                CHECKSUM
                (
                    CONCAT(CustomerNumber, '|RISK')
                )
            )
        ) AS RiskSeed,

        ABS (
            CONVERT (
                BIGINT,
                CHECKSUM
                (
                    CONCAT(CustomerNumber, '|LOCATION')
                )
            )
        ) AS LocationSeed,

        ABS (
            CONVERT (
                BIGINT,
                CHECKSUM
                (
                    CONCAT(CustomerNumber, '|ACTIVE')
                )
            )
        ) AS ActiveSeed,

        ABS (
            CONVERT (
                BIGINT,
                CHECKSUM (
                    CONCAT(CustomerNumber, '|REGISTRATION')
                )
            )
        ) AS RegistrationSeed,

        ABS (
            CONVERT (
                BIGINT,
                CHECKSUM (
                    CONCAT(CustomerNumber, '|AGE')
                )
            )
        ) AS AgeSeed,

        ABS (
            CONVERT (
                BIGINT,
                CHECKSUM (
                    CONCAT(CustomerNumber, '|FIRSTNAME')
                )
            )
        ) AS FirstNameSeed,

        ABS (
            CONVERT (
                BIGINT,
                CHECKSUM (
                    CONCAT(CustomerNumber, '|LASTNAME')
                )
            )
        ) AS LastNameSeed,

        ABS (
            CONVERT (
                BIGINT,
                CHECKSUM (
                    CONCAT(CustomerNumber, '|COMPANY')
                )
            )
        ) AS CompanySeed,

        ABS (
            CONVERT (
                BIGINT,
                CHECKSUM (
                    CONCAT(CustomerNumber, '|POSTAL')
                )
            )
        ) AS PostalSeed
    FROM NumberSeries
),
CustomerBase AS (
    SELECT
        CustomerNumber,

        SegmentSeed % 100 AS SegmentBucket,
        IncomeSeed % 100 AS IncomeBucket,
        RiskSeed % 100 AS RiskBucket,
        LocationSeed % 100 AS LocationBucket,
        ActiveSeed % 100 AS ActiveBucket,

        FirstNameSeed,
        LastNameSeed,
        CompanySeed,
        PostalSeed,

        DATEADD (
            DAY,
            CONVERT (
                INT,
                RegistrationSeed % @RegistrationDayCount
            ),
            @RegistrationStartDate
        ) AS RegistrationDate,

        AgeSeed
    FROM CustomerSeeds
),
LocationPool AS (
    SELECT
        BucketStart,
        BucketEnd,
        Country,
        StateProvince,
        City,
        PostalPrefix
    FROM (
        VALUES
            (0,  24, N'Türkiye', N'İstanbul',     N'İstanbul',     34),
            (25, 34, N'Türkiye', N'Ankara',       N'Ankara',        6),
            (35, 42, N'Türkiye', N'İzmir',        N'İzmir',        35),
            (43, 47, N'Türkiye', N'Bursa',        N'Bursa',        16),
            (48, 52, N'Türkiye', N'Antalya',      N'Antalya',       7),
            (53, 57, N'Türkiye', N'Kocaeli',      N'Kocaeli',      41),
            (58, 61, N'Türkiye', N'Konya',        N'Konya',        42),
            (62, 65, N'Türkiye', N'Adana',        N'Adana',         1),
            (66, 69, N'Türkiye', N'Gaziantep',    N'Gaziantep',    27),
            (70, 72, N'Türkiye', N'Mersin',       N'Mersin',       33),
            (73, 75, N'Türkiye', N'Kayseri',      N'Kayseri',      38),
            (76, 78, N'Türkiye', N'Samsun',       N'Samsun',       55),
            (79, 81, N'Türkiye', N'Trabzon',      N'Trabzon',      61),
            (82, 83, N'Türkiye', N'Eskişehir',    N'Eskişehir',    26),
            (84, 85, N'Türkiye', N'Diyarbakır',   N'Diyarbakır',   21),
            (86, 87, N'Türkiye', N'Tekirdağ',     N'Tekirdağ',     59),

            (88, 89, N'Almanya', N'Berlin',        N'Berlin',       10),
            (90, 90, N'Almanya', N'Bavyera',       N'Münih',        80),

            (91, 92, N'Birleşik Krallık', N'İngiltere', N'Londra', NULL),

            (93, 94, N'Hollanda', N'Kuzey Hollanda', N'Amsterdam', NULL),

            (95, 95, N'ABD', N'New York',  N'New York',  10),
            (96, 96, N'ABD', N'Illinois',  N'Chicago',   60),

            (97, 97, N'Birleşik Arap Emirlikleri', N'Dubai', N'Dubai', NULL),

            (98, 98, N'Fransa', N'Île-de-France', N'Paris', 75),

            (99, 99, N'İsviçre', N'Zürih', N'Zürih', 80)
    ) AS locations (
        BucketStart,
        BucketEnd,
        Country,
        StateProvince,
        City,
        PostalPrefix
    )
)
INSERT INTO dw.DimCustomer (
    CustomerID,
    FullName,
    BirthDate,
    CustomerSegment,
    IncomeBand,
    RiskLevel,
    RegistrationDate,
    City,
    StateProvince,
    Country,
    PostalCode,
    IsActive
)
SELECT
    CONCAT (
        'CUST',
        RIGHT(
            '000000' +
            CONVERT (
                VARCHAR(6),
                cb.CustomerNumber
            ),
            6
        )
    ) AS CustomerID,

    CASE
        WHEN cb.SegmentBucket >= 96
        THEN
            CONCAT (
                CHOOSE (
                    CONVERT(INT, cb.CompanySeed % 10) + 1,
                    N'Atlas',
                    N'Nova',
                    N'Pera',
                    N'Mavi',
                    N'Kuzey',
                    N'Delta',
                    N'Orion',
                    N'Armoni',
                    N'Doruk',
                    N'Eksen'
                ),
                N' ',
                CHOOSE (
                    CONVERT(INT, cb.FirstNameSeed % 10) + 1,
                    N'Teknoloji',
                    N'Ticaret',
                    N'Lojistik',
                    N'Finans',
                    N'Gıda',
                    N'Enerji',
                    N'Sağlık',
                    N'Dijital',
                    N'Danışmanlık',
                    N'Yapı'
                ),
                N' ',
                CHOOSE (
                    CONVERT(INT, cb.LastNameSeed % 3) + 1,
                    N'A.Ş.',
                    N'Ltd. Şti.',
                    N'Ticaret A.Ş.'
                )
            )

        ELSE
            CONCAT (
                CHOOSE (
                    CONVERT(INT, cb.FirstNameSeed % 30) + 1,
                    N'Ahmet',
                    N'Mehmet',
                    N'Mustafa',
                    N'Ali',
                    N'Emre',
                    N'Can',
                    N'Mert',
                    N'Burak',
                    N'Kerem',
                    N'Eren',
                    N'Deniz',
                    N'Selin',
                    N'Zeynep',
                    N'Elif',
                    N'Ayşe',
                    N'Ece',
                    N'Derya',
                    N'İrem',
                    N'Melis',
                    N'Ceren',
                    N'Luca',
                    N'Sofia',
                    N'Emma',
                    N'Daniel',
                    N'Maria',
                    N'Noah',
                    N'Olivia',
                    N'Liam',
                    N'Anna',
                    N'David'
                ),
                N' ',
                CHOOSE (
                    CONVERT(INT, cb.LastNameSeed % 30) + 1,
                    N'Yılmaz',
                    N'Kaya',
                    N'Demir',
                    N'Şahin',
                    N'Çelik',
                    N'Yıldız',
                    N'Aydın',
                    N'Arslan',
                    N'Koç',
                    N'Kurt',
                    N'Özdemir',
                    N'Polat',
                    N'Kılıç',
                    N'Aslan',
                    N'Güneş',
                    N'Kaplan',
                    N'Wagner',
                    N'Müller',
                    N'Smith',
                    N'Brown',
                    N'Johnson',
                    N'Taylor',
                    N'Martin',
                    N'Dubois',
                    N'Rossi',
                    N'Garcia',
                    N'De Vries',
                    N'Jansen',
                    N'Wilson',
                    N'Miller'
                )
            )
    END AS FullName,

    CASE
        WHEN cb.SegmentBucket >= 96
        THEN NULL

        ELSE
            DATEADD (
                DAY,
                -CONVERT (
                    INT,
                    -- Kayıt tarihinde yaklaşık 18–75 yaş
                    (18 * 365)
                    + ( cb.AgeSeed  % (57 * 365)
                    )
                ),
                cb.RegistrationDate
            )
    END AS BirthDate,

    CASE
        WHEN cb.SegmentBucket < 55 THEN 'Standard'
        WHEN cb.SegmentBucket < 75 THEN 'Silver'
        WHEN cb.SegmentBucket < 89 THEN 'Gold'
        WHEN cb.SegmentBucket < 96 THEN 'Platinum'
        ELSE 'Corporate'
    END AS CustomerSegment,

    CASE
        WHEN cb.SegmentBucket < 55
        THEN
            CASE
                WHEN cb.IncomeBucket < 35 THEN 'Low'
                WHEN cb.IncomeBucket < 70 THEN 'Lower-Middle'
                ELSE 'Middle'
            END

        WHEN cb.SegmentBucket < 75
        THEN
            CASE
                WHEN cb.IncomeBucket < 30 THEN 'Lower-Middle'
                WHEN cb.IncomeBucket < 80 THEN 'Middle'
                ELSE 'Upper-Middle'
            END

        WHEN cb.SegmentBucket < 89
        THEN
            CASE
                WHEN cb.IncomeBucket < 25 THEN 'Middle'
                WHEN cb.IncomeBucket < 80 THEN 'Upper-Middle'
                ELSE 'High'
            END

        WHEN cb.SegmentBucket < 96
        THEN
            CASE
                WHEN cb.IncomeBucket < 35 THEN 'Upper-Middle'
                ELSE 'High'
            END

        ELSE 'Corporate'
    END AS IncomeBand,

    CASE
        WHEN cb.RiskBucket < 62 THEN 'Low'
        WHEN cb.RiskBucket < 89 THEN 'Medium'
        WHEN cb.RiskBucket < 98 THEN 'High'
        ELSE 'Critical'
    END AS RiskLevel,

    cb.RegistrationDate,

    lp.City,
    lp.StateProvince,
    lp.Country,

    CASE
        WHEN lp.Country = N'Türkiye'
        THEN
            RIGHT ( '00000' + CONVERT ( VARCHAR(5),(lp.PostalPrefix * 1000) + CONVERT(INT,cb.PostalSeed % 1000)),
                5
            )

        WHEN lp.Country IN (
            N'Almanya',
            N'ABD',
            N'Fransa'
        )
        THEN
            RIGHT('00000'+CONVERT(VARCHAR(5),10000+CONVERT(INT,cb.PostalSeed % 90000)),
                5
            )

        WHEN lp.Country = N'İsviçre'
        THEN
            RIGHT('0000'+CONVERT(VARCHAR(4),1000+CONVERT(INT,cb.PostalSeed % 9000)),4
            )

        WHEN lp.Country = N'Birleşik Krallık'
        THEN
            CONCAT('UK-',RIGHT('0000'+CONVERT(VARCHAR(4),cb.PostalSeed % 10000),4
                )
            )

        WHEN lp.Country = N'Hollanda'
        THEN
            CONCAT('NL-',RIGHT('0000'+CONVERT(VARCHAR(4),cb.PostalSeed % 10000),
                    4
                )
            )

        ELSE NULL
    END AS PostalCode,

    CASE
        WHEN cb.ActiveBucket < 93
        THEN 1
        ELSE 0
    END AS IsActive

FROM CustomerBase AS cb

INNER JOIN LocationPool AS lp
    ON cb.LocationBucket
       BETWEEN lp.BucketStart AND lp.BucketEnd

WHERE NOT EXISTS(
    SELECT 1
    FROM dw.DimCustomer AS target
    WHERE target.CustomerID =
        CONCAT('CUST',RIGHT('000000'+CONVERT(VARCHAR(6),cb.CustomerNumber),
                6
            )
        )
);
GO

--Validate

SELECT
    COUNT(*) AS TotalCustomerRowCount,

    COUNT (
        CASE
            WHEN CustomerKey <> 0 THEN 1
        END
    ) AS RealCustomerCount,

    MIN(RegistrationDate) AS FirstRegistrationDate,

    MAX(RegistrationDate) AS LastRegistrationDate

FROM dw.DimCustomer;
GO
