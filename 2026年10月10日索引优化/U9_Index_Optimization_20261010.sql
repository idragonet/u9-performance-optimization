/***************************************************************************************************
* 用友 U9 生产环境第三期性能索引优化全量脚本 (2026-10-10)
* 目标数据库: Microsoft SQL Server 2016 Enterprise Edition
* 覆盖场景: 
*   - 场景 A: Portal/Web 前台客开高频定时关单任务 (closeSoLine 19.5s -> 0.15s 提速 126 倍)
*   - 场景 B: ApplicationServer 后台重型批处理引擎 (MRP 运算全流程 50+ 小时累计耗时治理)
*   - 场景 C: 存货核算月结与期间统计 (MonthClose 22.2 分钟长事务削减)
* 优化策略: 全程 ONLINE=ON (无锁业务不中断) + DATA_COMPRESSION=PAGE (页面压缩) + FILLFACTOR=90
* 包含索引清单:
*   1. SM_ShipPlanLine: 出货计划行来源单据行反查索引 (90.3万行，解决 closeSoLine 19.5s 慢查，已在正式库部署)
*   2. SM_ForecastOrderLine: 预测订单行主表外键索引 (30.8万行，解决 MRP_GetForecastOrder 7,911s/2小时慢查)
*   3. MRP_PlanOrderConsumption: 计划订单消退下发单据反查索引 (50.7万行，解决 MRP_Output 54,867s 卡顿)
*   4. PM_POLine: 采购订单行状态与MRP需求复合索引 (65.1万行，解决 MRP_GetPurchaseOrder 182,363s/50小时瓶颈)
*   5. InvTrans_DayClose: 存货日结状态检查极速覆盖索引 (152.3万行，解决存货月结 1,336s/22分钟卡顿，消灭 6.1万次未命中)
*   6. MRP_SimuPlanOrder: 模拟计划订单替代料与版本复合索引 (13万行，加速 MRP_MainVersionProcess 替代料计算)
*   7. InvTrans_WhQoh: 仓库现存量可用量快速覆盖索引 (42.9万行，解决 MRP_Pretreatment 14,156s 现存量预处理)
*   8. InvTrans_AccountPeriodLine: 存货期间核算行组织与日期范围索引 (加速月结期间统计 StatPeriodQueryInvTotal)
***************************************************************************************************/

-- =================================================================================================
-- 1. [解决日志 90% 慢查 · 90.3 万行] 出货计划行来源单据行 (SrcDocLine) 覆盖索引
-- 业务场景: 客开定时任务 KK290BP.closeSoLine() 自动关闭销售订单行，消除 27.1万行调拨单聚集索引全表扫描
-- 实测成效: 正式库耗时由 19,582 ms (19.5秒) 降至 155 ms (0.15秒)，提速 126 倍！
-- =================================================================================================
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

-- =================================================================================================
-- 2. [解决 MRP_GetForecastOrder 7,911秒/2小时慢查 · 30.8 万行] 预测订单行主表外键覆盖索引
-- 业务场景: MRP 运算提取预测订单需求，官方仅有物料索引，缺少主表外键 ForecastOrder 索引
-- 预期改善: 消除 28,042 次未命中全表扫描，DMV 预估改善度 91.36% ~ 99.78%
-- =================================================================================================
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Cust_SM_ForecastOrderLine_ForecastOrder' AND object_id = OBJECT_ID('dbo.SM_ForecastOrderLine'))
BEGIN
    PRINT '正在创建索引: IX_Cust_SM_ForecastOrderLine_ForecastOrder...';
    CREATE NONCLUSTERED INDEX [IX_Cust_SM_ForecastOrderLine_ForecastOrder]
    ON [dbo].[SM_ForecastOrderLine] ([ForecastOrder])
    INCLUDE ([ItemInfo_ItemID], [ShipPlanDate], [Num], [SupplyOrg], [Status])
    WITH (ONLINE = ON, DATA_COMPRESSION = PAGE, FILLFACTOR = 90);
    PRINT '[OK] IX_Cust_SM_ForecastOrderLine_ForecastOrder 创建成功！';
END
ELSE
    PRINT '[SKIP] 索引 IX_Cust_SM_ForecastOrderLine_ForecastOrder 已存在。';
GO

-- =================================================================================================
-- 3. [解决 MRP_Output 54,867秒/单次最长10分钟 · 50.7 万行] 计划订单消退下发单据反查索引
-- 业务场景: MRP 计划订单输出、单据下发与消退关系回写，按 ReleaseDoc_EntityID 反查消退表
-- 预期改善: 消除 12,330 次未命中全表扫描，DMV 预估改善度 99.64%
-- =================================================================================================
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Cust_MRP_PlanOrderConsumption_ReleaseDoc' AND object_id = OBJECT_ID('dbo.MRP_PlanOrderConsumption'))
BEGIN
    PRINT '正在创建索引: IX_Cust_MRP_PlanOrderConsumption_ReleaseDoc...';
    CREATE NONCLUSTERED INDEX [IX_Cust_MRP_PlanOrderConsumption_ReleaseDoc]
    ON [dbo].[MRP_PlanOrderConsumption] ([ReleaseDoc_EntityID])
    INCLUDE ([PlanOrder])
    WITH (ONLINE = ON, DATA_COMPRESSION = PAGE, FILLFACTOR = 90);
    PRINT '[OK] IX_Cust_MRP_PlanOrderConsumption_ReleaseDoc 创建成功！';
END
ELSE
    PRINT '[SKIP] 索引 IX_Cust_MRP_PlanOrderConsumption_ReleaseDoc 已存在。';
GO

-- =================================================================================================
-- 4. [解决 MRP_GetPurchaseOrder 182,363秒/50小时大瓶颈 · 65.1 万行] 采购订单行状态与MRP需求索引
-- 业务场景: MRP 提取采购在途与需求供给，高频按 [Cancel_Canceled=0]、[Status=2 已核准]、[IsMRPDemand=1] 过滤
-- 预期改善: 消除 65 万行采购订单行全表扫描，DMV 评分 12.9 万分，消除高频回表
-- =================================================================================================
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Cust_PM_POLine_Status_MRP' AND object_id = OBJECT_ID('dbo.PM_POLine'))
BEGIN
    PRINT '正在创建索引: IX_Cust_PM_POLine_Status_MRP...';
    CREATE NONCLUSTERED INDEX [IX_Cust_PM_POLine_Status_MRP]
    ON [dbo].[PM_POLine] ([Cancel_Canceled], [Status], [IsMRPDemand])
    INCLUDE ([ID], [PurchaseOrder], [ItemInfo_ItemID], [DocLineNo], [FAS])
    WITH (ONLINE = ON, DATA_COMPRESSION = PAGE, FILLFACTOR = 90);
    PRINT '[OK] IX_Cust_PM_POLine_Status_MRP 创建成功！';
END
ELSE
    PRINT '[SKIP] 索引 IX_Cust_PM_POLine_Status_MRP 已存在。';
GO

-- =================================================================================================
-- 5. [解决存货月结 1,336秒/22.2分钟卡顿 · 152.3 万行] 存货日结状态检查极速覆盖索引
-- 业务场景: 存货核算月结 P_InvTrans_MonthClose_AccountPeriodTotal 高频检查日结闭环状态
-- 预期改善: 补齐 CloseDate 与 IsClose，消除 61,692 次回表，DMV 预估改善度高达 99.82%！
-- =================================================================================================
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Cust_InvTrans_DayClose_Org_Wh_Date' AND object_id = OBJECT_ID('dbo.InvTrans_DayClose'))
BEGIN
    PRINT '正在创建索引: IX_Cust_InvTrans_DayClose_Org_Wh_Date...';
    CREATE NONCLUSTERED INDEX [IX_Cust_InvTrans_DayClose_Org_Wh_Date]
    ON [dbo].[InvTrans_DayClose] ([Org], [Wh], [CloseDate], [IsClose])
    WITH (ONLINE = ON, DATA_COMPRESSION = PAGE, FILLFACTOR = 90);
    PRINT '[OK] IX_Cust_InvTrans_DayClose_Org_Wh_Date 创建成功！';
END
ELSE
    PRINT '[SKIP] 索引 IX_Cust_InvTrans_DayClose_Org_Wh_Date 已存在。';
GO

-- =================================================================================================
-- 6. [解决 MRP_MainVersionProcess 5,004秒 · 13.0 万行] 模拟计划订单替代料与版本复合索引
-- 业务场景: MRP 模拟运算、主版本批处理与替代料净需求匹配
-- 预期改善: 补齐替代料引导列，消除 348,302 次 Seek 未命中，DMV 评分高达 58.8 万分！
-- =================================================================================================
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Cust_MRP_SimuPlanOrder_Sub_Version' AND object_id = OBJECT_ID('dbo.MRP_SimuPlanOrder'))
BEGIN
    PRINT '正在创建索引: IX_Cust_MRP_SimuPlanOrder_Sub_Version...';
    CREATE NONCLUSTERED INDEX [IX_Cust_MRP_SimuPlanOrder_Sub_Version]
    ON [dbo].[MRP_SimuPlanOrder] ([IsSubstitute], [PlanVersion])
    INCLUDE ([ID], [Item], [InputQty], [AdjustDemandDate], [PlantOrg], [SupplyOrg])
    WITH (ONLINE = ON, DATA_COMPRESSION = PAGE, FILLFACTOR = 90);
    PRINT '[OK] IX_Cust_MRP_SimuPlanOrder_Sub_Version 创建成功！';
END
ELSE
    PRINT '[SKIP] 索引 IX_Cust_MRP_SimuPlanOrder_Sub_Version 已存在。';
GO

-- =================================================================================================
-- 7. [解决 MRP_Pretreatment 14,156秒 · 42.9 万行] 仓库现存量可用量快速覆盖索引
-- 业务场景: MRP 净需求展开前置阶段快速加载各仓库物料现存量、预留量与可用量
-- 预期改善: 消除仓库级全表扫描，DMV 预估改善度 80.34%
-- =================================================================================================
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Cust_InvTrans_WhQoh_Wh_ItemCode' AND object_id = OBJECT_ID('dbo.InvTrans_WhQoh'))
BEGIN
    PRINT '正在创建索引: IX_Cust_InvTrans_WhQoh_Wh_ItemCode...';
    CREATE NONCLUSTERED INDEX [IX_Cust_InvTrans_WhQoh_Wh_ItemCode]
    ON [dbo].[InvTrans_WhQoh] ([Wh])
    INCLUDE ([ItemInfo_ItemCode], [StoreQty], [ResvStQty], [ResvOccupyStQty])
    WITH (ONLINE = ON, DATA_COMPRESSION = PAGE, FILLFACTOR = 90);
    PRINT '[OK] IX_Cust_InvTrans_WhQoh_Wh_ItemCode 创建成功！';
END
ELSE
    PRINT '[SKIP] 索引 IX_Cust_InvTrans_WhQoh_Wh_ItemCode 已存在。';
GO

-- =================================================================================================
-- 8. [解决存货期间统计 3,276秒 · 120 万行] 存货期间核算行组织与日期范围索引
-- 业务场景: P_InvTrans_MonthClose_StatPeriodQueryInvTotal 月结期间加权平均成本核算
-- 预期改善: 组织与会计期间起止日期复合引导，消除 120 万行全表扫描，DMV 评分 32.2 万分
-- =================================================================================================
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Cust_InvTrans_AccountPeriodLine_Org_Date' AND object_id = OBJECT_ID('dbo.InvTrans_AccountPeriodLine'))
BEGIN
    PRINT '正在创建索引: IX_Cust_InvTrans_AccountPeriodLine_Org_Date...';
    CREATE NONCLUSTERED INDEX [IX_Cust_InvTrans_AccountPeriodLine_Org_Date]
    ON [dbo].[InvTrans_AccountPeriodLine] ([Org], [FromDate], [ToDate])
    INCLUDE ([ID], [OwnedOrg], [Wh], [ItemInfo_ItemID], [ItemInfo_ItemCode], [StorageMainUOM], [CostUOM], [QtyPriceDealFlg], [IsVMI])
    WITH (ONLINE = ON, DATA_COMPRESSION = PAGE, FILLFACTOR = 90);
    PRINT '[OK] IX_Cust_InvTrans_AccountPeriodLine_Org_Date 创建成功！';
END
ELSE
    PRINT '[SKIP] 索引 IX_Cust_InvTrans_AccountPeriodLine_Org_Date 已存在。';
GO
