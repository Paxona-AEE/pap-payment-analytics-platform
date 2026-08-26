--Session B;Read  (Special Read)

USE PaymentProjectDW;
GO

SET NOCOUNT ON;

DROP TABLE #SessionBOriginalValue

CREATE TABLE #SessionBOriginalValue(
    AccountID INT NOT NULL
        PRIMARY KEY,

    BalanceRead DECIMAL(19,4) NOT NULL,

    RowVersionRead BINARY(8) NOT NULL
);

INSERT INTO #SessionBOriginalValue(
    AccountID,
    BalanceRead,
    RowVersionRead
)
SELECT
    AccountID,
    BalanceTRY,
    RowVersionStamp
FROM lab.PaymentAccount
WHERE AccountID = 1;

SELECT
    @@SPID AS SessionB_ID,
    AccountID,
    BalanceRead,

    CONVERT(
        VARCHAR(18),
        RowVersionRead,
        1
    ) AS RowVersionReadBySessionB

FROM #SessionAOriginalValue;
GO


--Session B;Update  (Special Read)

USE PaymentProjectDW;
GO

SET NOCOUNT ON;

UPDATE accountData
SET
    BalanceTRY =
        originalData.BalanceRead - 2000.0000,

    LastUpdatedDateTime =
        SYSDATETIME()

FROM lab.PaymentAccount AS accountData

INNER JOIN #SessionBOriginalValue AS originalData
    ON originalData.AccountID =
       accountData.AccountID

WHERE accountData.RowVersionStamp = originalData.RowVersionRead; (Main Limiter)
 
SELECT
    SUM(@@ROWCOUNT)
        AS SessionBRowsAffected;

SELECT
    AccountID,
    BalanceTRY,

    CONVERT(
        VARCHAR(18),
        RowVersionStamp,
        1
    ) AS CurrentRowVersion

FROM lab.PaymentAccount
WHERE AccountID = 1;
GO


--It looks like optimistic concurrency is working functionally!