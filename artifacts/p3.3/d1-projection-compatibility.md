# P3.3-projection Compatibility Report

- Old source revision: `P2.3-d1-database`
- New source revision: `P3.3-d1-database`
- Changes: `17`
- Fully compatible: `False`

## Impact summary

| Dimension | Impact | Count |
| --- | --- | ---: |
| Api | Behavioral | 0 |
| Api | Breaking | 0 |
| Api | NonBreaking | 0 |
| Api | None | 17 |
| Api | PotentiallyBreaking | 0 |
| Api | Unknown | 0 |
| PowerShell | Behavioral | 0 |
| PowerShell | Breaking | 10 |
| PowerShell | NonBreaking | 3 |
| PowerShell | None | 0 |
| PowerShell | PotentiallyBreaking | 4 |
| PowerShell | Unknown | 0 |
| Sdk | Behavioral | 0 |
| Sdk | Breaking | 0 |
| Sdk | NonBreaking | 0 |
| Sdk | None | 17 |
| Sdk | PotentiallyBreaking | 0 |
| Sdk | Unknown | 0 |

## Changes

| Kind | Resource | Operation | Schema | Path | API | SDK | PowerShell | Old | New | Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| OutputTypeChanged |  | Get-CfD1Database |  | cmdlets[Get-CfD1Database].outputType | None | None | PotentiallyBreaking | "System.Management.Automation.PSObject" | "Cloudflare.PowerShell.CfD1Database" | PowerShell projection outputType |
| PagingBehaviorChanged |  | Get-CfD1Database |  | cmdlets[Get-CfD1Database].pagingBehavior | None | None | Breaking | ["shared-runtime"] | "V4PagePaginationArray" | PowerShell projection pagingBehavior |
| PowerShellParameterSetChanged |  | Get-CfD1Database |  | cmdlets[Get-CfD1Database].parameterSets | None | None | Breaking | {"name":"Get","operationId":"d1-get-database","operationBinding":{"method":"GET","pathTemplate":"/accounts/{account_id}/d1/database/{database_id}","pathParameters":["AccountId","DatabaseId"],"queryParameters":["Fields"]},"requiredParameters":["AccountId","DatabaseId"],"optionalParameters":["Fields"]};{"name":"List","operationId":"d1-list-databases","operationBinding":{"method":"GET","pathTemplate":"/accounts/{account_id}/d1/database","pathParameters":["AccountId"],"queryParameters":["Name","Page","PerPage"]},"requiredParameters":["AccountId"],"optionalParameters":["Name","Page","PerPage"]} | {"name":"Get","operationId":"d1-get-database","operationBinding":{"method":"GET","pathTemplate":"/accounts/{account_id}/d1/database/{database_id}","pathParameters":["AccountId","DatabaseId"],"queryParameters":["Fields"],"bodyParameter":null,"bodyModel":null,"invokeKind":"single","outputPolicy":"item","bodySerialization":null,"errorTarget":"DatabaseId"},"requiredParameters":["AccountId","DatabaseId"],"optionalParameters":["Fields"]};{"name":"List","operationId":"d1-list-databases","operationBinding":{"method":"GET","pathTemplate":"/accounts/{account_id}/d1/database","pathParameters":["AccountId"],"queryParameters":["Name","Page","PerPage"],"bodyParameter":null,"bodyModel":null,"invokeKind":"paged","outputPolicy":"item","bodySerialization":null,"errorTarget":"AccountId"},"requiredParameters":["AccountId"],"optionalParameters":["Name","Page","PerPage"]} | PowerShell parameter-set names |
| OutputTypeChanged |  | New-CfD1Database |  | cmdlets[New-CfD1Database].outputType | None | None | PotentiallyBreaking | "System.Management.Automation.PSObject" | "Cloudflare.PowerShell.CfD1Database" | PowerShell projection outputType |
| PagingBehaviorChanged |  | New-CfD1Database |  | cmdlets[New-CfD1Database].pagingBehavior | None | None | Breaking | [] | <none> | PowerShell projection pagingBehavior |
| PowerShellParameterSetChanged |  | New-CfD1Database |  | cmdlets[New-CfD1Database].parameterSets | None | None | Breaking | {"name":"Create","operationId":"d1-create-database","operationBinding":{"method":"POST","pathTemplate":"/accounts/{account_id}/d1/database","pathParameters":["AccountId"],"queryParameters":[]},"requiredParameters":["AccountId"],"optionalParameters":[]} | {"name":"Create","operationId":"d1-create-database","operationBinding":{"method":"POST","pathTemplate":"/accounts/{account_id}/d1/database","pathParameters":["AccountId"],"queryParameters":[],"bodyParameter":"Database","bodyModel":"Inline_FA2961F0C454","invokeKind":"single","outputPolicy":"single","bodySerialization":"Value","errorTarget":"AccountId"},"requiredParameters":["AccountId","Database"],"optionalParameters":[]} | PowerShell parameter-set names |
| PowerShellParameterAdded |  | New-CfD1Database |  | cmdlets[New-CfD1Database].parameters[Database] | None | None | NonBreaking | missing | present | PowerShell parameter added |
| OutputTypeChanged |  | Remove-CfD1Database |  | cmdlets[Remove-CfD1Database].outputType | None | None | PotentiallyBreaking | "System.Management.Automation.PSObject" | <none> | PowerShell projection outputType |
| PagingBehaviorChanged |  | Remove-CfD1Database |  | cmdlets[Remove-CfD1Database].pagingBehavior | None | None | Breaking | [] | <none> | PowerShell projection pagingBehavior |
| PowerShellParameterSetChanged |  | Remove-CfD1Database |  | cmdlets[Remove-CfD1Database].parameterSets | None | None | Breaking | {"name":"Delete","operationId":"d1-delete-database","operationBinding":{"method":"DELETE","pathTemplate":"/accounts/{account_id}/d1/database/{database_id}","pathParameters":["AccountId","DatabaseId"],"queryParameters":[]},"requiredParameters":["AccountId","DatabaseId"],"optionalParameters":[]} | {"name":"Delete","operationId":"d1-delete-database","operationBinding":{"method":"DELETE","pathTemplate":"/accounts/{account_id}/d1/database/{database_id}","pathParameters":["AccountId","DatabaseId"],"queryParameters":[],"bodyParameter":null,"bodyModel":null,"invokeKind":"single","outputPolicy":"none","bodySerialization":null,"errorTarget":"DatabaseId"},"requiredParameters":["AccountId","DatabaseId"],"optionalParameters":[]} | PowerShell parameter-set names |
| OutputTypeChanged |  | Set-CfD1Database |  | cmdlets[Set-CfD1Database].outputType | None | None | PotentiallyBreaking | "System.Management.Automation.PSObject" | "Cloudflare.PowerShell.CfD1Database" | PowerShell projection outputType |
| PagingBehaviorChanged |  | Set-CfD1Database |  | cmdlets[Set-CfD1Database].pagingBehavior | None | None | Breaking | [] | <none> | PowerShell projection pagingBehavior |
| PowerShellParameterSetChanged |  | Set-CfD1Database |  | cmdlets[Set-CfD1Database].parameterSets | None | None | Breaking | {"name":"Update","operationId":"d1-update-database","operationBinding":{"method":"PUT","pathTemplate":"/accounts/{account_id}/d1/database/{database_id}","pathParameters":["AccountId","DatabaseId"],"queryParameters":[]},"requiredParameters":["AccountId","DatabaseId"],"optionalParameters":[]} | {"name":"PartialUpdate","operationId":"d1-update-partial-database","operationBinding":{"method":"PATCH","pathTemplate":"/accounts/{account_id}/d1/database/{database_id}","pathParameters":["AccountId","DatabaseId"],"queryParameters":[],"bodyParameter":"PartialDatabase","bodyModel":"d1_database-update-partial-request-body","invokeKind":"single","outputPolicy":"single","bodySerialization":"Value","errorTarget":"DatabaseId"},"requiredParameters":["AccountId","DatabaseId","PartialDatabase"],"optionalParameters":[]};{"name":"Update","operationId":"d1-update-database","operationBinding":{"method":"PUT","pathTemplate":"/accounts/{account_id}/d1/database/{database_id}","pathParameters":["AccountId","DatabaseId"],"queryParameters":[],"bodyParameter":"Database","bodyModel":"d1_database-update-request-body","invokeKind":"single","outputPolicy":"single","bodySerialization":"Value","errorTarget":"DatabaseId"},"requiredParameters":["AccountId","DatabaseId","Database"],"optionalParameters":[]} | PowerShell parameter-set names |
| PowerShellParameterBecameMandatory |  | Set-CfD1Database |  | cmdlets[Set-CfD1Database].parameters[AccountId].requiredIn | None | None | Breaking | "Update" | "PartialUpdate";"Update" | PowerShell required parameter-set membership |
| PowerShellParameterBecameMandatory |  | Set-CfD1Database |  | cmdlets[Set-CfD1Database].parameters[DatabaseId].requiredIn | None | None | Breaking | "Update" | "PartialUpdate";"Update" | PowerShell required parameter-set membership |
| PowerShellParameterAdded |  | Set-CfD1Database |  | cmdlets[Set-CfD1Database].parameters[Database] | None | None | NonBreaking | missing | present | PowerShell parameter added |
| PowerShellParameterAdded |  | Set-CfD1Database |  | cmdlets[Set-CfD1Database].parameters[PartialDatabase] | None | None | NonBreaking | missing | present | PowerShell parameter added |
