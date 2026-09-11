# Normalized API Model 与 PowerShell Projection Model

P1 的边界是：手写、可审查的 Normalized API Model 先经过 API correction，再经过 PowerShell projection，最后才生成源码。Raw OpenAPI 不进入 emitter。

```text
Normalized fixture
    ↓ API corrections
Corrected Normalized API Model
    ↓ PowerShell projection overrides
CmdletModel
    ↓ deterministic generator
Generated C# source + PowerShell module surface
```

## 1. Normalized API Model

Normalized 层描述 HTTP 合约和已经确认的 API 事实，不描述 PowerShell UX。

```text
ApiDocument
  - SourceRevision
  - Servers
  - SecuritySchemes
  - Schemas
  - Resources

ApiResource
  - ResourcePath
  - Bindings
  - Operations

ApiResourceScope
  - Bindings[]

ApiScopeBinding
  - ParameterName
  - ScopeType              # Zone, Account, Namespace, Instance, ...
  - Role                   # Parent, Nested, Primary

ApiOperation
  - OperationId
  - Method
  - PathTemplate
  - ResourcePath
  - OperationSemantic
  - Parameters[]
  - RequestBody?
  - Responses[]
  - Pagination?
  - AuthenticationRequirements
  - SourceLocations

OperationSemantic
  - Kind                    # List, Get, Create, Update, Edit, Delete, Action, ...
  - Source                  # OpenApiOperationId, OperationIdHeuristic, Override
  - Confidence              # High, Medium, Low
```

`Kind` 是语义标记，不是绝对 OpenAPI 事实。比如 `List + OperationIdHeuristic + High` 与人工 correction 后的 `Purge + Override + High` 都是合法状态。

Scope 由任意数量的 binding 组成，`ScopeKind` 只能作为派生摘要，不能取代 bindings：

```text
DNS Records: zone_id → Zone (Parent)
Nested resource: account_id → Account, namespace_name → Namespace,
                 instance_id → Instance
```

## 2. Response representation

Envelope 属于具体 response representation，不属于 operation：

```text
ApiResponseCase
  - StatusSelector       # Exact(200), Exact(201), Exact(204), Class(4XX), Default
  - Representations[]

ApiResponseRepresentation
  - ContentType          # application/json, text/plain, binary, no-content
  - Schema
  - EnvelopePolicy       # CloudflareResult, Raw, None, ErrorEnvelope
  - ParsingMode          # Json, Text, Binary, NoContent
```

因此同一个 operation 可以表达 `200`、`201`、`204`、`4XX` 和 `default`，也可以在不同状态下使用 JSON、文本、二进制或 no-content representation。

## 3. Request body and presence

```text
ApiRequestBody
  - Required
  - Representations[]
  - Presence

ApiRequestRepresentation
  - ContentType
  - Schema

ApiSchema
  - Kind                   # object, union, enum, primitive, array, reference
  - Name
  - Properties[]
  - RequiredProperties[]
  - OneOf / AnyOf / AllOf
  - Discriminator
  - ConstOrSingleValueEnum
  - ReadOnly / WriteOnly
  - SourceRef
```

Union 只由 `ApiSchema.Kind = union` 表达；`ApiRequestBody` 不再有 `Union` 字段。一个 body 可以同时有 `application/json`、`multipart/form-data`、`text/plain` 和 `binary` representation。

每个字段和参数必须区分：`required`、`optional`、`nullable`、`non-nullable`、`absent`、`explicit null`、`default`。最小可执行表达为：

```text
Required: bool
AllowsNull: bool
DefaultValue?
NullPolicy: omit | send-null | reject-null
```

PowerShell projection 将其映射为“参数未绑定”、“显式 `$null`”和“默认值”；未绑定不等于显式 null。

## 4. Parameter serialization

```text
ApiSerialization
  - Style                 # form, simple, matrix, label, deepObject, pipeDelimited, spaceDelimited, custom
  - Explode
  - AllowReserved
  - ArrayNotation         # repeat, comma, pipes, spaces, brackets, ...
  - ObjectNotation        # dots, brackets, json, ...
  - CustomSerializerId?
```

P1 使用三种已确认规则：scalar → `key=value`；array → `key=a&key=b`；nested object → `parent.child=value`。其余 OpenAPI serialization 保留在模型中，尚不代表 runtime 已实现。

## 5. API corrections 与 PowerShell projection overrides

两个文件不能混用：

```text
overrides/api-corrections.json
overrides/powershell-projection.json
```

API correction 修正 schema 与实际 wrapper 行为不一致的合约事实。P1 必须记录 DNS DELETE：schema 声明 request body，但官方 TypeScript/Python/Go wrapper 实际不发送 body；effective request body 为 absent。

PowerShell projection override 只描述 verb、noun、参数名、隐藏参数、ShouldProcess、ConfirmImpact、output policy、help 和特殊 UX。例如 purge 到 `Clear-Cf...` 属于 projection，而不是 normalized contract。

## 6. DNS union 与 cmdlet projection

DNS `RecordCreateParams`、`RecordEditParams` 和 response model 保留 `type` 单值 discriminator 以及 A、MX、CAA、HTTPS、SVCB 等 variant。默认 projection 是 typed input，不把 oneOf 展开成几十个参数集。

一个 primitive 表示“一次 cmdlet invocation 对应一个 HTTP operation”，不等于 `Invoke-*`。P1 首先投影 `Get-CfDnsRecord`、`New-CfDnsRecord`、`Remove-CfDnsRecord`，再以 `Set-CfDnsRecord` 实验 PUT/PATCH 的 parameter set；若证据不足，也允许两个 semantic cmdlet。

## 7. PowerShell Projection Model

```text
CmdletModel
  - Verb / Noun
  - OperationBinding
  - ParameterSets[]
  - Parameters[]
  - OutputType
  - PagingBehavior
  - SupportsShouldProcess
  - ConfirmImpact
  - HelpModel
  - OverrideTrace

CmdletParameter
  - Name / Type / Mandatory / Position
  - ValueFromPipeline / ValueFromPipelineByPropertyName
  - NullPolicy
  - ApiBinding

OperationBinding
  - OperationId
  - HttpMethod / PathTemplate
  - PathParameters / QueryParameters / BodyModel
```

## 8. Determinism

Emitter 必须稳定排序 operation、schema、property、union variant 和名称，不能依赖 filesystem/dictionary 顺序，不能生成随机 identifier 或 timestamp。Generated source 不人工修改；变化通过 fixture、correction、override 或 generator 的明确 diff 进入审查。
