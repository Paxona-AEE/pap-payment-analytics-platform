USE Master;
GO

CREATE DATABASE PaymentProjectDW;
GO

USE PaymentProjectDb;
GO


--Data Warehouse PUSH!!

IF NOT EXISTS  (
	SELECT 1
	FROM sys.schemas
	WHERE name = 'dw'
)
BEGIN
	EXEC('CREATE SCHEMA dw');
END;
GO
