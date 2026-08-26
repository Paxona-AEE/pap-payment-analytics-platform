--Suspicious FRAUD Special Case

IF NOT EXISTS (
    SELECT 1
    FROM dw.DimFraudReason
    WHERE FraudReasonKey = 0
)
BEGIN
    SET IDENTITY_INSERT dw.DimFraudReason ON;

    INSERT INTO dw.DimFraudReason (
        FraudReasonKey,
        FraudReasonCode,
        FraudCategory,
        FraudReasonName,
        SeverityLevel,
        FraudReasonDescription,
        IsActive
    )
    VALUES (
        0,
        'UNKNOWN',
        'Unknown',
        N'Bilinmeyen Fraud Nedeni',
        'None',
        N'Fraud nedeninin belirlenemediği veya kaynak sistemden eksik geldiği işlemler. 404',
        1
    );

    SET IDENTITY_INSERT dw.DimFraudReason OFF;
END;
GO

--Anonymous Case: Fraud?

IF NOT EXISTS (
    SELECT 1
    FROM dw.DimFraudReason
    WHERE FraudReasonKey = 1
)
BEGIN
    SET IDENTITY_INSERT dw.DimFraudReason ON;

    INSERT INTO dw.DimFraudReason
    (
        FraudReasonKey,
        FraudReasonCode,
        FraudCategory,
        FraudReasonName,
        SeverityLevel,
        FraudReasonDescription,
        IsActive
    )
    VALUES
    (
        1,
        'NO_FRAUD',
        'None',
        N'Fraud Göstergesi Yok',
        'None',
        N'İşlemde belirgin bir fraud veya şüpheli davranış göstergesi bulunmamaktadır.',
        1
    );

    SET IDENTITY_INSERT dw.DimFraudReason OFF;
END;
GO


--Fraud

INSERT INTO dw.DimFraudReason (
    FraudReasonCode,
    FraudCategory,
    FraudReasonName,
    SeverityLevel,
    FraudReasonDescription,
    IsActive
)
SELECT
    source.FraudReasonCode,
    source.FraudCategory,
    source.FraudReasonName,
    source.SeverityLevel,
    source.FraudReasonDescription,
    source.IsActive
FROM (
    VALUES
        (
            'STOLEN_CARD',
            'Card',
            N'Çalıntı Kart Şüphesi',
            'Critical',
            N'Kartın çalıntı olduğu veya yetkisiz bir kişi tarafından kullanıldığı değerlendirilmektedir.',
            1
        ),

        (
            'ACCOUNT_TAKEOVER',
            'Account',
            N'Hesap Ele Geçirme Şüphesi',
            'Critical',
            N'Müşteri hesabının başka bir kişi tarafından ele geçirilmiş olabileceğini gösteren davranışlar tespit edilmiştir.',
            1
        ),

        (
            'SUSPICIOUS_DEVICE',
            'Device',
            N'Şüpheli Cihaz',
            'High',
            N'İşlem daha önce görülmemiş, güvenilmeyen veya riskli olarak sınıflandırılmış bir cihazdan gerçekleştirilmiştir.',
            1
        ),

        (
            'ROOTED_DEVICE',
            'Device',
            N'Root veya Jailbreak Uygulanmış Cihaz',
            'High',
            N'İşlem güvenlik kısıtlamaları kaldırılmış bir mobil cihaz üzerinden gerçekleştirilmiştir.',
            1
        ),

        (
            'UNUSUAL_AMOUNT',
            'Behavioral',
            N'Olağandışı İşlem Tutarı',
            'Medium',
            N'İşlem tutarı müşterinin geçmiş harcama davranışına göre olağandışı derecede yüksek veya farklıdır.',
            1
        ),

        (
            'HIGH_VELOCITY',
            'Velocity',
            N'Yüksek İşlem Hızı',
            'High',
            N'Kısa bir zaman aralığında normalin üzerinde sayıda işlem gerçekleştirilmiştir.',
            1
        ),

        (
            'IMPOSSIBLE_TRAVEL',
            'Location',
            N'İmkânsız Seyahat',
            'Critical',
            N'Müşterinin çok kısa süre içerisinde fiziksel olarak ulaşması mümkün olmayan farklı konumlardan işlem yaptığı görülmüştür.',
            1
        ),

        (
            'LOCATION_MISMATCH',
            'Location',
            N'Konum Uyumsuzluğu',
            'Medium',
            N'İşlem konumu müşterinin normal kullanım bölgesi, cihaz konumu veya kart ülkesiyle uyuşmamaktadır.',
            1
        ),

        (
            'MULTIPLE_DECLINES',
            'Behavioral',
            N'Çoklu Reddedilen Deneme',
            'High',
            N'Kısa süre içerisinde aynı kart veya hesapla çok sayıda reddedilen işlem denenmiştir.',
            1
        ),

        (
            'MERCHANT_RISK',
            'Merchant',
            N'Riskli Merchant',
            'High',
            N'İşlemin gerçekleştirildiği merchant geçmiş fraud oranı veya risk kuralları nedeniyle yüksek riskli olarak değerlendirilmiştir.',
            1
        ),

        (
            'IDENTITY_MISMATCH',
            'Identity',
            N'Kimlik Bilgisi Uyumsuzluğu',
            'High',
            N'İşlem sırasında kullanılan müşteri, kart, fatura veya kimlik bilgileri arasında uyumsuzluk tespit edilmiştir.',
            1
        ),

        (
            'THREEDS_FAILURE',
            'Authentication',
            N'3D Secure Doğrulama Başarısızlığı',
            'Medium',
            N'3D Secure kimlik doğrulaması başarısız olmuş veya doğrulama süreci şüpheli şekilde tamamlanamamıştır.',
            1
        )
) AS source
(
    FraudReasonCode,
    FraudCategory,
    FraudReasonName,
    SeverityLevel,
    FraudReasonDescription,
    IsActive
)
WHERE NOT EXISTS
(
    SELECT 1
    FROM dw.DimFraudReason AS target
    WHERE target.FraudReasonCode = source.FraudReasonCode
);
GO

--Validate

SELECT
    FraudReasonKey,
    FraudReasonCode,
    FraudCategory,
    FraudReasonName,
    SeverityLevel,
    IsActive
FROM dw.DimFraudReason
ORDER BY FraudReasonKey;
GO