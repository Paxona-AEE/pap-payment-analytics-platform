USE PaymentProjectDW;
GO

-- Create the unknown device member.

IF NOT EXISTS(
    SELECT 1
    FROM dw.DimDevice
    WHERE DeviceKey = 0
)
BEGIN
    SET IDENTITY_INSERT dw.DimDevice ON;

    INSERT INTO dw.DimDevice(
        DeviceKey,
        DeviceID,
        DeviceType,
        OperatingSystem,
        BrowserName,
        AppVersion,
        DeviceCountry,
        IsTrustedDevice,
        IsEmulator,
        IsRootedOrJailbroken,
        RegisteredCustomerID
    )
    VALUES(
        0,
        'UNKNOWN',
        'Unknown',
        'Unknown',
        'Unknown',
        NULL,
        N'Bilinmiyor',
        0,
        0,
        0,
        'UNKNOWN'
    );

    SET IDENTITY_INSERT dw.DimDevice OFF;
END;
GO



-- Generate deterministic synthetic devices for existing customers.

;WITH CurrentCustomers AS(
    SELECT
        CustomerID,
        CustomerSegment,
        Country,
        RiskLevel,

        ABS(CONVERT(BIGINT,CHECKSUM(CONCAT(CustomerID, '|DEVICE_COUNT')
                )
            )
        ) % 100 AS DeviceCountBucket

    FROM dw.DimCustomer

    WHERE CustomerKey <> 0
),
CustomerDeviceCounts AS(
    SELECT
        CustomerID,
        CustomerSegment,
        Country,
        RiskLevel,

        CASE
            WHEN CustomerSegment = 'Standard'
            THEN
                CASE
                    WHEN DeviceCountBucket < 8  THEN 0
                    WHEN DeviceCountBucket < 58 THEN 1
                    WHEN DeviceCountBucket < 90 THEN 2
                    ELSE 3
                END

            WHEN CustomerSegment = 'Silver'
            THEN
                CASE
                    WHEN DeviceCountBucket < 3  THEN 0
                    WHEN DeviceCountBucket < 35 THEN 1
                    WHEN DeviceCountBucket < 75 THEN 2
                    WHEN DeviceCountBucket < 95 THEN 3
                    ELSE 4
                END

            WHEN CustomerSegment = 'Gold'
            THEN
                CASE
                    WHEN DeviceCountBucket < 1  THEN 0
                    WHEN DeviceCountBucket < 16 THEN 1
                    WHEN DeviceCountBucket < 54 THEN 2
                    WHEN DeviceCountBucket < 85 THEN 3
                    ELSE 4
                END

            WHEN CustomerSegment = 'Platinum'
            THEN
                CASE
                    WHEN DeviceCountBucket < 5  THEN 1
                    WHEN DeviceCountBucket < 30 THEN 2
                    WHEN DeviceCountBucket < 65 THEN 3
                    WHEN DeviceCountBucket < 90 THEN 4
                    ELSE 5
                END

            WHEN CustomerSegment = 'Corporate'
            THEN
                CASE
                    WHEN DeviceCountBucket < 5  THEN 1
                    WHEN DeviceCountBucket < 25 THEN 2
                    WHEN DeviceCountBucket < 60 THEN 3
                    WHEN DeviceCountBucket < 85 THEN 4
                    ELSE 5
                END

            ELSE 0
        END AS DeviceCount

    FROM CurrentCustomers
),
DeviceNumbers AS(
    SELECT
        customer.CustomerID,
        customer.CustomerSegment,
        customer.Country,
        customer.RiskLevel,

        numbers.DeviceSequence,

        CONCAT('DEV',RIGHT(customer.CustomerID, 6),RIGHT('00'+CONVERT(VARCHAR(2),numbers.DeviceSequence),
                2
            )
        ) AS DeviceID

    FROM CustomerDeviceCounts AS customer

    CROSS JOIN(VALUES(1),(2),(3),(4),(5)
    )
    AS numbers(DeviceSequence)

    WHERE numbers.DeviceSequence <= customer.DeviceCount
),
DeviceSeeds AS(
    SELECT
        DeviceID,
        CustomerID,
        CustomerSegment,
        Country,
        RiskLevel,
        DeviceSequence,

        ABS(
            CONVERT(
                BIGINT,
                CHECKSUM(CONCAT(DeviceID, '|TYPE'))
            )
        ) % 100 AS DeviceTypeBucket,

        ABS(
            CONVERT(
                BIGINT,
                CHECKSUM(CONCAT(DeviceID, '|OS'))
            )
        ) % 100 AS OperatingSystemBucket,

        ABS(
            CONVERT(
                BIGINT,
                CHECKSUM(CONCAT(DeviceID, '|BROWSER'))
            )
        ) % 100 AS BrowserBucket,

        ABS(
            CONVERT(
                BIGINT,
                CHECKSUM(CONCAT(DeviceID, '|APP_VERSION'))
            )
        ) AS AppVersionSeed,

        ABS(
            CONVERT(
                BIGINT,
                CHECKSUM(CONCAT(DeviceID, '|TRUST'))
            )
        ) % 100 AS TrustBucket,

        ABS(
            CONVERT(
                BIGINT,
                CHECKSUM(CONCAT(DeviceID, '|EMULATOR'))
            )
        ) % 100 AS EmulatorBucket,

        ABS(
            CONVERT(
                BIGINT,
                CHECKSUM(CONCAT(DeviceID, '|ROOT'))
            )
        ) % 100 AS RootBucket

    FROM DeviceNumbers
),
DeviceTypes AS(
    SELECT
        *,

        CASE
            WHEN CustomerSegment = 'Corporate'
            THEN
                CASE
                    WHEN DeviceTypeBucket < 20 THEN 'Mobile'
                    WHEN DeviceTypeBucket < 30 THEN 'Tablet'
                    WHEN DeviceTypeBucket < 65 THEN 'Desktop'
                    ELSE 'POS Terminal'
                END

            WHEN CustomerSegment = 'Standard'
            THEN
                CASE
                    WHEN DeviceTypeBucket < 66 THEN 'Mobile'
                    WHEN DeviceTypeBucket < 79 THEN 'Tablet'
                    WHEN DeviceTypeBucket < 98 THEN 'Desktop'
                    ELSE 'Unknown'
                END

            WHEN CustomerSegment = 'Silver'
            THEN
                CASE
                    WHEN DeviceTypeBucket < 64 THEN 'Mobile'
                    WHEN DeviceTypeBucket < 80 THEN 'Tablet'
                    WHEN DeviceTypeBucket < 99 THEN 'Desktop'
                    ELSE 'Unknown'
                END

            WHEN CustomerSegment = 'Gold'
            THEN
                CASE
                    WHEN DeviceTypeBucket < 62 THEN 'Mobile'
                    WHEN DeviceTypeBucket < 80 THEN 'Tablet'
                    WHEN DeviceTypeBucket < 99 THEN 'Desktop'
                    ELSE 'Unknown'
                END

            WHEN CustomerSegment = 'Platinum'
            THEN
                CASE
                    WHEN DeviceTypeBucket < 60 THEN 'Mobile'
                    WHEN DeviceTypeBucket < 78 THEN 'Tablet'
                    WHEN DeviceTypeBucket < 98 THEN 'Desktop'
                    ELSE 'Unknown'
                END

            ELSE 'Unknown'
        END AS DeviceType

    FROM DeviceSeeds
),
DevicesWithOS AS(
    SELECT
        *,

        CASE
            WHEN DeviceType = 'Mobile'
            THEN
                CASE
                    WHEN OperatingSystemBucket < 67 THEN 'Android'
                    WHEN OperatingSystemBucket < 97 THEN 'iOS'
                    ELSE 'HarmonyOS'
                END

            WHEN DeviceType = 'Tablet'
            THEN
                CASE
                    WHEN OperatingSystemBucket < 54 THEN 'Android'
                    WHEN OperatingSystemBucket < 94 THEN 'iPadOS'
                    ELSE 'Windows'
                END

            WHEN DeviceType = 'Desktop'
            THEN
                CASE
                    WHEN OperatingSystemBucket < 72 THEN 'Windows'
                    WHEN OperatingSystemBucket < 92 THEN 'macOS'
                    ELSE 'Linux'
                END

            WHEN DeviceType = 'POS Terminal'
            THEN
                CASE
                    WHEN OperatingSystemBucket < 55 THEN 'Android POS'
                    WHEN OperatingSystemBucket < 90 THEN 'Linux POS'
                    ELSE 'Proprietary OS'
                END

            ELSE 'Unknown'
        END AS OperatingSystem

    FROM DeviceTypes
),
DevicesWithBrowser AS(
    SELECT
        *,

        CASE
            WHEN DeviceType = 'POS Terminal'
            THEN 'Embedded App'

            WHEN DeviceType = 'Unknown'
            THEN 'Unknown'

            WHEN DeviceType = 'Mobile'
                 AND OperatingSystem = 'iOS'
            THEN
                CASE
                    WHEN BrowserBucket < 55 THEN 'Safari'
                    WHEN BrowserBucket < 85 THEN 'Mobile App WebView'
                    ELSE 'Chrome'
                END

            WHEN DeviceType = 'Mobile'
                 AND OperatingSystem = 'Android'
            THEN
                CASE
                    WHEN BrowserBucket < 55 THEN 'Chrome'
                    WHEN BrowserBucket < 75 THEN 'Samsung Internet'
                    WHEN BrowserBucket < 95 THEN 'Mobile App WebView'
                    ELSE 'Firefox'
                END

            WHEN DeviceType = 'Mobile'
                 AND OperatingSystem = 'HarmonyOS'
            THEN
                CASE
                    WHEN BrowserBucket < 60 THEN 'Huawei Browser'
                    ELSE 'Mobile App WebView'
                END

            WHEN DeviceType = 'Tablet'
                 AND OperatingSystem = 'iPadOS'
            THEN
                CASE
                    WHEN BrowserBucket < 60 THEN 'Safari'
                    WHEN BrowserBucket < 88 THEN 'Mobile App WebView'
                    ELSE 'Chrome'
                END

            WHEN DeviceType = 'Tablet'
            THEN
                CASE
                    WHEN BrowserBucket < 58 THEN 'Chrome'
                    WHEN BrowserBucket < 82 THEN 'Mobile App WebView'
                    WHEN BrowserBucket < 94 THEN 'Edge'
                    ELSE 'Firefox'
                END

            WHEN DeviceType = 'Desktop'
                 AND OperatingSystem = 'Windows'
            THEN
                CASE
                    WHEN BrowserBucket < 47 THEN 'Chrome'
                    WHEN BrowserBucket < 82 THEN 'Edge'
                    WHEN BrowserBucket < 96 THEN 'Firefox'
                    ELSE 'Opera'
                END

            WHEN DeviceType = 'Desktop'
                 AND OperatingSystem = 'macOS'
            THEN
                CASE
                    WHEN BrowserBucket < 55 THEN 'Safari'
                    WHEN BrowserBucket < 90 THEN 'Chrome'
                    ELSE 'Firefox'
                END

            WHEN DeviceType = 'Desktop'
                 AND OperatingSystem = 'Linux'
            THEN
                CASE
                    WHEN BrowserBucket < 52 THEN 'Chrome'
                    WHEN BrowserBucket < 95 THEN 'Firefox'
                    ELSE 'Edge'
                END

            ELSE 'Unknown'
        END AS BrowserName

    FROM DevicesWithOS
),
DeviceSecurityFlags AS(
    SELECT
        *,

        CASE
            WHEN DeviceType NOT IN ('Mobile', 'Tablet')
            THEN 0

            WHEN RiskLevel IN ('High', 'Critical')
                 AND EmulatorBucket < 4
            THEN 1

            WHEN EmulatorBucket < 1
            THEN 1

            ELSE 0
        END AS IsEmulator,

        CASE
            WHEN DeviceType NOT IN ('Mobile', 'Tablet')
            THEN 0

            WHEN RiskLevel IN ('High', 'Critical')
                 AND RootBucket < 6
            THEN 1

            WHEN RootBucket < 2
            THEN 1

            ELSE 0
        END AS IsRootedOrJailbroken

    FROM DevicesWithBrowser
),
FinalDevices AS(
    SELECT
        DeviceID,
        CustomerID,
        CustomerSegment,
        Country,
        RiskLevel,
        DeviceSequence,
        DeviceType,
        OperatingSystem,
        BrowserName,
        IsEmulator,
        IsRootedOrJailbroken,

        CASE
            WHEN DeviceType IN ('Mobile', 'Tablet')
            THEN
                CONCAT
                (
                    '6.',
                    CONVERT
                    (
                        VARCHAR(2),
                        AppVersionSeed % 8
                    ),
                    '.',
                    CONVERT
                    (
                        VARCHAR(2),
                        (AppVersionSeed / 10) % 10
                    )
                )

            WHEN DeviceType = 'POS Terminal'
            THEN
                CONCAT
                (
                    'POS-',
                    CONVERT
                    (
                        VARCHAR(2),
                        3 + (AppVersionSeed % 3)
                    ),
                    '.',
                    CONVERT
                    (
                        VARCHAR(2),
                        (AppVersionSeed / 10) % 10
                    )
                )

            ELSE NULL
        END AS AppVersion,

        CASE
            WHEN IsEmulator = 1
              OR IsRootedOrJailbroken = 1
            THEN 0

            WHEN RiskLevel = 'Critical'
            THEN
                CASE
                    WHEN TrustBucket < 35 THEN 1
                    ELSE 0
                END

            WHEN RiskLevel = 'High'
            THEN
                CASE
                    WHEN TrustBucket < 55 THEN 1
                    ELSE 0
                END

            WHEN DeviceType = 'POS Terminal'
            THEN
                CASE
                    WHEN TrustBucket < 90 THEN 1
                    ELSE 0
                END

            WHEN DeviceSequence = 1
            THEN
                CASE
                    WHEN TrustBucket < 92 THEN 1
                    ELSE 0
                END

            WHEN DeviceSequence = 2
            THEN
                CASE
                    WHEN TrustBucket < 80 THEN 1
                    ELSE 0
                END

            ELSE
                CASE
                    WHEN TrustBucket < 65 THEN 1
                    ELSE 0
                END
        END AS IsTrustedDevice

    FROM DeviceSecurityFlags
)
INSERT INTO dw.DimDevice(
    DeviceID,
    DeviceType,
    OperatingSystem,
    BrowserName,
    AppVersion,
    DeviceCountry,
    IsTrustedDevice,
    IsEmulator,
    IsRootedOrJailbroken,
    RegisteredCustomerID
)
SELECT
    source.DeviceID,
    source.DeviceType,
    source.OperatingSystem,
    source.BrowserName,
    source.AppVersion,
    source.Country,
    source.IsTrustedDevice,
    source.IsEmulator,
    source.IsRootedOrJailbroken,
    source.CustomerID

FROM FinalDevices AS source

WHERE NOT EXISTS
(
    SELECT 1
    FROM dw.DimDevice AS target
    WHERE target.DeviceID = source.DeviceID
);
GO

--Validate

SELECT

    COUNT(*) AS TotalDeviceRowCount,

    COUNT(
        CASE
            WHEN DeviceKey <> 0 THEN 1
        END
    ) AS RealDeviceCount,

    COUNT(
        CASE
            WHEN DeviceKey <> 0
             AND IsTrustedDevice = 1
            THEN 1
        END
    ) AS TrustedDeviceCount,

    COUNT(
        CASE
            WHEN DeviceKey <> 0
             AND IsEmulator = 1
            THEN 1
        END
    ) AS EmulatorCount,

    COUNT(
        CASE
            WHEN DeviceKey <> 0
             AND IsRootedOrJailbroken = 1
            THEN 1
        END
    ) AS RootedDeviceCount

FROM dw.DimDevice;
GO
