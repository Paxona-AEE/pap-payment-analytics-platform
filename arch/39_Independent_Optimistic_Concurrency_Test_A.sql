--Revert the value of the money, it will make everything better

UPDATE lab.PaymentAccount
SET
    BalanceTRY = 10000.0000,
    LastUpdatedDateTime = SYSDATETIME()
WHERE AccountID = 1;


--Session A;Read  (Special Read)

USE PaymentProjectDW;
GO

SET NOCOUNT ON;

DROP TABLE #SessionAOriginalValue

CREATE TABLE #SessionAOriginalValue(
    AccountID INT NOT NULL
        PRIMARY KEY,

    BalanceRead DECIMAL(19,4) NOT NULL,

    RowVersionRead BINARY(8) NOT NULL
);

INSERT INTO #SessionAOriginalValue(
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
    @@SPID AS SessionA_ID,
    AccountID,
    BalanceRead,

    CONVERT(
        VARCHAR(18),
        RowVersionRead,
        1
    ) AS RowVersionReadBySessionA

FROM #SessionAOriginalValue;
GO


--Session A;Update  (Special Read)

USE PaymentProjectDW;
GO

SET NOCOUNT ON;

UPDATE accountData
SET
    BalanceTRY =
        originalData.BalanceRead - 1000.0000,

    LastUpdatedDateTime =SYSDATETIME()

FROM lab.PaymentAccount AS accountData

INNER JOIN #SessionAOriginalValue AS originalData
    ON originalData.AccountID =
       accountData.AccountID

WHERE accountData.RowVersionStamp =
      originalData.RowVersionRead;

SELECT
    SUM(@@ROWCOUNT)
        AS SessionARowsAffected;

SELECT
    AccountID,
    BalanceTRY,

    CONVERT(
        VARCHAR(18),
        RowVersionStamp,
        1
    ) AS NewRowVersion

FROM lab.PaymentAccount
WHERE AccountID = 1;
GO