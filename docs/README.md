# Cloudflare SDK 研究文档

本目录记录 Cloudflare 官方 OpenAPI schema、Stainless 生成 SDK 以及 PowerShell-native SDK 方案的研究结果。研究阶段只产出证据、规则归纳和模型建议，不实现正式 generator，也不修改 `ref` 下的官方仓库。

## 文档入口

- [研究总报告](./cloudflare-sdk-research.md)：按任务说明组织的体系化结论。
- [证据索引](./evidence-index.md)：固定 commit、源码位置、取证范围和复核入口。
- [中间模型建议](./normalized-and-powershell-model.md)：Normalized API Model 与 PowerShell Projection Model 候选。

## 证据等级

- **Confirmed**：可以直接由固定版本源码或 schema 读取确认。
- **Inferred**：由两个或以上资源/语言实现归纳，仍应视为规则假设。
- **Proposed**：面向 PowerShell 项目的候选设计，不代表 Cloudflare 官方行为。
- **Unresolved**：当前证据不足，不能猜测或提前定案。

## 研究基线

| 项目 | 本地路径 | commit | 用途 |
| --- | --- | --- | --- |
| Cloudflare TypeScript SDK | `ref/cloudflare-typescript` | `faaaf89ed8064a9fb54de538ec3e89487f1302b0` | 主研究版本 |
| Cloudflare API schemas | `ref/api-schemas` | `28bfb054e5fa106464e9fbbf0ffbf362bc85234d` | OpenAPI 回溯 |
| Cloudflare Python SDK | `ref/cloudflare-python` | `68dc486d30710b666edbdf411d0b94db98652b1a` | 验证性对照 |
| Cloudflare Go SDK | `ref/cloudflare-go` | `a45114730bf2f913c5adff8f3ed7bf7534feffb9` | 验证性对照 |

TypeScript commit 是任务说明指定的固定基线。Python、Go 和 schema commit 已在本地记录，用于可复核的对照；它们不是 TypeScript commit 的同一发布日期快照，跨版本差异需要继续标记。

