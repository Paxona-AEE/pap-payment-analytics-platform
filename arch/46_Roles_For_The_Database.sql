/*
    PaymentProjectTest2 - Database Roles and Demo Users

    Roles:
      - rl_report_reader : read and execute access in report schema
      - rl_etl_operator  : run payment ETL procedures and ingest staging rows
      - rl_auditor       : read ETL control, reject and lineage information

    SCD Type 2 objects and permissions are intentionally excluded.
    The script is safe to run more than once.
*/


SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

------------------------------------------------------------
-- 1. PREREQUISITES
------------------------------------------------------------

IF SCHEMA_ID(N'etl') IS NULL
   OR SCHEMA_ID(N'stg') IS NULL
BEGIN
    THROW 60001,
          'etl veya stg semasi bulunamadi. Once ETL kurulum scriptleri calistirilmalidir.',
          1;
END;
GO

IF SCHEMA_ID(N'report') IS NULL
BEGIN
    EXEC(N'CREATE SCHEMA report AUTHORIZATION dbo;');
END;
GO

------------------------------------------------------------
-- 2. OBSOLETE SCD PROCEDURE CLEANUP
------------------------------------------------------------

DROP PROCEDURE IF EXISTS etl.usp_RunCustomerSCD2Batch;
DROP PROCEDURE IF EXISTS etl.usp_ApplyCustomerSCD2Batch;
GO

------------------------------------------------------------
-- 3. DATABASE ROLES
------------------------------------------------------------

IF DATABASE_PRINCIPAL_ID(N'rl_report_reader') IS NULL
BEGIN
    CREATE ROLE rl_report_reader AUTHORIZATION dbo;
END;
GO

IF DATABASE_PRINCIPAL_ID(N'rl_etl_operator') IS NULL
BEGIN
    CREATE ROLE rl_etl_operator AUTHORIZATION dbo;
END;
GO

IF DATABASE_PRINCIPAL_ID(N'rl_auditor') IS NULL
BEGIN
    CREATE ROLE rl_auditor AUTHORIZATION dbo;
END;
GO

------------------------------------------------------------
-- 4. DEMO USERS WITHOUT LOGIN
------------------------------------------------------------

IF DATABASE_PRINCIPAL_ID(N'LabReportUser') IS NULL
BEGIN
    CREATE USER LabReportUser
        WITHOUT LOGIN
        WITH DEFAULT_SCHEMA = report;
END
ELSE
BEGIN
    ALTER USER LabReportUser
        WITH DEFAULT_SCHEMA = report;
END;
GO

IF DATABASE_PRINCIPAL_ID(N'LabETLUser') IS NULL
BEGIN
    CREATE USER LabETLUser
        WITHOUT LOGIN
        WITH DEFAULT_SCHEMA = etl;
END
ELSE
BEGIN
    ALTER USER LabETLUser
        WITH DEFAULT_SCHEMA = etl;
END;
GO

IF DATABASE_PRINCIPAL_ID(N'LabAuditUser') IS NULL
BEGIN
    CREATE USER LabAuditUser
        WITHOUT LOGIN
        WITH DEFAULT_SCHEMA = etl;
END
ELSE
BEGIN
    ALTER USER LabAuditUser
        WITH DEFAULT_SCHEMA = etl;
END;
GO

------------------------------------------------------------
-- 5. REPORT READER PERMISSIONS
------------------------------------------------------------

GRANT SELECT
ON SCHEMA::report
TO rl_report_reader;
GO

GRANT EXECUTE
ON SCHEMA::report
TO rl_report_reader;
GO

------------------------------------------------------------
-- 6. ETL OPERATOR PERMISSIONS
------------------------------------------------------------

IF OBJECT_ID(N'etl.usp_ValidatePaymentTransactionBatch', N'P') IS NOT NULL
BEGIN
    GRANT EXECUTE
    ON OBJECT::etl.usp_ValidatePaymentTransactionBatch
    TO rl_etl_operator;
END;
GO

IF OBJECT_ID(N'etl.usp_LoadPaymentTransactionBatch', N'P') IS NOT NULL
BEGIN
    GRANT EXECUTE
    ON OBJECT::etl.usp_LoadPaymentTransactionBatch
    TO rl_etl_operator;
END;
GO

IF OBJECT_ID(N'etl.usp_CaptureFactValidationSnapshot', N'P') IS NOT NULL
BEGIN
    GRANT EXECUTE
    ON OBJECT::etl.usp_CaptureFactValidationSnapshot
    TO rl_etl_operator;
END;
GO

IF OBJECT_ID(N'stg.PaymentTransactionRaw', N'U') IS NOT NULL
BEGIN
    GRANT SELECT, INSERT
    ON OBJECT::stg.PaymentTransactionRaw
    TO rl_etl_operator;
END;
GO

IF OBJECT_ID(N'etl.ETLBatch', N'U') IS NOT NULL
BEGIN
    GRANT SELECT
    ON OBJECT::etl.ETLBatch
    TO rl_etl_operator;
END;
GO

IF OBJECT_ID(N'etl.ETLRunLog', N'U') IS NOT NULL
BEGIN
    GRANT SELECT
    ON OBJECT::etl.ETLRunLog
    TO rl_etl_operator;
END;
GO

IF OBJECT_ID(N'etl.PaymentTransactionReject', N'U') IS NOT NULL
BEGIN
    GRANT SELECT
    ON OBJECT::etl.PaymentTransactionReject
    TO rl_etl_operator;
END;
GO

IF OBJECT_ID(N'etl.PaymentTransactionLoadMap', N'U') IS NOT NULL
BEGIN
    GRANT SELECT
    ON OBJECT::etl.PaymentTransactionLoadMap
    TO rl_etl_operator;
END;
GO

IF OBJECT_ID(N'etl.FactValidationSnapshot', N'U') IS NOT NULL
BEGIN
    GRANT SELECT
    ON OBJECT::etl.FactValidationSnapshot
    TO rl_etl_operator;
END;
GO

------------------------------------------------------------
-- 7. AUDITOR PERMISSIONS
------------------------------------------------------------

IF OBJECT_ID(N'etl.ETLBatch', N'U') IS NOT NULL
BEGIN
    GRANT SELECT
    ON OBJECT::etl.ETLBatch
    TO rl_auditor;
END;
GO

IF OBJECT_ID(N'etl.ETLRunLog', N'U') IS NOT NULL
BEGIN
    GRANT SELECT
    ON OBJECT::etl.ETLRunLog
    TO rl_auditor;
END;
GO

IF OBJECT_ID(N'etl.PaymentTransactionReject', N'U') IS NOT NULL
BEGIN
    GRANT SELECT
    ON OBJECT::etl.PaymentTransactionReject
    TO rl_auditor;
END;
GO

IF OBJECT_ID(N'etl.PaymentTransactionLoadMap', N'U') IS NOT NULL
BEGIN
    GRANT SELECT
    ON OBJECT::etl.PaymentTransactionLoadMap
    TO rl_auditor;
END;
GO

IF OBJECT_ID(N'etl.FactValidationSnapshot', N'U') IS NOT NULL
BEGIN
    GRANT SELECT
    ON OBJECT::etl.FactValidationSnapshot
    TO rl_auditor;
END;
GO

------------------------------------------------------------
-- 8. ROLE MEMBERSHIPS
------------------------------------------------------------

IF NOT EXISTS
(
    SELECT 1
    FROM sys.database_role_members AS roleMember
    INNER JOIN sys.database_principals AS roleData
        ON roleData.principal_id = roleMember.role_principal_id
    INNER JOIN sys.database_principals AS memberData
        ON memberData.principal_id = roleMember.member_principal_id
    WHERE roleData.name = N'rl_report_reader'
      AND memberData.name = N'LabReportUser'
)
BEGIN
    ALTER ROLE rl_report_reader
    ADD MEMBER LabReportUser;
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.database_role_members AS roleMember
    INNER JOIN sys.database_principals AS roleData
        ON roleData.principal_id = roleMember.role_principal_id
    INNER JOIN sys.database_principals AS memberData
        ON memberData.principal_id = roleMember.member_principal_id
    WHERE roleData.name = N'rl_etl_operator'
      AND memberData.name = N'LabETLUser'
)
BEGIN
    ALTER ROLE rl_etl_operator
    ADD MEMBER LabETLUser;
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.database_role_members AS roleMember
    INNER JOIN sys.database_principals AS roleData
        ON roleData.principal_id = roleMember.role_principal_id
    INNER JOIN sys.database_principals AS memberData
        ON memberData.principal_id = roleMember.member_principal_id
    WHERE roleData.name = N'rl_auditor'
      AND memberData.name = N'LabAuditUser'
)
BEGIN
    ALTER ROLE rl_auditor
    ADD MEMBER LabAuditUser;
END;
GO

------------------------------------------------------------
-- 9. INSTALLATION CHECK: ROLE MEMBERS
------------------------------------------------------------

SELECT
    roleData.name AS DatabaseRole,
    memberData.name AS RoleMember,
    memberData.type_desc AS MemberType,
    memberData.default_schema_name AS DefaultSchema
FROM sys.database_role_members AS roleMember
INNER JOIN sys.database_principals AS roleData
    ON roleData.principal_id = roleMember.role_principal_id
INNER JOIN sys.database_principals AS memberData
    ON memberData.principal_id = roleMember.member_principal_id
WHERE roleData.name IN
      (
          N'rl_report_reader',
          N'rl_etl_operator',
          N'rl_auditor'
      )
ORDER BY
    roleData.name,
    memberData.name;
GO

------------------------------------------------------------
-- 10. OPTIONAL PERMISSION TESTS
------------------------------------------------------------

/*
    EXECUTE AS USER = 'LabReportUser';
    SELECT TOP (10) *
    FROM report.vw_MerchantDailyPaymentSummary;
    REVERT;

    EXECUTE AS USER = 'LabAuditUser';
    SELECT TOP (10) *
    FROM etl.ETLRunLog
    ORDER BY ETLRunID DESC;
    REVERT;
*/

SET NOCOUNT OFF;
GO