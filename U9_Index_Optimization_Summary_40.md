# 用友 U9 连续 3 天性能索引优化汇总表 (40 项全景)

> **实施周期**：2026年10月08日 ~ 2026年10月10日  
> **生产环境**：`192.168.100.210` / 数据库：`SHBC`  
> **覆盖数据总量**：**140,660,573 行（超 1.40 亿行）**  
> **物理磁盘总开销**：**3,107.91 MB（约 3.03 GB，全程 PAGE 高压）**  
> **生产部署状态**：**100% 全部联机生效（ONLINE=ON 无锁业务零中断）**

---

## 🏆 优化效果全景对照表

| 序号 | 目标业务表 | 表行数(W) | 优化提升(%) | 关联索引名称 (`IX_Cust_*`) | 核心优化场景说明 |
| :---: | :--- | :---: | :---: | :--- | :--- |
| **01** | `MO_ResUsageRptLineCost` | **1,677.6 W** | **99.81%** | `IX_Cust_MO_ResUsageRptLineCost_ResUsageRpt` | 资源用量行成本外键关联（耗时 17.8s 降至 34ms） |
| **02** | `MO_ResUsageRptLine` | **1,740.6 W** | **99.84%** | `IX_Cust_MO_ResUsageRptLine_DisPatchOrder` | 派工单用量反查（消除 30s 锁表超时与全表扫） |
| **03** | `PR_PRLine` | **67.0 W** | **99.60%** | `IX_Cust_PR_PRLine_SrcDocInfo` | 请购单行来源关联反查（耗时 17.9s 降至 71ms） |
| **04** | `SM_SOLine` | **82.8 W** | **99.51%** | `IX_Cust_SM_SOLine_Status` | 销售订单明细状态过滤（耗时 10.6s 降至 52ms） |
| **05** | `QC_QCDocLine` | **71.6 W** | **99.06%** | `IX_Cust_QC_QCDocLine_PerfOpt` | MO 完工质检状态校验（耗时 4.2s 降至 40ms） |
| **06** | `SM_ShipPlanLine` | **90.4 W** | **99.70%** | `IX_Cust_SM_ShipPlanLine_Customer` | 出运计划客户批量过滤（前台假死 70~92s 降至 0.24s） |
| **07** | `MO_DispatchOrderDocLine` | **3.0 W** | **87.24%** | `IX_Cust_MO_DispatchOrderDocLine_MO` | 生产派工单工序校验（消灭 2000+ 页扫描） |
| **08** | `MO_CompleteRpt` | **58.7 W** | **89.25%** | `IX_Cust_MO_CompleteRpt_PerfOpt` | 完工报告单状态/日期过滤（列表首屏秒开） |
| **09** | `CBO_Operation` | **10.9 W** | **88.81%** | `IX_Cust_CBO_Operation_PerfOpt` | 标准工序轮询（1980次高频轮询降 550万次内存读） |
| **10** | `PM_PurchaseOrder` | **27.0 W** | **98.93%** | `IX_Cust_PM_PurchaseOrder_Status` | 采购订单主表未结案检索（I/O 读降低 98.9%） |
| **11** | `SPR_SalePriceLine` | **10.7 W** | **99.40%** | `IX_Cust_SPR_SalePriceLine_Item` | 销售价表开单带价匹配（扫 500 页降为 3 页点查） |
| **12** | `PM_Receivement` | **47.9 W** | **92.31%** | `IX_Cust_PM_Receivement_ApproveOpt` | 采购收货单审核状态批量检索（理顺索引链条） |
| **13** | `AAI_TransVoucherToGLlog` | **832.4 W** | **50.00%** | `IX_Cust_AAI_TransVoucherToGLlog_Covering` | 存货总账凭证反查（832万行大表消除 Key Lookup 回表） |
| **14** | `InstanceState` | **0.3 W** | **96.83%** | `IX_Cust_InstanceState_Timer` | 工作流引擎定时器与审批超时轮询（开销降至 2 次） |
| **15** | `CA_CostQuery` | **756.8 W** | **57.14%** | `IX_Cust_CA_CostQuery_Period` | 成本核算期间多维分析（756万行大表精准命中） |
| **16** | `MRP_Log` | **4.0 W** | **82.70%** | `IX_Cust_MRP_Log_PlanVersion` | MRP 运算日志版本追溯（提速 1.6 倍，逻辑读降 82.7%） |
| **17** | `MO_MOResource` | **1,755.9 W** | **92.20%** | `IX_Cust_MO_MOResource_ResGroup` | 生产资源组排产排程（1755万行大表 I/O 降 92.2%） |
| **18** | `PR_DemandInterface` | **12.7 W** | **99.93%** | `IX_Cust_PR_DemandInterface_SrcDocNo` | 需求接口单据号反查（耗时降 99.7%，提速 314 倍） |
| **19** | `SM_ShipPlanAddress` | **120.3 W** | **45.00%** | `IX_Cust_SM_ShipPlanAddress_Covering` | 出货计划发运地址批量检索（彻底切断回表） |
| **20** | `MO_MOPickList` | **764.1 W** | **97.60%** | `IX_Cust_MO_MOPickList_MO_Issued` | 工单备料按工单统计发料（764万行大表 I/O 降 97.6%） |
| **21** | `SM_ShipLine` | **95.5 W** | **99.99%** | `IX_Cust_SM_ShipLine_SrcDocLine` | 销售出货行来源单据反查（提速 1223 倍，免 4.8万倍IO） |
| **22** | `InvDoc_TransferIn` | **27.1 W** | **99.86%** | `IX_Cust_InvDoc_TransferIn_FlexDoc` | 调拨入库单按出运计划单号反查（提速 62.2 倍） |
| **23** | `PR_PR` | **29.0 W** | **99.99%** | `IX_Cust_PR_PR_Org_CreatedOn` | 请购单组织与时间范围过滤（提速 24.6 倍，免 2.6万倍IO）|
| **24** | `PM_POShipLine` | **68.0 W** | **99.99%** | `IX_Cust_PM_POShipLine_CooperateSO` | 协同销售订单反查采购发运明细（提速 611 倍） |
| **25** | `AR_ARBillLine` | **125.0 W** | **99.99%** | `IX_Cust_AR_ARBillLine_SrcBillNum` | 应收单据行反查核销（提速 139 倍，逻辑读降 99.99%） |
| **26** | `MO_MOResource` | **1,755.9 W** | **100.00%** | `IX_Cust_MO_MOResource_OpRes` | 工序资源更新精准定位（22.7万页扫描降为 3 页点查） |
| **27** | `SM_ShipPlanLine` | **90.4 W** | **62.50%** | `IX_Cust_SM_ShipPlanLine_ShipPlan_Auth` | 出货计划行权限子查询（消除 80 次高频 Key Lookup） |
| **28** | `MO_MO` | **43.4 W** | **99.98%** | `IX_Cust_MO_MO_Org_BusinessType_Filter` | 生产工单复合条件筛选（1.4万页扫描降为 3 页点查） |
| **29** | `SPR_SalePriceList` | **0.2 W** | **93.75%** | `IX_Cust_SPR_SalePriceList_Org_Status` | 销售价表主表组织与状态过滤（I/O 读降低 93.75%） |
| **30** | `SPR_SalePriceLine` | **10.7 W** | **98.50%** | `IX_Cust_SPR_SalePriceLine_Customer` | 客户专属价表行检索（覆盖索引消除全表扫） |
| **31** | `MO_ResUsageRpt` | **224.4 W** | **99.96%** | `IX_Cust_MO_ResUsageRpt_Org_DocState_RptTime` | 资源报工头千万级联查（提速 18.2 倍，省 16.3万页读取）|
| **32** | `InvDoc_InnerBalanceLine` | **22.2 W** | **99.10%** | `IX_Cust_InvDoc_InnerBalanceLine_SrcSubLine` | 内部结算行来源子行追溯（消除回表开销） |
| **33** | `SM_ShipPlanLine` | **90.4 W** | **99.21%** | `IX_Cust_SM_ShipPlanLine_SrcDocLine` | **客开定时关单任务**（`closeSoLine` 19.5s 降至 0.15s，提速 126 倍） |
| **34** | `SM_ForecastOrderLine` | **30.9 W** | **99.78%** | `IX_Cust_SM_ForecastOrderLine_ForecastOrder` | **MRP预测需求抓取**（7,911s/2小时瓶颈消除，消灭全表扫）|
| **35** | `MRP_PlanOrderConsumption` | **50.8 W** | **99.64%** | `IX_Cust_MRP_PlanOrderConsumption_ReleaseDoc` | **MRP计划订单消退**（54,867s 累积卡顿消除，消退下发提速）|
| **36** | `PM_POLine` | **65.1 W** | **98.60%** | `IX_Cust_PM_POLine_Status_MRP` | **MRP采购在途提取**（182,363s/50小时大瓶颈彻底根治） |
| **37** | `InvTrans_DayClose` | **152.3 W** | **99.82%** | `IX_Cust_InvTrans_DayClose_Org_Wh_Date` | **存货月结总核算**（1,336s/22.2分钟消除，省 66.8万次读）|
| **38** | `MRP_SimuPlanOrder` | **13.1 W** | **99.50%** | `IX_Cust_MRP_SimuPlanOrder_Sub_Version` | **MRP替代料模拟试算**（5,004s 消除 34.8万次未命中） |
| **39** | `InvTrans_WhQoh` | **43.0 W** | **80.34%** | `IX_Cust_InvTrans_WhQoh_Wh_ItemCode` | **MRP现存量预处理**（14,156s 消除 43万行仓库全表扫） |
| **40** | `InvTrans_AccountPeriodLine` | **2,994.1 W** | **99.90%** | `IX_Cust_InvTrans_AccountPeriodLine_Org_Date` | **存货月结期间统计**（近 3,000万行超大表全表扫描治理） |

---

## 📈 数据汇总统计

* 🌟 **涉及核心物理表**：**23 张**
* 📊 **覆盖生产总行数**：**140,660,573 行（14,066.1 W 行）**
* 🚀 **平均性能/IO改善率**：**> 92.5%**
* 💾 **实际物理磁盘开销**：**3,107.91 MB（约 3.03 GB，平均每行仅消耗约 23 字节）**
