# 用友 U9 ERP SQL Server 生产环境索引性能调优库

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Database: SQL Server 2016+](https://img.shields.io/badge/Database-MSSQL%202016%2B-orange.svg)](#)
[![U9 ERP: Enterprise](https://img.shields.io/badge/ERP-UFIDA%20U9%20ERP-green.svg)](#)

本项目汇集了针对**用友 U9 ERP 生产环境核心业务模块**（生产制造、出货计划、采购协同、库存调拨、销售定价、应收核算、MRP 运算等）在千万级大表下的系统化 SQL Server 索引调优脚本与压测基准对比报告。

所有索引均源自生产环境真实超时日志（`ufida.ubf.perf.log`）与 SQL Server 动态性能视图（DMV Missing Indexes）的深度诊断，并在生产正式环境（`SHBC`）上实现 **100% 联机零锁上线**。

---

## 🛡️ 生产环境安全上线三大铁律

为确保高并发生产环境平稳运行，所有优化脚本严格遵循以下规范：

1. **`ONLINE = ON`（联机无锁）**：
   - 在线创建索引，不阻塞生产前台各组织并发制单、报工与出库，实现生产零停机。
2. **`DATA_COMPRESSION = PAGE`（页面级压缩）**：
   - 显著降低索引物理存储占用（实测 1,755 万行大表索引仅占 300MB 左右），成倍减少磁盘物理 I/O 并大幅提升 SQL Server Buffer Pool（内存缓存）命中率。
3. **`FILLFACTOR = 90`（预留空闲填充因子）**：
   - 预留 10% 页面空间，有效抑制高频业务数据录入时的索引页拆分（Page Split），延长索引免重构周期。
4. **命名规约 `IX_Cust_*`**：
   - 统一采用二开规范命名前缀，彻底与 U9 官方标准索引隔离，规避打官方补丁包时被静默重建或冲裁的风险。

---

## 📂 仓库目录结构

```text
u9-performance-optimization/
├── 2026年10月8日索引优化/
│   ├── U9_Index_Optimization_20261008.sql                  # 第一期 10 个核心索引完整执行脚本
│   └── U9_Index_Optimization_Benchmark_Report_20261008.md   # 第一期基准测试报告（执行耗时与逻辑读对比）
├── 2026年10月9日索引优化/
│   ├── U9_Index_Optimization_20261009.sql                  # 第二期 17 个全量核心优化索引脚本（正式库已部署）
│   ├── U9_Index_Optimization_Benchmark_Report_20261009.md   # 第二期 Part 1 基准报告（前 10 个索引）
│   └── U9_Index_Optimization_Part2_Benchmark_Report.md     # 第二期 Part 2 基准报告（新增 7 个索引）
└── 2026年10月10日索引优化/
    ├── U9_Index_Optimization_20261010.sql                  # 第三期 索引优化脚本（解决客开 19.5s 慢查）
    └── U9_Index_Optimization_Benchmark_Report_20261010.md  # 第三期 性能对比与基准实测报告（提速 126 倍）
```

---

## 📊 核心优化场景与成效汇总

### 第三期（2026-10-10）：前台定时关单与后台 MRP / 月结全场景 8 大核心索引

> **数据源穿透**：结合 `Portal\log`（Web前台/接口）与 `ApplicationServer\log\logapp`（**35份全量后台大作业日志**，涵盖 50+ 小时 MRP 运算与 22.2 分钟存货月结长事务）。

| 序号 | 目标表名 | 索引名称 | 表总行数 | 核心业务瓶颈与触发场景 | 改善幅度 / 收益 |
| :---: | :--- | :--- | :---: | :--- | :---: |
| 1 | `SM_ShipPlanLine` | `IX_Cust_SM_ShipPlanLine_SrcDocLine` | 903,278 行 | **客开定时关单 19.5s 慢查**（`closeSoLine`，正式库已生效） | 🚀 **19.5s ➡️ 0.15s (提速 126 倍)** |
| 2 | `SM_ForecastOrderLine` | `IX_Cust_SM_ForecastOrderLine_ForecastOrder` | 308,794 行 | **MRP预测需求抓取 7,911s/2小时**（`MRP_GetForecastOrder`） | ⚡ **改善 91.36% ~ 99.78%** |
| 3 | `MRP_PlanOrderConsumption` | `IX_Cust_MRP_PlanOrderConsumption_ReleaseDoc` | 507,789 行 | **MRP输出与订单消退 54,867s**（`MRP_Output` 单次最长 10 分钟） | 🚀 **改善 99.64% (免全表扫)** |
| 4 | `PM_POLine` | `IX_Cust_PM_POLine_Status_MRP` | 651,360 行 | **MRP采购在途提取 182,363s/50小时**（`MRP_GetPurchaseOrder`） | 🚀 **消除 65万行全表扫描** |
| 5 | `InvTrans_DayClose` | `IX_Cust_InvTrans_DayClose_Org_Wh_Date` | 1,523,398 行 | **存货月结总核算 1,336s/22.2分钟**（`MonthClose_AccountPeriodTotal`） | ⚡ **消灭 6.1万次日结回表 (改善 99.8%)** |
| 6 | `MRP_SimuPlanOrder` | `IX_Cust_MRP_SimuPlanOrder_Sub_Version` | 130,656 行 | **MRP替代料计算 5,004s**（`MRP_MainVersionProcess`） | ⚡ **消灭 34.8万次未命中 (58.8万分)** |
| 7 | `InvTrans_WhQoh` | `IX_Cust_InvTrans_WhQoh_Wh_ItemCode` | 429,518 行 | **MRP现存量预处理 14,156s**（`MRP_Pretreatment` 可用量检索） | 🚀 **改善 80.34%** |
| 8 | `InvTrans_AccountPeriodLine` | `IX_Cust_InvTrans_AccountPeriodLine_Org_Date` | 1,200,000 行 | **存货月结期间统计 3,276s**（`P_InvTrans_MonthClose_StatPeriodQueryInvTotal`） | 🚀 **消除 120万行范围全表扫** |

---

### 第二期（2026-10-09）：17 个全量索引正式环境部署统计

> **正式库（SHBC）实测数据**：覆盖业务数据量 **超 3,500 万行**，在 PAGE 压缩下总占用磁盘仅 **960.19 MB**。

| 序号 | 目标表名 | 索引名称 | 表总行数 | 占用大小 | 优化核心瓶颈 |
| :---: | :--- | :--- | :---: | :---: | :--- |
| 1 | `MO_MOResource` | `IX_Cust_MO_MOResource_OpRes` | 17,552,539 | 316.20 MB | **消除 34.8s 慢查**：消除 OpRes 更新全表扫与排产行锁阻塞 |
| 2 | `MO_MOResource` | `IX_Cust_MO_MOResource_ResGroup` | 17,552,539 | 269.21 MB | **DMV 历史第 1 痛点**（4.5 亿开销）：工单工序资源组排程过滤 |
| 3 | `MO_MOPickList` | `IX_Cust_MO_MOPickList_MO_Issued` | 7,639,231 | 158.02 MB | **发料进度统计**：消除 17.6 万次回表，覆盖发料与需求统计 |
| 4 | `MO_ResUsageRpt` | `IX_Cust_MO_ResUsageRpt_Org_DocState_RptTime` | 2,243,693 | 67.13 MB | **消除工时 29.5s 慢查**：穿透 1,739 万行明细的耗用报告范围索引 |
| 5 | `SM_ShipLine` | `IX_Cust_SM_ShipLine_SrcDocLine` | 954,529 | 28.88 MB | **提速 99.98%**：出货单反查来源单据组织与来源行 Key Lookup |
| 6 | `AR_ARBillLine` | `IX_Cust_AR_ARBillLine_SrcBillNum` | 1,249,476 | 24.70 MB | **提速 99.95%**：来源单号反查应收单行，消除全表扫描 |
| 7 | `SM_ShipPlanAddress` | `IX_Cust_SM_ShipPlanAddress_Covering` | 1,202,599 | 21.14 MB | **消除出运提交 18s 瓶颈**：出货计划行关联地址覆盖索引（免回表） |
| 8 | `MO_MO` | `IX_Cust_MO_MO_Org_BusinessType_Filter` | 433,399 | 20.76 MB | **消除工单列表 34.1s 慢查**：组织+开工状态+业务类型复合索引 |
| 9 | `SM_ShipPlanLine` | `IX_Cust_SM_ShipPlanLine_ShipPlan_Auth` | 903,273 | 17.45 MB | **解决 80 次慢查（最高 39.3s）**：行级权限 NOT IN 子查询覆盖 |
| 10 | `PM_POShipLine` | `IX_Cust_PM_POShipLine_CooperateSO` | 680,272 | 10.70 MB | **提速 98.38%**：采购订单发运单行协同销售订单精准 Seek |
| 11 | `PR_PR` | `IX_Cust_PR_PR_Org_CreatedOn` | 289,628 | 7.32 MB | **消除请购单更新 10.5s**：组织与创建日期联合范围检索索引 |
| 12 | `InvDoc_TransferIn` | `IX_Cust_InvDoc_TransferIn_FlexDoc` | 271,304 | 7.26 MB | **消除调拨 11 次 18s 慢查**：调拨入库弹性域出运单号高频反查 |
| 13 | `InvDoc_InnerBalanceLine` | `IX_Cust_InvDoc_InnerBalanceLine_SrcSubLine` | 222,305 | 5.26 MB | **DMV 评分 1.5 亿分**：内部结算单关联来源子行（预期改善 98.1%） |
| 14 | `SPR_SalePriceLine` | `IX_Cust_SPR_SalePriceLine_Customer` | 106,663 | 2.76 MB | **消除价表高频回表**：销售价表明细客户与价表联合索引 |
| 15 | `PR_DemandInterface` | `IX_Cust_PR_DemandInterface_SrcDocNo` | 126,324 | 2.13 MB | **DMV 第 2 痛点**（253 万次 Seek 未命中）：需求接口来源单号反查 |
| 16 | `MRP_Log` | `IX_Cust_MRP_Log_PlanVersion` | 40,396 | 1.07 MB | **消除日志 54s 瓶颈**：消除 MRP 计算日志倒序全表扫描与内存排序 |
| 17 | `SPR_SalePriceList` | `IX_Cust_SPR_SalePriceList_Org_Status` | 1,707 | 0.20 MB | **销售价表主表过滤**：补齐主表 Org 引导列，预期改善 90.4% |

---

## 📈 典型业务查询性能提升对比

实测基于 SQL Server `SET STATISTICS TIME, IO ON` 基准测试：

- **客开定时关闭销售订单行 (`closeSoLine`)**：
  - 优化前：耗时 **19,582 ms (19.58 秒)**，驱动 27.1 万行调拨单聚集索引全表扫描；
  - 优化后：耗时 **155 ms (0.15 秒)**（**提速 126 倍 ⚡**），全链路转为精准 Index Seek！
- **工序资源点查 (`MO_MOResource`)**：
  - 优化前：耗时 252.7 ms，逻辑读 227,624 页（约 1.74 GB 内存读取，全表扫描）；
  - 优化后：耗时 **28.7 ms**（**提速 8.8 倍**），逻辑读 **3 页**（**削减 99.999%**，精准 Index Seek）。
- **工时报告范围查询 (`MO_ResUsageRpt`)**：
  - 优化前：耗时 72.8 ms，逻辑读 12,056 页；
  - 优化后：耗时 **4.0 ms**（**提速 18.2 倍**），逻辑读 **7 页**（**削减 99.94%**）。
- **出货计划行级权限查询 (`SM_ShipPlanLine`)**：
  - 优化前：高并发下平均 15~39 秒，产生大量读锁；
  - 优化后：毫秒级返回，彻底消除生产出现的 80 次超时慢查。

---

## 📝 使用方法

直接在 SQL Server Management Studio (SSMS) 中连接目标 U9 数据库（如生产库或测试库），打开并执行对应的 SQL 脚本即可：

```sql
-- 推荐按期执行最新全量脚本（包含 IF NOT EXISTS 幂等检查）
:r "2026年10月10日索引优化/U9_Index_Optimization_20261010.sql"
```

脚本内均包含幂等性校验，已存在的索引会自动跳过，安全无副作用。

---

## 📄 开源许可证

本项目采用 [MIT 许可证](LICENSE)。
