# WorkersAI2API · D1 版

Cloudflare Workers AI → OpenAI 兼容接口。纯 D1 存储，不依赖 KV。

多账号轮询 · 用量看板 · 成本估算 · 事件驱动模型健康监控

## 文件说明

| 文件 | 作用 | 怎么用 |
|---|---|---|
| `worker.js` | 全部后端逻辑，单文件 | 粘贴到 Worker 编辑器，或用 wrangler 部署 |
| `schema.sql` | D1 建表语句 | D1 控制台「查询」执行一次；不执行也会自动建表 |
| `wrangler.toml.example` | 命令行部署配置模板 | 复制为 `wrangler.toml`，填 `database_id` |
| `.gitignore` | git 忽略规则 | 不用管 |
| `README.md` | 本文件 | — |

## 部署

### 1. 建 D1

控制台 →「存储和数据库」→「D1 SQL 数据库」→ 创建（名字随意，如 `workersai2api`）→ 复制 **Database ID**。

建表二选一：

- D1 →「查询」→ 粘贴 `schema.sql` → 执行
- 跳过，Worker 首次请求会自动建表

### 2. 建 Worker

「Workers 和 Pages」→「创建」→「Worker」→ 命名 → 部署 →「编辑代码」→ 粘贴 `worker.js` 全文 → 部署。

### 3. 绑定 D1

Worker →「设置」→「绑定」→ 添加 → D1 数据库：

| 字段 | 值 |
|---|---|
| 变量名 | `DB` |
| D1 数据库 | 上一步创建的库 |

变量名必须是 `DB`，否则接口返回 500。

### 4. 环境变量

Worker →「设置」→「变量和机密」：

| 变量 | 必填 | 用途 |
|---|---|---|
| `ADMIN_PASSWORD` | 是 | `/admin` 登录密码，存为机密 |
| `HEALTH_SCRIPT_NAME` | 否 | 被监控的 Worker 名，默认 `tc033` |
| `HEALTH_NOTIFY_TOKEN` | 否 | Telegram bot token |
| `HEALTH_NOTIFY_CHAT_ID` | 否 | Telegram chat id |

### 5. Cron

Worker →「设置」→「触发器」→ Cron → `*/5 * * * *`

### 6. 登录

打开 `https://<Worker 域名>/admin`，用 `ADMIN_PASSWORD` 登录，添加账号。

账号 token 权限：

| 权限 | 用途 |
|---|---|
| Workers AI: Read | 调模型 |
| Account Analytics: Read | 用量统计 |
| Workers Scripts: Read | 读 telemetry 日志 |

## 接口

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/v1/chat/completions` | 对话补全（支持流式） |
| POST | `/v1/completions` | 文本补全 |
| POST | `/v1/messages` | Anthropic 格式 |
| POST | `/v1/embeddings` | 向量 |
| GET | `/v1/models` | 模型列表 |
| GET | `/api/health` | 健康状态 |
| POST | `/api/health/check` | 立即检查一次 |
| POST | `/api/health/reset` | 清空健康状态 |

`/api/*` 需要面板登录态。

```bash
curl https://<Worker 域名>/v1/chat/completions \
  -H "Authorization: Bearer <面板密钥>" \
  -H "Content-Type: application/json" \
  -d '{"model":"glm-5.3","messages":[{"role":"user","content":"hi"}]}'
```

## 用量看板

`/admin` 概览页显示：

- 今日总 neurons、账号限额进度、预估费用
- 近 7 日走势
- 各模型今日请求数、neurons、成本
- 每账号明细

成本算法：

```
可计费 neurons = max(0, 今日总量 − 账号数 × 10000)
预估费用 = 可计费 neurons ÷ 1000 × $0.011
```

免费额度按每账号每天 10,000 neurons，「今日」按 UTC。

## 模型健康监控

平时不探测。Cron 每 5 分钟只读日志（零 neurons），发现真实失败才动作。

1. 查被监控 Worker 的 warn/error 日志
2. 匹配 `改走下一候选 @cf/A → @cf/B: 4006` 与 `timeout`
3. 命中后对目标模型发一次 `max_tokens: 1` 探测
4. 仍失败按 `1 / 5 / 15 / 30 / 60` 分钟退避，最多 5 次
5. 5 次不通停止
6. 恢复立即停止

Telegram 只发 3 条：首次不可用、5 次失败已停止、恢复可用。

## 存储

只有一张表：

```sql
CREATE TABLE IF NOT EXISTS app_store (
  key        TEXT PRIMARY KEY,
  value      TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);
```

| key | 内容 |
|---|---|
| `config` | 账号、面板密钥、模型映射 |
| `cache_usage_summary` | 用量汇总 |
| `cache_usage_details` | 每账号明细 |
| `model_health` | 健康状态与事件时间线 |

## wrangler 部署

```bash
cp wrangler.toml.example wrangler.toml      # 改 database_id
npx wrangler d1 execute workersai2api --remote --file=schema.sql
npx wrangler deploy
```

`wrangler.toml` 带 `keep_vars = true`，不会清掉 Dashboard 的变量和 Secret。

## 限制

1. 用量是账号级：`aiInferenceAdaptiveGroups` 没有 scriptName，同账号多 Worker 会合并。
2. 免费额度按 `账号数 × 10000` 估算，付费账号仅供参考。
3. 健康监控依赖日志文案，改了格式要同步改 `parseHealthEvent` 的正则。
4. Telegram bot 必须先跟接收人对话过（发过 `/start`）。
