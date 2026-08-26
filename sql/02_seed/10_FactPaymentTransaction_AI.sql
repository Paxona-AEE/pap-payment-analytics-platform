-- Deterministic synthetic payment generator for one million fact rows.

USE PaymentProjectDW;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

------------------------------------------------------------
-- PHASE 10A    (10, bu kısım AI ile oluşturulmuş bir payment generator, 1 milyon sentetik işlem ile devir yapar)
-- MÜŞTERİ, KART VE MERCHANT SEÇİM HAVUZLARI
------------------------------------------------------------

DECLARE @TestTransactionCount INT  = 10000;
DECLARE @AsOfDate            DATE = '20260630';
DECLARE @BaseStartDate       DATE = '20200101';

DECLARE @CardPoolCount     BIGINT;
DECLARE @MerchantPoolCount BIGINT;

------------------------------------------------------------
-- 1. ESKİ GEÇİCİ TABLOLARI TEMİZLE
------------------------------------------------------------

DROP TABLE IF EXISTS #SelectedEntities;
DROP TABLE IF EXISTS #TransactionSeed;
DROP TABLE IF EXISTS #TransactionNumber;

DROP TABLE IF EXISTS #MerchantPool;
DROP TABLE IF EXISTS #MerchantBase;

DROP TABLE IF EXISTS #CardPool;
DROP TABLE IF EXISTS #CardBase;

DROP TABLE IF EXISTS #WeightNumber;

------------------------------------------------------------
-- 2. AĞIRLIK NUMARALARI
--
-- Kart ve merchant kayıtlarının seçim havuzunda
-- farklı sayıda yer almasını sağlar.
------------------------------------------------------------

CREATE TABLE #WeightNumber (
    WeightNumber TINYINT NOT NULL
        PRIMARY KEY
);

INSERT INTO #WeightNumber (
    WeightNumber
)
VALUES
    (1),  (2),  (3),  (4),  (5),
    (6),  (7),  (8),  (9),  (10),
    (11), (12), (13), (14), (15),
    (16), (17), (18), (19), (20);

------------------------------------------------------------
-- 3. KULLANILABİLİR KARTLARI HAZIRLA
------------------------------------------------------------

SELECT
    card.CardKey,
    card.CardID,
    card.CardholderCustomerID,

    card.CardType,
    card.CardBrand,
    card.CardTier,

    card.IsVirtual,
    card.IsContactlessEnabled,

    card.CardCountry,
    card.IssueDate,

    customer.CustomerKey,
    customer.CustomerID,
    customer.CustomerSegment,

    customer.RiskLevel
        AS CustomerRiskLevel,

    customer.Country
        AS CustomerCountry,

    customer.RegistrationDate,

    CASE customer.CustomerSegment
        WHEN 'Standard'  THEN 2
        WHEN 'Silver'    THEN 3
        WHEN 'Gold'      THEN 5
        WHEN 'Platinum'  THEN 8
        WHEN 'Corporate' THEN 10
        ELSE 1
    END AS PoolWeight

INTO #CardBase

FROM dw.DimCard AS card

INNER JOIN dw.DimCustomer AS customer
    ON customer.CustomerID = card.CardholderCustomerID

WHERE card.CardKey <> 0
  AND card.CardStatus = 'Active'
  AND card.IssueDate <= @AsOfDate

  AND customer.CustomerKey <> 0
  AND customer.IsActive = 1;

------------------------------------------------------------
-- 3.1. KART HAVUZU KONTROLÜ
------------------------------------------------------------

IF NOT EXISTS(
    SELECT 1
    FROM #CardBase
)
BEGIN
    THROW 50001,
          'Fact üretimi için kullanılabilecek aktif kart bulunamadı.',
          1;
END;

------------------------------------------------------------
-- 3.2. AĞIRLIKLI KART HAVUZU
------------------------------------------------------------

SELECT
    ROW_NUMBER() OVER(
        ORDER BY
            card.CardKey,
            weight.WeightNumber
    ) AS CardPoolRow,

    card.CardKey,
    card.CardID,
    card.CardholderCustomerID,

    card.CardType,
    card.CardBrand,
    card.CardTier,

    card.IsVirtual,
    card.IsContactlessEnabled,

    card.CardCountry,
    card.IssueDate,

    card.CustomerKey,
    card.CustomerID,
    card.CustomerSegment,
    card.CustomerRiskLevel,
    card.CustomerCountry,
    card.RegistrationDate

INTO #CardPool

FROM #CardBase AS card

INNER JOIN #WeightNumber AS weight
    ON weight.WeightNumber <= card.PoolWeight;

CREATE UNIQUE CLUSTERED INDEX CX_CardPool
    ON #CardPool(CardPoolRow);

SELECT
    @CardPoolCount = COUNT_BIG(*)
FROM #CardPool;

IF @CardPoolCount = 0
BEGIN
    THROW 50002,
          'Ağırlıklı kart havuzu oluşturulamadı.',
          1;
END;

------------------------------------------------------------
-- 4. KULLANILABİLİR MERCHANT KAYITLARINI HAZIRLA
------------------------------------------------------------

SELECT
    merchant.MerchantKey,
    merchant.MerchantID,
    merchant.MerchantName,

    merchant.MerchantCategory,
    merchant.MerchantSubcategory,
    merchant.MerchantCategoryCode,

    merchant.MerchantSize,
    merchant.MerchantRiskLevel,

    merchant.Country
        AS MerchantCountry,

    merchant.OnboardingDate,
    merchant.IsOnlineMerchant,

    CASE merchant.MerchantSize
        WHEN 'Micro'      THEN 1
        WHEN 'Small'      THEN 2
        WHEN 'Medium'     THEN 5
        WHEN 'Large'      THEN 10
        WHEN 'Enterprise' THEN 20
        ELSE 1
    END AS PoolWeight

INTO #MerchantBase

FROM dw.DimMerchant AS merchant

WHERE merchant.MerchantKey <> 0
  AND merchant.IsActive = 1
  AND merchant.OnboardingDate <= @AsOfDate;

------------------------------------------------------------
-- 4.1. MERCHANT HAVUZU KONTROLÜ
------------------------------------------------------------

IF NOT EXISTS
(
    SELECT 1
    FROM #MerchantBase
)
BEGIN
    THROW 50003,
          'Fact üretimi için kullanılabilecek aktif merchant bulunamadı.',
          1;
END;

------------------------------------------------------------
-- 4.2. AĞIRLIKLI MERCHANT HAVUZU
------------------------------------------------------------

SELECT
    ROW_NUMBER() OVER
    (
        ORDER BY
            merchant.MerchantKey,
            weight.WeightNumber
    ) AS MerchantPoolRow,

    merchant.MerchantKey,
    merchant.MerchantID,
    merchant.MerchantName,

    merchant.MerchantCategory,
    merchant.MerchantSubcategory,
    merchant.MerchantCategoryCode,

    merchant.MerchantSize,
    merchant.MerchantRiskLevel,

    merchant.MerchantCountry,
    merchant.OnboardingDate,
    merchant.IsOnlineMerchant

INTO #MerchantPool

FROM #MerchantBase AS merchant

INNER JOIN #WeightNumber AS weight
    ON weight.WeightNumber <= merchant.PoolWeight;

CREATE UNIQUE CLUSTERED INDEX CX_MerchantPool
    ON #MerchantPool(MerchantPoolRow);

SELECT
    @MerchantPoolCount = COUNT_BIG(*)
FROM #MerchantPool;

IF @MerchantPoolCount = 0
BEGIN
    THROW 50004,
          'Ağırlıklı merchant havuzu oluşturulamadı.',
          1;
END;

------------------------------------------------------------
-- 5. TEST TRANSACTION NUMARALARINI OLUŞTUR
------------------------------------------------------------

SELECT TOP (@TestTransactionCount)

    CONVERT
    (
        BIGINT,

        ROW_NUMBER() OVER
        (
            ORDER BY
                objectA.object_id,
                objectB.object_id
        )
    ) AS TestTransactionNumber

INTO #TransactionNumber

FROM sys.all_objects AS objectA

CROSS JOIN sys.all_objects AS objectB;

CREATE UNIQUE CLUSTERED INDEX CX_TransactionNumber
    ON #TransactionNumber(TestTransactionNumber);

------------------------------------------------------------
-- 6. TRANSACTION SEED DEĞERLERİNİ OLUŞTUR
------------------------------------------------------------

SELECT
    numbers.TestTransactionNumber,

    ABS
    (
        CONVERT
        (
            BIGINT,

            CHECKSUM
            (
                CONCAT
                (
                    numbers.TestTransactionNumber,
                    '|CARD'
                )
            )
        )
    ) AS CardSeed,

    ABS
    (
        CONVERT
        (
            BIGINT,

            CHECKSUM
            (
                CONCAT
                (
                    numbers.TestTransactionNumber,
                    '|MERCHANT'
                )
            )
        )
    ) AS MerchantSeed,

    ABS
    (
        CONVERT
        (
            BIGINT,

            CHECKSUM
            (
                CONCAT
                (
                    numbers.TestTransactionNumber,
                    '|DATE'
                )
            )
        )
    ) AS DateSeed,

    ABS
    (
        CONVERT
        (
            BIGINT,

            CHECKSUM
            (
                CONCAT
                (
                    numbers.TestTransactionNumber,
                    '|TIME'
                )
            )
        )
    ) AS TimeSeed

INTO #TransactionSeed

FROM #TransactionNumber AS numbers;

CREATE UNIQUE CLUSTERED INDEX CX_TransactionSeed
    ON #TransactionSeed(TestTransactionNumber);

------------------------------------------------------------
-- 7. HER TRANSACTION İÇİN ENTITY SEÇİMİ
--
-- Her işlem için:
-- Bir müşteri
-- Müşteriye ait bir kart
-- Bir merchant
-- Geçerli en erken işlem tarihi
------------------------------------------------------------

SELECT
    seed.TestTransactionNumber,

    seed.DateSeed,
    seed.TimeSeed,

    --------------------------------------------------------
    -- CUSTOMER
    --------------------------------------------------------

    card.CustomerKey,
    card.CustomerID,
    card.CustomerSegment,
    card.CustomerRiskLevel,
    card.CustomerCountry,
    card.RegistrationDate,

    --------------------------------------------------------
    -- CARD
    --------------------------------------------------------

    card.CardKey,
    card.CardID,
    card.CardholderCustomerID,

    card.CardType,
    card.CardBrand,
    card.CardTier,

    card.IsVirtual,
    card.IsContactlessEnabled,

    card.CardCountry,
    card.IssueDate,

    --------------------------------------------------------
    -- MERCHANT
    --------------------------------------------------------

    merchant.MerchantKey,
    merchant.MerchantID,
    merchant.MerchantName,

    merchant.MerchantCategory,
    merchant.MerchantSubcategory,
    merchant.MerchantCategoryCode,

    merchant.MerchantSize,
    merchant.MerchantRiskLevel,
    merchant.MerchantCountry,

    merchant.OnboardingDate,
    merchant.IsOnlineMerchant,

    --------------------------------------------------------
    -- İŞLEMİN GERÇEKLEŞEBİLECEĞİ EN ERKEN TARİH
    --------------------------------------------------------

    CASE
        WHEN card.RegistrationDate >= card.IssueDate
         AND card.RegistrationDate >= merchant.OnboardingDate
         AND card.RegistrationDate >= @BaseStartDate
        THEN card.RegistrationDate

        WHEN card.IssueDate >= merchant.OnboardingDate
         AND card.IssueDate >= @BaseStartDate
        THEN card.IssueDate

        WHEN merchant.OnboardingDate >= @BaseStartDate
        THEN merchant.OnboardingDate

        ELSE @BaseStartDate
    END AS ValidStartDate

INTO #SelectedEntities

FROM #TransactionSeed AS seed

INNER JOIN #CardPool AS card
    ON card.CardPoolRow =
       1 + (seed.CardSeed % @CardPoolCount)

INNER JOIN #MerchantPool AS merchant
    ON merchant.MerchantPoolRow =
       1 + (seed.MerchantSeed % @MerchantPoolCount);

CREATE UNIQUE CLUSTERED INDEX CX_SelectedEntities
    ON #SelectedEntities(TestTransactionNumber);

------------------------------------------------------------
-- 8. SATIR SAYISI KONTROLÜ
------------------------------------------------------------

IF
(
    SELECT COUNT_BIG(*)
    FROM #TransactionSeed
) <> @TestTransactionCount
BEGIN
    THROW 50005,
          '#TransactionSeed beklenen işlem sayısını üretmedi.',
          1;
END;

IF
(
    SELECT COUNT_BIG(*)
    FROM #SelectedEntities
) <> @TestTransactionCount
BEGIN
    THROW 50006,
          '#SelectedEntities beklenen işlem sayısını üretmedi.',
          1;
END;

------------------------------------------------------------
-- 9. KART–MÜŞTERİ EŞLEŞME KONTROLÜ
------------------------------------------------------------

IF EXISTS
(
    SELECT 1
    FROM #SelectedEntities
    WHERE CustomerID <> CardholderCustomerID
)
BEGIN
    THROW 50007,
          'Kart ve müşteri arasında sahiplik uyumsuzluğu bulundu.',
          1;
END;

------------------------------------------------------------
-- 10. TARİH ARALIĞI KONTROLÜ
------------------------------------------------------------

IF EXISTS
(
    SELECT 1
    FROM #SelectedEntities
    WHERE ValidStartDate > @AsOfDate
)
BEGIN
    THROW 50008,
          'Bazı entity kayıtlarının başlangıç tarihi AsOfDate değerinden sonradır.',
          1;
END;

------------------------------------------------------------
-- 11. SONUÇ ÖZETİ
------------------------------------------------------------

SELECT
    (SELECT COUNT_BIG(*) FROM #CardBase)
        AS ActiveCardCount,

    (SELECT COUNT_BIG(*) FROM #CardPool)
        AS WeightedCardPoolCount,

    (SELECT COUNT_BIG(*) FROM #MerchantBase)
        AS ActiveMerchantCount,

    (SELECT COUNT_BIG(*) FROM #MerchantPool)
        AS WeightedMerchantPoolCount,

    (SELECT COUNT_BIG(*) FROM #TransactionSeed)
        AS TransactionSeedCount,

    (SELECT COUNT_BIG(*) FROM #SelectedEntities)
        AS SelectedEntityCount;

------------------------------------------------------------
-- 12. SEGMENT DAĞILIMI
------------------------------------------------------------

SELECT
    CustomerSegment,
    COUNT_BIG(*) AS SelectedTransactionCount

FROM #SelectedEntities

GROUP BY CustomerSegment

ORDER BY SelectedTransactionCount DESC;

------------------------------------------------------------
-- 13. MERCHANT BÜYÜKLÜĞÜ DAĞILIMI
------------------------------------------------------------

SELECT
    MerchantSize,
    COUNT_BIG(*) AS SelectedTransactionCount

FROM #SelectedEntities

GROUP BY MerchantSize

ORDER BY SelectedTransactionCount DESC;

------------------------------------------------------------
-- 14. ÖRNEK ENTITY SEÇİMLERİ
------------------------------------------------------------

SELECT TOP (20)
    TestTransactionNumber,

    CustomerID,
    CustomerSegment,

    CardID,
    CardType,
    CardBrand,

    MerchantID,
    MerchantCategory,
    MerchantSize,

    ValidStartDate

FROM #SelectedEntities

ORDER BY TestTransactionNumber;

SET NOCOUNT OFF;
GO

------------------------------------------------------------
-- PHASE 10B
-- TARİH, SAAT, KANAL VE PARA BİRİMİ
------------------------------------------------------------

DECLARE @AsOfDate DATE = '20260630';

------------------------------------------------------------
-- 1. ÖN KONTROL
------------------------------------------------------------

IF OBJECT_ID('tempdb..#SelectedEntities') IS NULL
BEGIN
    THROW 50101,
          '#SelectedEntities bulunamadı. Önce Phase 10A aynı sekmede çalıştırılmalıdır.',
          1;
END;

------------------------------------------------------------
-- 2. ÖNCEKİ 10B GEÇİCİ TABLOLARINI TEMİZLE
------------------------------------------------------------

DROP TABLE IF EXISTS #TransactionProfileSeed;
DROP TABLE IF EXISTS #TransactionDateBase;
DROP TABLE IF EXISTS #TransactionDateOnly;
DROP TABLE IF EXISTS #TransactionDateTime;
DROP TABLE IF EXISTS #TransactionChannelCandidate;
DROP TABLE IF EXISTS #TransactionChannel;
DROP TABLE IF EXISTS #TransactionCurrency;
DROP TABLE IF EXISTS #TransactionProfile;

------------------------------------------------------------
-- 3. DİĞER HESAPLAMALAR İÇİN SEED DEĞERLERİ
--
-- Her transaction numarası için deterministik değerler.
-- Aynı transaction numarası tekrar kullanılırsa
-- aynı seed değerleri oluşur.
------------------------------------------------------------

SELECT
    entity.*,

    ABS(
        CONVERT(
            BIGINT,
            CHECKSUM(
                CONCAT(
                    entity.TestTransactionNumber,
                    '|CHANNEL'
                )
            )
        )
    ) AS ChannelSeed,

    ABS
    (
        CONVERT
        (
            BIGINT,
            CHECKSUM
            (
                CONCAT
                (
                    entity.TestTransactionNumber,
                    '|CURRENCY'
                )
            )
        )
    ) AS CurrencySeed,

    ABS
    (
        CONVERT
        (
            BIGINT,
            CHECKSUM
            (
                CONCAT
                (
                    entity.TestTransactionNumber,
                    '|DEVICE'
                )
            )
        )
    ) AS DeviceSeed,

    ABS
    (
        CONVERT
        (
            BIGINT,
            CHECKSUM
            (
                CONCAT
                (
                    entity.TestTransactionNumber,
                    '|FX'
                )
            )
        )
    ) AS FXSeed,

    ABS
    (
        CONVERT
        (
            BIGINT,
            CHECKSUM
            (
                CONCAT
                (
                    entity.TestTransactionNumber,
                    '|AMOUNT'
                )
            )
        )
    ) AS AmountSeed,

    ABS
    (
        CONVERT
        (
            BIGINT,
            CHECKSUM
            (
                CONCAT
                (
                    entity.TestTransactionNumber,
                    '|SECURITY'
                )
            )
        )
    ) AS SecuritySeed,

    ABS
    (
        CONVERT
        (
            BIGINT,
            CHECKSUM
            (
                CONCAT
                (
                    entity.TestTransactionNumber,
                    '|RISK'
                )
            )
        )
    ) AS RiskSeed,

    ABS
    (
        CONVERT
        (
            BIGINT,
            CHECKSUM
            (
                CONCAT
                (
                    entity.TestTransactionNumber,
                    '|FRAUD'
                )
            )
        )
    ) AS FraudSeed,

    ABS
    (
        CONVERT
        (
            BIGINT,
            CHECKSUM
            (
                CONCAT
                (
                    entity.TestTransactionNumber,
                    '|STATUS'
                )
            )
        )
    ) AS StatusSeed,

    ABS
    (
        CONVERT
        (
            BIGINT,
            CHECKSUM
            (
                CONCAT
                (
                    entity.TestTransactionNumber,
                    '|REASON'
                )
            )
        )
    ) AS ReasonSeed,

    ABS
    (
        CONVERT
        (
            BIGINT,
            CHECKSUM
            (
                CONCAT
                (
                    entity.TestTransactionNumber,
                    '|TIMING'
                )
            )
        )
    ) AS TimingSeed,

    ABS
    (
        CONVERT
        (
            BIGINT,
            CHECKSUM
            (
                CONCAT
                (
                    entity.TestTransactionNumber,
                    '|FINANCIAL'
                )
            )
        )
    ) AS FinancialSeed,

    ABS
    (
        CONVERT
        (
            BIGINT,
            CHECKSUM
            (
                CONCAT
                (
                    entity.TestTransactionNumber,
                    '|INSTALLMENT'
                )
            )
        )
    ) AS InstallmentSeed,

    ABS
    (
        CONVERT
        (
            BIGINT,
            CHECKSUM
            (
                CONCAT
                (
                    entity.TestTransactionNumber,
                    '|CASHBACK'
                )
            )
        )
    ) AS CashbackSeed

INTO #TransactionProfileSeed

FROM #SelectedEntities AS entity;

CREATE UNIQUE CLUSTERED INDEX CX_TransactionProfileSeed
    ON #TransactionProfileSeed(TestTransactionNumber);

SELECT
    seed.*,

    DATEDIFF
    (
        DAY,
        seed.ValidStartDate,
        @AsOfDate
    ) AS AvailableDayCount,

    CAST
    (
        CONVERT
        (
            DECIMAL(10,6),
            seed.DateSeed % 10000
        )
        /
        9999.0

        AS DECIMAL(10,6)
    ) AS DateRatio

INTO #TransactionDateBase

FROM #TransactionProfileSeed AS seed;

CREATE UNIQUE CLUSTERED INDEX CX_TransactionDateBase
    ON #TransactionDateBase(TestTransactionNumber);

    IF EXISTS
(
    SELECT 1
    FROM #TransactionDateBase
    WHERE AvailableDayCount < 0
)
BEGIN
    THROW 50102,
          'Bazı kayıtların ValidStartDate değeri AsOfDate değerinden sonradır.',
          1;
END;


SELECT
    datebase.*,

    DATEADD
    (
        DAY,

        CONVERT
        (
            INT,
            FLOOR
            (
                datebase.AvailableDayCount
                *
                SQRT
                (
                    CONVERT
                    (
                        FLOAT,
                        datebase.DateRatio
                    )
                )
            )
        ),

        datebase.ValidStartDate
    ) AS TransactionDate

INTO #TransactionDateOnly

FROM #TransactionDateBase AS datebase;

CREATE UNIQUE CLUSTERED INDEX CX_TransactionDateOnly
    ON #TransactionDateOnly(TestTransactionNumber);

SELECT
    dated.*,

    DATEADD
    (
        MILLISECOND,

        CONVERT
        (
            INT,
            dated.TimeSeed % 1000
        ),

        DATEADD
        (
            SECOND,

            CONVERT
            (
                INT,
                dated.TimeSeed % 86400
            ),

            CONVERT
            (
                DATETIME2(3),
                dated.TransactionDate
            )
        )
    ) AS TransactionTimestamp

INTO #TransactionDateTime

FROM #TransactionDateOnly AS dated;

CREATE UNIQUE CLUSTERED INDEX CX_TransactionDateTime
    ON #TransactionDateTime(TestTransactionNumber);

SELECT
    transactiontime.*,

    CASE
        ----------------------------------------------------
        -- SANAL KARTLAR
        ----------------------------------------------------
        WHEN transactiontime.IsVirtual = 1
        THEN
            CASE
                WHEN transactiontime.ChannelSeed % 100 < 35
                    THEN 'ECOMMERCE'

                WHEN transactiontime.ChannelSeed % 100 < 55
                    THEN 'MOBILE_APP'

                WHEN transactiontime.ChannelSeed % 100 < 70
                    THEN 'DIGITAL_WALLET'

                WHEN transactiontime.ChannelSeed % 100 < 80
                    THEN 'RECURRING'

                WHEN transactiontime.ChannelSeed % 100 < 88
                    THEN 'PAYMENT_LINK'

                WHEN transactiontime.ChannelSeed % 100 < 95
                    THEN 'QR_PAYMENT'

                ELSE 'MOTO'
            END

        ----------------------------------------------------
        -- ONLINE MERCHANT
        ----------------------------------------------------
        WHEN transactiontime.IsOnlineMerchant = 1
        THEN
            CASE
                WHEN transactiontime.ChannelSeed % 100 < 34
                    THEN 'ECOMMERCE'

                WHEN transactiontime.ChannelSeed % 100 < 48
                    THEN 'MOBILE_APP'

                WHEN transactiontime.ChannelSeed % 100 < 59
                    THEN 'DIGITAL_WALLET'

                WHEN transactiontime.ChannelSeed % 100 < 67
                    THEN 'RECURRING'

                WHEN transactiontime.ChannelSeed % 100 < 74
                    THEN 'PAYMENT_LINK'

                WHEN transactiontime.ChannelSeed % 100 < 80
                    THEN 'QR_PAYMENT'

                WHEN transactiontime.ChannelSeed % 100 < 88
                    THEN 'CONTACTLESS_POS'

                WHEN transactiontime.ChannelSeed % 100 < 95
                    THEN 'POS'

                WHEN transactiontime.ChannelSeed % 100 < 98
                    THEN 'MOTO'

                ELSE 'ATM'
            END

        ----------------------------------------------------
        -- FİZİKSEL VEYA KARMA MERCHANT
        ----------------------------------------------------
        ELSE
            CASE
                WHEN transactiontime.ChannelSeed % 100 < 33
                    THEN 'POS'

                WHEN transactiontime.ChannelSeed % 100 < 57
                    THEN 'CONTACTLESS_POS'

                WHEN transactiontime.ChannelSeed % 100 < 71
                    THEN 'ECOMMERCE'

                WHEN transactiontime.ChannelSeed % 100 < 78
                    THEN 'MOBILE_APP'

                WHEN transactiontime.ChannelSeed % 100 < 83
                    THEN 'DIGITAL_WALLET'

                WHEN transactiontime.ChannelSeed % 100 < 87
                    THEN 'QR_PAYMENT'

                WHEN transactiontime.ChannelSeed % 100 < 91
                    THEN 'RECURRING'

                WHEN transactiontime.ChannelSeed % 100 < 94
                    THEN 'PAYMENT_LINK'

                WHEN transactiontime.ChannelSeed % 100 < 97
                    THEN 'ATM'

                ELSE 'MOTO'
            END
    END AS CandidateChannelCode

INTO #TransactionChannelCandidate

FROM #TransactionDateTime AS transactiontime;

CREATE UNIQUE CLUSTERED INDEX CX_TransactionChannelCandidate
    ON #TransactionChannelCandidate(TestTransactionNumber);

SELECT
    candidate.*,

    CASE
        WHEN candidate.CandidateChannelCode = 'CONTACTLESS_POS'
         AND candidate.IsContactlessEnabled = 0
        THEN 'POS'

        WHEN candidate.CandidateChannelCode = 'ATM'
         AND candidate.CardType <> 'Debit'
        THEN 'POS'

        ELSE candidate.CandidateChannelCode
    END AS PaymentChannelCode

INTO #TransactionChannel

FROM #TransactionChannelCandidate AS candidate;

CREATE UNIQUE CLUSTERED INDEX CX_TransactionChannel
    ON #TransactionChannel(TestTransactionNumber);

SELECT
    channelresult.*,

    CASE
        ----------------------------------------------------
        -- TÜRKİYE
        ----------------------------------------------------
        WHEN channelresult.MerchantCountry = N'Türkiye'
        THEN
            CASE
                WHEN channelresult.CurrencySeed % 100 < 92
                    THEN 'TRY'

                WHEN channelresult.CurrencySeed % 100 < 95
                    THEN 'USD'

                WHEN channelresult.CurrencySeed % 100 < 98
                    THEN 'EUR'

                WHEN channelresult.CurrencySeed % 100 = 98
                    THEN 'GBP'

                ELSE 'CHF'
            END

        ----------------------------------------------------
        -- EURO BÖLGESİ AĞIRLIKLI
        ----------------------------------------------------
        WHEN channelresult.MerchantCountry IN
        (
            N'Almanya',
            N'Fransa',
            N'Hollanda'
        )
        THEN
            CASE
                WHEN channelresult.CurrencySeed % 100 < 78
                    THEN 'EUR'

                WHEN channelresult.CurrencySeed % 100 < 90
                    THEN 'USD'

                WHEN channelresult.CurrencySeed % 100 < 95
                    THEN 'GBP'

                ELSE 'TRY'
            END

        ----------------------------------------------------
        -- BİRLEŞİK KRALLIK
        ----------------------------------------------------
        WHEN channelresult.MerchantCountry =
             N'Birleşik Krallık'
        THEN
            CASE
                WHEN channelresult.CurrencySeed % 100 < 80
                    THEN 'GBP'

                WHEN channelresult.CurrencySeed % 100 < 90
                    THEN 'EUR'

                WHEN channelresult.CurrencySeed % 100 < 97
                    THEN 'USD'

                ELSE 'TRY'
            END

        ----------------------------------------------------
        -- ABD
        ----------------------------------------------------
        WHEN channelresult.MerchantCountry = N'ABD'
        THEN
            CASE
                WHEN channelresult.CurrencySeed % 100 < 85
                    THEN 'USD'

                WHEN channelresult.CurrencySeed % 100 < 92
                    THEN 'EUR'

                WHEN channelresult.CurrencySeed % 100 < 97
                    THEN 'GBP'

                ELSE 'TRY'
            END

        ----------------------------------------------------
        -- BAE
        ----------------------------------------------------
        WHEN channelresult.MerchantCountry =
             N'Birleşik Arap Emirlikleri'
        THEN
            CASE
                WHEN channelresult.CurrencySeed % 100 < 80
                    THEN 'AED'

                WHEN channelresult.CurrencySeed % 100 < 90
                    THEN 'USD'

                WHEN channelresult.CurrencySeed % 100 < 95
                    THEN 'EUR'

                ELSE 'TRY'
            END

        ELSE 'USD'
    END AS CurrencyCode,

    CASE
        WHEN channelresult.CardCountry
             <> channelresult.MerchantCountry
        THEN 1
        ELSE 0
    END AS IsInternational

INTO #TransactionCurrency

FROM #TransactionChannel AS channelresult;

CREATE UNIQUE CLUSTERED INDEX CX_TransactionCurrency
    ON #TransactionCurrency(TestTransactionNumber);

SELECT
    currencyresult.*,

    paymentchannel.PaymentChannelKey,
    currency.CurrencyKey

INTO #TransactionProfile

FROM #TransactionCurrency AS currencyresult

INNER JOIN dw.DimPaymentChannel AS paymentchannel
    ON paymentchannel.PaymentChannelCode =
       currencyresult.PaymentChannelCode

INNER JOIN dw.DimCurrency AS currency
    ON currency.CurrencyCode =
       currencyresult.CurrencyCode;

CREATE UNIQUE CLUSTERED INDEX CX_TransactionProfile
    ON #TransactionProfile(TestTransactionNumber);

GO


------------------------------------------------------------
-- PHASE 10C
-- DÖVİZ KURU VE İŞLEM TUTARI
------------------------------------------------------------

------------------------------------------------------------
-- 1. ÖN KONTROL
------------------------------------------------------------


DROP TABLE IF EXISTS #AmountShape;
DROP TABLE IF EXISTS #FXBase;
DROP TABLE IF EXISTS #USDRate;
DROP TABLE IF EXISTS #FXRates;
DROP TABLE IF EXISTS #AmountParameters;
DROP TABLE IF EXISTS #AmountShape;
DROP TABLE IF EXISTS #AmountTRYRaw;
DROP TABLE IF EXISTS #AmountTRYFinal;
DROP TABLE IF EXISTS #TransactionAmount;







IF OBJECT_ID('tempdb..#TransactionProfile') IS NULL
BEGIN
    THROW 50201,
          '#TransactionProfile bulunamadı. Önce Phase 10B aynı sekmede çalıştırılmalıdır.',
          1;
END;

------------------------------------------------------------
-- 2. ÖNCEKİ 10C GEÇİCİ TABLOLARINI TEMİZLE
------------------------------------------------------------

DROP TABLE IF EXISTS #FXBase;
DROP TABLE IF EXISTS #USDRate;
DROP TABLE IF EXISTS #FXRates;
DROP TABLE IF EXISTS #AmountParameters;
DROP TABLE IF EXISTS #AmountTRYRaw;
DROP TABLE IF EXISTS #AmountTRYFinal;
DROP TABLE IF EXISTS #TransactionAmount;

------------------------------------------------------------
-- 3. TARİH VE KUR DALGALANMA PARAMETRELERİ
------------------------------------------------------------

SELECT
    profile.*,

    YEAR(profile.TransactionDate) AS TransactionYear,

    MONTH(profile.TransactionDate) AS TransactionMonth,

    CAST
    (
        0.970000
        +
        CONVERT
        (
            DECIMAL(10,6),
            profile.FXSeed % 601
        ) / 10000.0

        AS DECIMAL(10,6)
    ) AS FXNoiseFactor

INTO #FXBase

FROM #TransactionProfile AS profile;

CREATE UNIQUE CLUSTERED INDEX CX_FXBase
    ON #FXBase(TestTransactionNumber);


SELECT
    fxbase.*,

    CAST
    (
        (
            CASE fxbase.TransactionYear
                WHEN 2020
                THEN
                    5.80
                    + fxbase.TransactionMonth * 0.17

                WHEN 2021
                THEN
                    7.20
                    + fxbase.TransactionMonth * 0.45

                WHEN 2022
                THEN
                    13.00
                    + fxbase.TransactionMonth * 0.60

                WHEN 2023
                THEN
                    18.00
                    + fxbase.TransactionMonth * 0.90

                WHEN 2024
                THEN
                    29.00
                    + fxbase.TransactionMonth * 0.50

                WHEN 2025
                THEN
                    35.00
                    + fxbase.TransactionMonth * 0.55

                WHEN 2026
                THEN
                    42.00
                    + fxbase.TransactionMonth * 0.50

                ELSE 1.00
            END
        )
        *
        fxbase.FXNoiseFactor

        AS DECIMAL(19,8)
    ) AS USDTRY

INTO #USDRate

FROM #FXBase AS fxbase;

CREATE UNIQUE CLUSTERED INDEX CX_USDRate
    ON #USDRate(TestTransactionNumber);

SELECT
    usdrate.*,

    CAST
    (
        CASE usdrate.CurrencyCode
            WHEN 'TRY'
            THEN 1.00000000

            WHEN 'USD'
            THEN usdrate.USDTRY

            WHEN 'EUR'
            THEN usdrate.USDTRY * 1.09

            WHEN 'GBP'
            THEN usdrate.USDTRY * 1.28

            WHEN 'CHF'
            THEN usdrate.USDTRY * 1.12

            WHEN 'JPY'
            THEN usdrate.USDTRY / 150.00

            WHEN 'CNY'
            THEN usdrate.USDTRY / 7.20

            WHEN 'AED'
            THEN usdrate.USDTRY / 3.6725

            WHEN 'SAR'
            THEN usdrate.USDTRY / 3.75

            WHEN 'CAD'
            THEN usdrate.USDTRY / 1.35

            WHEN 'AUD'
            THEN usdrate.USDTRY / 1.50

            WHEN 'SEK'
            THEN
                (usdrate.USDTRY * 1.09) / 11.20

            WHEN 'KWD'
            THEN usdrate.USDTRY * 3.25

            ELSE 1.00000000
        END

        AS DECIMAL(19,8)
    ) AS ExchangeRateToTRY

INTO #FXRates

FROM #USDRate AS usdrate;


CREATE UNIQUE CLUSTERED INDEX CX_FXRates
    ON #FXRates(TestTransactionNumber);

SELECT
    fx.*,

    --------------------------------------------------------
    -- KATEGORİYE GÖRE MİNİMUM TUTAR
    --------------------------------------------------------

    CAST
    (
        CASE fx.MerchantCategory
            WHEN 'Grocery' THEN 40
            WHEN 'Restaurant' THEN 70
            WHEN 'Fashion' THEN 150
            WHEN 'Electronics' THEN 500
            WHEN 'Transportation' THEN 25
            WHEN 'Fuel' THEN 250
            WHEN 'Utilities' THEN 100
            WHEN 'Travel' THEN 1000
            WHEN 'Accommodation' THEN 700
            WHEN 'Healthcare' THEN 100
            WHEN 'Entertainment' THEN 40
            WHEN 'Education' THEN 500
            WHEN 'Financial Services' THEN 100
            WHEN 'Home and Living' THEN 250
            WHEN 'Beauty and Personal Care' THEN 100
            ELSE 50
        END

        AS DECIMAL(19,4)
    ) AS MinimumAmountTRY,

    --------------------------------------------------------
    -- KATEGORİYE GÖRE MAKSİMUM TUTAR
    --------------------------------------------------------

    CAST
    (
        CASE fx.MerchantCategory
            WHEN 'Grocery' THEN 5000
            WHEN 'Restaurant' THEN 4000
            WHEN 'Fashion' THEN 20000
            WHEN 'Electronics' THEN 80000
            WHEN 'Transportation' THEN 3000
            WHEN 'Fuel' THEN 7000
            WHEN 'Utilities' THEN 15000
            WHEN 'Travel' THEN 150000
            WHEN 'Accommodation' THEN 120000
            WHEN 'Healthcare' THEN 40000
            WHEN 'Entertainment' THEN 8000
            WHEN 'Education' THEN 75000
            WHEN 'Financial Services' THEN 60000
            WHEN 'Home and Living' THEN 50000
            WHEN 'Beauty and Personal Care' THEN 12000
            ELSE 15000
        END

        AS DECIMAL(19,4)
    ) AS MaximumAmountTRY,

    --------------------------------------------------------
    -- MÜŞTERİ SEGMENT ÇARPANI
    --------------------------------------------------------

    CAST
    (
        CASE fx.CustomerSegment
            WHEN 'Standard' THEN 0.80
            WHEN 'Silver' THEN 1.00
            WHEN 'Gold' THEN 1.25
            WHEN 'Platinum' THEN 1.60
            WHEN 'Corporate' THEN 2.30
            ELSE 1.00
        END

        AS DECIMAL(10,4)
    ) AS CustomerAmountMultiplier,

    --------------------------------------------------------
    -- MERCHANT BÜYÜKLÜĞÜ ÇARPANI
    --------------------------------------------------------

    CAST
    (
        CASE fx.MerchantSize
            WHEN 'Micro' THEN 0.80
            WHEN 'Small' THEN 0.90
            WHEN 'Medium' THEN 1.00
            WHEN 'Large' THEN 1.15
            WHEN 'Enterprise' THEN 1.30
            ELSE 1.00
        END

        AS DECIMAL(10,4)
    ) AS MerchantAmountMultiplier,

    --------------------------------------------------------
    -- YILA GÖRE NOMİNAL TUTAR ÇARPANI
    --------------------------------------------------------

    CAST
    (
        CASE fx.TransactionYear
            WHEN 2020 THEN 0.60
            WHEN 2021 THEN 0.70
            WHEN 2022 THEN 0.85
            WHEN 2023 THEN 1.00
            WHEN 2024 THEN 1.20
            WHEN 2025 THEN 1.45
            WHEN 2026 THEN 1.65
            ELSE 1.00
        END

        AS DECIMAL(10,4)
    ) AS YearAmountMultiplier,

    --------------------------------------------------------
    -- 0–1 ARASINDA TUTAR ORANI
    --------------------------------------------------------

    CAST
    (
        CONVERT
        (
            DECIMAL(10,6),
            fx.AmountSeed % 10000
        )
        /
        9999.0

        AS DECIMAL(10,6)
    ) AS AmountRatio

INTO #AmountParameters

FROM #FXRates AS fx;


CREATE UNIQUE CLUSTERED INDEX CX_AmountParameters
    ON #AmountParameters(TestTransactionNumber);

SELECT
    amountparameter.*,

    CONVERT
    (
        FLOAT,
        amountparameter.AmountRatio
    )
    *
    CONVERT
    (
        FLOAT,
        amountparameter.AmountRatio
    ) AS AmountShape

INTO #AmountShape

FROM #AmountParameters AS amountparameter;
GO

CREATE UNIQUE CLUSTERED INDEX CX_AmountShape
    ON #AmountShape(TestTransactionNumber);
GO

SELECT
    amountshape.*,

    CAST
    (
        (
            amountshape.MinimumAmountTRY
            +
            (
                amountshape.MaximumAmountTRY
                -
                amountshape.MinimumAmountTRY
            )
            *
            amountshape.AmountShape
        )
        *
        amountshape.CustomerAmountMultiplier
        *
        amountshape.MerchantAmountMultiplier
        *
        amountshape.YearAmountMultiplier

        AS DECIMAL(19,4)
    ) AS AmountTRYRaw

INTO #AmountTRYRaw

FROM #AmountShape AS amountshape;
GO


CREATE UNIQUE CLUSTERED INDEX CX_AmountTRYRaw
    ON #AmountTRYRaw(TestTransactionNumber);

SELECT
    rawamount.*,

    CAST
    (
        CASE
            WHEN rawamount.AmountTRYRaw < 1
            THEN 1.00

            ELSE
                ROUND
                (
                    rawamount.AmountTRYRaw,
                    2
                )
        END

        AS DECIMAL(19,4)
    ) AS AmountTRY

INTO #AmountTRYFinal

FROM #AmountTRYRaw AS rawamount;


CREATE UNIQUE CLUSTERED INDEX CX_AmountTRYFinal
    ON #AmountTRYFinal(TestTransactionNumber);

SELECT
    finalamount.*,

    CAST
    (
        ROUND
        (
            finalamount.AmountTRY
            /
            finalamount.ExchangeRateToTRY,
            4
        )

        AS DECIMAL(19,4)
    ) AS OriginalAmount

INTO #TransactionAmount

FROM #AmountTRYFinal AS finalamount;

CREATE UNIQUE CLUSTERED INDEX CX_TransactionAmount
    ON #TransactionAmount(TestTransactionNumber);

GO

SELECT
    OBJECT_ID('tempdb..#TransactionProfile')
        AS TransactionProfileObjectID;



------------------------------------------------------------
-- PHASE 10D
-- CİHAZ EŞLEŞTİRMESİ VE GÜVENLİK PROFİLİ
------------------------------------------------------------

SET NOCOUNT ON;

------------------------------------------------------------
-- 1. ÖN KONTROL
------------------------------------------------------------

IF OBJECT_ID('tempdb..#TransactionAmount') IS NULL
BEGIN
    THROW 50301,
          '#TransactionAmount bulunamadı. Önce Phase 10C aynı sekmede çalıştırılmalıdır.',
          1;
END;

------------------------------------------------------------
-- 2. ÖNCEKİ PHASE 10D TABLOLARINI TEMİZLE
------------------------------------------------------------

DROP TABLE IF EXISTS #CustomerDeviceList;
DROP TABLE IF EXISTS #CustomerDeviceCount;
DROP TABLE IF EXISTS #DeviceSelection;
DROP TABLE IF EXISTS #TransactionDevice;
DROP TABLE IF EXISTS #TransactionSecurity;

------------------------------------------------------------
-- 3. MÜŞTERİLERİN KULLANILABİLİR CİHAZLARINI HAZIRLA
--
-- POS Terminal ve Unknown cihazları müşteri dijital cihazı
-- olarak kullanmıyoruz.
------------------------------------------------------------

SELECT
    source.RegisteredCustomerID AS CustomerID,

    ROW_NUMBER() OVER
    (
        PARTITION BY source.RegisteredCustomerID
        ORDER BY
            source.IsTrustedDevice DESC,
            source.DeviceKey
    ) AS DeviceOrdinal,

    source.DeviceKey,
    source.DeviceID,
    source.DeviceType,
    source.OperatingSystem,
    source.BrowserName,
    source.AppVersion,
    source.DeviceCountry,

    source.IsTrustedDevice,
    source.IsEmulator,
    source.IsRootedOrJailbroken

INTO #CustomerDeviceList

FROM dw.DimDevice AS source

WHERE source.DeviceKey <> 0
  AND source.RegisteredCustomerID IS NOT NULL
  AND source.DeviceType IN
  (
      'Mobile',
      'Tablet',
      'Desktop'
  );

CREATE UNIQUE CLUSTERED INDEX CX_CustomerDeviceList
    ON #CustomerDeviceList
    (
        CustomerID,
        DeviceOrdinal
    );

------------------------------------------------------------
-- 4. HER MÜŞTERİNİN CİHAZ SAYISINI HESAPLA
------------------------------------------------------------

SELECT
    CustomerID,
    COUNT(*) AS DeviceCount

INTO #CustomerDeviceCount

FROM #CustomerDeviceList

GROUP BY CustomerID;

CREATE UNIQUE CLUSTERED INDEX CX_CustomerDeviceCount
    ON #CustomerDeviceCount(CustomerID);

------------------------------------------------------------
-- 5. HER TRANSACTION İÇİN KULLANILACAK CİHAZ SIRASINI SEÇ
--
-- Dijital kanallarda müşteriye ait cihaz seçilir.
-- Fiziksel POS, temassız POS, ATM ve MOTO işlemlerinde
-- müşteri cihazı kullanılmaz.
------------------------------------------------------------

SELECT
    transactiondata.*,

    ISNULL(devicecount.DeviceCount, 0) AS AvailableDeviceCount,

    CASE
        WHEN transactiondata.PaymentChannelCode IN
        (
            'ECOMMERCE',
            'MOBILE_APP',
            'DIGITAL_WALLET',
            'QR_PAYMENT',
            'PAYMENT_LINK',
            'RECURRING'
        )
        AND ISNULL(devicecount.DeviceCount, 0) > 0
        THEN
            1
            +
            CONVERT
            (
                INT,
                transactiondata.DeviceSeed
                %
                devicecount.DeviceCount
            )

        ELSE NULL
    END AS SelectedDeviceOrdinal

INTO #DeviceSelection

FROM #TransactionAmount AS transactiondata

LEFT JOIN #CustomerDeviceCount AS devicecount
    ON devicecount.CustomerID = transactiondata.CustomerID;

CREATE UNIQUE CLUSTERED INDEX CX_DeviceSelection
    ON #DeviceSelection(TestTransactionNumber);

------------------------------------------------------------
-- 6. SEÇİLEN CİHAZI TRANSACTION'A BAĞLA
--
-- Cihaz bulunamazsa DeviceKey = 0 kullanılır.
------------------------------------------------------------

SELECT
    selection.*,

    ISNULL(device.DeviceKey, 0) AS DeviceKey,

    ISNULL(device.DeviceID, 'UNKNOWN') AS DeviceID,

    ISNULL(device.DeviceType, 'Unknown') AS DeviceType,

    ISNULL(device.OperatingSystem, 'Unknown')
        AS OperatingSystem,

    ISNULL(device.BrowserName, 'Unknown')
        AS BrowserName,

    device.AppVersion,

    ISNULL(device.DeviceCountry, N'Bilinmiyor')
        AS DeviceCountry,

    ISNULL(device.IsTrustedDevice, 0)
        AS IsTrustedDevice,

    ISNULL(device.IsEmulator, 0)
        AS IsEmulator,

    ISNULL(device.IsRootedOrJailbroken, 0)
        AS IsRootedOrJailbroken,

    CASE
        WHEN device.DeviceKey IS NOT NULL
        THEN 1
        ELSE 0
    END AS UsesCustomerDevice

INTO #TransactionDevice

FROM #DeviceSelection AS selection

LEFT JOIN #CustomerDeviceList AS device
    ON device.CustomerID = selection.CustomerID
   AND device.DeviceOrdinal = selection.SelectedDeviceOrdinal;

CREATE UNIQUE CLUSTERED INDEX CX_TransactionDevice
    ON #TransactionDevice(TestTransactionNumber);

------------------------------------------------------------
-- 7. GÜVENLİK GÖSTERGELERİNİ HESAPLA
------------------------------------------------------------

SELECT
    transactiondevice.*,

    --------------------------------------------------------
    -- TEMASSIZ İŞLEM
    --------------------------------------------------------

    CASE
        WHEN transactiondevice.PaymentChannelCode =
             'CONTACTLESS_POS'
        THEN 1
        ELSE 0
    END AS IsContactless,

    --------------------------------------------------------
    -- RECURRING İŞLEM
    --------------------------------------------------------

    CASE
        WHEN transactiondevice.PaymentChannelCode =
             'RECURRING'
        THEN 1
        ELSE 0
    END AS IsRecurring,

    --------------------------------------------------------
    -- 3D SECURE
    --
    -- Kanal türüne göre farklı kullanım olasılıkları vardır.
    --------------------------------------------------------

    CASE
        WHEN transactiondevice.PaymentChannelCode = 'ECOMMERCE'
         AND transactiondevice.SecuritySeed % 100 < 88
        THEN 1

        WHEN transactiondevice.PaymentChannelCode = 'PAYMENT_LINK'
         AND transactiondevice.SecuritySeed % 100 < 92
        THEN 1

        WHEN transactiondevice.PaymentChannelCode = 'MOBILE_APP'
         AND transactiondevice.SecuritySeed % 100 < 78
        THEN 1

        WHEN transactiondevice.PaymentChannelCode = 'DIGITAL_WALLET'
         AND transactiondevice.SecuritySeed % 100 < 72
        THEN 1

        WHEN transactiondevice.PaymentChannelCode = 'QR_PAYMENT'
         AND transactiondevice.SecuritySeed % 100 < 65
        THEN 1

        WHEN transactiondevice.PaymentChannelCode = 'RECURRING'
         AND transactiondevice.SecuritySeed % 100 < 20
        THEN 1

        WHEN transactiondevice.PaymentChannelCode = 'MOTO'
         AND transactiondevice.SecuritySeed % 100 < 10
        THEN 1

        ELSE 0
    END AS Is3DSecure,

    --------------------------------------------------------
    -- TOKENIZATION
    --------------------------------------------------------

    CASE
        WHEN transactiondevice.PaymentChannelCode =
             'DIGITAL_WALLET'
         AND transactiondevice.SecuritySeed % 100 < 98
        THEN 1

        WHEN transactiondevice.PaymentChannelCode =
             'MOBILE_APP'
         AND transactiondevice.SecuritySeed % 100 < 85
        THEN 1

        WHEN transactiondevice.PaymentChannelCode =
             'RECURRING'
         AND transactiondevice.SecuritySeed % 100 < 90
        THEN 1

        WHEN transactiondevice.PaymentChannelCode =
             'QR_PAYMENT'
         AND transactiondevice.SecuritySeed % 100 < 75
        THEN 1

        WHEN transactiondevice.PaymentChannelCode =
             'ECOMMERCE'
         AND transactiondevice.SecuritySeed % 100 < 35
        THEN 1

        WHEN transactiondevice.PaymentChannelCode =
             'PAYMENT_LINK'
         AND transactiondevice.SecuritySeed % 100 < 45
        THEN 1

        ELSE 0
    END AS IsTokenized

INTO #TransactionSecurity

FROM #TransactionDevice AS transactiondevice;

CREATE UNIQUE CLUSTERED INDEX CX_TransactionSecurity
    ON #TransactionSecurity(TestTransactionNumber);

------------------------------------------------------------
-- 8. SATIR SAYISI KONTROLÜ
------------------------------------------------------------

SELECT
    (SELECT COUNT(*) FROM #TransactionAmount)
        AS TransactionAmountCount,

    (SELECT COUNT(*) FROM #DeviceSelection)
        AS DeviceSelectionCount,

    (SELECT COUNT(*) FROM #TransactionDevice)
        AS TransactionDeviceCount,

    (SELECT COUNT(*) FROM #TransactionSecurity)
        AS TransactionSecurityCount;

------------------------------------------------------------
-- 9. CİHAZ KULLANIM ORANI
------------------------------------------------------------

SELECT
    UsesCustomerDevice,

    CASE
        WHEN UsesCustomerDevice = 1
        THEN N'Müşteri cihazı kullanıldı'

        ELSE N'Cihaz kullanılmadı veya bilinmiyor'
    END AS DeviceUsageStatus,

    COUNT(*) AS TransactionCount,

    CAST
    (
        100.0
        *
        COUNT(*)
        /
        SUM(COUNT(*)) OVER ()

        AS DECIMAL(6,2)
    ) AS TransactionPercentage

FROM #TransactionSecurity

GROUP BY UsesCustomerDevice

ORDER BY UsesCustomerDevice DESC;

------------------------------------------------------------
-- 10. KANAL BAZINDA CİHAZ KULLANIMI
------------------------------------------------------------

SELECT
    PaymentChannelCode,

    COUNT(*) AS TransactionCount,

    SUM
    (
        CONVERT
        (
            INT,
            UsesCustomerDevice
        )
    ) AS TransactionsWithDevice,

    CAST
    (
        100.0
        *
        SUM
        (
            CONVERT
            (
                INT,
                UsesCustomerDevice
            )
        )
        /
        COUNT(*)

        AS DECIMAL(6,2)
    ) AS DeviceUsagePercentage

FROM #TransactionSecurity

GROUP BY PaymentChannelCode

ORDER BY TransactionCount DESC;

------------------------------------------------------------
-- 11. CİHAZ TÜRÜ DAĞILIMI
------------------------------------------------------------

SELECT
    DeviceType,
    COUNT(*) AS TransactionCount

FROM #TransactionSecurity

GROUP BY DeviceType

ORDER BY TransactionCount DESC;

------------------------------------------------------------
-- 12. GÜVENİLİR CİHAZ DAĞILIMI
------------------------------------------------------------

SELECT
    IsTrustedDevice,

    CASE
        WHEN IsTrustedDevice = 1
        THEN N'Güvenilir cihaz'

        ELSE N'Güvenilir olmayan veya bilinmeyen cihaz'
    END AS TrustStatus,

    COUNT(*) AS TransactionCount

FROM #TransactionSecurity

GROUP BY IsTrustedDevice

ORDER BY IsTrustedDevice DESC;

------------------------------------------------------------
-- 13. 3D SECURE KANAL DAĞILIMI
------------------------------------------------------------

SELECT
    PaymentChannelCode,

    COUNT(*) AS TransactionCount,

    SUM
    (
        CONVERT
        (
            INT,
            Is3DSecure
        )
    ) AS ThreeDSecureTransactionCount,

    CAST
    (
        100.0
        *
        SUM
        (
            CONVERT
            (
                INT,
                Is3DSecure
            )
        )
        /
        COUNT(*)

        AS DECIMAL(6,2)
    ) AS ThreeDSecurePercentage

FROM #TransactionSecurity

GROUP BY PaymentChannelCode

ORDER BY TransactionCount DESC;

------------------------------------------------------------
-- 14. TOKENIZATION KANAL DAĞILIMI
------------------------------------------------------------

SELECT
    PaymentChannelCode,

    COUNT(*) AS TransactionCount,

    SUM
    (
        CONVERT
        (
            INT,
            IsTokenized
        )
    ) AS TokenizedTransactionCount,

    CAST
    (
        100.0
        *
        SUM
        (
            CONVERT
            (
                INT,
                IsTokenized
            )
        )
        /
        COUNT(*)

        AS DECIMAL(6,2)
    ) AS TokenizedPercentage

FROM #TransactionSecurity

GROUP BY PaymentChannelCode

ORDER BY TransactionCount DESC;

------------------------------------------------------------
-- 15. CİHAZ-MÜŞTERİ EŞLEŞME KONTROLÜ
------------------------------------------------------------

SELECT
    COUNT(*) AS DeviceCustomerMismatchCount

FROM #TransactionSecurity AS transactionsecurity

INNER JOIN dw.DimDevice AS device
    ON device.DeviceKey = transactionsecurity.DeviceKey

WHERE transactionsecurity.DeviceKey <> 0
  AND device.RegisteredCustomerID
      <> transactionsecurity.CustomerID;

------------------------------------------------------------
-- 16. EMULATOR VE ROOT TUTARLILIĞI
------------------------------------------------------------

SELECT
    COUNT(*) AS InvalidTrustedRiskyDeviceCount

FROM #TransactionSecurity

WHERE IsTrustedDevice = 1
  AND
  (
      IsEmulator = 1
      OR IsRootedOrJailbroken = 1
  );

------------------------------------------------------------
-- 17. TEMASSIZ İŞLEM TUTARLILIĞI
------------------------------------------------------------

SELECT
    COUNT(*) AS InvalidContactlessTransactionCount

FROM #TransactionSecurity

WHERE IsContactless = 1
  AND
  (
      PaymentChannelCode <> 'CONTACTLESS_POS'
      OR IsContactlessEnabled = 0
  );

------------------------------------------------------------
-- 18. RECURRING İŞLEM TUTARLILIĞI
------------------------------------------------------------

SELECT
    COUNT(*) AS InvalidRecurringTransactionCount

FROM #TransactionSecurity

WHERE IsRecurring = 1
  AND PaymentChannelCode <> 'RECURRING';

------------------------------------------------------------
-- 19. ÖRNEK SONUÇLAR
------------------------------------------------------------

SELECT TOP (20)
    TestTransactionNumber,

    CustomerID,
    CardID,
    MerchantID,

    TransactionTimestamp,
    PaymentChannelCode,

    DeviceKey,
    DeviceID,
    DeviceType,
    OperatingSystem,

    IsTrustedDevice,
    IsEmulator,
    IsRootedOrJailbroken,

    IsContactless,
    IsRecurring,
    Is3DSecure,
    IsTokenized,

    CurrencyCode,
    OriginalAmount,
    AmountTRY

FROM #TransactionSecurity

ORDER BY TestTransactionNumber;

SET NOCOUNT OFF;




------------------------------------------------------------
-- PHASE 10E
-- FRAUD SKORU, FRAUD NEDENİ VE TRANSACTION STATUS
------------------------------------------------------------

SET NOCOUNT ON;

------------------------------------------------------------
-- 1. ÖN KONTROL
------------------------------------------------------------

IF OBJECT_ID('tempdb..#TransactionSecurity') IS NULL
BEGIN
    THROW 50401,
          '#TransactionSecurity bulunamadı. Önce Phase 10D aynı sekmede çalıştırılmalıdır.',
          1;
END;

------------------------------------------------------------
-- 2. GEREKLİ DIMENSION KAYITLARINI KONTROL ET
------------------------------------------------------------

IF EXISTS
(
    SELECT required.StatusCode
    FROM
    (
        VALUES
            ('APPROVED'),
            ('PENDING'),
            ('DECLINED'),
            ('FAILED'),
            ('CANCELLED'),
            ('REVERSED'),
            ('REFUNDED'),
            ('EXPIRED')
    ) AS required(StatusCode)

    LEFT JOIN dw.DimTransactionStatus AS target
        ON target.StatusCode = required.StatusCode

    WHERE target.TransactionStatusKey IS NULL
)
BEGIN
    THROW 50402,
          'DimTransactionStatus içerisinde gerekli status kodlarından biri eksik.',
          1;
END;

IF EXISTS
(
    SELECT required.FraudReasonCode
    FROM
    (
        VALUES
            ('NO_FRAUD'),
            ('STOLEN_CARD'),
            ('ACCOUNT_TAKEOVER'),
            ('SUSPICIOUS_DEVICE'),
            ('ROOTED_DEVICE'),
            ('UNUSUAL_AMOUNT'),
            ('HIGH_VELOCITY'),
            ('IMPOSSIBLE_TRAVEL'),
            ('LOCATION_MISMATCH'),
            ('MULTIPLE_DECLINES'),
            ('MERCHANT_RISK'),
            ('IDENTITY_MISMATCH'),
            ('THREEDS_FAILURE')
    ) AS required(FraudReasonCode)

    LEFT JOIN dw.DimFraudReason AS target
        ON target.FraudReasonCode = required.FraudReasonCode

    WHERE target.FraudReasonKey IS NULL
)
BEGIN
    THROW 50403,
          'DimFraudReason içerisinde gerekli fraud reason kodlarından biri eksik.',
          1;
END;

------------------------------------------------------------
-- 3. ÖNCEKİ PHASE 10E TABLOLARINI TEMİZLE
------------------------------------------------------------

DROP TABLE IF EXISTS #RiskBase;
DROP TABLE IF EXISTS #RiskProbability;
DROP TABLE IF EXISTS #FraudFlag;
DROP TABLE IF EXISTS #FraudScoreResult;
DROP TABLE IF EXISTS #TransactionStatusCode;
DROP TABLE IF EXISTS #FraudReasonResult;
DROP TABLE IF EXISTS #TransactionRiskStatus;

------------------------------------------------------------
-- 4. TEMEL RİSK PUANINI VE FRAUD OLASILIĞINI HESAPLA
------------------------------------------------------------

SELECT
    source.*,

    --------------------------------------------------------
    -- BASE RISK POINTS
    -- FraudScore üretiminde kullanılacak temel risk puanı
    --------------------------------------------------------

    5
    + CONVERT(INT, source.RiskSeed % 16)

    + CASE source.CustomerRiskLevel
        WHEN 'Low'      THEN 0
        WHEN 'Medium'   THEN 6
        WHEN 'High'     THEN 18
        WHEN 'Critical' THEN 30
        ELSE 0
      END

    + CASE source.MerchantRiskLevel
        WHEN 'Low'      THEN 0
        WHEN 'Medium'   THEN 5
        WHEN 'High'     THEN 15
        WHEN 'Critical' THEN 25
        ELSE 0
      END

    + CASE
        WHEN source.IsInternational = 1
        THEN 10
        ELSE 0
      END

    + CASE
        WHEN source.DeviceKey <> 0
         AND source.IsTrustedDevice = 0
        THEN 8
        ELSE 0
      END

    + CASE
        WHEN source.IsEmulator = 1
        THEN 25
        ELSE 0
      END

    + CASE
        WHEN source.IsRootedOrJailbroken = 1
        THEN 20
        ELSE 0
      END

    + CASE
        WHEN source.PaymentChannelCode IN
        (
            'ECOMMERCE',
            'MOBILE_APP',
            'DIGITAL_WALLET',
            'QR_PAYMENT',
            'PAYMENT_LINK',
            'MOTO'
        )
        THEN 4
        ELSE 0
      END

    + CASE
        WHEN source.AmountTRY >= 10000
        THEN 8
        ELSE 0
      END

    + CASE
        WHEN source.AmountTRY >= 50000
        THEN 8
        ELSE 0
      END

    + CASE
        WHEN source.Is3DSecure = 0
         AND source.PaymentChannelCode IN
        (
            'ECOMMERCE',
            'PAYMENT_LINK',
            'MOBILE_APP'
        )
        THEN 10
        ELSE 0
      END AS BaseRiskPoints,

    --------------------------------------------------------
    -- FRAUD PROBABILITY BASIS POINTS
    --
    -- 100 basis point = %1 fraud ihtimali
    --------------------------------------------------------

    20

    + CASE source.CustomerRiskLevel
        WHEN 'Low'      THEN 0
        WHEN 'Medium'   THEN 20
        WHEN 'High'     THEN 80
        WHEN 'Critical' THEN 180
        ELSE 0
      END

    + CASE source.MerchantRiskLevel
        WHEN 'Low'      THEN 0
        WHEN 'Medium'   THEN 15
        WHEN 'High'     THEN 70
        WHEN 'Critical' THEN 150
        ELSE 0
      END

    + CASE
        WHEN source.IsInternational = 1
        THEN 35
        ELSE 0
      END

    + CASE
        WHEN source.DeviceKey <> 0
         AND source.IsTrustedDevice = 0
        THEN 50
        ELSE 0
      END

    + CASE
        WHEN source.IsEmulator = 1
        THEN 400
        ELSE 0
      END

    + CASE
        WHEN source.IsRootedOrJailbroken = 1
        THEN 250
        ELSE 0
      END

    + CASE
        WHEN source.PaymentChannelCode IN
        (
            'ECOMMERCE',
            'MOBILE_APP',
            'DIGITAL_WALLET',
            'QR_PAYMENT',
            'PAYMENT_LINK',
            'MOTO'
        )
        THEN 15
        ELSE 0
      END

    + CASE
        WHEN source.AmountTRY >= 10000
        THEN 40
        ELSE 0
      END

    + CASE
        WHEN source.AmountTRY >= 50000
        THEN 80
        ELSE 0
      END

    + CASE
        WHEN source.Is3DSecure = 0
         AND source.PaymentChannelCode IN
        (
            'ECOMMERCE',
            'PAYMENT_LINK',
            'MOBILE_APP'
        )
        THEN 50
        ELSE 0
      END AS RawFraudProbabilityBasisPoints

INTO #RiskBase

FROM #TransactionSecurity AS source;

CREATE UNIQUE CLUSTERED INDEX CX_RiskBase
    ON #RiskBase(TestTransactionNumber);

------------------------------------------------------------
-- 5. FRAUD OLASILIĞINI SINIRLA
--
-- Minimum: 10 basis point = %0,10
-- Maximum: 2500 basis point = %25
------------------------------------------------------------

SELECT
    riskbase.*,

    CASE
        WHEN riskbase.RawFraudProbabilityBasisPoints < 10
        THEN 10

        WHEN riskbase.RawFraudProbabilityBasisPoints > 2500
        THEN 2500

        ELSE riskbase.RawFraudProbabilityBasisPoints
    END AS FraudProbabilityBasisPoints

INTO #RiskProbability

FROM #RiskBase AS riskbase;

CREATE UNIQUE CLUSTERED INDEX CX_RiskProbability
    ON #RiskProbability(TestTransactionNumber);

------------------------------------------------------------
-- 6. İŞLEMİN FRAUD OLUP OLMADIĞINI BELİRLE
------------------------------------------------------------

SELECT
    probability.*,

    CASE
        WHEN probability.FraudSeed % 10000
             < probability.FraudProbabilityBasisPoints
        THEN 1
        ELSE 0
    END AS IsFraud

INTO #FraudFlag

FROM #RiskProbability AS probability;

CREATE UNIQUE CLUSTERED INDEX CX_FraudFlag
    ON #FraudFlag(TestTransactionNumber);

------------------------------------------------------------
-- 7. FRAUD SCORE HESAPLA
--
-- Fraud işlemler: ağırlıklı olarak 70–100
-- Normal işlemler: ağırlıklı olarak 5–60
------------------------------------------------------------

SELECT
    fraudflag.*,

    CAST
    (
        CASE
            WHEN fraudflag.IsFraud = 1
            THEN
                CASE
                    WHEN
                        70
                        + fraudflag.BaseRiskPoints / 3
                        + CONVERT(INT, fraudflag.ReasonSeed % 16)
                        > 100
                    THEN 100

                    ELSE
                        70
                        + fraudflag.BaseRiskPoints / 3
                        + CONVERT(INT, fraudflag.ReasonSeed % 16)
                END

            ELSE
                CASE
                    WHEN fraudflag.BaseRiskPoints > 95
                    THEN 95

                    ELSE fraudflag.BaseRiskPoints
                END
        END

        AS DECIMAL(5,2)
    ) AS FraudScore

INTO #FraudScoreResult

FROM #FraudFlag AS fraudflag;

CREATE UNIQUE CLUSTERED INDEX CX_FraudScoreResult
    ON #FraudScoreResult(TestTransactionNumber);

------------------------------------------------------------
-- 8. TRANSACTION STATUS BELİRLE
------------------------------------------------------------

SELECT
    fraudscore.*,

    CASE
        ----------------------------------------------------
        -- FRAUD OLARAK İŞARETLENEN İŞLEMLER
        ----------------------------------------------------
        WHEN fraudscore.IsFraud = 1
        THEN
            CASE
                WHEN fraudscore.StatusSeed % 10000 < 4200
                    THEN 'DECLINED'

                WHEN fraudscore.StatusSeed % 10000 < 6200
                    THEN 'REVERSED'

                WHEN fraudscore.StatusSeed % 10000 < 7200
                    THEN 'FAILED'

                WHEN fraudscore.StatusSeed % 10000 < 8000
                    THEN 'CANCELLED'

                WHEN fraudscore.StatusSeed % 10000 < 9000
                    THEN 'APPROVED'

                WHEN fraudscore.StatusSeed % 10000 < 9400
                    THEN 'REFUNDED'

                WHEN fraudscore.StatusSeed % 10000 < 9700
                    THEN 'PENDING'

                ELSE 'EXPIRED'
            END

        ----------------------------------------------------
        -- NORMAL İŞLEMLER
        ----------------------------------------------------
        ELSE
            CASE
                WHEN fraudscore.StatusSeed % 10000 < 8450
                    THEN 'APPROVED'

                WHEN fraudscore.StatusSeed % 10000 < 9250
                    THEN 'DECLINED'

                WHEN fraudscore.StatusSeed % 10000 < 9560
                    THEN 'FAILED'

                WHEN fraudscore.StatusSeed % 10000 < 9700
                    THEN 'PENDING'

                WHEN fraudscore.StatusSeed % 10000 < 9800
                    THEN 'REVERSED'

                WHEN fraudscore.StatusSeed % 10000 < 9890
                    THEN 'REFUNDED'

                WHEN fraudscore.StatusSeed % 10000 < 9970
                    THEN 'CANCELLED'

                ELSE 'EXPIRED'
            END
    END AS StatusCode

INTO #TransactionStatusCode

FROM #FraudScoreResult AS fraudscore;

CREATE UNIQUE CLUSTERED INDEX CX_TransactionStatusCode
    ON #TransactionStatusCode(TestTransactionNumber);

------------------------------------------------------------
-- 9. FRAUD NEDENİNİ BELİRLE
------------------------------------------------------------

SELECT
    statusresult.*,

    CASE
        ----------------------------------------------------
        -- NORMAL VE DÜŞÜK RİSKLİ İŞLEM
        ----------------------------------------------------
        WHEN statusresult.IsFraud = 0
         AND statusresult.FraudScore < 55
        THEN 'NO_FRAUD'

        ----------------------------------------------------
        -- CİHAZ RİSKLERİ
        ----------------------------------------------------
        WHEN statusresult.IsRootedOrJailbroken = 1
        THEN 'ROOTED_DEVICE'

        WHEN statusresult.IsEmulator = 1
        THEN 'SUSPICIOUS_DEVICE'

        WHEN statusresult.DeviceKey <> 0
         AND statusresult.IsTrustedDevice = 0
         AND statusresult.FraudScore >= 60
        THEN 'SUSPICIOUS_DEVICE'

        ----------------------------------------------------
        -- LOKASYON RİSKLERİ
        ----------------------------------------------------
        WHEN statusresult.IsInternational = 1
         AND statusresult.FraudScore >= 85
        THEN 'IMPOSSIBLE_TRAVEL'

        WHEN statusresult.IsInternational = 1
         AND statusresult.FraudScore >= 60
        THEN 'LOCATION_MISMATCH'

        ----------------------------------------------------
        -- MERCHANT RİSKİ
        ----------------------------------------------------
        WHEN statusresult.MerchantRiskLevel IN
        (
            'High',
            'Critical'
        )
         AND statusresult.FraudScore >= 60
        THEN 'MERCHANT_RISK'

        ----------------------------------------------------
        -- OLAĞANDIŞI TUTAR
        ----------------------------------------------------
        WHEN statusresult.AmountTRY >= 20000
         AND statusresult.FraudScore >= 55
        THEN 'UNUSUAL_AMOUNT'

        ----------------------------------------------------
        -- ÇOKLU REDDEDİLEN DENEME
        ----------------------------------------------------
        WHEN statusresult.StatusCode = 'DECLINED'
         AND statusresult.FraudScore >= 55
         AND statusresult.ReasonSeed % 100 < 40
        THEN 'MULTIPLE_DECLINES'

        ----------------------------------------------------
        -- 3D SECURE BAŞARISIZLIĞI
        ----------------------------------------------------
        WHEN statusresult.Is3DSecure = 0
         AND statusresult.PaymentChannelCode IN
        (
            'ECOMMERCE',
            'PAYMENT_LINK',
            'MOBILE_APP'
        )
         AND statusresult.FraudScore >= 55
        THEN 'THREEDS_FAILURE'

        ----------------------------------------------------
        -- DİĞER YÜKSEK RİSK NEDENLERİ
        ----------------------------------------------------
        ELSE
            CASE statusresult.ReasonSeed % 5
                WHEN 0 THEN 'ACCOUNT_TAKEOVER'
                WHEN 1 THEN 'STOLEN_CARD'
                WHEN 2 THEN 'HIGH_VELOCITY'
                WHEN 3 THEN 'IDENTITY_MISMATCH'
                ELSE 'UNUSUAL_AMOUNT'
            END
    END AS FraudReasonCode

INTO #FraudReasonResult

FROM #TransactionStatusCode AS statusresult;

CREATE UNIQUE CLUSTERED INDEX CX_FraudReasonResult
    ON #FraudReasonResult(TestTransactionNumber);

------------------------------------------------------------
-- 10. DIMENSION KEY'LERİNİ BAĞLA
------------------------------------------------------------

SELECT
    reasonresult.*,

    transactionstatus.TransactionStatusKey,
    fraudreason.FraudReasonKey

INTO #TransactionRiskStatus

FROM #FraudReasonResult AS reasonresult

INNER JOIN dw.DimTransactionStatus AS transactionstatus
    ON transactionstatus.StatusCode =
       reasonresult.StatusCode

INNER JOIN dw.DimFraudReason AS fraudreason
    ON fraudreason.FraudReasonCode =
       reasonresult.FraudReasonCode;

CREATE UNIQUE CLUSTERED INDEX CX_TransactionRiskStatus
    ON #TransactionRiskStatus(TestTransactionNumber);

------------------------------------------------------------
-- 11. SATIR SAYISI KONTROLÜ
------------------------------------------------------------

SELECT
    (SELECT COUNT(*) FROM #TransactionSecurity)
        AS TransactionSecurityCount,

    (SELECT COUNT(*) FROM #RiskBase)
        AS RiskBaseCount,

    (SELECT COUNT(*) FROM #FraudFlag)
        AS FraudFlagCount,

    (SELECT COUNT(*) FROM #FraudScoreResult)
        AS FraudScoreCount,

    (SELECT COUNT(*) FROM #FraudReasonResult)
        AS FraudReasonCount,

    (SELECT COUNT(*) FROM #TransactionRiskStatus)
        AS TransactionRiskStatusCount;

------------------------------------------------------------
-- 12. FRAUD ORANI
------------------------------------------------------------

SELECT
    COUNT(*) AS TotalTransactionCount,

    SUM
    (
        CONVERT
        (
            INT,
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
                INT,
                IsFraud
            )
        )
        /
        COUNT(*)

        AS DECIMAL(8,4)
    ) AS FraudPercentage,

    CAST
    (
        AVG(FraudScore)
        AS DECIMAL(8,2)
    ) AS AverageFraudScore

FROM #TransactionRiskStatus;

------------------------------------------------------------
-- 13. FRAUD VE NORMAL İŞLEMLERİN SKORLARI
------------------------------------------------------------

SELECT
    IsFraud,

    CASE
        WHEN IsFraud = 1
        THEN N'Fraud'

        ELSE N'Fraud değil'
    END AS FraudStatus,

    COUNT(*) AS TransactionCount,

    MIN(FraudScore) AS MinimumFraudScore,

    CAST
    (
        AVG(FraudScore)
        AS DECIMAL(8,2)
    ) AS AverageFraudScore,

    MAX(FraudScore) AS MaximumFraudScore

FROM #TransactionRiskStatus

GROUP BY IsFraud

ORDER BY IsFraud DESC;

------------------------------------------------------------
-- 14. TRANSACTION STATUS DAĞILIMI
------------------------------------------------------------

SELECT
    StatusCode,

    COUNT(*) AS TransactionCount,

    CAST
    (
        100.0
        *
        COUNT(*)
        /
        SUM(COUNT(*)) OVER ()

        AS DECIMAL(6,2)
    ) AS TransactionPercentage

FROM #TransactionRiskStatus

GROUP BY StatusCode

ORDER BY TransactionCount DESC;

------------------------------------------------------------
-- 15. FRAUD NEDENİ DAĞILIMI
------------------------------------------------------------

SELECT
    FraudReasonCode,

    COUNT(*) AS TransactionCount,

    SUM
    (
        CONVERT
        (
            INT,
            IsFraud
        )
    ) AS ConfirmedFraudCount,

    CAST
    (
        AVG(FraudScore)
        AS DECIMAL(8,2)
    ) AS AverageFraudScore

FROM #TransactionRiskStatus

GROUP BY FraudReasonCode

ORDER BY TransactionCount DESC;

------------------------------------------------------------
-- 16. MÜŞTERİ RİSK SEVİYESİNE GÖRE FRAUD
------------------------------------------------------------

SELECT
    CustomerRiskLevel,

    COUNT(*) AS TransactionCount,

    SUM
    (
        CONVERT
        (
            INT,
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
                INT,
                IsFraud
            )
        )
        /
        COUNT(*)

        AS DECIMAL(8,4)
    ) AS FraudPercentage

FROM #TransactionRiskStatus

GROUP BY CustomerRiskLevel

ORDER BY FraudPercentage DESC;

------------------------------------------------------------
-- 17. MERCHANT RİSK SEVİYESİNE GÖRE FRAUD
------------------------------------------------------------

SELECT
    MerchantRiskLevel,

    COUNT(*) AS TransactionCount,

    SUM
    (
        CONVERT
        (
            INT,
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
                INT,
                IsFraud
            )
        )
        /
        COUNT(*)

        AS DECIMAL(8,4)
    ) AS FraudPercentage

FROM #TransactionRiskStatus

GROUP BY MerchantRiskLevel

ORDER BY FraudPercentage DESC;

------------------------------------------------------------
-- 18. KANALA GÖRE FRAUD ORANI
------------------------------------------------------------

SELECT
    PaymentChannelCode,

    COUNT(*) AS TransactionCount,

    SUM
    (
        CONVERT
        (
            INT,
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
                INT,
                IsFraud
            )
        )
        /
        COUNT(*)

        AS DECIMAL(8,4)
    ) AS FraudPercentage

FROM #TransactionRiskStatus

GROUP BY PaymentChannelCode

ORDER BY FraudPercentage DESC;

------------------------------------------------------------
-- 19. FRAUD İŞLEMDE NO_FRAUD KONTROLÜ
------------------------------------------------------------

SELECT
    COUNT(*) AS InvalidFraudReasonCount

FROM #TransactionRiskStatus

WHERE IsFraud = 1
  AND FraudReasonCode = 'NO_FRAUD';

------------------------------------------------------------
-- 20. FRAUD SCORE ARALIĞI KONTROLÜ
------------------------------------------------------------

SELECT
    COUNT(*) AS InvalidFraudScoreCount

FROM #TransactionRiskStatus

WHERE FraudScore < 0
   OR FraudScore > 100
   OR FraudScore IS NULL;

------------------------------------------------------------
-- 21. DIMENSION KEY KONTROLÜ
------------------------------------------------------------

SELECT
    COUNT(*) AS MissingDimensionKeyCount

FROM #TransactionRiskStatus

WHERE TransactionStatusKey IS NULL
   OR FraudReasonKey IS NULL;

------------------------------------------------------------
-- 22. ÖRNEK YÜKSEK RİSKLİ İŞLEMLER
------------------------------------------------------------

SELECT TOP (25)
    TestTransactionNumber,

    TransactionTimestamp,

    CustomerID,
    CustomerRiskLevel,

    MerchantID,
    MerchantRiskLevel,

    PaymentChannelCode,
    AmountTRY,

    DeviceType,
    IsTrustedDevice,
    IsEmulator,
    IsRootedOrJailbroken,

    IsInternational,
    Is3DSecure,

    FraudScore,
    IsFraud,
    FraudReasonCode,
    StatusCode

FROM #TransactionRiskStatus

ORDER BY
    FraudScore DESC,
    AmountTRY DESC;

SET NOCOUNT OFF;

------------------------------------------------------------
-- PHASE 10F
-- AUTHORIZATION, SETTLEMENT VE FINANSAL HESAPLAMALAR
------------------------------------------------------------

SET NOCOUNT ON;

------------------------------------------------------------
-- 1. ÖN KONTROL
------------------------------------------------------------

IF OBJECT_ID('tempdb..#TransactionRiskStatus') IS NULL
BEGIN
    THROW 50501,
          '#TransactionRiskStatus bulunamadı. Önce Phase 10E aynı sekmede çalıştırılmalıdır.',
          1;
END;

------------------------------------------------------------
-- 2. ÖNCEKİ PHASE 10F TABLOLARINI TEMİZLE
------------------------------------------------------------

DROP TABLE IF EXISTS #AuthorizationBase;
DROP TABLE IF EXISTS #AuthorizationResult;
DROP TABLE IF EXISTS #SettlementResult;
DROP TABLE IF EXISTS #CommissionParameters;
DROP TABLE IF EXISTS #FinancialBase;
DROP TABLE IF EXISTS #CashbackRaw;
DROP TABLE IF EXISTS #FinancialResult;
DROP TABLE IF EXISTS #InstallmentResult;
DROP TABLE IF EXISTS #TransactionFinancial;

------------------------------------------------------------
-- 3. AUTHORIZATION SÜRESİNİ HESAPLA
--
-- Approved, Declined, Reversed ve Refunded işlemler
-- authorization yanıtına sahiptir.
--
-- Failed işlemlerin bir kısmı authorization sırasında
-- teknik hata yaşamış olabilir.
------------------------------------------------------------

SELECT
    source.*,

    CASE
        WHEN source.StatusCode IN
        (
            'APPROVED',
            'DECLINED',
            'REVERSED',
            'REFUNDED'
        )
        THEN
            80
            +
            CONVERT
            (
                INT,
                source.TimingSeed % 2500
            )

        WHEN source.StatusCode = 'FAILED'
         AND source.TimingSeed % 100 < 40
        THEN
            500
            +
            CONVERT
            (
                INT,
                source.TimingSeed % 8000
            )

        ELSE NULL
    END AS AuthorizationDurationMs

INTO #AuthorizationBase

FROM #TransactionRiskStatus AS source;

CREATE UNIQUE CLUSTERED INDEX CX_AuthorizationBase
    ON #AuthorizationBase(TestTransactionNumber);

------------------------------------------------------------
-- 4. AUTHORIZATION TIMESTAMP OLUŞTUR
------------------------------------------------------------

SELECT
    authbase.*,

    CASE
        WHEN authbase.AuthorizationDurationMs IS NOT NULL
        THEN
            DATEADD
            (
                MILLISECOND,
                authbase.AuthorizationDurationMs,
                authbase.TransactionTimestamp
            )

        ELSE NULL
    END AS AuthorizationTimestamp

INTO #AuthorizationResult

FROM #AuthorizationBase AS authbase;

CREATE UNIQUE CLUSTERED INDEX CX_AuthorizationResult
    ON #AuthorizationResult(TestTransactionNumber);

------------------------------------------------------------
-- 5. SETTLEMENT TIMESTAMP OLUŞTUR
--
-- Approved:
-- Authorization sonrasında yaklaşık 1–3 gün
--
-- Reversed:
-- Authorization sonrasında 5 dakika–1 gün
--
-- Refunded:
-- Authorization sonrasında yaklaşık 3–30 gün
------------------------------------------------------------

SELECT
    authresult.*,

    CASE
        WHEN authresult.StatusCode = 'APPROVED'
        THEN
            DATEADD
            (
                MINUTE,

                (
                    1440
                    *
                    (
                        1
                        +
                        CONVERT
                        (
                            INT,
                            authresult.TimingSeed % 3
                        )
                    )
                )
                +
                CONVERT
                (
                    INT,
                    authresult.TimingSeed % 720
                ),

                authresult.AuthorizationTimestamp
            )

        WHEN authresult.StatusCode = 'REVERSED'
        THEN
            DATEADD
            (
                MINUTE,

                5
                +
                CONVERT
                (
                    INT,
                    authresult.TimingSeed % 1436
                ),

                authresult.AuthorizationTimestamp
            )

        WHEN authresult.StatusCode = 'REFUNDED'
        THEN
            DATEADD
            (
                MINUTE,

                (
                    1440
                    *
                    (
                        3
                        +
                        CONVERT
                        (
                            INT,
                            authresult.TimingSeed % 28
                        )
                    )
                )
                +
                CONVERT
                (
                    INT,
                    authresult.TimingSeed % 720
                ),

                authresult.AuthorizationTimestamp
            )

        ELSE NULL
    END AS SettlementTimestamp

INTO #SettlementResult

FROM #AuthorizationResult AS authresult;

CREATE UNIQUE CLUSTERED INDEX CX_SettlementResult
    ON #SettlementResult(TestTransactionNumber);

------------------------------------------------------------
-- 6. KOMİSYON ORANLARINI BELİRLE
------------------------------------------------------------

SELECT
    settlement.*,

    CAST
    (
        CASE settlement.PaymentChannelCode
            WHEN 'POS'             THEN 0.0120
            WHEN 'CONTACTLESS_POS' THEN 0.0110
            WHEN 'ECOMMERCE'       THEN 0.0220
            WHEN 'MOBILE_APP'      THEN 0.0180
            WHEN 'DIGITAL_WALLET'  THEN 0.0160
            WHEN 'QR_PAYMENT'      THEN 0.0130
            WHEN 'RECURRING'       THEN 0.0150
            WHEN 'PAYMENT_LINK'    THEN 0.0200
            WHEN 'MOTO'            THEN 0.0250
            WHEN 'ATM'             THEN 0.0080
            ELSE 0.0150
        END

        AS DECIMAL(10,6)
    ) AS BaseCommissionRate,

    CAST
    (
        CASE settlement.MerchantSize
            WHEN 'Micro'      THEN 1.15
            WHEN 'Small'      THEN 1.05
            WHEN 'Medium'     THEN 0.95
            WHEN 'Large'      THEN 0.85
            WHEN 'Enterprise' THEN 0.75
            ELSE 1.00
        END

        AS DECIMAL(10,6)
    ) AS MerchantSizeFactor

INTO #CommissionParameters

FROM #SettlementResult AS settlement;

CREATE UNIQUE CLUSTERED INDEX CX_CommissionParameters
    ON #CommissionParameters(TestTransactionNumber);

------------------------------------------------------------
-- 7. FEE VE MERCHANT KOMİSYONUNU HESAPLA
--
-- Bu sentetik modelde yalnızca Approved işlemler
-- finansal gelir oluşturur.
------------------------------------------------------------

SELECT
    parameters.*,

    CAST
    (
        CASE
            WHEN parameters.StatusCode <> 'APPROVED'
            THEN 0

            WHEN parameters.PaymentChannelCode = 'ATM'
            THEN
                15
                +
                CONVERT
                (
                    DECIMAL(19,4),
                    parameters.FinancialSeed % 35
                )

            WHEN parameters.IsInternational = 1
            THEN
                ROUND
                (
                    parameters.AmountTRY * 0.0050,
                    4
                )

            WHEN parameters.PaymentChannelCode = 'MOTO'
            THEN
                ROUND
                (
                    parameters.AmountTRY * 0.0030,
                    4
                )

            ELSE 0
        END

        AS DECIMAL(19,4)
    ) AS FeeAmountTRY,

    CAST
    (
        CASE
            WHEN parameters.StatusCode <> 'APPROVED'
            THEN 0

            ELSE
                ROUND
                (
                    parameters.AmountTRY
                    *
                    parameters.BaseCommissionRate
                    *
                    parameters.MerchantSizeFactor,
                    4
                )
        END

        AS DECIMAL(19,4)
    ) AS MerchantCommissionTRY

INTO #FinancialBase

FROM #CommissionParameters AS parameters;

CREATE UNIQUE CLUSTERED INDEX CX_FinancialBase
    ON #FinancialBase(TestTransactionNumber);

------------------------------------------------------------
-- 8. HAM CASHBACK TUTARINI HESAPLA
------------------------------------------------------------

SELECT
    financial.*,

    CAST
    (
        CASE
            WHEN financial.StatusCode <> 'APPROVED'
            THEN 0

            WHEN financial.CustomerSegment = 'Standard'
             AND financial.CashbackSeed % 100 < 5
            THEN financial.AmountTRY * 0.0025

            WHEN financial.CustomerSegment = 'Silver'
             AND financial.CashbackSeed % 100 < 10
            THEN financial.AmountTRY * 0.0050

            WHEN financial.CustomerSegment = 'Gold'
             AND financial.CashbackSeed % 100 < 20
            THEN financial.AmountTRY * 0.0100

            WHEN financial.CustomerSegment = 'Platinum'
             AND financial.CashbackSeed % 100 < 30
            THEN financial.AmountTRY * 0.0150

            ELSE 0
        END

        AS DECIMAL(19,4)
    ) AS RawCashbackAmountTRY

INTO #CashbackRaw

FROM #FinancialBase AS financial;

CREATE UNIQUE CLUSTERED INDEX CX_CashbackRaw
    ON #CashbackRaw(TestTransactionNumber);

------------------------------------------------------------
-- 9. VERGİ VE NİHAİ CASHBACK TUTARI
--
-- TaxAmountTRY:
-- Merchant komisyonunun %20'si olarak modellenmiştir.
--
-- Cashback:
-- İşlem başına en fazla 500 TRY ile sınırlandırılmıştır.
------------------------------------------------------------

SELECT
    cashback.*,

    CAST
    (
        ROUND
        (
            cashback.MerchantCommissionTRY * 0.20,
            4
        )

        AS DECIMAL(19,4)
    ) AS TaxAmountTRY,

    CAST
    (
        CASE
            WHEN cashback.RawCashbackAmountTRY > 500
            THEN 500

            ELSE
                ROUND
                (
                    cashback.RawCashbackAmountTRY,
                    4
                )
        END

        AS DECIMAL(19,4)
    ) AS CashbackAmountTRY

INTO #FinancialResult

FROM #CashbackRaw AS cashback;

CREATE UNIQUE CLUSTERED INDEX CX_FinancialResult
    ON #FinancialResult(TestTransactionNumber);

------------------------------------------------------------
-- 10. TAKSİT SAYISINI BELİRLE
--
-- Yalnızca:
-- Approved
-- Credit card
-- TRY
-- Belirli kategoriler
-- 1.000 TRY üzeri işlemler
--
-- taksitli olabilir.
------------------------------------------------------------

SELECT
    financialresult.*,

    CONVERT
    (
        TINYINT,

        CASE
            WHEN financialresult.StatusCode = 'APPROVED'
             AND financialresult.CardType = 'Credit'
             AND financialresult.CurrencyCode = 'TRY'
             AND financialresult.AmountTRY >= 1000
             AND financialresult.MerchantCategory IN
             (
                 'Fashion',
                 'Electronics',
                 'Travel',
                 'Accommodation',
                 'Healthcare',
                 'Education',
                 'Home and Living'
             )
             AND financialresult.InstallmentSeed % 100 < 38
            THEN
                CASE
                    WHEN financialresult.InstallmentSeed % 100 < 13
                    THEN 3

                    WHEN financialresult.InstallmentSeed % 100 < 25
                    THEN 6

                    WHEN financialresult.InstallmentSeed % 100 < 33
                    THEN 9

                    ELSE 12
                END

            ELSE 1
        END
    ) AS InstallmentCount

INTO #InstallmentResult

FROM #FinancialResult AS financialresult;

CREATE UNIQUE CLUSTERED INDEX CX_InstallmentResult
    ON #InstallmentResult(TestTransactionNumber);

------------------------------------------------------------
-- 11. DATE KEY DEĞERLERİNİ OLUŞTUR
------------------------------------------------------------

SELECT
    installment.*,

    CONVERT
    (
        INT,
        CONVERT
        (
            CHAR(8),
            installment.TransactionDate,
            112
        )
    ) AS TransactionDateKey,

    CASE
        WHEN installment.AuthorizationTimestamp IS NOT NULL
        THEN
            CONVERT
            (
                INT,
                CONVERT
                (
                    CHAR(8),
                    CONVERT
                    (
                        DATE,
                        installment.AuthorizationTimestamp
                    ),
                    112
                )
            )

        ELSE NULL
    END AS AuthorizationDateKey,

    CASE
        WHEN installment.SettlementTimestamp IS NOT NULL
        THEN
            CONVERT
            (
                INT,
                CONVERT
                (
                    CHAR(8),
                    CONVERT
                    (
                        DATE,
                        installment.SettlementTimestamp
                    ),
                    112
                )
            )

        ELSE NULL
    END AS SettlementDateKey

INTO #TransactionFinancial

FROM #InstallmentResult AS installment;

CREATE UNIQUE CLUSTERED INDEX CX_TransactionFinancial
    ON #TransactionFinancial(TestTransactionNumber);

------------------------------------------------------------
-- 12. SATIR SAYISI KONTROLÜ
------------------------------------------------------------

SELECT
    (SELECT COUNT(*) FROM #TransactionRiskStatus)
        AS TransactionRiskStatusCount,

    (SELECT COUNT(*) FROM #AuthorizationResult)
        AS AuthorizationResultCount,

    (SELECT COUNT(*) FROM #SettlementResult)
        AS SettlementResultCount,

    (SELECT COUNT(*) FROM #FinancialResult)
        AS FinancialResultCount,

    (SELECT COUNT(*) FROM #InstallmentResult)
        AS InstallmentResultCount,

    (SELECT COUNT(*) FROM #TransactionFinancial)
        AS TransactionFinancialCount;

------------------------------------------------------------
-- 13. AUTHORIZATION TIMESTAMP TUTARLILIĞI
------------------------------------------------------------

SELECT
    COUNT(*) AS InvalidAuthorizationTimestampCount

FROM #TransactionFinancial

WHERE AuthorizationTimestamp IS NOT NULL
  AND AuthorizationTimestamp < TransactionTimestamp;

------------------------------------------------------------
-- 14. SETTLEMENT TIMESTAMP TUTARLILIĞI
------------------------------------------------------------

SELECT
    COUNT(*) AS InvalidSettlementTimestampCount

FROM #TransactionFinancial

WHERE SettlementTimestamp IS NOT NULL
  AND
  (
      AuthorizationTimestamp IS NULL
      OR SettlementTimestamp < AuthorizationTimestamp
  );

------------------------------------------------------------
-- 15. STATUS VE AUTHORIZATION KONTROLÜ
------------------------------------------------------------

SELECT
    COUNT(*) AS MissingRequiredAuthorizationCount

FROM #TransactionFinancial

WHERE StatusCode IN
(
    'APPROVED',
    'DECLINED',
    'REVERSED',
    'REFUNDED'
)
AND AuthorizationTimestamp IS NULL;

------------------------------------------------------------
-- 16. STATUS VE SETTLEMENT KONTROLÜ
------------------------------------------------------------

SELECT
    COUNT(*) AS MissingRequiredSettlementCount

FROM #TransactionFinancial

WHERE StatusCode IN
(
    'APPROVED',
    'REVERSED',
    'REFUNDED'
)
AND SettlementTimestamp IS NULL;

------------------------------------------------------------
-- 17. SETTLEMENT OLMAMASI GEREKEN STATUS KONTROLÜ
------------------------------------------------------------

SELECT
    COUNT(*) AS UnexpectedSettlementCount

FROM #TransactionFinancial

WHERE StatusCode IN
(
    'DECLINED',
    'FAILED',
    'PENDING',
    'CANCELLED',
    'EXPIRED'
)
AND SettlementTimestamp IS NOT NULL;

------------------------------------------------------------
-- 18. FİNANSAL TUTAR KONTROLÜ
------------------------------------------------------------

SELECT
    COUNT(*) AS InvalidFinancialAmountCount

FROM #TransactionFinancial

WHERE FeeAmountTRY < 0
   OR MerchantCommissionTRY < 0
   OR TaxAmountTRY < 0
   OR CashbackAmountTRY < 0
   OR InstallmentCount NOT BETWEEN 1 AND 36;

------------------------------------------------------------
-- 19. APPROVED OLMAYAN İŞLEMLERDE GELİR KONTROLÜ
------------------------------------------------------------

SELECT
    COUNT(*) AS InvalidNonApprovedFinancialCount

FROM #TransactionFinancial

WHERE StatusCode <> 'APPROVED'
  AND
  (
      FeeAmountTRY <> 0
      OR MerchantCommissionTRY <> 0
      OR TaxAmountTRY <> 0
      OR CashbackAmountTRY <> 0
  );

------------------------------------------------------------
-- 20. TAKSİT TUTARLILIĞI
------------------------------------------------------------

SELECT
    COUNT(*) AS InvalidInstallmentCount

FROM #TransactionFinancial

WHERE InstallmentCount > 1
  AND
  (
      StatusCode <> 'APPROVED'
      OR CardType <> 'Credit'
      OR CurrencyCode <> 'TRY'
      OR AmountTRY < 1000
  );

------------------------------------------------------------
-- 21. DIMDATE KEY KONTROLÜ
------------------------------------------------------------

SELECT
    COUNT(*) AS MissingTransactionDateKeyCount

FROM #TransactionFinancial AS transactionfinancial

LEFT JOIN dw.DimDate AS dimdate
    ON dimdate.DateKey =
       transactionfinancial.TransactionDateKey

WHERE dimdate.DateKey IS NULL;

------------------------------------------------------------
-- 22. AUTHORIZATION DATE KEY KONTROLÜ
------------------------------------------------------------

SELECT
    COUNT(*) AS MissingAuthorizationDateKeyCount

FROM #TransactionFinancial AS transactionfinancial

LEFT JOIN dw.DimDate AS dimdate
    ON dimdate.DateKey =
       transactionfinancial.AuthorizationDateKey

WHERE transactionfinancial.AuthorizationDateKey IS NOT NULL
  AND dimdate.DateKey IS NULL;

------------------------------------------------------------
-- 23. SETTLEMENT DATE KEY KONTROLÜ
------------------------------------------------------------

SELECT
    COUNT(*) AS MissingSettlementDateKeyCount

FROM #TransactionFinancial AS transactionfinancial

LEFT JOIN dw.DimDate AS dimdate
    ON dimdate.DateKey =
       transactionfinancial.SettlementDateKey

WHERE transactionfinancial.SettlementDateKey IS NOT NULL
  AND dimdate.DateKey IS NULL;

------------------------------------------------------------
-- 24. STATUS BAZINDA TIMESTAMP ÖZETİ
------------------------------------------------------------

SELECT
    StatusCode,

    COUNT(*) AS TransactionCount,

    COUNT(AuthorizationTimestamp)
        AS AuthorizationTimestampCount,

    COUNT(SettlementTimestamp)
        AS SettlementTimestampCount,

    CAST
    (
        AVG
        (
            CONVERT
            (
                DECIMAL(19,2),
                AuthorizationDurationMs
            )
        )

        AS DECIMAL(19,2)
    ) AS AverageAuthorizationDurationMs

FROM #TransactionFinancial

GROUP BY StatusCode

ORDER BY TransactionCount DESC;

------------------------------------------------------------
-- 25. FİNANSAL ÖZET
------------------------------------------------------------

SELECT
    SUM(AmountTRY)
        AS TotalTransactionVolumeTRY,

    SUM(FeeAmountTRY)
        AS TotalFeeAmountTRY,

    SUM(MerchantCommissionTRY)
        AS TotalMerchantCommissionTRY,

    SUM(TaxAmountTRY)
        AS TotalTaxAmountTRY,

    SUM(CashbackAmountTRY)
        AS TotalCashbackAmountTRY,

    CAST
    (
        AVG(AmountTRY)
        AS DECIMAL(19,2)
    ) AS AverageTransactionAmountTRY

FROM #TransactionFinancial;

------------------------------------------------------------
-- 26. TAKSİT DAĞILIMI
------------------------------------------------------------

SELECT
    InstallmentCount,
    COUNT(*) AS TransactionCount,

    CAST
    (
        100.0
        *
        COUNT(*)
        /
        SUM(COUNT(*)) OVER ()

        AS DECIMAL(6,2)
    ) AS TransactionPercentage

FROM #TransactionFinancial

GROUP BY InstallmentCount

ORDER BY InstallmentCount;

------------------------------------------------------------
-- 27. KANAL BAZINDA KOMİSYON
------------------------------------------------------------

SELECT
    PaymentChannelCode,

    COUNT(*) AS TransactionCount,

    SUM(AmountTRY) AS TotalAmountTRY,

    SUM(MerchantCommissionTRY)
        AS TotalMerchantCommissionTRY,

    CAST
    (
        AVG(MerchantCommissionTRY)
        AS DECIMAL(19,4)
    ) AS AverageMerchantCommissionTRY

FROM #TransactionFinancial

GROUP BY PaymentChannelCode

ORDER BY TotalMerchantCommissionTRY DESC;

------------------------------------------------------------
-- 28. ÖRNEK SONUÇLAR
------------------------------------------------------------

SELECT TOP (25)
    TestTransactionNumber,

    TransactionTimestamp,
    AuthorizationTimestamp,
    SettlementTimestamp,

    TransactionDateKey,
    AuthorizationDateKey,
    SettlementDateKey,

    CustomerID,
    CardID,
    MerchantID,

    StatusCode,
    AmountTRY,

    FeeAmountTRY,
    MerchantCommissionTRY,
    TaxAmountTRY,
    CashbackAmountTRY,

    InstallmentCount

FROM #TransactionFinancial

ORDER BY TestTransactionNumber;

SET NOCOUNT OFF;




------------------------------------------------------------
-- PHASE 10G
-- 10.000 TEST TRANSACTION'I FACT TABLOSUNA EKLEME
------------------------------------------------------------

SET NOCOUNT ON;
SET XACT_ABORT ON;

------------------------------------------------------------
-- 1. ÖN KONTROLLER
------------------------------------------------------------

IF OBJECT_ID('tempdb..#TransactionFinancial') IS NULL
BEGIN
    THROW 50601,
          '#TransactionFinancial bulunamadı. Önce Phase 10F aynı sekmede çalıştırılmalıdır.',
          1;
END;

IF OBJECT_ID('dw.FactPaymentTransaction') IS NULL
BEGIN
    THROW 50602,
          'dw.FactPaymentTransaction tablosu bulunamadı.',
          1;
END;

IF
(
    SELECT COUNT(*)
    FROM #TransactionFinancial
) <> 10000
BEGIN
    THROW 50603,
          '#TransactionFinancial tablosunda tam olarak 10.000 test kaydı bulunmalıdır.',
          1;
END;

------------------------------------------------------------
-- 2. FACT YÜKLEMESİ
------------------------------------------------------------

BEGIN TRY

    BEGIN TRANSACTION;

    --------------------------------------------------------
    -- DAHA ÖNCE EKLENMİŞ TEST KAYITLARINI TEMİZLE
    --
    -- Gerçek veya ileride üretilecek 1 milyonluk kayıtlar
    -- bu DELETE işleminden etkilenmez.
    --------------------------------------------------------

    DELETE FROM dw.FactPaymentTransaction
    WHERE SourceSystem = 'SyntheticGeneratorTestV1'
       OR TransactionID LIKE 'TXN-TEST-%';

    --------------------------------------------------------
    -- TEST KAYITLARINI FACT TABLOSUNA EKLE
    --------------------------------------------------------

INSERT INTO dw.FactPaymentTransaction
(
    TransactionID,                 -- 1
    TransactionReference,          -- 2

    TransactionDateKey,            -- 3
    AuthorizationDateKey,          -- 4
    SettlementDateKey,             -- 5

    CustomerKey,                   -- 6
    CardKey,                       -- 7
    MerchantKey,                   -- 8

    PaymentChannelKey,             -- 9
    CurrencyKey,                   -- 10
    TransactionStatusKey,          -- 11

    DeviceKey,                     -- 12
    FraudReasonKey,                -- 13

    TransactionTimestamp,          -- 14
    AuthorizationTimestamp,        -- 15
    SettlementTimestamp,           -- 16

    OriginalAmount,                -- 17
    ExchangeRateToTRY,             -- 18
    AmountTRY,                     -- 19

    FeeAmountTRY,                  -- 20
    MerchantCommissionTRY,         -- 21
    TaxAmountTRY,                  -- 22
    CashbackAmountTRY,             -- 23

    InstallmentCount,              -- 24
    TransactionCount,              -- 25
    AuthorizationDurationMs,       -- 26

    IsInternational,               -- 27
    IsContactless,                 -- 28
    IsRecurring,                   -- 29
    Is3DSecure,                    -- 30
    IsTokenized,                   -- 31
    IsFraud,                       -- 32

    FraudScore,                    -- 33
    SourceSystem                   -- 34
)
SELECT
    CONCAT
    (
        'TXN-TEST-',
        RIGHT
        (
            REPLICATE('0', 12)
            + CONVERT
            (
                VARCHAR(12),
                source.TestTransactionNumber
            ),
            12
        )
    ) AS TransactionID,            -- 1

    CONCAT
    (
        'REF-TEST-',
        CONVERT
        (
            CHAR(8),
            source.TransactionDate,
            112
        ),
        '-',
        RIGHT
        (
            REPLICATE('0', 10)
            + CONVERT
            (
                VARCHAR(10),
                source.TestTransactionNumber
            ),
            10
        )
    ) AS TransactionReference,     -- 2

    source.TransactionDateKey,     -- 3
    source.AuthorizationDateKey,   -- 4
    source.SettlementDateKey,      -- 5

    source.CustomerKey,            -- 6
    source.CardKey,                -- 7
    source.MerchantKey,            -- 8

    source.PaymentChannelKey,      -- 9
    source.CurrencyKey,            -- 10
    source.TransactionStatusKey,   -- 11

    source.DeviceKey,              -- 12
    source.FraudReasonKey,         -- 13

    source.TransactionTimestamp,   -- 14
    source.AuthorizationTimestamp, -- 15
    source.SettlementTimestamp,    -- 16

    source.OriginalAmount,         -- 17
    source.ExchangeRateToTRY,      -- 18
    source.AmountTRY,              -- 19

    source.FeeAmountTRY,           -- 20
    source.MerchantCommissionTRY,  -- 21
    source.TaxAmountTRY,           -- 22
    source.CashbackAmountTRY,      -- 23

    source.InstallmentCount,       -- 24
    CONVERT(TINYINT, 1),           -- 25 TransactionCount
    source.AuthorizationDurationMs,-- 26

    source.IsInternational,        -- 27
    source.IsContactless,          -- 28
    source.IsRecurring,            -- 29
    source.Is3DSecure,             -- 30
    source.IsTokenized,            -- 31
    source.IsFraud,                -- 32

    source.FraudScore,             -- 33
    'SyntheticGeneratorTestV1'     -- 34 SourceSystem

FROM #TransactionFinancial AS source;

    DECLARE @InsertedRowCount INT = @@ROWCOUNT;

    --------------------------------------------------------
    -- BEKLENEN SAYI EKLENMEDİYSE TRANSACTION'I DURDUR
    --------------------------------------------------------

    IF @InsertedRowCount <> 10000
    BEGIN
        THROW 50604,
              'Fact tablosuna eklenen test kaydı sayısı 10.000 değildir.',
              1;
    END;

    COMMIT TRANSACTION;

    PRINT '10.000 test transaction başarıyla eklendi.';

END TRY

BEGIN CATCH

    IF XACT_STATE() <> 0
    BEGIN
        ROLLBACK TRANSACTION;
    END;

    THROW;

END CATCH;

------------------------------------------------------------
-- 3. FACT SATIR SAYISI KONTROLÜ
------------------------------------------------------------

SELECT
    COUNT(*) AS TestFactRowCount,

    MIN(TransactionTimestamp)
        AS FirstTransactionTimestamp,

    MAX(TransactionTimestamp)
        AS LastTransactionTimestamp,

    SUM(TransactionCount)
        AS TotalTransactionCount

FROM dw.FactPaymentTransaction

WHERE SourceSystem = 'SyntheticGeneratorTestV1';

------------------------------------------------------------
-- 4. TRANSACTION ID TEKRARI KONTROLÜ
------------------------------------------------------------

SELECT
    TransactionID,
    COUNT(*) AS DuplicateCount

FROM dw.FactPaymentTransaction

WHERE SourceSystem = 'SyntheticGeneratorTestV1'

GROUP BY TransactionID

HAVING COUNT(*) > 1;

------------------------------------------------------------
-- 5. STATUS DAĞILIMI
------------------------------------------------------------

SELECT
    status.StatusCode,
    status.StatusName,

    COUNT(*) AS TransactionCount,

    CAST
    (
        100.0
        *
        COUNT(*)
        /
        SUM(COUNT(*)) OVER ()

        AS DECIMAL(6,2)
    ) AS TransactionPercentage

FROM dw.FactPaymentTransaction AS fact

INNER JOIN dw.DimTransactionStatus AS status
    ON status.TransactionStatusKey =
       fact.TransactionStatusKey

WHERE fact.SourceSystem = 'SyntheticGeneratorTestV1'

GROUP BY
    status.StatusCode,
    status.StatusName

ORDER BY TransactionCount DESC;

------------------------------------------------------------
-- 6. FRAUD ÖZETİ
------------------------------------------------------------

SELECT
    COUNT(*) AS TotalTransactionCount,

    SUM
    (
        CONVERT
        (
            INT,
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
                INT,
                IsFraud
            )
        )
        /
        COUNT(*)

        AS DECIMAL(8,4)
    ) AS FraudPercentage,

    CAST
    (
        AVG(FraudScore)
        AS DECIMAL(8,2)
    ) AS AverageFraudScore

FROM dw.FactPaymentTransaction

WHERE SourceSystem = 'SyntheticGeneratorTestV1';

------------------------------------------------------------
-- 7. FİNANSAL ÖZET
------------------------------------------------------------

SELECT
    SUM(AmountTRY)
        AS TotalTransactionVolumeTRY,

    SUM(FeeAmountTRY)
        AS TotalFeeAmountTRY,

    SUM(MerchantCommissionTRY)
        AS TotalMerchantCommissionTRY,

    SUM(TaxAmountTRY)
        AS TotalTaxAmountTRY,

    SUM(CashbackAmountTRY)
        AS TotalCashbackAmountTRY,

    CAST
    (
        AVG(AmountTRY)
        AS DECIMAL(19,2)
    ) AS AverageTransactionAmountTRY

FROM dw.FactPaymentTransaction

WHERE SourceSystem = 'SyntheticGeneratorTestV1';

------------------------------------------------------------
-- 8. KART-MÜŞTERİ EŞLEŞME KONTROLÜ
------------------------------------------------------------

SELECT
    COUNT(*) AS CardCustomerMismatchCount

FROM dw.FactPaymentTransaction AS fact

INNER JOIN dw.DimCard AS card
    ON card.CardKey = fact.CardKey

INNER JOIN dw.DimCustomer AS customer
    ON customer.CustomerKey = fact.CustomerKey

WHERE fact.SourceSystem = 'SyntheticGeneratorTestV1'
  AND card.CardholderCustomerID <> customer.CustomerID;

------------------------------------------------------------
-- 9. CİHAZ-MÜŞTERİ EŞLEŞME KONTROLÜ
------------------------------------------------------------

SELECT
    COUNT(*) AS DeviceCustomerMismatchCount

FROM dw.FactPaymentTransaction AS fact

INNER JOIN dw.DimDevice AS device
    ON device.DeviceKey = fact.DeviceKey

INNER JOIN dw.DimCustomer AS customer
    ON customer.CustomerKey = fact.CustomerKey

WHERE fact.SourceSystem = 'SyntheticGeneratorTestV1'
  AND fact.DeviceKey <> 0
  AND device.RegisteredCustomerID <> customer.CustomerID;

------------------------------------------------------------
-- 10. TIMESTAMP TUTARLILIĞI
------------------------------------------------------------

SELECT
    COUNT(*) AS InvalidTimestampCount

FROM dw.FactPaymentTransaction

WHERE SourceSystem = 'SyntheticGeneratorTestV1'
  AND
  (
      (
          AuthorizationTimestamp IS NOT NULL
          AND AuthorizationTimestamp < TransactionTimestamp
      )
      OR
      (
          SettlementTimestamp IS NOT NULL
          AND
          (
              AuthorizationTimestamp IS NULL
              OR SettlementTimestamp < AuthorizationTimestamp
          )
      )
  );

------------------------------------------------------------
-- 11. KUR VE TUTAR TUTARLILIĞI
------------------------------------------------------------

SELECT
    COUNT(*) AS CurrencyConversionMismatchCount

FROM dw.FactPaymentTransaction

WHERE SourceSystem = 'SyntheticGeneratorTestV1'
  AND ABS
  (
      AmountTRY
      -
      (
          OriginalAmount
          *
          ExchangeRateToTRY
      )
  ) > 0.10;

------------------------------------------------------------
-- 12. DATE KEY EŞLEŞME KONTROLÜ
------------------------------------------------------------

SELECT
    COUNT(*) AS MissingDateDimensionCount

FROM dw.FactPaymentTransaction AS fact

LEFT JOIN dw.DimDate AS transactiondate
    ON transactiondate.DateKey =
       fact.TransactionDateKey

LEFT JOIN dw.DimDate AS authorizationdate
    ON authorizationdate.DateKey =
       fact.AuthorizationDateKey

LEFT JOIN dw.DimDate AS settlementdate
    ON settlementdate.DateKey =
       fact.SettlementDateKey

WHERE fact.SourceSystem = 'SyntheticGeneratorTestV1'
  AND
  (
      transactiondate.DateKey IS NULL

      OR
      (
          fact.AuthorizationDateKey IS NOT NULL
          AND authorizationdate.DateKey IS NULL
      )

      OR
      (
          fact.SettlementDateKey IS NOT NULL
          AND settlementdate.DateKey IS NULL
      )
  );

------------------------------------------------------------
-- 13. ÖRNEK FACT KAYITLARI
------------------------------------------------------------

SELECT TOP (25)
    fact.PaymentTransactionKey,
    fact.TransactionID,
    fact.TransactionReference,

    fact.TransactionTimestamp,
    fact.AuthorizationTimestamp,
    fact.SettlementTimestamp,

    customer.CustomerID,
    customer.CustomerSegment,

    card.CardID,
    card.CardType,
    card.CardBrand,

    merchant.MerchantID,
    merchant.MerchantCategory,

    channel.PaymentChannelCode,
    currency.CurrencyCode,
    status.StatusCode,

    fact.OriginalAmount,
    fact.ExchangeRateToTRY,
    fact.AmountTRY,

    fact.MerchantCommissionTRY,
    fact.CashbackAmountTRY,

    fact.FraudScore,
    fact.IsFraud

FROM dw.FactPaymentTransaction AS fact

INNER JOIN dw.DimCustomer AS customer
    ON customer.CustomerKey = fact.CustomerKey

INNER JOIN dw.DimCard AS card
    ON card.CardKey = fact.CardKey

INNER JOIN dw.DimMerchant AS merchant
    ON merchant.MerchantKey = fact.MerchantKey

INNER JOIN dw.DimPaymentChannel AS channel
    ON channel.PaymentChannelKey =
       fact.PaymentChannelKey

INNER JOIN dw.DimCurrency AS currency
    ON currency.CurrencyKey =
       fact.CurrencyKey

INNER JOIN dw.DimTransactionStatus AS status
    ON status.TransactionStatusKey =
       fact.TransactionStatusKey

WHERE fact.SourceSystem = 'SyntheticGeneratorTestV1'

ORDER BY fact.PaymentTransactionKey;

SET NOCOUNT OFF;


------------------------------------------------------------
-- PHASE 10H
-- 10.000 DOĞRULANMIŞ TEST KAYDINDAN
-- 1.000.000 PRODUCTION FACT KAYDI ÜRETME
------------------------------------------------------------

SET NOCOUNT ON;
SET XACT_ABORT ON;

------------------------------------------------------------
-- 1. AYARLAR
------------------------------------------------------------

DECLARE @TargetProductionCount BIGINT = 1000000;
DECLARE @RequiredTemplateCount INT = 10000;

-- Her batch:
-- 5 kopya × 10.000 template = 50.000 satır
DECLARE @CopiesPerBatch INT = 5;

------------------------------------------------------------
-- 2. TEST KAYITLARINI KONTROL ET
------------------------------------------------------------

DECLARE @ActualTemplateCount INT =
(
    SELECT COUNT(*)
    FROM dw.FactPaymentTransaction
    WHERE SourceSystem = 'SyntheticGeneratorTestV1'
);

IF @ActualTemplateCount <> @RequiredTemplateCount
BEGIN
    THROW 50701,
          'Fact tablosunda tam olarak 10.000 test kaydı bulunmalıdır.',
          1;
END;

------------------------------------------------------------
-- 3. ÖNCEKİ GEÇİCİ TABLOLARI TEMİZLE
------------------------------------------------------------

DROP TABLE IF EXISTS #ProductionTemplate;
DROP TABLE IF EXISTS #CopyNumber;
DROP TABLE IF EXISTS #BatchMap;

------------------------------------------------------------
-- 4. TEST KAYITLARINI TEMPLATE TABLOSUNA AL
------------------------------------------------------------

SELECT
    ROW_NUMBER() OVER
    (
        ORDER BY fact.PaymentTransactionKey
    ) AS TemplateNumber,

    fact.PaymentTransactionKey,

    fact.TransactionDateKey,
    fact.AuthorizationDateKey,
    fact.SettlementDateKey,

    fact.CustomerKey,
    fact.CardKey,
    fact.MerchantKey,

    fact.PaymentChannelKey,
    fact.CurrencyKey,
    fact.TransactionStatusKey,

    fact.DeviceKey,
    fact.FraudReasonKey,

    fact.TransactionTimestamp,
    fact.AuthorizationTimestamp,
    fact.SettlementTimestamp,

    fact.OriginalAmount,
    fact.ExchangeRateToTRY,
    fact.AmountTRY,

    fact.FeeAmountTRY,
    fact.MerchantCommissionTRY,
    fact.TaxAmountTRY,
    fact.CashbackAmountTRY,

    fact.InstallmentCount,
    fact.AuthorizationDurationMs,

    fact.IsInternational,
    fact.IsContactless,
    fact.IsRecurring,
    fact.Is3DSecure,
    fact.IsTokenized,
    fact.IsFraud,

    fact.FraudScore

INTO #ProductionTemplate

FROM dw.FactPaymentTransaction AS fact

WHERE fact.SourceSystem = 'SyntheticGeneratorTestV1';

CREATE UNIQUE CLUSTERED INDEX CX_ProductionTemplate
    ON #ProductionTemplate(TemplateNumber);

------------------------------------------------------------
-- 5. TEMPLATE SAYISINI TEKRAR DOĞRULA
------------------------------------------------------------

IF
(
    SELECT COUNT(*)
    FROM #ProductionTemplate
) <> @RequiredTemplateCount
BEGIN
    THROW 50702,
          '#ProductionTemplate içerisinde 10.000 satır bulunamadı.',
          1;
END;

------------------------------------------------------------
-- 6. 1–100 ARASINDA COPY NUMBER OLUŞTUR
--
-- 100 kopya × 10.000 template = 1.000.000 satır
------------------------------------------------------------

SELECT TOP (100)
    ROW_NUMBER() OVER
    (
        ORDER BY
            objectA.object_id,
            objectB.object_id
    ) AS CopyNumber

INTO #CopyNumber

FROM sys.all_objects AS objectA
CROSS JOIN sys.all_objects AS objectB;

CREATE UNIQUE CLUSTERED INDEX CX_CopyNumber
    ON #CopyNumber(CopyNumber);

------------------------------------------------------------
-- 7. MEVCUT PRODUCTION KAYIT SAYISINI BUL
--
-- Script yarıda kaldıysa mevcut üretim kayıtları korunur
-- ve bir sonraki tam kopyadan devam edilir.
------------------------------------------------------------

DECLARE @ExistingProductionCount BIGINT =
(
    SELECT COUNT_BIG(*)
    FROM dw.FactPaymentTransaction
    WHERE SourceSystem = 'SyntheticGeneratorV1'
);

IF @ExistingProductionCount > @TargetProductionCount
BEGIN
    THROW 50703,
          'Production kayıt sayısı hedef olan 1.000.000 değerini aşmaktadır.',
          1;
END;

------------------------------------------------------------
-- Her kopya tam olarak 10.000 satır olmalıdır.
-- Yarım veya bozuk bir batch varsa otomatik devam etmiyoruz.
------------------------------------------------------------

IF @ExistingProductionCount % @RequiredTemplateCount <> 0
BEGIN
    THROW 50704,
          'Mevcut production kayıt sayısı 10.000 katı değildir. Önce yarım batch temizlenmelidir.',
          1;
END;

------------------------------------------------------------
-- Örneğin:
-- Existing = 0       → Copy 1
-- Existing = 250000  → Copy 26
------------------------------------------------------------

DECLARE @NextCopyNumber INT =
    CONVERT
    (
        INT,
        @ExistingProductionCount
        /
        @RequiredTemplateCount
    ) + 1;

DECLARE @LastCopyNumber INT = 100;
DECLARE @EndCopyNumber INT;
DECLARE @ExpectedBatchRows INT;
DECLARE @InsertedBatchRows INT;
DECLARE @CurrentProductionCount BIGINT;

------------------------------------------------------------
-- 8. 50.000 SATIRLIK BATCH DÖNGÜSÜ
------------------------------------------------------------

WHILE @NextCopyNumber <= @LastCopyNumber
BEGIN
    SET @EndCopyNumber =
        CASE
            WHEN
                @NextCopyNumber
                + @CopiesPerBatch
                - 1
                > @LastCopyNumber
            THEN @LastCopyNumber

            ELSE
                @NextCopyNumber
                + @CopiesPerBatch
                - 1
        END;

    SET @ExpectedBatchRows =
        (
            @EndCopyNumber
            -
            @NextCopyNumber
            + 1
        )
        *
        @RequiredTemplateCount;

    --------------------------------------------------------
    -- Önceki batch haritasını temizle
    --------------------------------------------------------

    DROP TABLE IF EXISTS #BatchMap;

    --------------------------------------------------------
    -- Bu batch için template × copy kombinasyonlarını oluştur
    --------------------------------------------------------

    SELECT
        template.*,

        copy.CopyNumber,

        CONVERT
        (
            BIGINT,

            (
                CONVERT
                (
                    BIGINT,
                    copy.CopyNumber - 1
                )
                *
                @RequiredTemplateCount
            )
            +
            template.TemplateNumber
        ) AS GlobalTransactionNumber,

        CAST
        (
            1.0000
            +
            CONVERT
            (
                DECIMAL(10,4),

                (
                    copy.CopyNumber * 37
                    +
                    template.TemplateNumber * 13
                )
                % 100
            )
            /
            1000.0

            AS DECIMAL(10,4)
        ) AS AmountMultiplier

    INTO #BatchMap

    FROM #ProductionTemplate AS template

    INNER JOIN #CopyNumber AS copy
        ON copy.CopyNumber
           BETWEEN @NextCopyNumber
               AND @EndCopyNumber;

    CREATE UNIQUE CLUSTERED INDEX CX_BatchMap
        ON #BatchMap(GlobalTransactionNumber);

    --------------------------------------------------------
    -- BATCH SATIR SAYISINI DOĞRULA
    --------------------------------------------------------

    IF
    (
        SELECT COUNT(*)
        FROM #BatchMap
    ) <> @ExpectedBatchRows
    BEGIN
        THROW 50705,
              '#BatchMap beklenen satır sayısını üretmedi.',
              1;
    END;

    --------------------------------------------------------
    -- BATCH INSERT
    --------------------------------------------------------

    BEGIN TRY

        BEGIN TRANSACTION;

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
        SELECT
            ------------------------------------------------
            -- BENZERSİZ TRANSACTION ID
            ------------------------------------------------

            CONCAT
            (
                'TXN-',
                RIGHT
                (
                    REPLICATE('0', 12)
                    +
                    CONVERT
                    (
                        VARCHAR(12),
                        batch.GlobalTransactionNumber
                    ),
                    12
                )
            ) AS TransactionID,

            ------------------------------------------------
            -- BENZERSİZ REFERENCE
            ------------------------------------------------

            CONCAT
            (
                'REF-',
                CONVERT
                (
                    VARCHAR(8),
                    batch.TransactionDateKey
                ),
                '-',
                RIGHT
                (
                    REPLICATE('0', 12)
                    +
                    CONVERT
                    (
                        VARCHAR(12),
                        batch.GlobalTransactionNumber
                    ),
                    12
                )
            ) AS TransactionReference,

            ------------------------------------------------
            -- DATE KEYS
            ------------------------------------------------

            batch.TransactionDateKey,
            batch.AuthorizationDateKey,
            batch.SettlementDateKey,

            ------------------------------------------------
            -- ENTITY KEYS
            ------------------------------------------------

            batch.CustomerKey,
            batch.CardKey,
            batch.MerchantKey,

            ------------------------------------------------
            -- DIMENSION KEYS
            ------------------------------------------------

            batch.PaymentChannelKey,
            batch.CurrencyKey,
            batch.TransactionStatusKey,

            batch.DeviceKey,
            batch.FraudReasonKey,

            ------------------------------------------------
            -- TIMESTAMPS
            ------------------------------------------------

            batch.TransactionTimestamp,
            batch.AuthorizationTimestamp,
            batch.SettlementTimestamp,

            ------------------------------------------------
            -- TUTARLAR
            ------------------------------------------------

            CAST
            (
                ROUND
                (
                    batch.OriginalAmount
                    *
                    batch.AmountMultiplier,
                    4
                )
                AS DECIMAL(19,4)
            ) AS OriginalAmount,

            batch.ExchangeRateToTRY,

            CAST
            (
                ROUND
                (
                    batch.AmountTRY
                    *
                    batch.AmountMultiplier,
                    4
                )
                AS DECIMAL(19,4)
            ) AS AmountTRY,

            CAST
            (
                ROUND
                (
                    batch.FeeAmountTRY
                    *
                    batch.AmountMultiplier,
                    4
                )
                AS DECIMAL(19,4)
            ) AS FeeAmountTRY,

            CAST
            (
                ROUND
                (
                    batch.MerchantCommissionTRY
                    *
                    batch.AmountMultiplier,
                    4
                )
                AS DECIMAL(19,4)
            ) AS MerchantCommissionTRY,

            CAST
            (
                ROUND
                (
                    batch.TaxAmountTRY
                    *
                    batch.AmountMultiplier,
                    4
                )
                AS DECIMAL(19,4)
            ) AS TaxAmountTRY,

            CAST
            (
                CASE
                    WHEN
                        batch.CashbackAmountTRY
                        *
                        batch.AmountMultiplier
                        > 500
                    THEN 500

                    ELSE
                        ROUND
                        (
                            batch.CashbackAmountTRY
                            *
                            batch.AmountMultiplier,
                            4
                        )
                END

                AS DECIMAL(19,4)
            ) AS CashbackAmountTRY,

            ------------------------------------------------
            -- COUNT, INSTALLMENT, DURATION
            ------------------------------------------------

            batch.InstallmentCount,

            CONVERT(TINYINT, 1)
                AS TransactionCount,

            batch.AuthorizationDurationMs,

            ------------------------------------------------
            -- FLAGS
            ------------------------------------------------

            batch.IsInternational,
            batch.IsContactless,
            batch.IsRecurring,
            batch.Is3DSecure,
            batch.IsTokenized,
            batch.IsFraud,

            ------------------------------------------------
            -- FRAUD VE SOURCE
            ------------------------------------------------

            batch.FraudScore,

            'SyntheticGeneratorV1'
                AS SourceSystem

        FROM #BatchMap AS batch;

        SET @InsertedBatchRows = @@ROWCOUNT;

        IF @InsertedBatchRows <> @ExpectedBatchRows
        BEGIN
            THROW 50706,
                  'Fact tablosuna eklenen batch satır sayısı beklenen değerden farklıdır.',
                  1;
        END;

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
    -- İLERLEME MESAJI
    --------------------------------------------------------

    SET @CurrentProductionCount =
    (
        SELECT COUNT_BIG(*)
        FROM dw.FactPaymentTransaction
        WHERE SourceSystem = 'SyntheticGeneratorV1'
    );

    RAISERROR
    (
        N'Copy %d–%d tamamlandı. Production kayıt sayısı: %d',
        10,
        1,
        @NextCopyNumber,
        @EndCopyNumber,
        @CurrentProductionCount
    ) WITH NOWAIT;

    SET @NextCopyNumber = @EndCopyNumber + 1;
END;

------------------------------------------------------------
-- 9. NİHAİ PRODUCTION SAYISINI DOĞRULA
------------------------------------------------------------

DECLARE @FinalProductionCount BIGINT =
(
    SELECT COUNT_BIG(*)
    FROM dw.FactPaymentTransaction
    WHERE SourceSystem = 'SyntheticGeneratorV1'
);

IF @FinalProductionCount <> @TargetProductionCount
BEGIN
    THROW 50707,
          'Production fact kayıt sayısı 1.000.000 değildir.',
          1;
END;

------------------------------------------------------------
-- 10. TEST KAYITLARINI SİL
--
-- Production yüklemesi tam başarıya ulaştıktan sonra
-- 10.000 test kaydı kaldırılır.
------------------------------------------------------------

BEGIN TRY

    BEGIN TRANSACTION;

    DELETE FROM dw.FactPaymentTransaction
    WHERE SourceSystem = 'SyntheticGeneratorTestV1';

    DECLARE @DeletedTestRowCount INT = @@ROWCOUNT;

    IF @DeletedTestRowCount <> @RequiredTemplateCount
    BEGIN
        THROW 50708,
              'Silinen test kaydı sayısı 10.000 değildir.',
              1;
    END;

    COMMIT TRANSACTION;

END TRY

BEGIN CATCH

    IF XACT_STATE() <> 0
    BEGIN
        ROLLBACK TRANSACTION;
    END;

    THROW;

END CATCH;

------------------------------------------------------------
-- 11. SONUÇ: SOURCE SYSTEM DAĞILIMI
------------------------------------------------------------

SELECT
    SourceSystem,
    COUNT_BIG(*) AS FactRowCount

FROM dw.FactPaymentTransaction

GROUP BY SourceSystem

ORDER BY FactRowCount DESC;

------------------------------------------------------------
-- 12. PRODUCTION SATIR SAYISI
------------------------------------------------------------

SELECT
    COUNT_BIG(*) AS ProductionFactRowCount,

    SUM
    (
        CONVERT
        (
            BIGINT,
            TransactionCount
        )
    ) AS ProductionTransactionCount,

    MIN(TransactionTimestamp)
        AS FirstTransactionTimestamp,

    MAX(TransactionTimestamp)
        AS LastTransactionTimestamp

FROM dw.FactPaymentTransaction

WHERE SourceSystem = 'SyntheticGeneratorV1';

------------------------------------------------------------
-- 13. TRANSACTION ID TEKRARI
------------------------------------------------------------

SELECT
    TransactionID,
    COUNT(*) AS DuplicateCount

FROM dw.FactPaymentTransaction

WHERE SourceSystem = 'SyntheticGeneratorV1'

GROUP BY TransactionID

HAVING COUNT(*) > 1;

------------------------------------------------------------
-- 14. KUR–TUTAR TUTARLILIĞI
------------------------------------------------------------

SELECT
    COUNT_BIG(*) AS CurrencyConversionMismatchCount

FROM dw.FactPaymentTransaction

WHERE SourceSystem = 'SyntheticGeneratorV1'

  AND ABS
  (
      AmountTRY
      -
      (
          OriginalAmount
          *
          ExchangeRateToTRY
      )
  ) > 0.15;

------------------------------------------------------------
-- 15. KART–MÜŞTERİ EŞLEŞMESİ
------------------------------------------------------------

SELECT
    COUNT_BIG(*) AS CardCustomerMismatchCount

FROM dw.FactPaymentTransaction AS fact

INNER JOIN dw.DimCard AS card
    ON card.CardKey = fact.CardKey

INNER JOIN dw.DimCustomer AS customer
    ON customer.CustomerKey = fact.CustomerKey

WHERE fact.SourceSystem = 'SyntheticGeneratorV1'
  AND card.CardholderCustomerID <> customer.CustomerID;

------------------------------------------------------------
-- 16. CİHAZ–MÜŞTERİ EŞLEŞMESİ
------------------------------------------------------------

SELECT
    COUNT_BIG(*) AS DeviceCustomerMismatchCount

FROM dw.FactPaymentTransaction AS fact

INNER JOIN dw.DimDevice AS device
    ON device.DeviceKey = fact.DeviceKey

INNER JOIN dw.DimCustomer AS customer
    ON customer.CustomerKey = fact.CustomerKey

WHERE fact.SourceSystem = 'SyntheticGeneratorV1'
  AND fact.DeviceKey <> 0
  AND device.RegisteredCustomerID <> customer.CustomerID;

------------------------------------------------------------
-- 17. STATUS DAĞILIMI
------------------------------------------------------------

SELECT
    status.StatusCode,

    COUNT_BIG(*) AS TransactionCount,

    CAST
    (
        100.0
        *
        COUNT_BIG(*)
        /
        SUM(COUNT_BIG(*)) OVER ()

        AS DECIMAL(6,2)
    ) AS TransactionPercentage

FROM dw.FactPaymentTransaction AS fact

INNER JOIN dw.DimTransactionStatus AS status
    ON status.TransactionStatusKey =
       fact.TransactionStatusKey

WHERE fact.SourceSystem = 'SyntheticGeneratorV1'

GROUP BY status.StatusCode

ORDER BY TransactionCount DESC;

------------------------------------------------------------
-- 18. FRAUD ÖZETİ
------------------------------------------------------------

SELECT
    COUNT_BIG(*) AS TotalTransactionCount,

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
        COUNT_BIG(*)

        AS DECIMAL(8,4)
    ) AS FraudPercentage,

    CAST
    (
        AVG(FraudScore)
        AS DECIMAL(8,2)
    ) AS AverageFraudScore

FROM dw.FactPaymentTransaction

WHERE SourceSystem = 'SyntheticGeneratorV1';

------------------------------------------------------------
-- 19. FİNANSAL ÖZET
------------------------------------------------------------

SELECT
    SUM(AmountTRY)
        AS TotalTransactionVolumeTRY,

    SUM(FeeAmountTRY)
        AS TotalFeeAmountTRY,

    SUM(MerchantCommissionTRY)
        AS TotalMerchantCommissionTRY,

    SUM(TaxAmountTRY)
        AS TotalTaxAmountTRY,

    SUM(CashbackAmountTRY)
        AS TotalCashbackAmountTRY,

    CAST
    (
        AVG(AmountTRY)
        AS DECIMAL(19,2)
    ) AS AverageTransactionAmountTRY

FROM dw.FactPaymentTransaction

WHERE SourceSystem = 'SyntheticGeneratorV1';

SET NOCOUNT OFF;


GO

SELECT
    SourceSystem,
    COUNT_BIG(*) AS RowCount
FROM dw.FactPaymentTransaction
GROUP BY SourceSystem
ORDER BY RowCount DESC;
GO

SELECT
    COUNT_BIG(*) AS ProductionCount
FROM dw.FactPaymentTransaction
WHERE SourceSystem = 'SyntheticGeneratorV1';

SELECT
    COUNT_BIG(*) AS TestCount
FROM dw.FactPaymentTransaction
WHERE SourceSystem = 'SyntheticGeneratorTestV1';
GO

SELECT
    TransactionID,
    COUNT(*) AS DuplicateCount
FROM dw.FactPaymentTransaction
GROUP BY TransactionID
HAVING COUNT(*) > 1;
GO
