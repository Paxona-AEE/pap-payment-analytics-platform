
--We need anonimity for that one aswell

ALTER TABLE dw.DimTransactionStatus
DROP CONSTRAINT CK_DimTransactionStatus_Group;

ALTER TABLE dw.DimTransactionStatus
ADD CONSTRAINT CK_DimTransactionStatus_Group
CHECK (
    StatusGroup IN (
        'Unknown',
        'Successful',
        'Pending',
        'Failed',
        'Cancelled',
        'Reversed'
    )
);
GO

--The rest is not so different from the other ones!

IF NOT EXISTS (
    SELECT 1
    FROM dw.DimTransactionStatus
    WHERE TransactionStatusKey = 0
)
BEGIN
    SET IDENTITY_INSERT dw.DimTransactionStatus ON;

    INSERT INTO dw.DimTransactionStatus (
        TransactionStatusKey,
        StatusCode,
        StatusName,
        StatusGroup,
        IsSuccessful,
        IsFinalStatus,
        StatusDescription
    )
    VALUES(
        0,
        'UNKNOWN',
        N'Bilinmeyen Durum',
        'Unknown',
        0,
        0,
        N'İşlem durumunun belirlenemediği veya kaynak sistemden eksik geldiği kayıtlar.'
    );

    SET IDENTITY_INSERT dw.DimTransactionStatus OFF;
END;
GO

--Other values

INSERT INTO dw.DimTransactionStatus (
    StatusCode,
    StatusName,
    StatusGroup,
    IsSuccessful,
    IsFinalStatus,
    StatusDescription
)
SELECT
    source.StatusCode,
    source.StatusName,
    source.StatusGroup,
    source.IsSuccessful,
    source.IsFinalStatus,
    source.StatusDescription
FROM(
    VALUES(
            'APPROVED',
            N'Onaylandı',
            'Successful',
            1,
            1,
            N'İşlem başarıyla yetkilendirilmiş ve ödeme kabul edilmiştir.'
        ),

        (
            'PENDING',
            N'Beklemede',
            'Pending',
            0,
            0,
            N'İşlemin sonucu henüz kesinleşmemiştir ve ek işlem veya sistem yanıtı beklenmektedir.'
        ),

        (
            'DECLINED',
            N'Reddedildi',
            'Failed',
            0,
            1,
            N'İşlem banka, kart kuruluşu veya risk kuralları tarafından açıkça reddedilmiştir.'
        ),

        (
            'FAILED',
            N'Başarısız',
            'Failed',
            0,
            1,
            N'İşlem teknik hata, bağlantı problemi veya sistem sorunu nedeniyle tamamlanamamıştır.'
        ),

        (
            'CANCELLED',
            N'İptal Edildi',
            'Cancelled',
            0,
            1,
            N'İşlem müşteri, merchant veya sistem tarafından tamamlanmadan iptal edilmiştir.'
        ),

        (
            'REVERSED',
            N'Ters İşlem Uygulandı',
            'Reversed',
            0,
            1,
            N'Başlangıçta onaylanan işlem daha sonra otomatik veya operasyonel olarak geri çevrilmiştir.'
        ),

        (
            'REFUNDED',
            N'İade Edildi',
            'Reversed',
            0,
            1,
            N'Tamamlanan ödemenin tamamı veya ilgili işlem tutarı müşteriye daha sonra iade edilmiştir.'
        ),

        (
            'EXPIRED',
            N'Süresi Doldu',
            'Failed',
            0,
            1,
            N'Belirlenen süre içerisinde tamamlanmadığı için işlem geçerliliğini kaybetmiştir.'
        )
) 
AS source (
    StatusCode,
    StatusName,
    StatusGroup,
    IsSuccessful,
    IsFinalStatus,
    StatusDescription
)
WHERE NOT EXISTS (
    SELECT 1
    FROM dw.DimTransactionStatus AS target
    WHERE target.StatusCode = source.StatusCode
);
GO

--Validate these values

SELECT
    TransactionStatusKey,
    StatusCode,
    StatusName,
    StatusGroup,
    IsSuccessful,
    IsFinalStatus,
    StatusDescription
FROM dw.DimTransactionStatus
ORDER BY TransactionStatusKey;
GO