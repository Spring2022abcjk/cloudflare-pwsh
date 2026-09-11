# Cloudflare 官方 SDK 研究总报告

## 0. 结论摘要

**Confirmed**：Cloudflare 的 TypeScript、Python、Go SDK 都把生成的 endpoint wrapper 做成很薄的参数分流层；path、query、body 的边界已由生成代码确定。跨 endpoint 的 HTTP、envelope、错误、retry、认证、序列化和 pagination 属于共享 runtime。

**Confirmed**：DNS `edit` 是 `PATCH`，但 `RecordEditParams` 与 `RecordUpdateParams` 一样，A variant 的 `zone_id`、`name`、`ttl`、`type` 都是 required；PATCH 在这个 schema 里不是“任意字段的 partial object”。`type` 仍然是单值 literal/enum discriminator。

**Confirmed**：DNS `delete` 的 TypeScript、Python、Go wrapper 都把 `dns_record_id` 作为独立 method argument，把 `zone_id` 放在 params/body helper 中，并且实际不发送 DELETE body；OpenAPI operation 的 requestBody 声明与生成 wrapper 的实际调用不完全一致，必须作为 exception 保留。

**Inferred**：PowerShell SDK 应把严格 API 映射的 primitive 层与 GET-merge-PUT 等便利行为分开；不能用一个看似简单的 `Set-CfDnsRecord -Ttl` 隐藏 PUT 的完整覆盖语义。

**Proposed**：采用 `Runtime → Normalized Model → Projection → Generated` 四层，并允许可审查的 override database。DNS 的 union 先保留为 typed model，不以大量 parameter sets 作为默认生成策略。

## 1. 研究基线与范围

研究基线见 [README](./README.md)。TypeScript 以任务指定 commit 为主基线；schema、Python、Go 的本地 commit 已记录，但不是同一时间点的锁定快照。因此，schema 与生成代码的 requiredness 若出现差异，以“各自 commit 的直接证据”为准，并在报告中说明。

结论标签含义：Confirmed、Inferred、Proposed、Unresolved。报告中的“官方”只指 `ref` 下这些 commit 的源码行为，不把当前网络上的最新行为倒灌进固定基线。

## 2. DNS Records CRUD 取证

### 2.1 Endpoint Signature Matrix

| Operation | HTTP | Resource ID | Parent ID | Query | Body | Response | Pagination |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `create` | POST | — | `zone_id` in params → path | `include_shadow_metadata` | `RecordCreateParams` union | `RecordResponse` | — |
| `list` | GET | — | `zone_id` in params → path | remaining params, including page/per_page and nested filters | — | `RecordResponse` item | `V4PagePaginationArray` |
| `get` | GET | `dnsRecordID` method arg → path | `zone_id` in params → path | `include_shadow_metadata` | — | `RecordResponse` | — |
| `update` | PUT | `dnsRecordID` method arg → path | `zone_id` in params → path | `include_shadow_metadata` | `RecordUpdateParams` union | `RecordResponse` | — |
| `edit` | PATCH | `dnsRecordID` method arg → path | `zone_id` in params → path | `include_shadow_metadata` | `RecordEditParams` union | `RecordResponse` | — |
| `delete` | DELETE | `dnsRecordID` method arg → path | `zone_id` in params → path | none in wrapper | no body sent by wrapper | `RecordDeleteResponse` | — |

TypeScript evidence is in `records.ts:41-136`, `:199-252`; the corresponding Python and Go signatures preserve the same primary-ID/parent-scope split.

### 2.2 Create、PUT、PATCH 字段关系

以 A record 为例：

| Field | Create | PUT Update | PATCH Edit |
| --- | --- | --- | --- |
| `zone_id` | required path field in params | required path field in params | required path field in params |
| `name` | required body | required body | required body |
| `ttl` | required body | required body | required body |
| `type` | required body, literal `'A'` | required body, literal `'A'` | required body, literal `'A'` |
| `include_shadow_metadata` | optional query | optional query | optional query |
| `comment` | optional body | optional body | optional body |
| `content` | optional in generated model | optional in generated model | optional in generated model |
| `proxied` | optional body | optional body | optional body |
| `settings` | optional body | optional body | optional body |
| `tags` | optional body | optional body | optional body |

**Confirmed**：`edit()` 的实现是 `const { zone_id, include_shadow_metadata, ...body } = params` 后调用 `patch(path, { query, body })`；它没有从 runtime 推断字段位置。`RecordEditParams.ARecord` 的 requiredness 和 `type: 'A'` 与 update variant 一致。

**Confirmed**：`RecordCreateParams`、`RecordUpdateParams`、`RecordEditParams` 都是相同变体集合的 union；请求参数类型不是单一“大而全” record object。

对固定 TypeScript 文件的 21 个 variant block 做了静态复核：Create、PUT Update、PATCH Edit 三个参数 union 中，所有 variant 都声明了 `name`、`ttl`、`type`，且这三个字段都没有 `?` optional 标记。这个结果强化了“PATCH 不是把 body 全部变成 optional”的结论；它仍不替代真实 API 请求验证。

**Unresolved**：Cloudflare API 的产品语义把 PATCH 称为 update，但固定版本 schema 没有把 DNS PATCH body 的所有字段标为 optional。不能仅凭 HTTP method 把它当作通用 JSON Merge Patch；要以 operation schema 的 requiredness 为准。

### 2.3 DELETE 的 body 例外

OpenAPI 路径 `/zones/{zone_id}/dns_records/{dns_record_id}` 的 DELETE operation 在当前 schema 文档中带有 requestBody 结构，但：

- TypeScript `delete()` 只调用 `_client.delete(path, options)`；
- Python `delete()` 只调用 `_delete(path, options=...)`，没有 body；
- Go `Delete()` 调用 `ExecuteNewRequest(..., nil, ...)`，明确传入 nil body。

因此 normalized model 必须同时记录 `schema.RequestBodyDeclared = true` 与 `observedWrapper.SendsBody = false`。这不是普通规则，应成为 `override candidate` 或 schema-quality warning。

### 2.4 Response model

`RecordResponse` 是 20+ variant union。TypeScript response variant 继承基础 record shape 后增加 `id`、`created_on`、`meta`、`modified_on`、`proxiable` 等 response-only 字段。Python 用 response `BaseModel` 继承对应 record model，Go 用 `RecordResponse` 加 `AsUnion()` 运行时 union。

**Confirmed**：request 与 response 不是同一个模型。PowerShell 若只输出 `PSCustomObject` 会丢失 discriminator、variant 和 response-only 约束；Normalized 层应保留 `CfARecord`、`CfAAAARecord` 等可辨识变体。

## 3. OpenAPI → SDK 映射

### 3.1 DNS union 链

当前 schema 的结构可以概括为：

```text
dns-records_dns-record-post / patch
    anyOf: dns-record-without-data | dns-record-with-data

dns-record-without-data
    oneOf: ARecord | AAAARecord | CNAMERecord | MXRecord | NSRecord |
           OPENPGPKEYRecord | PTRRecord | TXTRecord

dns-record-with-data
    oneOf: CAARecord | CERTRecord | DNSKEYRecord | DSRecord | HTTPSRecord |
           LOCRecord | NAPTRRecord | SMIMEARecord | SRVRecord | SSHFPRecord |
           SVCBRecord | TLSARecord | URIRecord

each concrete variant
    allOf: dns-record-shared-fields + variant-specific properties
```

**Confirmed**：具体 record 类型的 `type` 是单值 enum，例如 A schema 中 `enum: ["A"]`；TypeScript/Python/Go 生成结果分别表现为 literal、`Literal["A"]`、带 `api:"required"` 的 typed field。

需要特别保留一个版本边界：当前 `ref/api-schemas` commit 中，`dns-records_dns-record-shared-fields` 本身没有 `required` 列表，A/MX 等 concrete schema 的 inline variant properties 也没有 required 列表；而固定 TypeScript commit 的 generated input model 明确把 `name`、`ttl`、`type` 生成成 required。由于两仓库不是同一锁定快照，这只能记录为“schema commit 与 generated SDK commit 的差异”，不能在本轮断言 Stainless 一定在哪个阶段补充了 requiredness。

**Inferred**：Stainless 将 `oneOf`/`anyOf`/`allOf` 与单值 enum、requiredness 和 `$ref` 组合解释为语言 union、继承和 discriminator；但当前 SDK 仓库没有公开足够的 Stainless 配置来证明每一条命名规则的内部实现。命名来源只能确认到 schema title/组件名与生成名称的一致映射，不能声称是完整算法。

### 3.2 Request vs response 类型关系

```text
OpenAPI shared fields
    ├─ request variant: ARecordParam / RecordCreateParams.ARecord
    ├─ request variant: ARecordParam / RecordUpdateParams.ARecord
    ├─ request variant: ARecordParam / RecordEditParams.ARecord
    └─ response variant: RecordResponse.ARecord
          + id / timestamps / meta / proxiable / modification timestamps
```

不同 operation 产生独立 params 类型，是因为同一个 body shape 还要携带不同的 path/query 参数集合和不同的 requiredness。不要在 Normalized 层用名称去重掉 operation context。

## 4. Runtime Architecture

### 4.1 Envelope、parse、unwrap

TypeScript 请求链：

```text
endpoint wrapper
    → client.get/post/put/patch/delete
    → methodRequest()
    → request()/makeRequest()
    → fetch
    → HTTP status check
    → defaultParseResponse()
    → APIPromise.parse()
    → _thenUnwrap(obj => obj.result)
    → typed result
```

`defaultParseResponse()` 按 HTTP 204、`__binaryResponse`、content-type JSON 或 text 解析；它本身不检查 `success` 字段。非 2xx 在 `makeRequest()` 中读 body，再交给 `APIError.generate()`。所以 endpoint wrapper 只需 unwrap `result`，但它不是 envelope 验证器。

Python 显式使用 `ResultWrapper[T]` 与 `_unwrapper()`；Go 生成 `ResponseEnvelope` 后读取 `env.Result`。三种语言都把 Cloudflare 的 `result` 提取放在 generated/runtime 协议上，而不是业务 cmdlet 中。

**Unresolved**：对于 HTTP 2xx 但 payload `success=false` 的异常响应，当前三套 runtime 取证未发现一个统一的独立 application-error 分支；不能把 `success=false` 自动等同于 HTTP 异常。P1 runtime 应用 mock response 明确验证这一点。

### 4.2 Error model

| Condition | TypeScript | Python | Go |
| --- | --- | --- | --- |
| 400 | `BadRequestError` | `BadRequestError` | `*apierror.Error`, `StatusCode=400` |
| 401 | `AuthenticationError` | `AuthenticationError` | `*apierror.Error`, `StatusCode=401` |
| 403 | `PermissionDeniedError` | `PermissionDeniedError` | `*apierror.Error`, status retained |
| 404 | `NotFoundError` | `NotFoundError` | `*apierror.Error`, status retained |
| 409 | `ConflictError` | `ConflictError` | `*apierror.Error`, status retained |
| 422 | `UnprocessableEntityError` | `UnprocessableEntityError` | `*apierror.Error`, status retained |
| 429 | `RateLimitError` | `RateLimitError` | `*apierror.Error`, status retained |
| 5xx | `InternalServerError` | `InternalServerError` | `*apierror.Error`, status retained |
| connection/timeout | `APIConnectionError` / `APIConnectionTimeoutError` | `APIConnectionError` / `APITimeoutError` | transport/context error |

TypeScript/Python 保留解析后的 `errors` array；Go 的 `apierror.Error` 保留 `Errors`、request、response 和 raw JSON。Cloudflare error code/message 因此不应丢弃。

**Proposed PowerShell mapping**：runtime exception 应包含 HTTP status、Cloudflare error array、raw body、request ID/headers；`ErrorRecord.CategoryInfo` 可按 status 映射，但 `FullyQualifiedErrorId` 应稳定地包含 `Cloudflare.<status-or-error-code>`，不能只依赖本地化 message。

### 4.3 Retry

三种 SDK 的共享 retry 规则基本一致：

- 默认 `maxRetries = 2`；
- 连接错误/timeout 会 retry；
- HTTP 408、409、429、5xx 会 retry；
- `x-should-retry: true/false` 覆盖状态码判断；
- 优先使用 `retry-after-ms`，再使用 `Retry-After` 秒数或 HTTP date；
- 没有 header 时，初始 0.5 秒、指数退避、最大 8 秒、带 jitter；
- Go 额外明确要求 request body 可重放；不能恢复 body 时不 retry。

**Confirmed**：retry 属于 shared runtime，不属于 generated DNS cmdlet。

**Unresolved**：是否默认为所有 Cloudflare mutation 自动设置幂等 key，以及 Cloudflare API 对每类 mutation 的幂等语义，仍需针对 PowerShell runtime 单独验证；SDK 源码只确认它们生成/复用 Stainless retry idempotency header/key。

### 4.4 Authentication

固定版本 SDK 支持：

- API token → `Authorization: Bearer <token>`；
- Global API key + email → `X-Auth-Key` 与 `X-Auth-Email`；
- user service key → `X-Auth-User-Service-Key`。

默认环境变量为 `CLOUDFLARE_API_TOKEN`、`CLOUDFLARE_API_KEY`、`CLOUDFLARE_EMAIL`、`CLOUDFLARE_API_USER_SERVICE_KEY`；还支持 `CLOUDFLARE_BASE_URL`。TypeScript 的 per-request `headers` 可以覆盖/显式清除认证 header；Python/Go 也有 request/client options 层。

**Inferred**：PowerShell 可以提供 `Connect-Cf` 作为 session/context 初始化命令，但认证选择、secret 存储和 per-request override 必须是 runtime/context 设计，不应由每个 generated cmdlet 重复实现。

### 4.5 RequestOptions

通用选项与 endpoint 参数分开：`headers`、`query`、`body`、`timeout`、`maxRetries`、`signal/cancellation`、`idempotencyKey`、custom fetch/HTTP client、base URL、binary response flag 等属于 runtime request options；`zone_id`、`include_shadow_metadata`、record fields 属于 operation contract。

### 4.6 Query 与 body 序列化

TypeScript 的 query helper 使用 `allowDots: true` 与 `arrayFormat: 'repeat'`：

```text
scalar        → key=value
array         → key=a&key=b
nested object → parent.child=value
```

`undefined` 在 query 中被跳过；一般 `null` 在 qs serializer 中转为空值，除非开启严格 null 选项。DNS list 的 `comment.exact`、`name.contains`、`tag.startswith` 等结构在生成模型中表现为 nested object，最终使用点号键。

JSON body 通过 `JSON.stringify`/等价 encoder 发送。endpoint wrapper 的 rest destructuring 把 path/query 参数从 body 中移除；可选字段未传通常成为 `undefined` 并被 JSON encoder 省略，而显式 `null` 是另一种语义。PowerShell projection 必须保留“未绑定”和“显式 `$null`”的区别，不能用默认值填平。

非 JSON endpoint 已确认存在：DNS export 返回 text，DNS import 与 LOA create 使用 multipart，AI Search download 使用 binary response。它们需要 Normalized `ContentType` 和 output mode，而不是假设所有 operation 都是 Cloudflare JSON envelope。

## 5. Pagination

TypeScript 的 `AbstractPage` 只要求 `nextPageRequestOptions()` 与 `getPaginatedItems()`；`hasNextPage()` 先检查当前 page 是否有 item，再检查下一页请求是否存在。`PagePromise` await 时得到 page，async iteration 时委托 page 逐 item 自动翻页。

当前 runtime 类：

| Strategy | Request params | Response info | Next page | Stop |
| --- | --- | --- | --- | --- |
| `V4PagePagination` | `page`, `per_page` | `result.items`, page/per_page | page + 1 | current items empty 或无 next rule |
| `V4PagePaginationArray` | `page`, `per_page` | `result[]`, page/per_page | page + 1 | current result empty 或无 next rule |
| `CursorPagination` | `cursor`, `per_page` | `result[]`, `result_info.cursor` | response cursor | cursor absent |
| `CursorPaginationAfter` | `cursor` | `result_info.cursors.after` | after cursor | after absent |
| `CursorLimitPagination` | `cursor`, `limit` | `result_info.cursor` | response cursor | cursor absent |
| `SinglePage` | none | `result[]` | none | always |

**Proposed PowerShell behavior**：默认 pipeline 输出 item；需要 page metadata 时提供显式 `-IncludePageInfo` 或单独 page API，不让每个 generated cmdlet 自己写循环。应保留终止规则与已见 cursor/page 防护，避免把 UI item count 当成分页完成证明。

## 6. Generated / handwritten 边界与资源层级

### 6.1 Generated boundary

TypeScript、Python、Go endpoint/resource/runtime 文件均带 `File generated from our OpenAPI spec by Stainless` 标记。各仓库 CONTRIBUTING 明确说明大部分代码为 generated，并指出 generator 不修改 `src/lib/`（Python）、`src/lib/`（TypeScript）或 examples 等保留区域。不能通过当前仓库证明完整 Stainless 配置、命名 override 数据库或 generator 内部算法，因为这些通常不随 SDK 源码发布。

**Confirmed**：Cloudflare SDK 的手写边界主要是 runtime/library、examples、配置/构建维护；generated 目录禁止直接承载持久化手工修复。

### 6.2 Resource hierarchy

`client.dns.records` 对应 TypeScript `DNS` resource 挂载 `records` child resource；深层样本 `client.aiSearch.namespaces.instances.jobs` 对应 path `/accounts/{account_id}/ai-search/namespaces/{name}/instances/{id}/jobs`，并在 class `_key` 中保留 `['aiSearch','namespaces','instances','jobs']`。

**Inferred**：resource tree 与文件夹、client property、path/tag/operation 共同有关；不能只根据 URL 的第一个 segment 生成模块。PowerShell projection 应使用 `ResourcePath` 与 scope metadata，而不是预先限制为 `ZoneId + ResourceId`。

### 6.3 Zones 与 account/deep nested 验证

Zones 资源显示了另一种稳定差异：`create(body)` 直接 body，`list(query)` 直接 query，`delete/edit/get` 把 `zone_id` 放在 params，再将其他字段作为 body/query。Account-scoped AI Search jobs 显示多级 parent IDs；因此 `zone_id` 与 `account_id` 是同一“parent scope parameter”概念的不同实例。

## 7. Cross-SDK Matrix

| Concept | OpenAPI | TypeScript | Python | Go | PowerShell candidate |
| --- | --- | --- | --- | --- | --- |
| path param | `in: path` | destructure → `path\`...\`` | named argument → path template | `param.Field` `path:` | typed path binding |
| query | `in: query` | params rest → query | keyword args → `maybe_transform` query | `URLQuery()` tags | serializer-owned query model |
| body | requestBody | rest body object | `maybe_transform` body | `BodyUnion` + `MarshalJSON` | typed body model |
| enum | enum/single-value enum | literal union | `Literal` | named string type / validator | `ValidateSet` or model enum |
| oneOf | oneOf | TS union | `TypeAlias Union` | union interface + runtime registry | `ApiUnion` + typed input |
| allOf | allOf/ref | interface extends | model inheritance | composed structs | base + variant model |
| discriminator | single-value enum/shape | literal field | `Required[Literal]` | required typed field | runtime validation + completion |
| pagination | result/result_info | `PagePromise` + `AbstractPage` | `BasePage` / auto pager | page type + auto pager | pipeline enumerator |
| envelope | result/success/errors | typed cast + `_thenUnwrap` | `ResultWrapper` | `ResponseEnvelope` | runtime envelope parser |
| errors | status/error body | typed status subclasses | typed status subclasses | one `apierror.Error` with status | exception + ErrorRecord |
| auth | security scheme/headers | client + env + request headers | client + env + request options | client options + env | context + secret store |
| null/omission | schema/default | `undefined` omitted by JSON | `Omit`/`NotGiven` | `param.Field` presence | bound-state/explicit-null wrapper |
| raw/binary | content type | `__binaryResponse` / text | raw/stream/content options | response/body options | raw response mode |

## 8. PowerShell 设计评估

### 8.1 DNS UX 四方案

| 方案 | 优点 | 风险 |
| --- | --- | --- |
| A：单 `New-CfDnsRecord -Type A` | 发现简单、命令少 | 20+ variant 会造成参数集与 nullable 逻辑复杂 |
| B：`New-CfARecord` 等 | 每类字段清晰、验证强 | 命令数量膨胀，跨类型自动化不统一 |
| C：typed input object | 保留 union、适合 pipeline 和生成 | 新用户需要先理解 object model |
| D：混合 | 高频 A/AAAA/MX 有 convenience，完整 API 仍可用 | 需要清楚 primitive/convenience 边界 |

**Proposed**：P0 采用 C + D 的边界研究结果：generated primitive 接受 typed input/record model；外层可以提供少量 handwritten convenience constructors，但不要先把 20+ variant 直接展开为一个巨大 parameter-set cmdlet。

PowerShell 7.x 参数集上限为 32，正好高于但非常接近 DNS variant 数量；每个 parameter set 还要有唯一参数组合。这个约束使“每个 oneOf variant 一个 parameter set”不适合作为全局生成规则。`Get-Verb` 运行结果确认 `Get`、`New`、`Set`、`Remove`、`Clear`、`Connect`、`Test` 等 approved verbs 可用；operation 到 verb 必须有默认规则加 override。约束依据：[about_Parameter_Sets](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_parameter_sets?view=powershell-7.5) 与 [Get-Verb](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/get-verb?view=powershell-5.1)。

### 8.2 Primitive 与 convenience

```text
Generated primitive
  → 严格匹配 HTTP operation、requiredness、query/body、pagination、raw output

Handwritten convenience
  → 可执行 GET → merge → PUT
  → 明确命名和帮助文档
  → 不改变 primitive 的 PUT 完整覆盖语义
```

建议 primitive 可命名为 `Invoke-CfDnsRecordEdit` 或内部 runtime operation，convenience 才使用 `Set-CfDnsRecord`；最终名称仍需在实际 PowerShell module 试用后定案。

### 8.3 Pipeline、ShouldProcess、命名与 override

- `Get` list 默认逐 item 输出；page info 通过显式选项或独立 API 暴露。
- `New`、`Set`、`Remove` 等 mutation 应支持 `SupportsShouldProcess`；DELETE、purge、bulk delete 的 `ConfirmImpact` 应由 operation kind + override 决定，不能只依据 HTTP verb。
- `list/get/retrieve → Get`，`create → New`，`update/replace → Set`，`edit/patch → Set` 或 primitive `Invoke`，`delete → Remove`，`purge → Clear`，`verify/test → Test` 是候选默认规则。
- 不能机械映射的 action、download、job、mixed-scope operation 进入 override database。

## 9. Generator stability 与兼容性

生成器必须保证：stable operation ordering、stable schema/variant ordering、stable property ordering、固定 formatter、无随机命名。测试应包括 golden output、schema snapshot、serializer contract、pagination contract 和 representative endpoint request snapshots。

schema compatibility 至少检查：

| 变化 | API breaking 风险 | SDK source 风险 | PowerShell command 风险 |
| --- | --- | --- | --- |
| endpoint removed/path changed | 高 | 高 | 高 |
| required parameter added | 高 | 高 | 高 |
| enum value removed | 高 | 中 | 高 |
| enum value added | 低/需兼容 | 中 | completion 变化 |
| property type changed | 高 | 高 | 高 |
| response variant added | 低到中 | 中 | output type 变化 |
| operation renamed by override | API 不变 | 中 | 高 |

应将 API、SDK 类型和 PowerShell 命令三种 breaking change 分开报告，不能只看 generated diff 行数。

## 10. Exceptions

1. DNS DELETE schema 声明 requestBody，三个 SDK wrapper 实际不发送 body。
2. DNS PATCH 名称是 `edit`，但参数 requiredness 仍接近完整 record，而非普通 partial patch。
3. Zones `create` 使用 `body` 直接签名，DNS create 则把 `zone_id` 与 query 混在完整 params 中。
4. DNS export 是 text，DNS import/LOA create 是 multipart，AI Search download 是 binary；Cloudflare response envelope 不是所有 endpoint 的输出格式。
5. Go 对 union 的默认顶层 struct 同时保留宽字段与 `AsUnion()` runtime 类型，不能简单等同于 TypeScript interface union。
6. 当前公开 SDK 仓库没有足够的 Stainless config/override 文件，不能把所有 resource naming、special case 归因于 OpenAPI。

## 11. Unresolved Questions

- 固定 schema commit 与固定 TypeScript commit 不是同一快照时，requiredness 差异的精确来源是什么？需要锁定生成时使用的 schema revision。
- HTTP 2xx + `success=false` 是否在真实 Cloudflare endpoint 发生，以及官方 SDK 是否有 endpoint-specific 处理？需要 mock/fixture 或运行时测试。
- Cloudflare 各 mutation 的幂等性与 retry-safe 清单是什么？不能因为 SDK 生成 idempotency key 就推断 API 全部安全。
- Stainless 的 resource hierarchy、命名 override、pagination config 是否存在未随公开仓库发布的配置？需要官方 generator/config 证据或通过更多仓库历史反推。
- PowerShell typed model 应以 .NET class、`PSTypeName` + `PSCustomObject`、还是 class-based model 为主？需要考虑序列化、module loading 和 pipeline 性能。
- `-RawResponse`、`-IncludePageInfo`、page object 和 item pipeline 的最终 UX 仍需小规模 prototype 验证。

## 12. P1 进入条件

在进入 DNS generator prototype 前，应至少完成：

1. 将 normalized operation fixture 固定为上述六个 DNS CRUD operation，并包含 DELETE body discrepancy 标记。
2. 为 A、MX、CAA、HTTPS/SVCB 建立 request body serializer fixtures，覆盖 omitted、null、nested data、single-value enum。
3. 为 V4 array pagination、cursor pagination、single page 建立 runtime contract fixtures。
4. 为 400/401/403/404/409/429/5xx、connection timeout 和 Cloudflare errors array 建立 PowerShell exception fixtures。
5. 选择一个 strict primitive 命名和一个 convenience 命名，确认 `Get-Verb`、`ShouldProcess`、pipeline output 与 help 形态。
6. generator 只读取 normalized model + override，不直接从 raw OpenAPI 生成 PowerShell 参数。
