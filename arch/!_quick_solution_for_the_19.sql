
IF EXISTS
(
    SELECT 1
    FROM sys.check_constraints
    WHERE parent_object_id = OBJECT_ID(N'dw.DimCard')
      AND name = N'CK_DimCard_CardStatus'
)
BEGIN
    ALTER TABLE dw.DimCard
    DROP CONSTRAINT CK_DimCard_CardStatus;
END;
GO

ALTER TABLE dw.DimCard WITH CHECK
ADD CONSTRAINT CK_DimCard_CardStatus
CHECK
(
    CardStatus IN
    (
        'Unknown',
        'Active',
        'Blocked',
        'Suspended',
        'Cancelled',
        'Expired'
    )
);
GO



--PHASE 2 


IF NOT EXISTS
(
    SELECT 1
    FROM dw.DimCard
    WHERE CardKey = 0
)
BEGIN
    SET IDENTITY_INSERT dw.DimCard ON;

    INSERT INTO dw.DimCard
    (
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
    VALUES
    (
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


--PHASE 3

SELECT
    COUNT(*) AS TotalRows,
    SUM(CASE WHEN CardKey = 0 THEN 1 ELSE 0 END) AS UnknownRows,
    SUM(CASE WHEN CardKey <> 0 THEN 1 ELSE 0 END) AS RealCardRows
FROM dw.DimCard;

SELECT
    CardStatus,
    COUNT(*) AS CardCount
FROM dw.DimCard
GROUP BY CardStatus
ORDER BY CardStatus;