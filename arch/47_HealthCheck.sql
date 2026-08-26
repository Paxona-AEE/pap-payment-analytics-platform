
------------------------------------------------------------
-- STATISTICS SAĞLIK RAPORU
------------------------------------------------------------

SELECT
    schemaData.name AS SchemaName,
    objectData.name AS ObjectName,
    statisticsData.name AS StatisticsName,

    statisticsProperties.last_updated
        AS LastUpdatedDateTime,

    statisticsProperties.rows
        AS RowsAtLastUpdate,

    statisticsProperties.rows_sampled
        AS RowsSampled,

    statisticsProperties.modification_counter
        AS ModificationCounter,

    CAST(
        100.0 *
        statisticsProperties.modification_counter/
        NULLIF(
            statisticsProperties.rows,
            0
        )

        AS DECIMAL(10,2)
    ) AS ModificationPercent,

    statisticsData.auto_created
        AS IsAutoCreated,

    statisticsData.user_created
        AS IsUserCreated,

    statisticsData.no_recompute
        AS NoRecompute

FROM sys.stats AS statisticsData

INNER JOIN sys.objects AS objectData
    ON objectData.object_id =
       statisticsData.object_id

INNER JOIN sys.schemas AS schemaData
    ON schemaData.schema_id =
       objectData.schema_id

OUTER APPLY sys.dm_db_stats_properties
(
    statisticsData.object_id,
    statisticsData.stats_id
) AS statisticsProperties

WHERE objectData.type IN
      (
          'U',
          'V'
      )

  AND objectData.is_ms_shipped = 0

ORDER BY
    statisticsProperties.modification_counter DESC,
    schemaData.name,
    objectData.name,
    statisticsData.name;
GO


------------------------------------------------------------
-- COLUMNSTORE ROWGROUP SAĞLIK RAPORU
------------------------------------------------------------

SELECT
    schemaData.name AS SchemaName,
    tableData.name AS TableName,
    indexData.name AS IndexName,

    rowGroup.partition_number
        AS PartitionNumber,

    rowGroup.row_group_id
        AS RowGroupID,

    rowGroup.state_desc
        AS RowGroupState,

    rowGroup.total_rows
        AS TotalRows,

    rowGroup.deleted_rows
        AS DeletedRows,

    CAST
    (
        100.0 *
        rowGroup.deleted_rows
        /
        NULLIF
        (
            rowGroup.total_rows,
            0
        )

        AS DECIMAL(10,2)
    ) AS DeletedRowPercent,

    rowGroup.created_time
        AS CreatedDateTime,

    rowGroup.closed_time
        AS ClosedDateTime

FROM sys.dm_db_column_store_row_group_physical_stats
     AS rowGroup

INNER JOIN sys.indexes AS indexData
    ON indexData.object_id =
       rowGroup.object_id

   AND indexData.index_id =
       rowGroup.index_id

INNER JOIN sys.tables AS tableData
    ON tableData.object_id =
       indexData.object_id

INNER JOIN sys.schemas AS schemaData
    ON schemaData.schema_id =
       tableData.schema_id

ORDER BY
    schemaData.name,
    tableData.name,
    indexData.name,
    rowGroup.partition_number,
    rowGroup.row_group_id;
GO







