# WorkersAI2API · D1 版

把 Cloudflare Workers AI 包装成 OpenAI 兼容接口，自带管理面板、用量看板和模型健康监控。

**纯 D1 存储，不需要 KV。**

## 功能

### OpenAI 兼容接口
- `POST /v1/chat/completions`
- `POST /v1/completions`
- `POST /v1/messages`
- `POST /v1/embeddings`
- `GET  /v1/models`

### 多账号负载均衡
多个 Cloudflare 账号随机轮询，非 2xx 自动切下一个账号。

### 用量看板
- 今日总 neurons、账号限额进度、预估费用
- 过去 7 日走势
- 今日模型占比：请求次数、neuron 数、单模型成本
- 每账号用量明细

成本口径：先扣免费额度，再乘单价。

```
可计费 neurons = max(0, 今日总量 - 账号数 × 10000)
预估费用 = 可计费 neurons / 1000 × $0.011
```

### 模型健康监控（事件驱动）
不做定时探测，只在日志里发现真实失败时才探测，避免无意义的 neurons 消耗。

1. Cron 每 5 分钟查一次被监控 Worker 的 telemetry（warn + error），零 neurons。
2. 解析 `改走下一候选 @cf/A → @cf/B: 4006`、`timeout`。
3. 发现失败才对该模型做一次轻量探测（`max_tokens: 1`）。
4. 失败按 `1 / 5 / 15 / 30 / 60` 分钟退避，最多 5 次。
5. 5 次仍不通就停止探测。
6. 恢复后立即停止。

通知（Telegram）全程只有 3 条：
- 首次判定不可用
- 连续 5 次探测失败，已停止
- 恢复可用

接口：
- `GET  /api/health`
- `POST /api/health/check`
- `POST /api/health/reset`

## 部署

### 1. 建 D1 数据库
控制台 →「存储和数据库」→「D1 SQL 数据库」→ 创建，例如 `workersai2api`。

表可以自动创建，也可以先在 D1 控制台执行 `schema.sql`。

### 2. 建 Worker
控制台 →「Workers 和 Pages」→「创建」→「Worker」→ 粘贴 `worker.js` 全文 → 部署。

### 3. 绑定
- D1 绑定变量名：**`DB`**（必须）
- 环境变量：

| 变量 | 说明 |
|---|---|
| `ADMIN_PASSWORD` | 面板登录密码，建议 Secret |
| `HEALTH_NOTIFY_TOKEN` | Telegram bot token，Secret，可选 |
| `HEALTH_NOTIFY_CHAT_ID` | 接收通知的 chat id，可选 |
| `HEALTH_SCRIPT_NAME` | 被监控的 Worker 名，默认 `tc033` |

### 4. Cron
触发器 → Cron → `*/5 * * * *`

### 5. 登录
访问 `/admin`，用 `ADMIN_PASSWORD` 登录，添加账号。

账号 token 权限：
- Workers AI: Read
- Account Analytics: Read
- Workers Scripts / Observability: Read

## wrangler 部署（可选）

```bash
cp wrangler.toml.example wrangler.toml
# 修改 database_id
npx wrangler d1 execute workersai2api --remote --file=schema.sql
npx wrangler deploy
```

`wrangler.toml` 里已经带 `keep_vars = true`，部署时不会清掉 Dashboard 上配置的变量和 Secret。

## 存储结构

一张通用表 `app_store`，一行一个 key，value 是 JSON：

| key | 内容 |
|---|---|
| `config` | 账号、代理密钥、模型映射 |
| `cache_usage_summary` | 用量汇总 |
| `cache_usage_details` | 每账号用量明细 |
| `model_health` | 模型健康状态与事件时间线 |

```sql
SELECT key, length(value) AS bytes,
       datetime(updated_at/1000, 'unixepoch') AS updated
FROM app_store ORDER BY updated_at DESC;
```

## 已知限制

1. GraphQL `aiInferenceAdaptiveGroups` 只有 `date` + `modelId`，没有 scriptName，所以用量是账号级，多 Worker 共用账号会合并。
2. `账号数 × 10000` 是免费额度假设，付费计划只作参考。
3. 「今日」按 UTC 计算。
4. 健康监控依赖被监控 Worker 的日志文案，改文案要同步改 `parseHealthEvent` 的正则。
5. Telegram 通知要求 bot 能主动给你发消息，先给 bot 发过 `/start`。

## 说明

基于 WorkersAI2API 改造，增加了 D1 存储、用量可视化、成本口径修正和事件驱动的模型健康监控。
