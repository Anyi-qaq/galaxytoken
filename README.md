# 星河 Token

一个跑在 HarmonyOS 上的小工具：把各家 AI 大模型的**订阅套餐额度**和**按量付费余额**汇总到一屏，顺带提供一张桌面服务卡片。

---

## ⚠️ 先叠甲：这是「许愿式编程」的产物

**请先读完这一节再往下看。**

这个项目不是从需求文档、架构评审、迭代计划里长出来的。它的真实生产过程是：

> 一个人对着 AI 说「我想要一个能看各家额度的鸿蒙应用」，然后一路许愿、一路验收、一路返工，最后拼出来的东西。

所以请务必了解以下事实：

### 关于代码来源

- **几乎全部代码由 AI 生成。** 人类负责提需求、看截图、说「这里不对」「这个不要了」，不负责逐行手写。
- **没有经过团队 Code Review。** 只有「能编译 + 能跑起来 + 截图看着对」这三道关。
- **架构是为一次性生成而设计的**：扁平、直白、能自解释，但不是长期演进的架构。
- **测试覆盖不均。** 有解析逻辑的固定响应测试，但没有集成测试、没有 UI 自动化回归、没有真机矩阵测试。

### 关于可靠性

这是一个**个人自用级别**的玩具。请按以下预期使用：

| 你期待 | 实际 |
|---|---|
| 稳定拿到额度 | 上游接口一改就挂 |
| 出错有好提示 | 尽力而为，可能只给一行红字 |
| 数据绝对准确 | 依赖各家语义，已尽量验证但无法保证 |
| 有人维护 | 没有承诺，随时停更 |

### 关于接口合法性

**这是最需要说清楚的一点。**

本项目调用的接口分三类，**可靠性依次递减**：

1. **有官方文档的公开 API** — DeepSeek、Kimi、OpenRouter 等，相对稳定。
2. **有官方开源代码佐证的接口** — 智谱 GLM 的额度端点可从官方仓库 [zai-org/ZCode](https://github.com/zai-org/ZCode)（Apache-2.0）的生产代码中核实，字段语义有第一方注释背书。虽无网页文档，但可信度高。
3. **仅靠实测推断的接口** — 没有官方文档也没有官方代码，靠长期观察确定语义，随时可能变。

**本项目的立场**：

- 仅供**个人查看自己账号**的额度，不做任何自动化操作、不代刷、不绕过付费。
- 所有请求都使用**你自己的凭据**，直连官方域名，不经过任何中间服务器。
- 如果某个平台认为这种读取方式不可接受，请**立即停止使用对应来源**，本项目不为此负责。
- 请自行确认你的使用方式符合各平台的服务条款。

### 关于凭据安全

- 凭据存在鸿蒙 **Asset Store**（系统级密钥库），不是明文配置文件。
- 日志里只记长度、不记值；报错文本会把 `sk-` / `Bearer` / Cookie / JWT 替换成占位符。
- **但**：这是个人项目，没有做过安全审计。如果你要填生产环境的 Key，请自己权衡。

**一句话总结：能用、好用、但别拿它当生产力基础设施。**

---

## 功能

### 额度总览

- 一屏看多来源，按列自适应：手机 1 列、平板 2 列、2in1 3 列
- 每个来源显示 5 小时 / 本周 / 本月三个窗口的已用比例与重置倒计时
- 余额类来源只显示金额，不占三行空窗口
- 前台每 1 / 5 / 15 / 30 分钟自动刷新，支持下拉刷新

### 支持来源

**余额类（6 家）** — 一次 GET + 一个 Key：

| 来源 | 端点 | 币种 |
|---|---|---|
| DeepSeek | `GET /user/balance` | CNY / USD |
| Kimi | `GET /v1/users/me/balance` | CNY / USD |
| OpenRouter | `GET /api/v1/credits` | USD |
| 阶跃星辰 | `GET /v1/accounts` | CNY |
| 硅基流动 | `GET /v1/user/info` | CNY / USD |
| Novita AI | `GET /v3/user/balance` | USD |

**套餐类（3 家）** — 5 小时 / 每周时间窗口：

| 来源 | 端点 | 备注 |
|---|---|---|
| Kimi Code | `GET /coding/v1/usages` | 新套餐已取消每周上限 |
| 智谱 GLM Coding Plan | `GET /api/monitor/usage/quota/limit` | 5h/周/月三窗口，语义见 ZCode 官方源码 |
| MiniMax M Plan | `GET /v1/token_plan/remains` | 业务错误可能藏在 HTTP 200 里 |

另有**演示数据**（内置、不联网）与**自定义来源**。

### 自定义来源

按用途分成两类，编辑页只显示对应字段：

- **套餐额度** — 填 5 小时 / 本周 / 本月三个 JSON 路径，支持「已用%」「剩余%」「绝对值」三种语义
- **按量付费余额** — 只填余额金额路径与币种

这样设计是因为两者语义完全不同：硬塞在一个表单里，用户不知道该填哪一半。

### 桌面服务卡片

2×2 / 4×4 两种尺寸，缓存优先渲染。卡片**不做网络请求**，数据由主应用推送。

---

## 技术栈

- HarmonyOS **API 26**（7.0.0），Stage 模型
- ArkTS / ArkUI 声明式
- **零第三方依赖**（`dependencies` 为空）
- 系统 Kit：`NetworkKit`、`ArkData(preferences)`、`AssetStoreKit`、`FormKit`、`CryptoArchitectureKit`

### 源码规模

31 个 `.ets` 文件，约 7200 行。

```
entry/src/main/ets/
├── common/       常量、格式化、断点、日志
├── components/   卡片、窗口条、侧边导航
├── model/        类型定义、JSON 路径解析
├── net/          HTTP 客户端（超时、大小限制、重定向）
├── pages/        首页、来源管理、来源编辑、设置
├── service/      聚合刷新、卡片桥接
├── sources/      适配器注册表 + 各家实现
├── store/        设置存储、凭据存储
├── widget/       服务卡片 UI
└── widgetability/ 卡片 FormExtensionAbility
```

---

## 构建与运行

### 前置

- DevEco Studio **26.0.0** 或更高
- HarmonyOS SDK **API 26**
- 一台真机或模拟器（API 26）

### 步骤

```bash
# 1. 打开工程
#    DevEco Studio → Open → 选择本目录

# 2. 配置调试签名
#    File → Project Structure → Signing Configs → 勾选 Automatically generate signature

# 3. 构建
hvigorw assembleHap

# 4. 安装运行
hdc install entry/build/default/outputs/default/entry-default-signed.hap
```

### 关于签名

仓库里的 `build-profile.json5` **被 git 忽略**——它含证书路径与口令，属于本机环境，不该入库。仓库放的是一份不含签名材料的 `build-profile.example.json5`。

首次克隆后：

```bash
cp build-profile.example.json5 build-profile.json5
```

然后用 DevEco Studio 打开工程，在 **File → Project Structure → Signing Configs** 里勾选自动生成签名，工具会把材料补进这个文件。

---

## 已知限制

- **不做汇率换算**，多币种分行展示。币种标错概不负责。
- **桌面卡片最快约 30 分钟**刷新一次，秒级实时依赖应用在前台。
- 千问、Claude、Codex、Google AI、OpenDesign、CommandCode 等**我不会做**。

---

## 免责声明

本项目以 **MIT License** 发布，**不提供任何担保**。

- 因使用本软件导致的**数据错误、额度判断失误、账号异常、服务条款纠纷**，作者不承担责任。
- 本项目**不隶属于**任何 AI 平台，所有商标归各自所有者。
- 请勿用于商业用途、批量账号管理、或任何违反平台条款的场景。

**如果你不接受以上任何一条，请不要使用本项目。**

---

## 致谢

- 各家接口的清单与字段语义参考了 [cc-switch](https://github.com/farion1231/cc-switch) 的 `services/balance.rs` 与 `services/coding_plan.rs`（MIT）。本项目未包含其源代码，实现为独立重写。
- 图标由 gpt-image 生成。

---

## License

[MIT](LICENSE)
