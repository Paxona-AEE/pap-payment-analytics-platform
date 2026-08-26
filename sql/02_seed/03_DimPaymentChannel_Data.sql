USE PaymentProjectDW;
GO

-- Create the unknown payment channel member.

IF NOT EXISTS (
    SELECT 1
    FROM dw.DimPaymentChannel
    WHERE PaymentChannelKey = 0
)
BEGIN
    SET IDENTITY_INSERT dw.DimPaymentChannel ON;

    INSERT INTO dw.DimPaymentChannel (
        PaymentChannelKey,
        PaymentChannelCode,
        PaymentChannelName,
        ChannelGroup,
        IsCardPresent,
        ChannelDescription
    )
    VALUES
    (
        0,
        'UNKNOWN',
        N'Bilinmeyen Kanal',
        'Other',
        0,
        N'Ödeme kanalının belirlenemediği veya kaynak sistemden eksik geldiği işlemler.'
    );

    SET IDENTITY_INSERT dw.DimPaymentChannel OFF;
END;
GO

-- Insert the supported payment channels.

INSERT INTO dw.DimPaymentChannel (
    PaymentChannelCode,
    PaymentChannelName,
    ChannelGroup,
    IsCardPresent,
    ChannelDescription
)
SELECT
    source.PaymentChannelCode,
    source.PaymentChannelName,
    source.ChannelGroup,
    source.IsCardPresent,
    source.ChannelDescription
FROM (
    VALUES (
            'POS',
            N'Fiziksel POS',
            'Physical',
            1,
            N'Kartın fiziksel POS terminaline takıldığı veya manyetik şerit ile okutulduğu işlemler.'
        ),

        (
            'CONTACTLESS_POS',
            N'Temassız POS',
            'Physical',
            1,
            N'Kartın veya temassız ödeme destekleyen cihazın POS terminaline yaklaştırıldığı işlemler.'
        ),

        (
            'ECOMMERCE',
            N'E-Ticaret',
            'Digital',
            0,
            N'İnternet sitesi veya çevrim içi mağaza üzerinden gerçekleştirilen kartlı ödeme işlemleri.'
        ),

        (
            'MOBILE_APP',
            N'Mobil Uygulama',
            'Digital',
            0,
            N'Bir mobil uygulama içerisinden başlatılan ödeme işlemleri.'
        ),

        (
            'DIGITAL_WALLET',
            N'Dijital Cüzdan',
            'Digital',
            0,
            N'Dijital cüzdan veya tokenlaştırılmış kart bilgisi kullanılarak gerçekleştirilen işlemler.'
        ),

        (
            'QR_PAYMENT',
            N'QR Ödeme',
            'Digital',
            0,
            N'QR kod okutularak veya QR kod oluşturularak gerçekleştirilen ödeme işlemleri.'
        ),

        (
            'PAYMENT_LINK',
            N'Ödeme Linki',
            'Digital',
            0,
            N'Müşteriye gönderilen güvenli ödeme bağlantısı üzerinden gerçekleştirilen işlemler.'
        ),

        (
            'RECURRING',
            N'Düzenli Ödeme',
            'Recurring',
            0,
            N'Abonelik, üyelik veya periyodik fatura için otomatik olarak tekrarlanan işlemler.'
        ),

        (
            'ATM',
            N'ATM',
            'ATM',
            1,
            N'ATM cihazı üzerinden gerçekleştirilen kartlı finansal işlemler.'
        ),

        (
            'MOTO',
            N'Posta veya Telefon Siparişi',
            'Other',
            0,
            N'Kart bilgilerinin posta veya telefon yoluyla alındığı card-not-present işlemler.'
        )
)
AS source (
    PaymentChannelCode,
    PaymentChannelName,
    ChannelGroup,
    IsCardPresent,
    ChannelDescription
)
WHERE NOT EXISTS (
    SELECT 1
    FROM dw.DimPaymentChannel AS target
    WHERE target.PaymentChannelCode = source.PaymentChannelCode
);
GO

--Validate

SELECT
    PaymentChannelKey,
    PaymentChannelCode,
    PaymentChannelName,
    ChannelGroup,
    IsCardPresent,
    ChannelDescription
FROM dw.DimPaymentChannel
ORDER BY PaymentChannelKey;
GO
