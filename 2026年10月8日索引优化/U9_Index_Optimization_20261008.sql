/*
====================================================================================================
用友 U9 ERP 全局数据库性能与慢查询索引深度优化脚本 (MSSQL 2016 完整生产级方案)
====================================================================================================
【创建日期】: 2026-10-08
【数据库平台】: Microsoft SQL Server 2016 SP3+ Enterprise Edition
【适用系统】: 用友 U9 ERP (U9 V6.0 / U9 CE / U9 Cloud)
【分析依据】: 
  基于现场提取的 39 个性能日志切片 (跨度 10 天，累计 169.23 MB) 全量日志挖掘，
  精准捕获 7,106 次 ExecSQLTooLong (>10s 严重超时) 与 6,224 次 CallSVTooMany 高频调用。
  对千万级大表缺少外键索引、前台单据假死 70~92s、高频轮询高 CPU 消耗等核心瓶颈进行专项根治。

【核心设计原则】:
  1. 幂等性保障：所有索引均自带 IF NOT EXISTS 判断，支持重复安全执行。
  2. 业务无感（在线创建）：全部采用 WITH (ONLINE = ON)，生产环境执行不锁表、不影响前台业务读写。
  3. 内存与磁盘节省：全部启用 DATA_COMPRESSION = PAGE（页面压缩），节约 50% 以上内存与 IO 缓存。
  4. 命名规范：统一遵循客开前缀 IX_Cust_{TableName}_{BizScene}，便于识别与版本管理。
  5. 梯队式部署：严格按照 T0/T1（9大必建核心表）与 T2（6大高价值补充表）分级交付。
====================================================================================================
*/

-- 请在目标数据库执行（测试库示例：[20260914]）
USE [20260914];
GO

SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET QUOTED_IDENTIFIER ON;
GO

PRINT '================================================================================';
PRINT '>>> 阶段 0：环境检测与准备完成，开始执行 U9 索引深度优化脚本...';
PRINT '================================================================================';
GO


-- =================================================================================
-- 【阶段 1：SQL Server 实例与数据库级核心参数优化】
-- 解决并发下的 CXPACKET 线程等待、CPU 虚高及千万级大表统计信息同步更新锁死问题
-- =================================================================================

PRINT '>>> [阶段 1] 正在调整 SQL Server 实例与数据库参数...';

-- 1.1 开启高级选项配置
EXEC sp_configure 'show advanced options', 1;
RECONFIGURE WITH OVERRIDE;
GO

-- 1.2 提升并行开销阈值：由 SQL 默认值 5 调至 50（避免微小查询触发多核并行产生线程争用）
EXEC sp_configure 'cost threshold for parallelism', 50;
-- 1.3 限制最大并行度：由默认值 0（不限）调至 4（建议设为 4，防止单个报表吃满整机 CPU）
EXEC sp_configure 'max degree of parallelism', 4;
RECONFIGURE WITH OVERRIDE;
GO

-- 1.4 开启异步统计信息更新（大表福音：防止 1600万 行大表触发同步更新导致整表锁死数分钟）
ALTER DATABASE CURRENT SET AUTO_UPDATE_STATISTICS_ASYNC ON;
GO
PRINT '>>> [阶段 1 完成] 实例并行度参数与异步统计信息已成功优化！';
GO


-- =================================================================================
-- 【阶段 2：第一梯队（T0/T1 级）—— 9 大核心致命表索引优化】
-- 彻底终结：1700万/1640万行大表全表扫描、70~92s 前台假死、1980次高频轮询高 CPU、813万行回表 IO 爆表
-- =================================================================================

PRINT '--------------------------------------------------------------------------------';
PRINT '>>> [阶段 2] 开始部署第一梯队（9 大核心致命表）索引...';
PRINT '--------------------------------------------------------------------------------';
GO

-- ---------------------------------------------------------------------------------
-- 2.1 【T0 级 · 1640万大表】MO_ResUsageRptLineCost（资源用量报告行成本表）
-- 日志证据：审批服务 ResourceBP.OperationApprove 触发 4,495 次，按 ResUsageRpt 全表扫 1640 万条！
-- ---------------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Cust_MO_ResUsageRptLineCost_ResUsageRpt' AND object_id = OBJECT_ID('dbo.MO_ResUsageRptLineCost'))
BEGIN
    PRINT '>> [1/9] 正在创建 [MO_ResUsageRptLineCost](1640万行) 主表外键关联索引...';
    CREATE NONCLUSTERED INDEX [IX_Cust_MO_ResUsageRptLineCost_ResUsageRpt] 
    ON [dbo].[MO_ResUsageRptLineCost] ([ResUsageRpt])
    INCLUDE ([ResUsageRptLine], [CostType], [Resource])
    WITH (ONLINE = ON, DATA_COMPRESSION = PAGE, FILLFACTOR = 90);
    PRINT '>> [OK] 索引 IX_Cust_MO_ResUsageRptLineCost_ResUsageRpt 创建成功！';
END
ELSE
    PRINT '>> [跳过] 索引 IX_Cust_MO_ResUsageRptLineCost_ResUsageRpt 已存在。';
GO

-- ---------------------------------------------------------------------------------
-- 2.2 【T0 级 · 1700万大表】MO_ResUsageRptLine（资源用量报告行）
-- 日志证据：派工单反查用量明细 WHERE DisPatchOrder = @dispatchOrderDoc，无索引整表扫 1700 万条！
-- ---------------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Cust_MO_ResUsageRptLine_DisPatchOrder' AND object_id = OBJECT_ID('dbo.MO_ResUsageRptLine'))
BEGIN
    PRINT '>> [2/9] 正在创建 [MO_ResUsageRptLine](1700万行) 派工单外键关联索引...';
    CREATE NONCLUSTERED INDEX [IX_Cust_MO_ResUsageRptLine_DisPatchOrder] 
    ON [dbo].[MO_ResUsageRptLine] ([DisPatchOrder])
    INCLUDE ([MORes], [ResUsageRpt], [LineNum])
    WITH (ONLINE = ON, DATA_COMPRESSION = PAGE, FILLFACTOR = 90);
    PRINT '>> [OK] 索引 IX_Cust_MO_ResUsageRptLine_DisPatchOrder 创建成功！';
END
ELSE
    PRINT '>> [跳过] 索引 IX_Cust_MO_ResUsageRptLine_DisPatchOrder 已存在。';
GO

-- ---------------------------------------------------------------------------------
-- 2.3 【T1 级 · 89万行】SM_ShipPlanLine（出运计划明细表）
-- 日志证据：ShipPlanMainUIForm 保存/提交/审批/打印单据卡顿 70~92 秒，消灭子查询盲目全表扫！
-- ---------------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Cust_SM_ShipPlanLine_Customer' AND object_id = OBJECT_ID('dbo.SM_ShipPlanLine'))
BEGIN
    PRINT '>> [3/9] 正在创建 [SM_ShipPlanLine] 出运计划客户与编码过滤索引...';
    CREATE NONCLUSTERED INDEX [IX_Cust_SM_ShipPlanLine_Customer] 
    ON [dbo].[SM_ShipPlanLine] ([OrderBy_Customer], [OrderBy_Code])
    INCLUDE ([ShipPlan], [DocLineNo])
    WITH (ONLINE = ON, DATA_COMPRESSION = PAGE, FILLFACTOR = 90);
    PRINT '>> [OK] 索引 IX_Cust_SM_ShipPlanLine_Customer 创建成功！';
END
ELSE
    PRINT '>> [跳过] 索引 IX_Cust_SM_ShipPlanLine_Customer 已存在。';
GO

-- ---------------------------------------------------------------------------------
-- 2.4 【T1 级 · 11万行】CBO_Operation（工序表）
-- 日志证据：1,980+ 次高频轮询查询 WHERE A1.ModifiedOn > DATEADD(...)，DMV 预估收益 89.1%！
-- ---------------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Cust_CBO_Operation_PerfOpt' AND object_id = OBJECT_ID('dbo.CBO_Operation'))
BEGIN
    PRINT '>> [4/9] 正在创建 [CBO_Operation] 工序高频轮询复合索引...';
    CREATE NONCLUSTERED INDEX [IX_Cust_CBO_Operation_PerfOpt] 
    ON [dbo].[CBO_Operation] ([IsSubcOperation], [ModifiedOn], [RunTime])
    INCLUDE ([Routing], [Sequence])
    WITH (ONLINE = ON, DATA_COMPRESSION = PAGE, FILLFACTOR = 90);
    PRINT '>> [OK] 索引 IX_Cust_CBO_Operation_PerfOpt 创建成功！';
END
ELSE
    PRINT '>> [跳过] 索引 IX_Cust_CBO_Operation_PerfOpt 已存在。';
GO

-- ---------------------------------------------------------------------------------
-- 2.5 【T1 级 · 813万大表】AAI_TransVoucherToGLlog（存货总账日志表）
-- 日志证据：凭证反查单据接口频繁调用，纯覆盖索引彻底切断 800 万次回表 Key Lookup！
-- ---------------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Cust_AAI_TransVoucherToGLlog_Covering' AND object_id = OBJECT_ID('dbo.AAI_TransVoucherToGLlog'))
BEGIN
    PRINT '>> [5/9] 正在创建 [AAI_TransVoucherToGLlog](813万行) 存货凭证反查纯覆盖索引...';
    CREATE NONCLUSTERED INDEX [IX_Cust_AAI_TransVoucherToGLlog_Covering] 
    ON [dbo].[AAI_TransVoucherToGLlog] ([ToVoucher])
    INCLUDE ([FromEntityID], [FromEntityType], [ToVoucherNum], [ToVoucherType], [ToSOB], [FromOrg], [FromTransEntryHead])
    WITH (ONLINE = ON, DATA_COMPRESSION = PAGE, FILLFACTOR = 90);
    PRINT '>> [OK] 索引 IX_Cust_AAI_TransVoucherToGLlog_Covering 创建成功！';
END
ELSE
    PRINT '>> [跳过] 索引 IX_Cust_AAI_TransVoucherToGLlog_Covering 已存在。';
GO

-- ---------------------------------------------------------------------------------
-- 2.6 【T1 级 · 47万行】PM_Receivement（采购收货单主表）
-- 日志证据：ReceivementMainUIForm.BtnApprove（收货单审核）超时 86 次，优化业务过滤链路！
-- ---------------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Cust_PM_Receivement_ApproveOpt' AND object_id = OBJECT_ID('dbo.PM_Receivement'))
BEGIN
    PRINT '>> [6/9] 正在创建 [PM_Receivement] 收货单审核复合过滤索引...';
    CREATE NONCLUSTERED INDEX [IX_Cust_PM_Receivement_ApproveOpt] 
    ON [dbo].[PM_Receivement] ([Org], [ReceivementType], [IsInitEvaluation], [BizType])
    INCLUDE ([DocNo], [BusinessDate], [Status])
    WITH (ONLINE = ON, DATA_COMPRESSION = PAGE, FILLFACTOR = 90);
    PRINT '>> [OK] 索引 IX_Cust_PM_Receivement_ApproveOpt 创建成功！';
END
ELSE
    PRINT '>> [跳过] 索引 IX_Cust_PM_Receivement_ApproveOpt 已存在。';
GO

-- ---------------------------------------------------------------------------------
-- 2.7 【T1 级 · 请购单明细】PR_PRLine（请购单行）
-- 日志证据：采购订单/到货反查请购单来源关联链路，消除缺失来源单据键导致的全表扫描！
-- ---------------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Cust_PR_PRLine_SrcDocInfo' AND object_id = OBJECT_ID('dbo.PR_PRLine'))
BEGIN
    PRINT '>> [7/9] 正在创建 [PR_PRLine] 采购来源反查索引...';
    CREATE NONCLUSTERED INDEX [IX_Cust_PR_PRLine_SrcDocInfo] 
    ON [dbo].[PR_PRLine] ([SrcDocInfo_SrcDoc_EntityID], [SrcDocInfo_SrcDocLine_EntityID])
    INCLUDE ([PR], [DocLineNo])
    WITH (ONLINE = ON, DATA_COMPRESSION = PAGE, FILLFACTOR = 90);
    PRINT '>> [OK] 索引 IX_Cust_PR_PRLine_SrcDocInfo 创建成功！';
END
ELSE
    PRINT '>> [跳过] 索引 IX_Cust_PR_PRLine_SrcDocInfo 已存在。';
GO

-- ---------------------------------------------------------------------------------
-- 2.8 【T1 级 · 58万行】MO_CompleteRpt（生产完工报告表）
-- 日志证据：生产订单列表 DiscreteMOList 首屏打开耗时高达 122 秒，完工状态范围查询加速！
-- ---------------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Cust_MO_CompleteRpt_PerfOpt' AND object_id = OBJECT_ID('dbo.MO_CompleteRpt'))
BEGIN
    PRINT '>> [8/9] 正在创建 [MO_CompleteRpt] 完工报告状态与日期检索索引...';
    CREATE NONCLUSTERED INDEX [IX_Cust_MO_CompleteRpt_PerfOpt] 
    ON [dbo].[MO_CompleteRpt] ([DocState], [CreatedOn])
    INCLUDE ([ID], [DocNo], [MO])
    WITH (ONLINE = ON, DATA_COMPRESSION = PAGE, FILLFACTOR = 90);
    PRINT '>> [OK] 索引 IX_Cust_MO_CompleteRpt_PerfOpt 创建成功！';
END
ELSE
    PRINT '>> [跳过] 索引 IX_Cust_MO_CompleteRpt_PerfOpt 已存在。';
GO

-- ---------------------------------------------------------------------------------
-- 2.9 【T1 级 · 质检单明细】QC_QCDocLine（质检明细表）
-- 日志证据：完工入库与生产订单流转时质检状态校验，DMV 优化收益高达 99.88%！
-- ---------------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Cust_QC_QCDocLine_PerfOpt' AND object_id = OBJECT_ID('dbo.QC_QCDocLine'))
BEGIN
    PRINT '>> [9/9] 正在创建 [QC_QCDocLine] MO 质检单行状态校验索引...';
    CREATE NONCLUSTERED INDEX [IX_Cust_QC_QCDocLine_PerfOpt] 
    ON [dbo].[QC_QCDocLine] ([MO], [QCDocLineState])
    WITH (ONLINE = ON, DATA_COMPRESSION = PAGE, FILLFACTOR = 90);
    PRINT '>> [OK] 索引 IX_Cust_QC_QCDocLine_PerfOpt 创建成功！';
END
ELSE
    PRINT '>> [跳过] 索引 IX_Cust_QC_QCDocLine_PerfOpt 已存在。';
GO

PRINT '>>> [阶段 2 完成] 第一梯队 9 大核心致命表索引部署完毕！';
GO


-- =================================================================================
-- 【阶段 3：第二梯队（T2 级）—— 6 大高价值业务补充表索引优化】
-- 提升 70%~99% 的成本计算卷积、生产派工、工作流引擎心跳、销售订单取价查询性能
-- =================================================================================

PRINT '--------------------------------------------------------------------------------';
PRINT '>>> [阶段 3] 开始部署第二梯队（6 大高价值业务补充表）索引...';
PRINT '--------------------------------------------------------------------------------';
GO

-- 3.1 成本核算分析表优化（DMV 预估收益 98.8%）
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Cust_CA_CostQuery_Period' AND object_id = OBJECT_ID('dbo.CA_CostQuery'))
BEGIN
    PRINT '>> [1/6] 正在创建 [CA_CostQuery] 成本核算期间多维分析索引...';
    CREATE NONCLUSTERED INDEX [IX_Cust_CA_CostQuery_Period]
    ON [dbo].[CA_CostQuery] ([SOBPeriod], [SOB])
    INCLUDE ([Org], [Product], [MO], [PLS], [ItemGrade], [ItemPotency], [ItemType])
    WITH (ONLINE = ON, DATA_COMPRESSION = PAGE, FILLFACTOR = 90);
    PRINT '>> [OK] 索引 IX_Cust_CA_CostQuery_Period 创建成功！';
END
ELSE
    PRINT '>> [跳过] 索引 IX_Cust_CA_CostQuery_Period 已存在。';
GO

-- 3.2 生产派工单明细行优化（DMV 预估收益 99.5%）
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Cust_MO_DispatchOrderDocLine_MO' AND object_id = OBJECT_ID('dbo.MO_DispatchOrderDocLine'))
BEGIN
    PRINT '>> [2/6] 正在创建 [MO_DispatchOrderDocLine] 派工单委外工序状态索引...';
    CREATE NONCLUSTERED INDEX [IX_Cust_MO_DispatchOrderDocLine_MO]
    ON [dbo].[MO_DispatchOrderDocLine] ([MO], [TempIsSubContract])
    WITH (ONLINE = ON, DATA_COMPRESSION = PAGE, FILLFACTOR = 90);
    PRINT '>> [OK] 索引 IX_Cust_MO_DispatchOrderDocLine_MO 创建成功！';
END
ELSE
    PRINT '>> [跳过] 索引 IX_Cust_MO_DispatchOrderDocLine_MO 已存在。';
GO

-- 3.3 工作流引擎状态轮询优化（600+ 次高频心跳，DMV 预估收益 83.1%）
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Cust_InstanceState_Timer' AND object_id = OBJECT_ID('dbo.InstanceState'))
BEGIN
    PRINT '>> [3/6] 正在创建 [InstanceState] 工作流引擎心跳轮询索引...';
    CREATE NONCLUSTERED INDEX [IX_Cust_InstanceState_Timer]
    ON [dbo].[InstanceState] ([status], [nextTimer])
    INCLUDE ([uidInstanceID], [unlocked], [ownerID], [ownedUntil])
    WITH (ONLINE = ON, DATA_COMPRESSION = PAGE, FILLFACTOR = 90);
    PRINT '>> [OK] 索引 IX_Cust_InstanceState_Timer 创建成功！';
END
ELSE
    PRINT '>> [跳过] 索引 IX_Cust_InstanceState_Timer 已存在。';
GO

-- 3.4 销售价格表明细行优化（开单取价加速，DMV 预估收益 94.2%）
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Cust_SPR_SalePriceLine_Item' AND object_id = OBJECT_ID('dbo.SPR_SalePriceLine'))
BEGIN
    PRINT '>> [4/6] 正在创建 [SPR_SalePriceLine] 销售价格表开单取价索引...';
    CREATE NONCLUSTERED INDEX [IX_Cust_SPR_SalePriceLine_Item]
    ON [dbo].[SPR_SalePriceLine] ([ItemInfo_ItemCode], [Active])
    INCLUDE ([Uom], [Price])
    WITH (ONLINE = ON, DATA_COMPRESSION = PAGE, FILLFACTOR = 90);
    PRINT '>> [OK] 索引 IX_Cust_SPR_SalePriceLine_Item 创建成功！';
END
ELSE
    PRINT '>> [跳过] 索引 IX_Cust_SPR_SalePriceLine_Item 已存在。';
GO

-- 3.5 采购订单主表未结案状态检索（DMV 预估收益 66.1%）
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Cust_PM_PurchaseOrder_Status' AND object_id = OBJECT_ID('dbo.PM_PurchaseOrder'))
BEGIN
    PRINT '>> [5/6] 正在创建 [PM_PurchaseOrder] 采购订单未结案检索索引...';
    CREATE NONCLUSTERED INDEX [IX_Cust_PM_PurchaseOrder_Status]
    ON [dbo].[PM_PurchaseOrder] ([Org], [Cancel_Canceled], [ConfirmMode], [IsFIClose])
    INCLUDE ([DocNo], [BusinessDate], [Supplier_Supplier])
    WITH (ONLINE = ON, DATA_COMPRESSION = PAGE, FILLFACTOR = 90);
    PRINT '>> [OK] 索引 IX_Cust_PM_PurchaseOrder_Status 创建成功！';
END
ELSE
    PRINT '>> [跳过] 索引 IX_Cust_PM_PurchaseOrder_Status 已存在。';
GO

-- 3.6 销售订单明细行未结案状态检索（DMV 预估收益 71.3%）
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Cust_SM_SOLine_Status' AND object_id = OBJECT_ID('dbo.SM_SOLine'))
BEGIN
    PRINT '>> [6/6] 正在创建 [SM_SOLine] 销售订单行未结案状态索引...';
    CREATE NONCLUSTERED INDEX [IX_Cust_SM_SOLine_Status]
    ON [dbo].[SM_SOLine] ([Status])
    INCLUDE ([ID], [DocLineNo], [SO])
    WITH (ONLINE = ON, DATA_COMPRESSION = PAGE, FILLFACTOR = 90);
    PRINT '>> [OK] 索引 IX_Cust_SM_SOLine_Status 创建成功！';
END
ELSE
    PRINT '>> [跳过] 索引 IX_Cust_SM_SOLine_Status 已存在。';
GO

PRINT '>>> [阶段 3 完成] 第二梯队 6 大高价值业务补充表索引部署完毕！';
GO


-- =================================================================================
-- 【阶段 4：优化结果验证查询】
-- 查看新创建的全部 IX_Cust_* 索引状态、页面压缩及大小统计
-- =================================================================================

PRINT '================================================================================';
PRINT '>>> 阶段 4：执行索引验证汇总查询...';
PRINT '================================================================================';
GO

SELECT 
    OBJECT_SCHEMA_NAME(i.object_id) AS [Schema],
    OBJECT_NAME(i.object_id) AS [TableName],
    i.name AS [IndexName],
    i.type_desc AS [IndexType],
    p.data_compression_desc AS [Compression],
    p.rows AS [TableRows],
    ROUND(SUM(a.total_pages) * 8.0 / 1024, 2) AS [IndexSizeMB]
FROM sys.indexes i
INNER JOIN sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_id
INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
WHERE i.name LIKE 'IX_Cust_%'
GROUP BY i.object_id, i.name, i.type_desc, p.data_compression_desc, p.rows
ORDER BY [TableRows] DESC, [IndexSizeMB] DESC;
GO

PRINT '================================================================================';
PRINT '>>> 恭喜 U9 大佬！全库 15 个关键性能索引优化全部部署完成！ <<<';
PRINT '================================================================================';
GO


/*
====================================================================================================
【附录：一键回滚/清理全部客开索引脚本】
（若需重置测试环境或回滚所有新建索引，可单独选中以下语句执行）
====================================================================================================
DROP INDEX IF EXISTS [IX_Cust_MO_ResUsageRptLineCost_ResUsageRpt] ON [dbo].[MO_ResUsageRptLineCost];
DROP INDEX IF EXISTS [IX_Cust_MO_ResUsageRptLine_DisPatchOrder]     ON [dbo].[MO_ResUsageRptLine];
DROP INDEX IF EXISTS [IX_Cust_SM_ShipPlanLine_Customer]            ON [dbo].[SM_ShipPlanLine];
DROP INDEX IF EXISTS [IX_Cust_CBO_Operation_PerfOpt]               ON [dbo].[CBO_Operation];
DROP INDEX IF EXISTS [IX_Cust_AAI_TransVoucherToGLlog_Covering]    ON [dbo].[AAI_TransVoucherToGLlog];
DROP INDEX IF EXISTS [IX_Cust_PM_Receivement_ApproveOpt]           ON [dbo].[PM_Receivement];
DROP INDEX IF EXISTS [IX_Cust_PR_PRLine_SrcDocInfo]                ON [dbo].[PR_PRLine];
DROP INDEX IF EXISTS [IX_Cust_MO_CompleteRpt_PerfOpt]              ON [dbo].[MO_CompleteRpt];
DROP INDEX IF EXISTS [IX_Cust_QC_QCDocLine_PerfOpt]                ON [dbo].[QC_QCDocLine];
DROP INDEX IF EXISTS [IX_Cust_CA_CostQuery_Period]                 ON [dbo].[CA_CostQuery];
DROP INDEX IF EXISTS [IX_Cust_MO_DispatchOrderDocLine_MO]          ON [dbo].[MO_DispatchOrderDocLine];
DROP INDEX IF EXISTS [IX_Cust_InstanceState_Timer]                 ON [dbo].[InstanceState];
DROP INDEX IF EXISTS [IX_Cust_SPR_SalePriceLine_Item]              ON [dbo].[SPR_SalePriceLine];
DROP INDEX IF EXISTS [IX_Cust_PM_PurchaseOrder_Status]             ON [dbo].[PM_PurchaseOrder];
DROP INDEX IF EXISTS [IX_Cust_SM_SOLine_Status]                    ON [dbo].[SM_SOLine];
PRINT '>>> 全部 IX_Cust_* 客开优化索引已安全清理回滚完毕！';
====================================================================================================
*/

