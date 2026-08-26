--First setting the unknown currencies

IF NOT EXISTS (
    SELECT 1
    FROM dw.DimCurrency
    WHERE CurrencyKey = 0
)
BEGIN
    SET IDENTITY_INSERT dw.DimCurrency ON;

    INSERT INTO dw.DimCurrency (
        CurrencyKey,
        CurrencyCode,
        CurrencyName,
        CurrencySymbol,
        DecimalPlaces,
        IsActive
    )
    VALUES (
        0,
        'UNK',
        N'Bilinmeyen Para Birimi',
        NULL,
        2,
        1
    );

    SET IDENTITY_INSERT dw.DimCurrency OFF;
END;
GO

--CurrencyKey = 0 set for the unknown generic currencies

--Now, going to insert the rest of the currencies (That is available!)

INSERT INTO dw.DimCurrency (
    CurrencyCode,
    CurrencyName,
    CurrencySymbol,
    DecimalPlaces,
    IsActive
)
SELECT
    source.CurrencyCode,
    source.CurrencyName,
    source.CurrencySymbol,
    source.DecimalPlaces,
    source.IsActive
FROM (
    VALUES
        ('TRY', N'Türk Lirası',             N'₺',   2, 1),
        ('USD', N'Amerikan Doları',         N'$',   2, 1),
        ('EUR', N'Euro',                    N'€',   2, 1),
        ('GBP', N'İngiliz Sterlini',        N'£',   2, 1),
        ('CHF', N'İsviçre Frangı',          N'CHF', 2, 1),
        ('JPY', N'Japon Yeni',              N'JP¥', 0, 1),
        ('CNY', N'Çin Yuanı',               N'CN¥', 2, 1),
        ('AED', N'Birleşik Arap Emirlikleri Dirhemi', N'AED', 2, 1),
        ('SAR', N'Suudi Arabistan Riyali',  N'SAR', 2, 1),
        ('CAD', N'Kanada Doları',           N'C$',  2, 1),
        ('AUD', N'Avustralya Doları',       N'A$',  2, 1),
        ('SEK', N'İsveç Kronu',             N'kr',  2, 1),
        ('KWD', N'Kuveyt Dinarı',           N'KWD', 3, 1)
) 
AS source(
    CurrencyCode,
    CurrencyName,
    CurrencySymbol,
    DecimalPlaces,
    IsActive
)
WHERE NOT EXISTS(
    SELECT 1
    FROM dw.DimCurrency AS target
    WHERE target.CurrencyCode = source.CurrencyCode
);
GO

--Validate? --Succesfull!!! First section covers the unknown currency
SELECT
    CurrencyKey,
    CurrencyCode,
    CurrencyName,
    CurrencySymbol,
    DecimalPlaces,
    IsActive
FROM dw.DimCurrency
ORDER BY CurrencyKey;
GO