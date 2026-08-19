# P6 OpenClaw 产品闭环（已归档）

LLM Hub V1 / P6 的固定组合、黄金 runner、受限输入、运行时 Compose 与报告聚合
均为一次性冻结验收证据，已按生产加固决策 D-10 从产品运行面删除。它们不是持续
维护的 OpenClaw 启动入口，也不得重新用于日常或 CI 验证。

最后可读快照是本批基线
`fdbbab2155a9e088c37d2a8a2057178e19ac9534`。需要审阅历史材料时，在本仓执行：

```bash
git show fdbbab2155a9e088c37d2a8a2057178e19ac9534:docker_openclaw/p6/<路径>
```

仍保留的 `scripts/test-p6-gates.sh` 是不启动容器的静态产品契约检查；OpenClaw
的受支持构建与日常启动方式见父目录 README 和 `demo/`。
