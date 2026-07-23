# SurgeRelay-macOS 全功能整合审计

> 审计日期：2026-07-22
> 上游固定基线：[`EEliberto/SurgeRelay-macOS@b19d0dd6`](https://github.com/EEliberto/SurgeRelay-macOS/tree/b19d0dd6d6b9593be9cdf01c578de76c55d43150)（2026-07-17，当前 `main`）
> 上游正式版本：[`v270717`](https://github.com/EEliberto/SurgeRelay-macOS/releases/tag/v270717)
> Surge Shallow 对照基线：[`funnythingfunnylove/Surge-Shallow@1bce3c40`](https://github.com/funnythingfunnylove/Surge-Shallow/tree/1bce3c40b5e20310a1f92aea8797571854fb3ea1)（1.7.0 / Build 14）

`v270717` tag 固定在 `5a68545432812ba8a76d09abe30abd57eb6de1d5`，而本次审计的 `main@b19d0dd6` 比该 tag 多 13 个提交；因此源码行为以固定 `main` 为准，Release/appcast 只用于功能演进和发布链路核对。上游工程目标是 macOS 26、arm64、Swift 6，使用 Sparkle 2.9.3 且关闭 App Sandbox（[project.yml L1-L20](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/project.yml#L1-L20)、[L51-L60](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/project.yml#L51-L60)）。

## 1. 结论

SurgeRelay-macOS 与 Surge Shallow 解决的是相邻但不同的问题：

- SurgeRelay-macOS 是 **Surge 模块转换、编辑、按平台汇总和稳定分发系统**。它接收 Surge、Loon、Quantumult X 模块/重写来源，使用本机下载的 Script-Hub JavaScript 转换器生成 `.sgmodule`，再发布到 iCloud 或私有 GitHub + Cloudflare；README 对产品边界有明确描述（[README L8-L18](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/README.md#L8-L18)、[L41-L57](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/README.md#L41-L57)）。
- Surge Shallow 1.7.0 是 **规则源编排、完整 Profile 管理和 macOS/iOS Detached Profile 发布系统**，目前管理规则、General、Proxy、Proxy Group、平台差异和 `.conf/.dconf`，并不具备模块转换与 `.sgmodule` 分发子系统（[Shallow README L3-L33](https://github.com/funnythingfunnylove/Surge-Shallow/blob/1bce3c40b5e20310a1f92aea8797571854fb3ea1/README.md#L3-L33)）。

因此，“整合全部功能”应解释为：在 Surge Shallow 中新增一个与现有 Profile Relay 并列的 **Module Relay 域**，共享调度、状态、iCloud 安全写入和菜单栏基础设施；不应把模块伪装成规则源，也不应让模块合并器修改 Profile 规则编排语义。

当前落地采用 `SurgeModuleManagement` feature target，而不是嵌入上游 App：Surge Shallow 仍只有一个 executable 和一个 `@main`；主 `AppModel` 持有模块管理控制器，主侧边栏提供“模块”入口，主设置页提供“模块管理”分区，主菜单栏读取同一份 feature 状态。上游 `RootView`、窗口关闭行为和独立登录启动服务不参与构建；模块列表使用主详情区内的列表—详情布局，不再嵌套第二套 `NavigationSplitView`。模块模型构造过程保持只读：已配置的模块功能由 Surge Shallow 主启动流程拉起，尚未配置时则保持休眠，直到用户进入“模块”后才显示首次启用流程。

`Sources/SurgeModuleManagement` 中保留的是模块解析、转换、编辑、合并、发布及其必要的 feature UI。源码沿用 Apache 2.0 上游实现并记录固定 commit，但公开接缝已经改为 `ModuleManagementController` / `ModuleManagementView` / `ModuleManagementSettingsSection`，不再以另一套 App 的 Root/Settings 生命周期作为集成边界。

审计结果（以整合前的 Surge Shallow 1.7.0 为基线）：上游共识别出 **8 个产品域、38 个可验收功能点**；当时完全覆盖 3 项、部分覆盖 8 项、缺少 27 项。整合前最大缺口依次是：

1. Script-Hub 本地转换引擎及全部转换选项；
2. `.sgmodule` 模块数据模型、预览编辑、参数/策略/MITM 覆盖和冲突处理；
3. iOS/macOS/tvOS/visionOS 汇总与独立模块输出；
4. 私有 GitHub 原子发布、Cloudflare 稳定地址及发布后验证；
5. Web 管理、SSE 状态流和 Surge Ponte 原生客户端/服务器模式；
6. Sparkle 更新、首次设置向导、图标检索和诊断导出。

## 2. 审计方法与状态定义

本审计只使用上游仓库的 README、Release、源代码、工程配置、测试和许可证等一手材料。所有源码链接固定到提交 `b19d0dd6d6b9593be9cdf01c578de76c55d43150`，避免后续 `main` 漂移。

矩阵状态：

- **已有**：Surge Shallow 1.7.0 已有同等用户能力和相近边界。
- **部分**：已有可复用基础设施，但对象、文件格式、平台或用户流程不同。
- **缺失**：当前产品和数据模型中没有该能力。
- **上游边界**：上游源码中存在限制、未完成分支或用户文案与实现不完全一致；整合时需明确产品决策，不能机械复制。

## 3. 全功能矩阵

### 3.1 首次启动、角色与主界面

| # | 上游功能与可验收行为 | 一手证据 | Surge Shallow 1.7.0 | 整合要求 |
|---:|---|---|---|---|
| 1 | 首次启动向导先选择此 Mac 为服务器或客户端；客户端必须输入 Ponte 地址并测试成功，服务器再选择 iCloud 或 GitHub 存储。发现既有 iCloud 配置时提示并复用。 | [WelcomeWizard L90-L153](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Views/WelcomeWizardView.swift#L90-L153)、[L195-L234](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Views/WelcomeWizardView.swift#L195-L234)、[L244-L313](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Views/WelcomeWizardView.swift#L244-L313) | **缺失**；Shallow 直接读取/创建 `relay.json`，已有 Profile 导入确认不是首次运行向导（[RootView L30-L76](https://github.com/funnythingfunnylove/Surge-Shallow/blob/1bce3c40b5e20310a1f92aea8797571854fb3ea1/Sources/SurgeShallow/Views/RootView.swift#L30-L76)）。 | 新增非破坏性向导；若检测到现有 `relay.json`，默认进入“保留现有 Profile Relay + 启用 Module Relay”，不得覆盖。
| 2 | 主窗口关闭后隐藏并切换为 accessory，进程继续留在菜单栏；重新打开恢复 regular activation policy，关闭最后窗口不退出。 | [SurgeRelayApp L58-L75](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/SurgeRelayApp.swift#L58-L75)、[MainWindowCloseBehavior L4-L35](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Views/MainWindowCloseBehavior.swift#L4-L35) | **部分**；有 MenuBarExtra，但主窗口没有上游的“关闭即隐藏/accessory”显式行为（[SurgeShallowApp L13-L49](https://github.com/funnythingfunnylove/Surge-Shallow/blob/1bce3c40b5e20310a1f92aea8797571854fb3ea1/Sources/SurgeShallow/SurgeShallowApp.swift#L13-L49)）。 | 复用单一进程级 RuntimeHost；关闭主窗口后 Profile 与 Module 调度、Web/Ponte 服务继续运行。
| 3 | 模块页是分栏管理界面，含搜索、添加、全部更新、模块/平台汇总选择、详情/预览切换、后退/前进导航。 | [ModulesView L330-L385](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Views/ModulesView.swift#L330-L385) | **缺失**；现有侧边栏只有总览、规则源、Proxy、Profiles、更新记录、设置（[RootView L81-L120](https://github.com/funnythingfunnylove/Surge-Shallow/blob/1bce3c40b5e20310a1f92aea8797571854fb3ea1/Sources/SurgeShallow/Views/RootView.swift#L81-L120)）。 | 新增一级 `Modules` Tab；保持现有 Profile 各 Tab，不把模块列表塞进规则源页。

### 3.2 模块来源、转换和模块级配置

| # | 上游功能与可验收行为 | 一手证据 | Surge Shallow 1.7.0 | 整合要求 |
|---:|---|---|---|---|
| 4 | 模块来源支持自动识别、Quantumult X Rewrite、Loon Plugin、原生 Surge Module；`.sgmodule` 识别为 Surge，`.plugin/.lpx` 识别为 Loon，其他自动路径最终回退为 QX。 | [RelayModule L28-L80](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Models/RelayModule.swift#L28-L80) | **缺失**；当前格式是 Surge 规则列表/Ruleset/Profile、域名列表、Clash payload（[RuleSource L3-L21](https://github.com/funnythingfunnylove/Surge-Shallow/blob/1bce3c40b5e20310a1f92aea8797571854fb3ea1/Sources/SurgeProfileRelayCore/Models/RuleSource.swift#L3-L21)）。 | 建立独立 `ModuleSourceFormat`，严格保留上游自动回退行为，并在 UI 显示最终检测格式。
| 5 | 模块可添加/编辑名称、HTTP(S) 来源、格式、输出文件名、全局启用状态和 Script-Hub 选项；添加重复 URL 时拒绝。粘贴 URL 后 500ms 防抖读取上游 `#!name` 自动填名，缺失时从文件名推导；输出文件重名自动使用 `-2/-3`。 | [RelayModule L104-L168](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Models/RelayModule.swift#L104-L168)、[L244-L269](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Models/RelayModule.swift#L244-L269)、[ModuleEditor L111-L136](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Views/ModuleEditorView.swift#L111-L136)、[AppModel L2142-L2174](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/AppModel.swift#L2142-L2174) | **部分**；规则源有相似 CRUD、排序和 HTTP(S) 校验，但数据语义不同（[Shallow AppModel L157-L230](https://github.com/funnythingfunnylove/Surge-Shallow/blob/1bce3c40b5e20310a1f92aea8797571854fb3ea1/Sources/SurgeShallow/AppModel.swift#L157-L230)）。 | 复用列表/表单组件，不复用 `RuleSource` 模型；URL 去重应采用上游 canonical identity；自动填名不能覆盖用户已编辑名称。
| 6 | URL 身份规范化：scheme/host 小写、移除 fragment、移除 HTTP 80/HTTPS 443、空 path 补 `/`，用此结果判断重复。 | [RelayModule L3-L25](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Models/RelayModule.swift#L3-L25) | **缺失**；Shallow 批量添加只对 trim 后的完整 URL 小写比较（[Shallow AppModel L189-L205](https://github.com/funnythingfunnylove/Surge-Shallow/blob/1bce3c40b5e20310a1f92aea8797571854fb3ea1/Sources/SurgeShallow/AppModel.swift#L189-L205)）。 | 抽成通用 RemoteSourceIdentity，同时给规则源和模块源使用；保留 query，不把含不同订阅参数的 URL 合并。
| 7 | 非 Surge 来源使用运行时下载的 Script-Hub `Rewrite-Parser.js` 和 `script-converter.js`，在 JavaScriptCore 中本地执行；原生 Surge 模块直接下载、命名、清理和校验。清理器还会删除空 Body Rewrite，并把兼容的 Loon Map Local `script-request/response` 行转换到 Surge `[Script]`，自动生成不冲突脚本名。 | [ScriptHubClient L46-L80](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Services/ScriptHubClient.swift#L46-L80)、[ScriptHubUpstreamService L10-L40](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Services/ScriptHubUpstreamService.swift#L10-L40)、[ModuleMerger L433-L502](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Services/ModuleMerger.swift#L433-L502)、[L505-L568](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Services/ModuleMerger.swift#L505-L568) | **缺失**。 | 增加 `ModuleConversionEngine` actor、引擎缓存和版本状态；下载代码的来源、hash、更新时间和执行超时必须可诊断；清理必须幂等并有格式样本测试。
| 8 | Script-Hub 引擎支持自动更新、手动检查、上游模块 URL、revision、上次检查和错误显示；缺失引擎时即便关闭自动更新也会拉取。 | [SettingsView L466-L522](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Views/SettingsView.swift#L466-L522)、[AppModel L889-L895](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/AppModel.swift#L889-L895) | **缺失**。 | 新增设置分区和首次引擎准备状态；引擎更新失败但存在缓存时继续使用缓存并显示警告。
| 9 | Script-Hub 高级选项覆盖脚本转换、响应脚本转换、兼容模式、前置/原始/转换脚本处理、include/exclude、MITM→Force HTTP、注释重写、Map Local Header、jsDelivr、策略、MITM 增删/正则删、脚本名/timeout/engine/cron/argument 改写、no-resolve、SNI、pre-matching、jq、请求 Header、内容 eval 及相应 URL。 | [ScriptHubOptions L5-L47](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Models/ScriptHubOptions.swift#L5-L47)、[L94-L145](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Models/ScriptHubOptions.swift#L94-L145) | **缺失**。 | 全部字段结构化，禁止只提供“原始 query 编辑框”；要求 URL 导入/导出 query round-trip 测试。
| 10 | Script-Hub 输出包含动态转换脚本时，将脚本实体化为 `assets/<module-id>/<hash>-<name>.js`，重写模块中的 `script-path`；此能力要求 GitHub 与 Cloudflare 已配置。 | [ScriptHubClient L94-L135](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Services/ScriptHubClient.swift#L94-L135) | **缺失**。 | 资产作为发布事务的一部分；模块文件和脚本资产必须同一 Git commit，iCloud 模式下需明确这项选项不可用或提供本地稳定路径。
| 11 | 下载/转换结果必须非空、不是错误 HTML，且至少包含 `#!name` 或 Surge 配置段；来源 revision 检查支持 ETag、Last-Modified、SHA-256，最大 20 MB。 | [ScriptHubClient L82-L91](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Services/ScriptHubClient.swift#L82-L91)、[L139-L180](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Services/ScriptHubClient.swift#L139-L180) | **部分**；规则源已有条件请求、可配置大小门禁与解析后才更新缓存（[Shallow README L26-L30](https://github.com/funnythingfunnylove/Surge-Shallow/blob/1bce3c40b5e20310a1f92aea8797571854fb3ea1/README.md#L26-L30)）。 | 抽出通用 HTTP revision fetcher，但分别使用 Rule 和 Module validator；模块大小默认按上游 20 MB 或统一为用户可配。
| 12 | 更新失败且有组件缓存时汇总继续使用缓存并记录“沿用缓存”；首次失败、无缓存时不覆盖当前汇总模块。 | [AppModel L1037-L1087](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/AppModel.swift#L1037-L1087) | **已有**；Profile Relay 同样区分首次失败与最后成功缓存（[RelayEngine L160-L179](https://github.com/funnythingfunnylove/Surge-Shallow/blob/1bce3c40b5e20310a1f92aea8797571854fb3ea1/Sources/SurgeProfileRelayCore/Services/RelayEngine.swift#L160-L179)）。 | 将策略抽成共用 `LastKnownGoodPolicy`，但缓存命名空间分离。

### 3.3 模块编辑、参数、图标与冲突

| # | 上游功能与可验收行为 | 一手证据 | Surge Shallow 1.7.0 | 整合要求 |
|---:|---|---|---|---|
| 13 | 模块详情提供只读/可编辑预览、查找、保存、恢复转换结果；磁盘生成文件会写入中英文“不要直接编辑”警告。 | [Components L175-L311](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Views/Components.swift#L175-L311)、[ModuleMerger L354-L365](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Services/ModuleMerger.swift#L354-L365) | **缺失**；Shallow 的 Profile 最近预览是只读（[RootView L123-L157](https://github.com/funnythingfunnylove/Surge-Shallow/blob/1bce3c40b5e20310a1f92aea8797571854fb3ea1/Sources/SurgeShallow/Views/RootView.swift#L123-L157)）。 | 模块编辑器独立实现，使用 override 文件作 source of truth；不要开放直接编辑已发布 `.sgmodule`。
| 14 | 本地编辑可抽取为结构化覆盖：Script argument、策略别名、追加规则、追加 MITM hostname；再次合并时应用这些覆盖。 | [RelayModule L112-L119](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Models/RelayModule.swift#L112-L119)、[AppModel L1834-L1859](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/AppModel.swift#L1834-L1859)、[ModuleMerger L194-L200](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Services/ModuleMerger.swift#L194-L200) | **缺失**。 | 建模为 `ModuleOverrides`；Policy mapping 必须只修改规则策略字段，MITM hostname 做去重。
| 15 | 自动发现模块参数定义，根据默认值渲染 Toggle 或 TextField，支持批量确认和恢复默认值，并展示参数帮助。 | [ModulesView L888-L919](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Views/ModulesView.swift#L888-L919)、[L1006-L1020](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Views/ModulesView.swift#L1006-L1020)、[AppModel L1758-L1832](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/AppModel.swift#L1758-L1832) | **缺失**。 | 同时支持原生 UI、Web 和 Ponte 客户端；参数变更只重建汇总，不重复下载上游。
| 16 | 模型和 UI 提供“上游已变化 vs 本地编辑”冲突比较、保留本地编辑、恢复转换结果。 | [Components L187-L201](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Views/Components.swift#L187-L201)、[L314-L349](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Views/Components.swift#L314-L349) | **缺失**。 | 见“上游源码边界”：最新上游更新路径把 `hasOverrideConflict` 设为 `false`，并没有产生 `true` 的可达赋值；整合时应补齐基于 `overrideBaseHash` 的真实三方冲突检测，而不是复制当前死分支。
| 17 | 模块图标：读取上游图标、手动 URL、自定义缓存、恢复默认；支持按中国/美国/日本/香港/台湾区域搜索 App Store 图标。平台汇总图标只允许手动 URL；单图标最大 5 MB。 | [RelayModule L117-L120](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Models/RelayModule.swift#L117-L120)、[ModulesView L1131-L1179](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Views/ModulesView.swift#L1131-L1179)、[L1218-L1345](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Views/ModulesView.swift#L1218-L1345)、[ModuleIconStore L17-L30](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Services/ModuleIconStore.swift#L17-L30) | **缺失**。 | 新增图标缓存和 App Store Search API；校验 MIME/大小，失败时回退上游图标/默认图标。

### 3.4 合并、平台和 iCloud 输出

| # | 上游功能与可验收行为 | 一手证据 | Surge Shallow 1.7.0 | 整合要求 |
|---:|---|---|---|---|
| 18 | 汇总目标覆盖 iOS/iPadOS、macOS、tvOS、visionOS；每个平台可独立开启、排序并启停某一模块。默认启用 iOS 和 macOS。 | [AppSettings L65-L108](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Models/AppSettings.swift#L65-L108)、[L110-L163](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Models/AppSettings.swift#L110-L163)、[L201-L223](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Models/AppSettings.swift#L201-L223) | **部分**；Profile Relay 当前只建模 macOS 与 iOS（[Shallow README L17-L24](https://github.com/funnythingfunnylove/Surge-Shallow/blob/1bce3c40b5e20310a1f92aea8797571854fb3ea1/README.md#L17-L24)）。 | Module 平台枚举独立于 Profile 平台，新增 tvOS/visionOS 不应强迫 Profile Relay 生成相应 `.conf`。
| 19 | 合并模块元数据：生成平台专属 name/desc/author/category，合并作者和 requirement；含设备变量的 requirement 只保留 CORE_VERSION 子句。 | [ModuleMerger L12-L54](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Services/ModuleMerger.swift#L12-L54)、[L183-L190](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Services/ModuleMerger.swift#L183-L190) | **缺失**。 | 按测试固化 metadata 输出；不要让 `.sgmodule` requirement 进入 `.conf` Profile requirement。
| 20 | 配置段顺序优先 General、MITM、Rule、Host、URL Rewrite、Header Rewrite、Body Rewrite、Map Local、Script，其余按来源顺序；普通段按完整行去重。 | [ModuleMerger L99-L131](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Services/ModuleMerger.swift#L99-L131) | **部分**；Profile Relay 有自己的规则顺序和跨源去重，不是模块段合并（[Shallow README L14-L23](https://github.com/funnythingfunnylove/Surge-Shallow/blob/1bce3c40b5e20310a1f92aea8797571854fb3ea1/README.md#L14-L23)）。 | 新增 `ModuleMerger`，不调用 `RuleMerger`。
| 21 | General/MITM 按 key 合并，靠前模块优先；多个 `%APPEND%/%INSERT%` 合并值并去重，同时保留高优先级模块的 placement directive。 | [ModuleMerger L112-L171](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Services/ModuleMerger.swift#L112-L171) | **缺失**。 | 精确移植语义与优先级测试，尤其覆盖同 key 普通值 vs directive 的组合。
| 22 | iCloud 模式输出固定汇总文件：iOS 为 `Surge-Relay.sgmodule`，其他平台为 `Surge-Relay-<platform>.sgmodule`；用户可额外启用每个来源的独立模块输出。 | [AppSettings L137-L163](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Models/AppSettings.swift#L137-L163)、[L266-L279](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Models/AppSettings.swift#L266-L279)、[ModulesView L819-L869](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Views/ModulesView.swift#L819-L869) | **缺失**；当前只发布 `.conf/.dconf`（[Shallow README L35-L52](https://github.com/funnythingfunnylove/Surge-Shallow/blob/1bce3c40b5e20310a1f92aea8797571854fb3ea1/README.md#L35-L52)）。 | 默认建议采用 Shallow 品牌文件名以避免与旧 Surge Relay 冲突，同时提供“兼容文件名”迁移开关。
| 23 | iCloud 写入使用 `NSFileCoordinator` + atomic write；仅覆盖具有严格 Relay 元数据的汇总文件，独立模块另写 UUID ownership marker；冲突版本必须都是本 App 管理的文件才会解决。 | [ModuleFileStore L132-L179](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Services/ModuleFileStore.swift#L132-L179)、[L210-L259](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Services/ModuleFileStore.swift#L210-L259)、[L397-L418](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Services/ModuleFileStore.swift#L397-L418) | **已有基础**；Profile Publisher/Persistence 已有 atomic、协调、冲突和 ownership 保护（[Shallow README L28-L30](https://github.com/funnythingfunnylove/Surge-Shallow/blob/1bce3c40b5e20310a1f92aea8797571854fb3ea1/README.md#L28-L30)、[RelayPersistence L75-L110](https://github.com/funnythingfunnylove/Surge-Shallow/blob/1bce3c40b5e20310a1f92aea8797571854fb3ea1/Sources/SurgeProfileRelayCore/Services/RelayPersistence.swift#L75-L110)）。 | 扩展为按 artifact type 验证 ownership，绝不只靠文件名判断。
| 24 | 如果用户删除一个由 App 生成的独立 iCloud 文件，1 秒监视器会关闭该模块的独立输出；若只存在旧文件名则迁移。 | [AppModel L1642-L1690](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/AppModel.swift#L1642-L1690) | **缺失**。 | 可用 DispatchSource/FilePresenter 替代 1 秒轮询；验收要求外部删除不会被立即“复活”。

### 3.5 GitHub、Cloudflare 与稳定订阅

| # | 上游功能与可验收行为 | 一手证据 | Surge Shallow 1.7.0 | 整合要求 |
|---:|---|---|---|---|
| 25 | 同步方式可选 iCloud 或 GitHub 私有仓库；GitHub 必须配置 owner/repo/branch/directory、Token 和 Cloudflare 公共根 URL，公开仓库在上传边界被拒绝。 | [AppSettings L11-L63](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Models/AppSettings.swift#L11-L63)、[GitHubClient L73-L98](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Services/GitHubClient.swift#L73-L98) | **缺失**；Shallow 的 GitHub 能力仅用于发现规则文件，不用于发布产物。 | 新增发布凭据和目标配置；Profile Relay 是否同时支持 GitHub 发布应作为单独开关，不随 Module 模式强制开启。
| 26 | GitHub 发布用 Git Data API 创建 blobs/tree/commit，比较 branch head 后 non-force 更新 ref；内容不变不提交；head 移动、409/422/429/rate limit 做指数退避与 jitter，最多 5 次。 | [GitHubClient L100-L129](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Services/GitHubClient.swift#L100-L129)、[L132-L236](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Services/GitHubClient.swift#L132-L236)、[L239-L250](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Services/GitHubClient.swift#L239-L250) | **缺失**。 | 实现单事务多文件发布；保留 CAS 与幂等行为；覆盖两个 Mac 同时发布测试。
| 27 | 发布后通过 Cloudflare URL 重新下载每个平台汇总文件，最多 4 次，必须与本地 Data 完全相等才报告成功。 | [AppModel L1291-L1305](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/AppModel.swift#L1291-L1305)、[L1323-L1370](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/AppModel.swift#L1323-L1370) | **缺失**。 | 发布状态区分“Git commit 成功”与“CDN 可读取已验证”；失败时保留 commit SHA 供诊断。
| 28 | 汇总与每个独立模块均显示并可复制稳定订阅 URL；Mac 关机后已发布文件仍可用。 | [README L41-L57](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/README.md#L41-L57)、[ModulesView L923-L960](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Views/ModulesView.swift#L923-L960) | **缺失**。 | URL 作为派生展示，不持久化带 Token 的 API URL；复制按钮需分别标识平台/单模块。

### 3.6 Web 管理与 Surge Ponte

| # | 上游功能与可验收行为 | 一手证据 | Surge Shallow 1.7.0 | 整合要求 |
|---:|---|---|---|---|
| 29 | 内置 HTTP Web 管理服务，可开关端口、显示 Bonjour `.local` URL、浏览器打开和二维码；通过 `_http._tcp` 发布。Web 资源支持桌面/移动自适应、iPhone safe area、触控滚动、深色与 reduced-motion，并带 manifest/Apple Touch Icon/standalone 元数据。 | [SettingsView L333-L374](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Views/SettingsView.swift#L333-L374)、[WebManagementServer L108-L150](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Services/WebManagementServer.swift#L108-L150)、[app.css L755-L902](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/WebResources/app.css#L755-L902)、[index.html L1-L18](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/WebResources/index.html#L1-L18) | **缺失**。 | 新增 Web server 生命周期；端口变更热重启，应用唤醒/网络恢复时自愈；Web 外观跟随浏览器/系统而不是强绑定本机 Shallow 偏好。
| 30 | Web UI 能读状态/活动/设置，修改通用、Web、Script-Hub 和同步设置，测试 GitHub/Cloudflare，清历史、导出诊断、搜索 App Store 图标、全部更新、添加和重排模块。 | [WebManagementAPI L19-L88](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Services/WebManagementAPI.swift#L19-L88) | **缺失**。 | API 版本化，例如 `/api/v1`; 与原生 App 共享 application service，不复制业务逻辑。
| 31 | Web UI 能按平台启停单个/全部模块，编辑/删除/启停/更新模块，开关独立 iCloud 输出，编辑/恢复预览，接受冲突，自定义图标，读写 overrides 和 arguments。 | [WebManagementAPI L93-L120](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Services/WebManagementAPI.swift#L93-L120)、[L293-L418](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Services/WebManagementAPI.swift#L293-L418) | **缺失**。 | Web 与 native 权限/校验相同；所有写操作返回 operation ID 或最新 revision，避免盲写。
| 32 | `/api/events` 通过 SSE 推送状态，忙时 400ms、空闲 1s，约 10s heartbeat；客户端同时轮询 activity，SSE 中断后保留最后投影并指数退避重连。 | [WebManagementServer L203-L265](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Services/WebManagementServer.swift#L203-L265)、[AppModel+RemoteClient L73-L174](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/AppModel%2BRemoteClient.swift#L73-L174) | **缺失**。 | 保留“最后良好投影”体验；Module 和 Profile 更新都应进入统一 activity stream。
| 33 | Ponte 服务器模式沿用本机 iCloud/GitHub 并开放 Web API；客户端模式不启动本地 Web 服务、不加载本地模块，使用 `host.sgponte[:port]` 连接服务器并执行原生远程管理。 | [AppSettings L287-L331](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Models/AppSettings.swift#L287-L331)、[AppModel L130-L178](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/AppModel.swift#L130-L178)、[SettingsView L380-L452](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Views/SettingsView.swift#L380-L452) | **缺失**。 | 设备角色存本机 UserDefaults，不随 iCloud；客户端不得误写本地 `relay.json` 或模块 registry。
| 34 | 网络从断开恢复、App 变为 active、Mac 唤醒时尝试恢复 Web server/Ponte session；Web server 失败指数退避至 30 秒。 | [NetworkPathMonitor L4-L29](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Services/NetworkPathMonitor.swift#L4-L29)、[AppModel+WebServerLifecycle L5-L50](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/AppModel%2BWebServerLifecycle.swift#L5-L50)、[L110-L128](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/AppModel%2BWebServerLifecycle.swift#L110-L128) | **缺失**。 | 作为共享 ConnectivitySupervisor，避免 Profile 调度和 Web 重连各自建立重复 NWPathMonitor。

### 3.7 自动化、菜单栏、诊断和应用更新

| # | 上游功能与可验收行为 | 一手证据 | Surge Shallow 1.7.0 | 整合要求 |
|---:|---|---|---|---|
| 35 | 刷新间隔为手动/15 分钟/1 小时/6 小时/12 小时；支持登录启动、自动同步、平台汇总开关。调度器按间隔调用 updateAll；启动时若从未更新、缓存缺失或达到间隔会更新，否则直接从缓存重建。单模块更新 350ms、合并重建 450ms、GitHub 自动发布 1.2s 防抖。 | [SettingsView L294-L327](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Views/SettingsView.swift#L294-L327)、[AppModel L181-L221](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/AppModel.swift#L181-L221)、[L575-L585](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/AppModel.swift#L575-L585)、[L1124-L1188](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/AppModel.swift#L1124-L1188) | **部分**；已有规则源调度、启动检查和登录启动（[Shallow Settings L61-L95](https://github.com/funnythingfunnylove/Surge-Shallow/blob/1bce3c40b5e20310a1f92aea8797571854fb3ea1/Sources/SurgeShallow/Views/SettingsView.swift#L61-L95)）。 | 单一 scheduler 按 Profile/Module 各自 due 状态派发，保留“立即更新规则”和“立即更新模块”两个动作及“全部同步”；防抖不能互相取消另一个域的任务。
| 36 | 菜单栏显示客户端/服务器与 Web 状态、进度、最新更新、启用来源数；可更新全部、复制 iOS 汇总地址、切自动同步/登录启动、打开主窗口/设置、检查 App 更新、退出。客户端断线时图标变淡。 | [MenuBarContent L12-L80](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Views/MenuBarContent.swift#L12-L80)、[SurgeRelayApp L105-L107](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/SurgeRelayApp.swift#L105-L107) | **部分**；Shallow 菜单栏已有规则源数量、规则数、更新和打开 Profile，但无模块/Web/Ponte/订阅 URL/Sparkle 状态（[MenuBarView L7-L66](https://github.com/funnythingfunnylove/Surge-Shallow/blob/1bce3c40b5e20310a1f92aea8797571854fb3ea1/Sources/SurgeShallow/Views/MenuBarView.swift#L7-L66)）。 | 合并为分区菜单：Profiles、Modules、Remote；状态项不应因总数增多而溢出。
| 37 | 更新历史记录 updated/unchanged/cachedAfterFailure/failed/published、模块、耗时、消息、是否缓存和内容变化；最多 200 条。诊断页显示最近 20 条，可清除或导出脱敏 JSON。 | [ServiceModels L25-L78](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Models/ServiceModels.swift#L25-L78)、[SettingsView L652-L679](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Views/SettingsView.swift#L652-L679)、[AppModel L2043-L2072](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/AppModel.swift#L2043-L2072) | **部分**；Shallow 有最多 200 条 Profile 更新记录，但无模块粒度耗时、缓存位、发布 commit、诊断导出（[RelayDocument L34-L65](https://github.com/funnythingfunnylove/Surge-Shallow/blob/1bce3c40b5e20310a1f92aea8797571854fb3ea1/Sources/SurgeProfileRelayCore/Models/RelayDocument.swift#L34-L65)、[L119-L123](https://github.com/funnythingfunnylove/Surge-Shallow/blob/1bce3c40b5e20310a1f92aea8797571854fb3ea1/Sources/SurgeProfileRelayCore/Models/RelayDocument.swift#L119-L123)）。 | 统一 history envelope，保留 `domain=profile/module/publish/remote`; 导出必须遮蔽 URL query、GitHub Token 和请求 Header。
| 38 | 使用 Sparkle 自动检查和手动“检查更新”；appcast URL 和 Ed25519 公钥写入 Info.plist。 | [SurgeRelayApp L91-L103](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/SurgeRelayApp.swift#L91-L103)、[CheckForUpdatesView L16-L30](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Views/CheckForUpdatesView.swift#L16-L30)、[Info.plist L34-L39](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Info.plist#L34-L39) | **缺失**。 | 新增 Surge Shallow 自己的 appcast、公钥和签名私钥管理，绝不可复用上游公钥；GitHub Release 资产改为 Sparkle 可验签格式。

## 4. 数据模型与文件格式对照

### 4.1 上游持久化布局

上游默认把配置目录放在 Surge iCloud 根目录下的 `Surge Relay/`，把派生缓存放在本机 Application Support。路径定义见 [AppSettings L225-L259](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Models/AppSettings.swift#L225-L259) 和 [PersistenceStore L38-L71](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Services/PersistenceStore.swift#L38-L71)：

```text
~/Library/Mobile Documents/iCloud~com~nssurge~inc/Documents/
├── Surge-Relay.sgmodule                # iOS/iPadOS 汇总
├── Surge-Relay-macOS.sgmodule          # 可选
├── Surge-Relay-tvOS.sgmodule           # 可选
├── Surge-Relay-visionOS.sgmodule       # 可选
├── <name>-Surge-Relay.sgmodule         # 用户选择的独立模块输出
└── Surge Relay/
    ├── settings.json
    ├── settings.json.bak
    ├── modules.json
    ├── script-hub-state.json
    ├── update-history.json
    ├── Overrides/<module-uuid>.module
    └── Backups/<filename>/<timestamp>-<id>.backup

~/Library/Application Support/Surge Relay/Cache/
├── Components/<module-uuid>.cache
├── Assets/<module-uuid>/...
├── Icons/<module-uuid>
├── ScriptHubEngine/*.js
├── Combined-<platform>.cache
└── CombinedOverride-<platform>.cache
```

上游配置写入使用 pretty/sorted JSON、ISO-8601 日期、atomic write；每文件最多保留 20 份备份，主文件损坏时会保留 `.corrupt-<timestamp>` 并从备份恢复（[PersistenceStore L184-L261](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Services/PersistenceStore.swift#L184-L261)）。

关键模型：

- `RelayModule`：身份、来源、格式、输出、平台/独立输出、Script-Hub 参数、编辑覆盖、图标、HTTP revision、内容 hash、引擎 revision、冲突状态、更新时间/错误（[RelayModule L104-L132](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Models/RelayModule.swift#L104-L132)）。
- `AppSettings`：Script-Hub、刷新/自动发布/登录启动、GitHub/Cloudflare、存储方式、Web 端口、四平台设置、图标区域（[AppSettings L137-L164](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Models/AppSettings.swift#L137-L164)）。
- 设备角色和 Ponte 地址刻意保存在本机 UserDefaults，不随 iCloud（[AppSettings L287-L319](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Models/AppSettings.swift#L287-L319)）。

### 4.2 Surge Shallow 当前布局

Surge Shallow 当前使用单一 schema v6 `relay.json` 管理 Profile/Rule 域，包含 sources、sharedProfile、targets、settings、history（[RelayDocument L68-L117](https://github.com/funnythingfunnylove/Surge-Shallow/blob/1bce3c40b5e20310a1f92aea8797571854fb3ea1/Sources/SurgeProfileRelayCore/Models/RelayDocument.swift#L68-L117)）：

```text
~/Library/Mobile Documents/iCloud~com~nssurge~inc/Documents/
├── Surge-Profile-Relay-macOS.conf
├── Surge-Profile-Relay-iOS.conf
├── Surge-Profile-Relay-Shared.dconf
└── Surge Profile Relay/
    ├── relay.json
    └── relay.json.bak

~/Library/Application Support/Surge Profile Relay/
├── Cache/<rule-source-uuid>.rules
└── Preview/...
```

当前 `relay.json` 已经是 iCloud 多 Mac 的共享管理真相，且有未解决冲突拒写、备份恢复和协调写入（[RelayPersistence L75-L110](https://github.com/funnythingfunnylove/Surge-Shallow/blob/1bce3c40b5e20310a1f92aea8797571854fb3ea1/Sources/SurgeProfileRelayCore/Services/RelayPersistence.swift#L75-L110)）。

### 4.3 推荐整合后的 schema

为避免破坏 1.7.0 兼容性，推荐升级 `relay.json` 为新 schema，在根级新增可选 `moduleRelay`，而不是引入第二套互相覆盖的共享设置：

```json
{
  "schemaVersion": 7,
  "sources": [],
  "sharedProfile": {},
  "targets": [],
  "settings": {},
  "history": [],
  "moduleRelay": {
    "modules": [],
    "settings": {
      "storageMode": "iCloud",
      "scriptHub": {},
      "github": {},
      "web": {},
      "platforms": {}
    },
    "upstreamState": {}
  }
}
```

本机缓存建议放在现有 Application Support 下的新命名空间：

```text
~/Library/Application Support/Surge Profile Relay/ModuleRelay/
├── Components/
├── Assets/
├── Combined/
└── Engine/
```

设备角色、Ponte 地址、外观偏好、窗口状态继续保存在本机 UserDefaults；它们不能跟 `relay.json` 同步。模块手工 override 属于用户配置，应放在 iCloud 管理目录并使用独立备份；下载/转换/汇总缓存是派生物，只放本机。

## 5. 同步与更新机制的完整行为

上游一次模块更新的用户可见状态机为：

```text
到期/手动触发
  → 如需要，更新 Script-Hub 引擎
  → 对每个模块做条件 revision 检查
  → 未变化且引擎未变化：读取缓存
  → 变化或引擎变化：下载并转换
  → 校验、保存组件和资产、应用 override
  → 失败：有缓存则沿用；无缓存则停止覆盖
  → 按每个平台的模块顺序和启停状态合并
  → iCloud 协调写入，或 GitHub 原子提交
  → GitHub 模式通过 Cloudflare 回读逐字节验证
  → 写入 update history 与 UI/SSE 状态
```

源代码证据覆盖任务互斥/取消和 200ms coalescing（[AppModel L829-L867](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/AppModel.swift#L829-L867)）、并发过程中的本地 generation 防陈旧写入（[L869-L895](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/AppModel.swift#L869-L895)）、组件更新和缓存回退（[L903-L1078](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/AppModel.swift#L903-L1078)）、重建与发布（[L1080-L1107](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/AppModel.swift#L1080-L1107)）。

整合后必须保留两条相互独立的发布门禁：

- Profile Relay：规则解析、Profile lint、`surge-cli --check`、所有启用目标通过后才写 `.conf/.dconf`。
- Module Relay：模块转换 validator、全部必要组件有缓存、合并器成功、iCloud ownership 或 GitHub/Cloudflare 验证通过后才报告完成。

模块失败不能阻止无关 Profile 发布，Profile lint 失败也不能回滚已验证的 Module 更新；“全部同步”只聚合两个结果。

## 6. 设置、菜单栏与通知边界

上游设置页包含 7 个 pane：通用、Web 管理、Surge Ponte、Script Hub、同步、诊断、关于（[SettingsView L104-L138](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Views/SettingsView.swift#L104-L138)）。建议整合后的 Shallow 设置页保留当前“外观/iCloud/自动更新/安全门禁”，新增：

1. `Modules`：模块默认刷新、启用平台、文件名策略、独立输出默认值；
2. `Script-Hub`：上游、自动更新、revision、缓存状态；
3. `发布`：iCloud 与私有 GitHub + Cloudflare；
4. `远程管理`：Web、端口、二维码、Ponte 角色/地址；
5. `诊断`：Profile 与 Module 统一历史、导出、清除；
6. `软件更新`：Sparkle 渠道与手动检查。

关于“通知”：上游没有发现 `UNUserNotificationCenter`/`NSUserNotification` 系统通知实现。用户反馈依靠主界面状态、菜单栏状态、Web/SSE 和 Sparkle UI；嵌入式 Script-Hub 的 `$notification.post` 被显式实现为空操作（[EmbeddedScriptHubEngine L101-L119](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Services/EmbeddedScriptHubEngine.swift#L101-L119)）。因此“全部功能”并不要求新增系统通知；如果产品希望加入，应作为 Shallow 扩展并默认只通知失败/需要人工冲突处理，避免周期更新噪声。

## 7. 上游边界与整合时必须修正的问题

以下不是推测，而是固定提交源码显示的边界：

1. **Web/Ponte API 没有认证门禁。** `NWListener` 监听端口并接受非 loopback 连接；请求只记录 `isLoopback`，API 分派没有检查它，也没有 Authorization/会话校验（[WebManagementServer L108-L178](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Services/WebManagementServer.swift#L108-L178)、[L297-L343](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Services/WebManagementServer.swift#L297-L343)、[WebManagementAPI L13-L26](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Services/WebManagementAPI.swift#L13-L26)）。整合版应至少使用首次配对生成的 bearer token，局域网 Web 采用 Keychain 存储，二维码带一次性配对码；远程写 API 还应做 CSRF/origin 限制。
2. **GitHub Token 实际存入 iCloud `settings.json`。** `KeychainStore.swift` 明确说明 credentials intentionally stored in iCloud settings，`AppSettings` 直接含 `githubToken`（[KeychainStore L1-L2](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Services/KeychainStore.swift#L1-L2)、[AppSettings L148-L155](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Models/AppSettings.swift#L148-L155)）。整合版应把 Token 放 Keychain；`relay.json` 只存 credential reference 和“已配置”状态。
3. **override 冲突 UI 目前没有可达触发。** 最新更新路径对有/无 override 都把 `hasOverrideConflict=false`，全仓没有把它设为 `true` 的运行时代码（[AppModel L984-L998](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/AppModel.swift#L984-L998)）。整合应比较旧 `overrideBaseHash` 与新转换 hash，发生差异时保存新上游、继续使用旧 override 并置 conflict。
4. **删除模块后的 GitHub 旧文件清理与 UI 文案不一致。** 删除流程删除本地组件/资产/图标后重建，但没有把被删文件名传入下一次 GitHub publish；GitHub 发布只删除当前文件声明的 `legacyNames`（[AppModel L806-L827](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/AppModel.swift#L806-L827)、[GitHubClient L161-L168](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Services/GitHubClient.swift#L161-L168)），而 UI 写“旧版本会保留到下次发布”（[ModulesView L431-L445](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Views/ModulesView.swift#L431-L445)）。整合版需持久化 pending deletions，并在同一 Git tree transaction 删除。
5. **自动格式的兜底是 Quantumult X。** 无已知扩展名/路径的 URL 会默认为 QX，而不是内容探测（[RelayModule L54-L67](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Models/RelayModule.swift#L54-L67)）。整合可先保持兼容，再增加下载后内容探测与明确提示。
6. **Web 请求体上限固定 4 MB，模块来源上限固定 20 MB。** 前者见 [WebManagementServer L98-L107](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Services/WebManagementServer.swift#L98-L107)，后者见 [ScriptHubClient L167-L173](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Services/ScriptHubClient.swift#L167-L173)。Shallow 已有用户可调规则源大小，模块与 Web 上限应各自配置并保留合理硬上限。
7. **ATS 允许任意网络加载。** 上游 Info.plist 设置 `NSAllowsArbitraryLoads=true`（[Info.plist L29-L33](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/SurgeRelay/Info.plist#L29-L33)），这是为了 HTTP Script-Hub/Ponte/来源兼容。整合版应优先 HTTPS，仅对用户明确添加的 HTTP 来源以及本地/Ponte 地址做受控例外。
8. **当前 Sparkle appcast 指向不存在的最新 DMG。** 固定提交的 appcast 声明 build `27071709`，下载 URL 是 `Surge-Relay-270717-build-27071709.dmg`（[appcast L5-L12](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/appcast.xml#L5-L12)、[L39-L40](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/appcast.xml#L39-L40)），但 `v270717` Release 的一手资产名是 [`Surge-Relay-270717-build-270717.dmg`](https://github.com/EEliberto/SurgeRelay-macOS/releases/tag/v270717)。2026-07-22 实测前者 HTTP 404、后者 HTTP 200。整合版的 Release workflow 必须在发布后下载 appcast enclosure 并验证长度与 Sparkle 签名，禁止只验证本地 DMG。
9. **Cloudflare 教程的“最新 Worker 源码”链接在仓库中不存在。** 教程同时链接 `Deployment/CloudflareWorker/src/index.js`（[Guide L13-L20](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/docs/GitHub-Cloudflare-Guide.md#L13-L20)、[L177-L179](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/docs/GitHub-Cloudflare-Guide.md#L177-L179)），固定提交的 Git tree 没有该文件；可复制代码只存在于教程内嵌区（[L95-L175](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/docs/GitHub-Cloudflare-Guide.md#L95-L175)）。整合版应把 Worker 作为受测试、可部署的源码目录提交，并让教程引用 commit permalink。

## 8. 许可证与第三方材料

上游 SurgeRelay-macOS 是 **Apache License 2.0**，不是 MIT（[LICENSE L1-L5](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/LICENSE#L1-L5)、[L66-L71](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/LICENSE#L66-L71)）。Surge Shallow 当前是 MIT，并在 THIRD_PARTY_NOTICES 中声明当前只是独立实现、未打包上游源码（[Shallow THIRD_PARTY_NOTICES L1-L8](https://github.com/funnythingfunnylove/Surge-Shallow/blob/1bce3c40b5e20310a1f92aea8797571854fb3ea1/THIRD_PARTY_NOTICES.md#L1-L8)）。

如果直接复制/修改上游源码，发布前必须：

- 保留 Apache 2.0 LICENSE 和适用版权/NOTICE；
- 在修改过的文件中作显著修改声明；
- 更新 Shallow 的 THIRD_PARTY_NOTICES，不再声称“不 bundle Surge Relay source code”；
- 保留 Shallow 自有代码的 MIT 声明，并在分发物中同时携带两种许可证。

上游运行时会下载并执行 GPL-3.0 的 Script-Hub 文件，且上游 THIRD_PARTY_NOTICES 已明确该关系（[THIRD_PARTY_NOTICES L3-L9](https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/THIRD_PARTY_NOTICES.md#L3-L9)）。整合版需要复用该运行时下载模式、保留归属与许可证展示；不要把固定 Script-Hub 脚本直接提交进当前 MIT 源码树，除非单独完成对应 GPL 分发处理。

## 9. 推荐实施顺序与验收门槛

### Phase A：Module Core（先完成）

- 新模型：ModuleRelayDocument、RelayModule、ScriptHubOptions、四平台设置、history。
- 本地 Script-Hub 引擎下载/缓存/执行、原生 Surge passthrough、全部转换选项。
- ModuleMerger、参数/策略/MITM 覆盖、组件和资产缓存。
- 模块列表、详情、预览编辑、真实 override conflict。
- iCloud 汇总和独立 `.sgmodule`，ownership、冲突与 pending deletion。

验收：单元测试覆盖三类来源、所有 query 映射、段合并、缓存回退、四平台输出、非管理文件拒写；使用至少一个 QX、Loon、Surge 样本做端到端转换。

### Phase B：稳定分发与自动化

- 私有 GitHub + Cloudflare 设置、CAS 原子发布、资产同事务、CDN 回读验证。
- 合并 Profile/Module scheduler、菜单栏状态、诊断导出。
- 首次设置/迁移向导；Sparkle 更新链路。

验收：两个并发 publisher 的 head-moved 重试、内容不变不提交、删除模块清远端、Cloudflare 旧缓存不误报成功；Sparkle 线上资产签名可验证。

### Phase C：远程管理

- 版本化 Web API、Web UI、SSE/activity、QR 配对。
- Ponte 原生客户端/服务器模式、网络恢复和最后良好投影。
- Keychain credentials、bearer pairing、CSRF/origin 与日志脱敏。

验收：LAN、Ponte、断网/睡眠/唤醒、SSE 中断、服务器重启、客户端写操作；未配对请求不能读取来源 URL、Token 状态或执行 mutation。

### 最终“全部整合”完成定义

只有以下同时满足，才可宣称 SurgeRelay-macOS 全部功能已整合：

1. 矩阵 38 项均达到“已有”，或对第 7 节的上游边界有明确修正版行为与测试；
2. 现有 Profile/Ruleset/Profile Import、深浅色、iCloud `relay.json` 兼容和 `surge-cli --check` 流程无回归；
3. 旧 schema 可无损迁移，Module Relay 关闭时生成产物与 1.7.0 完全一致；
4. iCloud 验证不修改用户既有 Profile/模块，非管理同名文件始终拒绝覆盖；
5. GitHub Token 和 Web pairing secret 不写入 `relay.json`、诊断文件或日志；
6. macOS 安装包、Sparkle appcast、GitHub Release、许可证与第三方 notices 同步更新。

## 10. Release 功能演进附录

上游 Release 与固定 `main` 的功能演进可归纳为以下四个阶段。此附录用于迁移验收和回归测试分组，不替代第 3 节的源码级功能矩阵：

| 版本 | 主要能力增量 | 整合回归重点 |
|---|---|---|
| `v1.1.1` | 引入私有 GitHub 发布与 Cloudflare 稳定订阅地址、可配置目录和菜单栏常驻管理。 | Git Data API 原子发布、非公开仓库门禁、CDN 回读校验、菜单栏进程生命周期。 |
| `v260702` / `v260703-r3` | 增加欢迎向导、iCloud/GitHub 双存储和来源独立模块输出。 | 已有配置无损发现、角色与存储选择、独立文件 ownership、删除/重命名迁移。 |
| `v260710` | 扩展到 iOS/iPadOS、macOS、tvOS、visionOS 四平台，并完善图标、预览编辑与完整 Web 管理。 | 平台级排序/启停、图标缓存与检索、override 持久化、Web API/UI/SSE 等价能力。 |
| `v270717` | 增加 Surge Ponte 原生客户端/服务器模式及网络断开、睡眠和唤醒后的自动恢复。 | 本地与远程角色隔离、最后良好投影、Web/Ponte 生命周期、网络恢复和配对认证。 |

Release 页面只能证明面向用户的功能声明；最终行为仍以本文固定的 `main@b19d0dd6` 源码和逐项验收测试为准。特别是 `v270717` tag 与固定 `main` 存在 13 个提交差异，发布资产名也存在第 7 节所述 appcast 错配。
