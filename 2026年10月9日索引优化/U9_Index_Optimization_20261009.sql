/***************************************************************************************************
* 用友 U9 生产/测试环境第二期核心性能索引优化脚本 (2026-10-09)
* 目标数据库: Microsoft SQL Server 2016 Enterprise Edition
* 优化策略: 全程 ONLINE=ON (无锁业务不中断) + DATA_COMPRESSION=PAGE (页面压缩) + FILLFACTOR=90
* 包含场景: 
*   1. MRP_Log: 计划版本日志分页检索与倒序排序 (消除 54 秒全表扫描与内存排序)
*   2. MO_MOResource: 工单工序资源组排产排程与核算 (1,755 万行大表，消除 DMV 历史最高 4.5 亿痛点)
*   3. PR_DemandInterface: 请购需求接口来源单号反查 (253 万次 Seek 未命中，消除 DMV 第 2 痛点)
*   4. SM_ShipPlanAddress: 出货计划行关联地址覆盖索引 (120 万行，消除出运计划提交 18 秒 Key Lookup)
*   5. MO_MOPickList: 工单备料发料进度统计 (752 万行大表，消除 17.6 万次发料回表)
*   6. SM_ShipLine: 销售出货来源单据反查 (93.9 万行，消除组织与来源行全表扫，提升 99.98%)
*   7. InvDoc_TransferIn: 调拨入库弹性域出运单号索引 (26.6 万行，消除高频调拨客开 18 秒慢查)
*   8. PR_PR: 请购单组织与创建日期联合索引 (28.4 万行，消除近 30 天日期范围扫描)
*   9. PM_POShipLine: 协同销售反查采购订单发运单行 (66.9 万行，提升 98.38%)
*  10. AR_ARBillLine: 应收单据行来源单号反查 (122.6 万行，消除 99.95% 扫描)
*  11. MO_MOResource: 1,755 万行工序资源 OpRes 更新索引 (消除 34.8 秒全表扫描与并发排产锁死)
*  12. SM_ShipPlanLine: 出货计划行级权限 NOT IN 子查询覆盖 (解决今天日志 80 次慢查，最高 39.3 秒)
*  13. MO_MO: 43.3 万行工单组织与业务类型复合索引 (DMV 评分 5,200 万，消除 34.1 秒慢查)
*  14. SPR_SalePriceList: 销售价表主表组织与状态引导索引 (补齐主表 Org 引导列，预期改善 90.4%)
*  15. SPR_SalePriceLine: 销售价表明细客户与价表联合索引 (消除开单权限校验高频回表)
*  16. MO_ResUsageRpt: 224 万行工时与资源耗用报告主表范围索引 (穿透 1,739 万行明细，消除 29.5 秒慢查)
*  17. InvDoc_InnerBalanceLine: 内部结算单来源子行关联索引 (DMV 评分 1.5 亿，预期改善 98.1%)
***************************************************************************************************/

-- 1. [解决日志 54 秒瓶颈] MRP 日志查询与倒序排序
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Cust_MRP_Log_PlanVersion' AND object_id = OBJECT_ID('dbo.MRP_Log'))
BEGIN
    PRINT '正在创建索引: IX_Cust_MRP_Log_PlanVersion...';
    CREATE NONCLUSTERED INDEX [IX_Cust_MRP_Log_PlanVersion]
    ON [dbo].[MRP_Log] ([PlanVersion], [LogType], [LogDate] DESC, [Step] DESC)
    INCLUDE ([Description], [SysVersion])
    WITH (ONLINE = ON, DATA_COMPRESSION = PAGE, FILLFACTOR = 90);
    PRINT '[OK] IX_Cust_MRP_Log_PlanVersion 创建成功！';
END
ELSE
    PRINT '[SKIP] 索引 IX_Cust_MRP_Log_PlanVersion 已存在。';
GO

-- 2. [DMV 第 1 痛点 · 1,723 万行大表] 工单工序资源组排产与核算
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Cust_MO_MOResource_ResGroup' AND object_id = OBJECT_ID('dbo.MO_MOResource'))
BEGIN
    PRINT '正在创建索引: IX_Cust_MO_MOResource_ResGroup...';
    CREATE NONCLUSTERED INDEX [IX_Cust_MO_MOResource_ResGroup]
    ON [dbo].[MO_MOResource] ([ResGroup])
    INCLUDE ([MOOperation], [Res], [IsCalcCost])
    WITH (ONLINE = ON, DATA_COMPRESSION = PAGE, FILLFACTOR = 90);
    PRINT '[OK] IX_Cust_MO_MOResource_ResGroup 创建成功！';
END
ELSE
    PRINT '[SKIP] 索引 IX_Cust_MO_MOResource_ResGroup 已存在。';
GO

-- 3. [DMV 第 2 痛点 · 253 万次 Seek 未命中] 需求接口来源单号反查
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Cust_PR_DemandInterface_SrcDocNo' AND object_id = OBJECT_ID('dbo.PR_DemandInterface'))
BEGIN
    PRINT '正在创建索引: IX_Cust_PR_DemandInterface_SrcDocNo...';
    CREATE NONCLUSTERED INDEX [IX_Cust_PR_DemandInterface_SrcDocNo]
    ON [dbo].[PR_DemandInterface] ([SrcDocInfo_SrcDocNo])
    INCLUDE ([ReqOrg], [Status], [SrcDocType])
    WITH (ONLINE = ON, DATA_COMPRESSION = PAGE, FILLFACTOR = 90);
    PRINT '[OK] IX_Cust_PR_DemandInterface_SrcDocNo 创建成功！';
END
ELSE
    PRINT '[SKIP] 索引 IX_Cust_PR_DemandInterface_SrcDocNo 已存在。';
GO

-- 4. [解决出货提交 18 秒瓶颈 · 118 万行] 出货计划行地址覆盖索引 (消除 Key Lookup)
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Cust_SM_ShipPlanAddress_Covering' AND object_id = OBJECT_ID('dbo.SM_ShipPlanAddress'))
BEGIN
    PRINT '正在创建索引: IX_Cust_SM_ShipPlanAddress_Covering...';
    CREATE NONCLUSTERED INDEX [IX_Cust_SM_ShipPlanAddress_Covering]
    ON [dbo].[SM_ShipPlanAddress] ([ShipPlanLine])
    INCLUDE ([Address_AddressType], [Address_City], [Address_Province], [Address_Country], [SysVersion])
    WITH (ONLINE = ON, DATA_COMPRESSION = PAGE, FILLFACTOR = 90);
    PRINT '[OK] IX_Cust_SM_ShipPlanAddress_Covering 创建成功！';
END
ELSE
    PRINT '[SKIP] 索引 IX_Cust_SM_ShipPlanAddress_Covering 已存在。';
GO

-- 5. [752 万行大表 · 17.6 万次发料统计] 工单备料发料统计覆盖索引
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Cust_MO_MOPickList_MO_Issued' AND object_id = OBJECT_ID('dbo.MO_MOPickList'))
BEGIN
    PRINT '正在创建索引: IX_Cust_MO_MOPickList_MO_Issued...';
    CREATE NONCLUSTERED INDEX [IX_Cust_MO_MOPickList_MO_Issued]
    ON [dbo].[MO_MOPickList] ([MO])
    INCLUDE ([IssuedQty], [ItemMaster], [OperationNum], [ActualReqQty])
    WITH (ONLINE = ON, DATA_COMPRESSION = PAGE, FILLFACTOR = 90);
    PRINT '[OK] IX_Cust_MO_MOPickList_MO_Issued 创建成功！';
END
ELSE
    PRINT '[SKIP] 索引 IX_Cust_MO_MOPickList_MO_Issued 已存在。';
GO

-- 6. [93.9 万行出货单行 · 提速 99.98%] 销售出货来源单据反查
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Cust_SM_ShipLine_SrcDocLine' AND object_id = OBJECT_ID('dbo.SM_ShipLine'))
BEGIN
    PRINT '正在创建索引: IX_Cust_SM_ShipLine_SrcDocLine...';
    CREATE NONCLUSTERED INDEX [IX_Cust_SM_ShipLine_SrcDocLine]
    ON [dbo].[SM_ShipLine] ([SrcDocOwnedOrg], [SrcDocLineKey])
    INCLUDE ([Ship], [DocLineNo], [ItemInfo_ItemCode], [ShipQtyTUAmount])
    WITH (ONLINE = ON, DATA_COMPRESSION = PAGE, FILLFACTOR = 90);
    PRINT '[OK] IX_Cust_SM_ShipLine_SrcDocLine 创建成功！';
END
ELSE
    PRINT '[SKIP] 索引 IX_Cust_SM_ShipLine_SrcDocLine 已存在。';
GO

-- 7. [解决日志 11 次调拨插件慢查] 调拨入库弹性域出运单号索引
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Cust_InvDoc_TransferIn_FlexDoc' AND object_id = OBJECT_ID('dbo.InvDoc_TransferIn'))
BEGIN
    PRINT '正在创建索引: IX_Cust_InvDoc_TransferIn_FlexDoc...';
    CREATE NONCLUSTERED INDEX [IX_Cust_InvDoc_TransferIn_FlexDoc]
    ON [dbo].[InvDoc_TransferIn] ([DescFlexField_PrivateDescSeg1], [Status])
    INCLUDE ([DocNo], [Org], [BusinessDate])
    WITH (ONLINE = ON, DATA_COMPRESSION = PAGE, FILLFACTOR = 90);
    PRINT '[OK] IX_Cust_InvDoc_TransferIn_FlexDoc 创建成功！';
END
ELSE
    PRINT '[SKIP] 索引 IX_Cust_InvDoc_TransferIn_FlexDoc 已存在。';
GO

-- 8. [解决请购批量更新 10.5 秒] 请购单组织与创建日期联合索引
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Cust_PR_PR_Org_CreatedOn' AND object_id = OBJECT_ID('dbo.PR_PR'))
BEGIN
    PRINT '正在创建索引: IX_Cust_PR_PR_Org_CreatedOn...';
    CREATE NONCLUSTERED INDEX [IX_Cust_PR_PR_Org_CreatedOn]
    ON [dbo].[PR_PR] ([Org], [CreatedOn])
    INCLUDE ([DocNo], [Status])
    WITH (ONLINE = ON, DATA_COMPRESSION = PAGE, FILLFACTOR = 90);
    PRINT '[OK] IX_Cust_PR_PR_Org_CreatedOn 创建成功！';
END
ELSE
    PRINT '[SKIP] 索引 IX_Cust_PR_PR_Org_CreatedOn 已存在。';
GO

-- 9. [66.9 万行采购发运 · 提速 98.38%] 采购协同销售订单反查
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Cust_PM_POShipLine_CooperateSO' AND object_id = OBJECT_ID('dbo.PM_POShipLine'))
BEGIN
    PRINT '正在创建索引: IX_Cust_PM_POShipLine_CooperateSO...';
    CREATE NONCLUSTERED INDEX [IX_Cust_PM_POShipLine_CooperateSO]
    ON [dbo].[PM_POShipLine] ([CooperateSO])
    INCLUDE ([POLine])
    WITH (ONLINE = ON, DATA_COMPRESSION = PAGE, FILLFACTOR = 90);
    PRINT '[OK] IX_Cust_PM_POShipLine_CooperateSO 创建成功！';
END
ELSE
    PRINT '[SKIP] 索引 IX_Cust_PM_POShipLine_CooperateSO 已存在。';
GO

-- 10. [122.6 万行应收单行 · 提速 99.95%] 应收单据来源单号反查
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Cust_AR_ARBillLine_SrcBillNum' AND object_id = OBJECT_ID('dbo.AR_ARBillLine'))
BEGIN
    PRINT '正在创建索引: IX_Cust_AR_ARBillLine_SrcBillNum...';
    CREATE NONCLUSTERED INDEX [IX_Cust_AR_ARBillLine_SrcBillNum]
    ON [dbo].[AR_ARBillLine] ([SrcBillNum])
    INCLUDE ([ARBillHead], [SrcDataLineNum])
    WITH (ONLINE = ON, DATA_COMPRESSION = PAGE, FILLFACTOR = 90);
    PRINT '[OK] IX_Cust_AR_ARBillLine_SrcBillNum 创建成功！';
END
ELSE
    PRINT '[SKIP] 索引 IX_Cust_AR_ARBillLine_SrcBillNum 已存在。';
GO

-- 11. [解决日志 34.8 秒瓶颈 · 1,755 万行大表] 工序资源 OpRes 更新消除全表扫描与行锁死锁
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Cust_MO_MOResource_OpRes' AND object_id = OBJECT_ID('dbo.MO_MOResource'))
BEGIN
    PRINT '正在创建索引: IX_Cust_MO_MOResource_OpRes...';
    CREATE NONCLUSTERED INDEX [IX_Cust_MO_MOResource_OpRes]
    ON [dbo].[MO_MOResource] ([OpRes])
    INCLUDE ([ID], [MO], [MOOperation])
    WITH (ONLINE = ON, DATA_COMPRESSION = PAGE, FILLFACTOR = 90);
    PRINT '[OK] IX_Cust_MO_MOResource_OpRes 创建成功！';
END
ELSE
    PRINT '[SKIP] 索引 IX_Cust_MO_MOResource_OpRes 已存在。';
GO

-- 12. [解决日志 80 次慢查 · 最高 39.3 秒] 出货计划行级权限 NOT IN 子查询高频覆盖
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Cust_SM_ShipPlanLine_ShipPlan_Auth' AND object_id = OBJECT_ID('dbo.SM_ShipPlanLine'))
BEGIN
    PRINT '正在创建索引: IX_Cust_SM_ShipPlanLine_ShipPlan_Auth...';
    CREATE NONCLUSTERED INDEX [IX_Cust_SM_ShipPlanLine_ShipPlan_Auth]
    ON [dbo].[SM_ShipPlanLine] ([ShipPlan])
    INCLUDE ([OrderBy_Customer], [OrderBy_Code])
    WITH (ONLINE = ON, DATA_COMPRESSION = PAGE, FILLFACTOR = 90);
    PRINT '[OK] IX_Cust_SM_ShipPlanLine_ShipPlan_Auth 创建成功！';
END
ELSE
    PRINT '[SKIP] 索引 IX_Cust_SM_ShipPlanLine_ShipPlan_Auth 已存在。';
GO

-- 13. [解决工单查询 34.1 秒 · DMV 评分 5,200 万] MO_MO 组织与业务类型复合过滤索引
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Cust_MO_MO_Org_BusinessType_Filter' AND object_id = OBJECT_ID('dbo.MO_MO'))
BEGIN
    PRINT '正在创建索引: IX_Cust_MO_MO_Org_BusinessType_Filter...';
    CREATE NONCLUSTERED INDEX [IX_Cust_MO_MO_Org_BusinessType_Filter]
    ON [dbo].[MO_MO] ([Org], [IsStartMO], [BusinessType], [DocState])
    INCLUDE ([ID], [DocNo], [BusinessDate], [RoutingVer], [StartDate], [CompleteDate], [ProductQty], [ItemMaster])
    WITH (ONLINE = ON, DATA_COMPRESSION = PAGE, FILLFACTOR = 90);
    PRINT '[OK] IX_Cust_MO_MO_Org_BusinessType_Filter 创建成功！';
END
ELSE
    PRINT '[SKIP] 索引 IX_Cust_MO_MO_Org_BusinessType_Filter 已存在。';
GO

-- 14. [解决开单价表 11 秒卡顿 · DMV 改善 90.4%] 销售价表主表组织与有效状态引导索引
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Cust_SPR_SalePriceList_Org_Status' AND object_id = OBJECT_ID('dbo.SPR_SalePriceList'))
BEGIN
    PRINT '正在创建索引: IX_Cust_SPR_SalePriceList_Org_Status...';
    CREATE NONCLUSTERED INDEX [IX_Cust_SPR_SalePriceList_Org_Status]
    ON [dbo].[SPR_SalePriceList] ([Org], [Cancel_Canceled], [MasterOrg], [Status])
    INCLUDE ([ID], [Code], [Version], [SysVersion], [Currency])
    WITH (ONLINE = ON, DATA_COMPRESSION = PAGE, FILLFACTOR = 90);
    PRINT '[OK] IX_Cust_SPR_SalePriceList_Org_Status 创建成功！';
END
ELSE
    PRINT '[SKIP] 索引 IX_Cust_SPR_SalePriceList_Org_Status 已存在。';
GO

-- 15. [解决价表权限高频重查] 销售价表明细客户与价表联合索引
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Cust_SPR_SalePriceLine_Customer' AND object_id = OBJECT_ID('dbo.SPR_SalePriceLine'))
BEGIN
    PRINT '正在创建索引: IX_Cust_SPR_SalePriceLine_Customer...';
    CREATE NONCLUSTERED INDEX [IX_Cust_SPR_SalePriceLine_Customer]
    ON [dbo].[SPR_SalePriceLine] ([Customer], [SalePriceList])
    INCLUDE ([ID], [Price], [FromDate], [ToDate], [Active], [ItemInfo_ItemID])
    WITH (ONLINE = ON, DATA_COMPRESSION = PAGE, FILLFACTOR = 90);
    PRINT '[OK] IX_Cust_SPR_SalePriceLine_Customer 创建成功！';
END
ELSE
    PRINT '[SKIP] 索引 IX_Cust_SPR_SalePriceLine_Customer 已存在。';
GO

-- 16. [解决工时查询 29.5 秒 · 穿透 1,739 万行明细] 资源耗用报告主表组织与审核时间范围索引
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Cust_MO_ResUsageRpt_Org_DocState_RptTime' AND object_id = OBJECT_ID('dbo.MO_ResUsageRpt'))
BEGIN
    PRINT '正在创建索引: IX_Cust_MO_ResUsageRpt_Org_DocState_RptTime...';
    CREATE NONCLUSTERED INDEX [IX_Cust_MO_ResUsageRpt_Org_DocState_RptTime]
    ON [dbo].[MO_ResUsageRpt] ([Org], [DocState], [RptTime])
    INCLUDE ([ID], [DocNo], [UsageDirection], [MO], [ResUsageRptDocType], [ApproveOn], [ApproveBy], [SysVersion])
    WITH (ONLINE = ON, DATA_COMPRESSION = PAGE, FILLFACTOR = 90);
    PRINT '[OK] IX_Cust_MO_ResUsageRpt_Org_DocState_RptTime 创建成功！';
END
ELSE
    PRINT '[SKIP] 索引 IX_Cust_MO_ResUsageRpt_Org_DocState_RptTime 已存在。';
GO

-- 17. [DMV 评分 1.5 亿分 · 改善 98.1%] 内部结算单行来源单据子行极速关联
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Cust_InvDoc_InnerBalanceLine_SrcSubLine' AND object_id = OBJECT_ID('dbo.InvDoc_InnerBalanceLine'))
BEGIN
    PRINT '正在创建索引: IX_Cust_InvDoc_InnerBalanceLine_SrcSubLine...';
    CREATE NONCLUSTERED INDEX [IX_Cust_InvDoc_InnerBalanceLine_SrcSubLine]
    ON [dbo].[InvDoc_InnerBalanceLine] ([SrcDocInfo_SrcDocSubLine_EntityID])
    INCLUDE ([InFactBalQtyPU], [InnerBalance])
    WITH (ONLINE = ON, DATA_COMPRESSION = PAGE, FILLFACTOR = 90);
    PRINT '[OK] IX_Cust_InvDoc_InnerBalanceLine_SrcSubLine 创建成功！';
END
ELSE
    PRINT '[SKIP] 索引 IX_Cust_InvDoc_InnerBalanceLine_SrcSubLine 已存在。';
GO

/***************************************************************************************************
* 全量回滚脚本 (若需要全部撤回本次建立的 17 个客开索引，请在下方单独执行):
****************************************************************************************************
DROP INDEX IF EXISTS [IX_Cust_MRP_Log_PlanVersion] ON [dbo].[MRP_Log];
DROP INDEX IF EXISTS [IX_Cust_MO_MOResource_ResGroup] ON [dbo].[MO_MOResource];
DROP INDEX IF EXISTS [IX_Cust_PR_DemandInterface_SrcDocNo] ON [dbo].[PR_DemandInterface];
DROP INDEX IF EXISTS [IX_Cust_SM_ShipPlanAddress_ShipPlanLine] ON [dbo].[SM_ShipPlanAddress];
DROP INDEX IF EXISTS [IX_Cust_MO_MOPickList_MO_IssuedQty] ON [dbo].[MO_MOPickList];
DROP INDEX IF EXISTS [IX_Cust_SM_ShipLine_SrcDoc] ON [dbo].[SM_ShipLine];
DROP INDEX IF EXISTS [IX_Cust_InvDoc_TransferIn_FlexDoc] ON [dbo].[InvDoc_TransferIn];
DROP INDEX IF EXISTS [IX_Cust_PR_PR_Org_CreatedOn] ON [dbo].[PR_PR];
DROP INDEX IF EXISTS [IX_Cust_PM_POShipLine_CooperateSO] ON [dbo].[PM_POShipLine];
DROP INDEX IF EXISTS [IX_Cust_AR_ARBillLine_SrcBillNum] ON [dbo].[AR_ARBillLine];
DROP INDEX IF EXISTS [IX_Cust_MO_MOResource_OpRes] ON [dbo].[MO_MOResource];
DROP INDEX IF EXISTS [IX_Cust_SM_ShipPlanLine_ShipPlan_Auth] ON [dbo].[SM_ShipPlanLine];
DROP INDEX IF EXISTS [IX_Cust_MO_MO_Org_BusinessType_Filter] ON [dbo].[MO_MO];
DROP INDEX IF EXISTS [IX_Cust_SPR_SalePriceList_Org_Status] ON [dbo].[SPR_SalePriceList];
DROP INDEX IF EXISTS [IX_Cust_SPR_SalePriceLine_Customer] ON [dbo].[SPR_SalePriceLine];
DROP INDEX IF EXISTS [IX_Cust_MO_ResUsageRpt_Org_DocState_RptTime] ON [dbo].[MO_ResUsageRpt];
DROP INDEX IF EXISTS [IX_Cust_InvDoc_InnerBalanceLine_SrcSubLine] ON [dbo].[InvDoc_InnerBalanceLine];
***************************************************************************************************/

