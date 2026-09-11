# Normalized API Model 与 PowerShell Projection Model

本文只提出候选模型。它不是 generator 实现，也不把 OpenAPI 直接等同于 PowerShell 命令设计。

## 1. 两层模型边界

```text
OpenAPI document
    ↓ resolve refs / compose oneOf-anyOf-allOf / normalize parameters
Normalized API Model
    ↓ semantic projection + overrides
PowerShell Projection Model
    ↓ generator
Generated cmdlets / models / help
```

关键边界：

- `ApiOperation` 描述 HTTP 合约，不决定 cmdlet 名称、pipeline 行为或 `ShouldProcess`。
- `ApiUnion` 保留 variant、discriminator、requiredness 和来源 schema，不退化为 `object`。
- `CmdletModel` 可以把一个 API operation 投影成 primitive cmdlet，也可以由多个 operation 组成 handwritten convenience cmdlet。
- 所有来源位置和 override 命中都应保留，方便 schema 更新后的 diff 与解释。

## 2. Normalized API Model 候选

```text
ApiDocument
  - SourceRevision
  - Servers
  - SecuritySchemes
  - Schemas
  - Resources

ApiResource
  - ResourcePath: ["dns", "records"]
  - ScopeKind: zone | account | global | mixed
  - ParentResources
  - Operations

ApiOperation
  - OperationId
  - Method
  - PathTemplate
  - ResourcePath
  - Kind: list | get | create | update | edit | delete | action | upload | download
  - Parameters
  - RequestBody
  - Responses
  - Envelope: CloudflareEnvelope | raw | text | binary | unknown
  - PaginationStrategy?
  - AuthenticationRequirements
  - SourceLocations

ApiParameter
  - Name
  - Location: path | query | header | cookie
  - Required
  - Schema
  - Serialization: scalar | repeat | dots | brackets | custom
  - IsParentScopeId
  - IsPrimaryResourceId

ApiRequestBody
  - ContentType
  - Schema
  - Required
  - Union?
  - OmissionSemantics: absent | null | explicit-default | unknown

ApiResponse
  - StatusCodes
  - ContentTypes
  - Envelope
  - ResultSchema
  - Nullable

ApiSchema
  - Kind: object | union | enum | primitive | array | reference
  - Name
  - Properties
  - RequiredProperties
  - AllOf
  - OneOf
  - AnyOf
  - Discriminator?
  - ConstOrSingleValueEnum?
  - ReadOnly / WriteOnly
  - SourceRef

ApiPagination
  - Strategy: v4-page-array | v4-page-object | cursor | cursor-after | cursor-limit | single-page | unknown
  - RequestFields
  - ResponseFields
  - NextPageRule
  - StopRule

ApiOverride
  - Match: operationId | path+method | schema name | resource path
  - CmdletName / ParameterName / Hidden / OutputType
  - Serializer / Pagination / Help / ShouldProcess
  - Reason
  - Source
```

## 3. PowerShell Projection Model 候选

```text
CmdletModel
  - Verb
  - Noun
  - OperationBinding: one | many
  - ParameterSets
  - Parameters
  - InputObjectBinding
  - OutputType
  - PipelineMode: item | page | raw-response | binary
  - PagingBehavior
  - SupportsShouldProcess
  - ConfirmImpact
  - HelpModel
  - OverrideTrace

CmdletParameter
  - Name
  - Type
  - Mandatory
  - Position
  - ValueFromPipeline
  - ValueFromPipelineByPropertyName
  - ValidateSet / ArgumentCompleter
  - NullPolicy: omit | send-null | reject-null
  - ApiBinding: path | query | header | body | context

ParameterSet
  - Name
  - DiscriminatorConstraints
  - RequiredParameters
  - BodyShape
  - MaxComplexityScore

OutputType
  - TypeName
  - VariantType
  - EnvelopePolicy
  - PageInfoPolicy
```

## 4. DNS union 的建议保留形式

Normalized 层应保留：

```text
RecordCreateParams
  = oneOf(
      ARecordParam, AAAARecordParam, CNAMERecordParam, ...,
      CAARecordParam, HTTPSRecordParam, ...
    )

variant discriminator:
  property = type
  value = "A" | "AAAA" | "CNAME" | ...

common required body fields:
  name, ttl, type
```

PowerShell projection 不应机械生成 20+ 参数集：PowerShell 7.x 的参数集上限为 32 个，且每个集合必须有可区分的参数组合。建议先把变体作为 typed input / body model 保留，再由 UX 层决定是否暴露少量高价值 convenience parameters。

## 5. Override 文件候选

```yaml
version: 1
operations:
  dns-records-for-a-zone-delete-dns-record:
    verb: Remove
    noun: CfDnsRecord
    supportsShouldProcess: true
    confirmImpact: High
  dns-records-for-a-zone-patch-dns-record:
    primitiveName: Invoke-CfDnsRecordEdit
    convenienceAlias: Set-CfDnsRecord
schemas:
  dns-records_dns-record-patch:
    preserveUnion: true
    discriminator: type
```

Override 必须是小型、可审查、可版本控制的数据，不应在 generated 文件里手写修补。

