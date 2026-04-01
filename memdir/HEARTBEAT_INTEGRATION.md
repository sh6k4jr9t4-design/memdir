# HEARTBEAT.md 补充：记忆模块维护

## 记忆维护（每天检查一次）

如果超过 24 小时未执行记忆维护：
1. 运行 `bash memdir/memory_consolidate.sh all` 整理日志
2. 运行 `bash memdir/memory_age.sh run` 执行老化
3. 运行 `bash memdir/memory_index.sh stats` 检查状态
4. 更新 memory/heartbeat-state.json 中的 lastMemoryMaintenance 时间戳

## 使用记忆搜索

需要查找记忆时：
- 使用 `bash memdir/memory_search.sh <keyword>` 搜索
- 使用 `bash memdir/memory_index.sh list importance` 查看高权重记忆
- 使用 `bash memdir/memory_access.sh <id>` 标记访问（自动提升权重）

## Cron 建议

可以用 OpenClaw cron 设置定期维护：
```
schedule: 每天凌晨 3:00
task: 运行记忆维护（consolidate + age）
```
