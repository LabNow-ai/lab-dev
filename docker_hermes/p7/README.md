# P7 Hermes 产品链（已归档）

LLM Hub V1 / P7 的固定组合、Launcher overlay、受限输入、黄金 runner 与报告
聚合均为一次性冻结验收证据，已按生产加固决策 D-10 从产品运行面删除。它们不是
持续维护的 Hermes 构建、启动或 CI 入口。

最后可读快照是本批基线
`fdbbab2155a9e088c37d2a8a2057178e19ac9534`。需要审阅历史材料时，在本仓执行：

```bash
git show fdbbab2155a9e088c37d2a8a2057178e19ac9534:docker_hermes/p7/<路径>
```

仍保留的 `scripts/test-p7-gates.sh` 是不启动容器的 Hermes 静态产品契约检查；
受支持构建与日常启动方式见父目录 README 和 `demo/`。
