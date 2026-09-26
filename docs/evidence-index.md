# 证据索引

本页主要索引固定 SDK/schema 研究证据。当前阶段状态与证据边界见
[路线图](./roadmap.md)、[P3.5a 历史只读证据](./P3.5a-live-validation.md)、
[P3.5b 限定单记录完成证据](./P3.5b-constrained-crud-validation.md)、
[P3.5c 证据矩阵](./P3.5c-transport-evidence-plan.md)及
[P4.2 release checklist](./P4.2-release-checklist.md)。P3.5c 在用户接受的
限定证据范围内 Complete，缺少真实账户证据的场景和 DNS export 差异仍明示；
P4.2 总体 Partial，P4.3 尚未开始。

## 仓库与工作树

本轮没有修改官方 SDK。`ref/api-schemas` 和 `ref/cloudflare-typescript` 原有未跟踪的研究证据文件均保留；Python 和 Go 仅以浅克隆方式加入 `ref`，用于验证性对照。

| 证据 | 位置 |
| --- | --- |
| TypeScript DNS endpoint wrapper | `ref/cloudflare-typescript/src/resources/dns/records.ts:41-252` |
| TypeScript DNS models | `ref/cloudflare-typescript/src/resources/dns/records.ts:3733-6609`、`:6701-11430`、`:13491-13503` |
| TypeScript pagination runtime | `ref/cloudflare-typescript/src/core/pagination.ts:13-225`、`:227-435` |
| TypeScript request/error runtime | `ref/cloudflare-typescript/src/client.ts:178-500`、`:534-990`、`ref/cloudflare-typescript/src/core/error.ts:6-136` |
| TypeScript parse/options/query | `ref/cloudflare-typescript/src/internal/parse.ts:16-56`、`src/internal/request-options.ts:9-91`、`src/internal/utils/query.ts:5-7` |
| TypeScript generated boundary | `ref/cloudflare-typescript/CONTRIBUTING.md:17-19` |
| Zones cross-resource check | `ref/cloudflare-typescript/src/resources/zones/zones.ts:175-253` |
| Deep nested hierarchy check | `ref/cloudflare-typescript/src/resources/aisearch/namespaces/instances/jobs.ts:13-153` |
| Binary/multipart special payloads | `ref/cloudflare-typescript/src/resources/addressing/loa-documents.ts:28-62`、`src/resources/aisearch/namespaces/instances/items.ts:158-167`、`src/resources/dns/records.ts:273-280` |
| Python DNS wrapper | `ref/cloudflare-python/src/cloudflare/resources/dns/records.py:1597-1634`、`:3227-3454`、`:5123-5163`、`:5240-5264` |
| Python union types | `ref/cloudflare-python/src/cloudflare/types/dns/record_create_params.py:1718-1740`、`record_edit_params.py:1718-1740`、`record_response.py:1311-1333` |
| Python shared runtime | `ref/cloudflare-python/src/cloudflare/_base_client.py:1000-1126`、`:1196-1212`、`:758-849` |
| Python errors/retry constants | `ref/cloudflare-python/src/cloudflare/_exceptions.py:26-120`、`_constants.py:8-14` |
| Go DNS wrapper and params | `ref/cloudflare-go/dns/record.go:55-242`、`:7040-7420`、`:7897-7904`、`:8239-8315` |
| Go union/runtime | `ref/cloudflare-go/dns/record.go:3382-3516`、`ref/cloudflare-go/internal/requestconfig/requestconfig.go:253-384`、`:437-480` |
| Go errors/auth environment | `ref/cloudflare-go/internal/apierror/apierror.go:14-56`、`client.go:475-503` |
| OpenAPI DNS operations | `ref/api-schemas/openapi.json` paths `/zones/{zone_id}/dns_records` and `/zones/{zone_id}/dns_records/{dns_record_id}` |
| OpenAPI DNS union chain | schemas `dns-records_dns-record-post`, `dns-records_dns-record-patch`, `dns-records_dns-record-without-data`, `dns-records_dns-record-with-data`, `dns-records_*Record` |

## 已生成的精确切片

以下文件是研究过程中产生的本地证据切片，不是官方 SDK 源码：

- `ref/cloudflare-typescript/dns-record-edit-slices.json`
- `ref/cloudflare-typescript/dns-record-create-slices.json`
- `ref/cloudflare-typescript/dns-record-update-slices.json`
- `ref/cloudflare-typescript/dns-records-list-slices.json`
- `ref/cloudflare-typescript/pagination-runtime-slices.json`
- `ref/api-schemas/dns-core-operations.json`
- `ref/api-schemas/dns-concrete-record-schemas.json`
- `ref/api-schemas/dns-record-variant-schemas.json`

## 可复核命令

```powershell
git -C .\ref\cloudflare-typescript rev-parse HEAD
git -C .\ref\api-schemas rev-parse HEAD
git -C .\ref\cloudflare-python rev-parse HEAD
git -C .\ref\cloudflare-go rev-parse HEAD
Get-Verb | Sort-Object Verb
```

