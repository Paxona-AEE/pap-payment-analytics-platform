ALTER TABLE dw.DimCustomer
DROP CONSTRAINT UQ_DimCustomer_CustomerID;

ALTER TABLE dw.DimCard
DROP CONSTRAINT UQ_DimCard_CardID;

ALTER TABLE dw.DimMerchant
DROP CONSTRAINT UQ_DimMerchant_MerchantID;

--Gonna alter some constraints in order to main the SCD Type 2, history management
--Uniquness according to both customer id and the effective start date, it is best to cover so!

ALTER TABLE dw.DimCustomer
ADD CONSTRAINT UQ_DimCustomer_Version
UNIQUE (CustomerID, EffectiveStartDate);

ALTER TABLE dw.DimCard
ADD CONSTRAINT UQ_DimCard_Version
UNIQUE (CardID, EffectiveStartDate);

ALTER TABLE dw.DimMerchant
ADD CONSTRAINT UQ_DimMerchant_Version
UNIQUE (MerchantID, EffectiveStartDate);