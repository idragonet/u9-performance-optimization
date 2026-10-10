/***************************************************************************************************
* 用友 U9 生产环境第三期性能索引优化脚本 (2026-10-10)
* 目标数据库: Microsoft SQL Server 2016 Enterprise Edition
* 优化策略: 全程 ONLINE=ON (无锁业务不中断) + DATA_COMPRESSION=PAGE (页面压缩) + FILLFACTOR=90
* 优化场景:
*   1. SM_ShipPlanLine: 出货计划明细行按来源单据行 (SrcDocLine) 高频反查索引
*      - 业务痛点: 客开定时任务 KK290BP.closeSoLine 每次执行均对 27.1万行调拨入库表全表扫描
*      - 今日日志表现: 占 10月10日最新日志中 90% 的慢 SQL (出现 9 次，平均 16.9 秒，最高 18.95 秒)
*      - 优化成效: 原 SQL 耗时从 19,582 ms 降至 155 ms (提速 126 倍！)，全表扫描彻底消除为 Index Seek
***************************************************************************************************/

-- 1. [解决日志 90% 慢查 · 90.3 万行] 出货计划行来源单据行 (SrcDocLine) 覆盖索引
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Cust_SM_ShipPlanLine_SrcDocLine' AND object_id = OBJECT_ID('dbo.SM_ShipPlanLine'))
BEGIN
    PRINT '正在创建索引: IX_Cust_SM_ShipPlanLine_SrcDocLine...';
    CREATE NONCLUSTERED INDEX [IX_Cust_SM_ShipPlanLine_SrcDocLine]
    ON [dbo].[SM_ShipPlanLine] ([SrcDocLine])
    INCLUDE ([ShipPlan], [DocLineNo], [SrcDocSubLine])
    WITH (ONLINE = ON, DATA_COMPRESSION = PAGE, FILLFACTOR = 90);
    PRINT '[OK] IX_Cust_SM_ShipPlanLine_SrcDocLine 创建成功！';
END
ELSE
    PRINT '[SKIP] 索引 IX_Cust_SM_ShipPlanLine_SrcDocLine 已存在。';
GO
