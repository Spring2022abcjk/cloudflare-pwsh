# Cloudflare SDK 研究文档

本目录记录 Cloudflare 官方 OpenAPI schema、Stainless 生成 SDK 以及 PowerShell-native SDK 方案的研究结果。研究阶段只产出证据、规则归纳和模型建议，不实现正式 generator，也不修改 `ref` 下的官方仓库。

## 文档入口

- [研究总报告](./cloudflare-sdk-research.md)：按任务说明组织的体系化结论。
- [证据索引](./evidence-index.md)：固定 commit、源码位置、取证范围和复核入口。
- [中间模型建议](./normalized-and-powershell-model.md)：Normalized API Model 与 PowerShell Projection Model 候选。
- [P1.1 总结](./P1.1-summary.md)：DNS vertical slice 的确认项、实现项、原型决策、未解决项和 P1.2 延后项。
- [P1.1.5 总结](./P1.1.5-summary.md)：通用 correction/projection、强类型 presence/union 与生成边界。
- [P1.2 总结](./P1.2-summary.md)：OpenAPI loader/ref resolver/normalizer、correction 和 DNS semantic diff。
- [架构](./architecture.md)：长期 pipeline、层边界、已确认架构事实和 deferred boundary。
- [路线图](./roadmap.md)：P1 完成项与 P2.1–P4 路线。
- [开发原则](./development-principles.md)：后续 agent 必须遵守的长期规则。
- [P2.1 总结](./P2.1-summary.md)：Zones、D1、AI Search 跨资源归一化、投影快照和回归结果。
- [P2.2 总结](./P2.2-summary.md)：multipart、text、binary transport 的归一化结论和 runtime 边界。
- [P2.3 总结](./P2.3-summary.md)：PowerShell projection 扩展、`Get-CfZone` 二进制 cmdlet 隔离实验和迁移边界。
- [P2.4 总结](./P2.4-summary.md)：规范化模型兼容性引擎、投影差异、真实 schema revision 报告和 net10 基线。
- [ADR 0001](./adr/0001-net10-powershell76-baseline.md)：PowerShell 7.6/.NET 10 统一基线决策。

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
