-- WorkersAI2API 纯 D1 存储结构
-- 在 Cloudflare D1 控制台的「查询（Query）」里执行一次即可。
-- Worker 首次请求也会自动执行同样的 CREATE TABLE，二者等效。

CREATE TABLE IF NOT EXISTS app_store (
  key        TEXT PRIMARY KEY,
  value      TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);

-- 说明：
-- key 取值固定为以下几种，value 都是 JSON 文本：
--   config               账号、API 密钥、自定义模型映射
--   cache_usage_summary  用量汇总（5 分钟 TTL，逻辑层判断）
--   cache_usage_details  每账号用量明细
--   model_health         模型健康状态与事件时间线
--
-- 查看当前存了什么：
--   SELECT key, length(value) AS bytes, datetime(updated_at/1000, 'unixepoch') AS updated
--   FROM app_store ORDER BY updated_at DESC;
--
-- 清理旧缓存（可选）：
--   DELETE FROM app_store WHERE key LIKE 'cache_%'
--     AND updated_at < (unixepoch('now') * 1000 - 86400000);
