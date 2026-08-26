CREATE TABLE dw.DimDevice(
    DeviceKey INT IDENTITY(1,1) NOT NULL,

    DeviceID VARCHAR(50) NOT NULL,

    DeviceType VARCHAR(30) NULL,
    OperatingSystem VARCHAR(50) NULL,
    BrowserName VARCHAR(50) NULL,
    AppVersion VARCHAR(30) NULL,

    DeviceCountry NVARCHAR(100) NULL,

    IsTrustedDevice BIT NOT NULL
        CONSTRAINT DF_DimDevice_IsTrusted
        DEFAULT (0),

    IsEmulator BIT NOT NULL
        CONSTRAINT DF_DimDevice_IsEmulator
        DEFAULT (0),

    IsRootedOrJailbroken BIT NOT NULL
        CONSTRAINT DF_DimDevice_IsRooted
        DEFAULT (0),

    CONSTRAINT PK_DimDevice
        PRIMARY KEY (DeviceKey),

    CONSTRAINT UQ_DimDevice_DeviceID
        UNIQUE (DeviceID),

    CONSTRAINT CK_DimDevice_DeviceType
        CHECK (
            DeviceType IS NULL
            OR DeviceType IN (
                'Mobile',
                'Tablet',
                'Desktop',
                'POS Terminal',
                'ATM',
                'Unknown'
            )
        )
);
GO