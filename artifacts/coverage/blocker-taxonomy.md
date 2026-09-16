# P3.3 Projection Blocker Taxonomy

- Source revision: `4.0.0`
- Total operations: `3407`
- Projection conflicts: `568` before → `57` after
- NeedsManualReview: `617` before → `617` after
- Projection/manual overlap before: `77`

Percentages for the first three categories use the before projection-conflict population as denominator; the semantic category uses the before manual-review population.

## Categories

| Category | Count | Percentage | Before classification | After classification | Resolution class |
| --- | ---: | ---: | --- | --- | --- |
| `ScopeProjectionAmbiguity` | 458 | 80.63% | NeedsManualReview=65; UnsupportedProjectionCapability=393 | NeedsManualReview=65; ExcludedByPolicy=393 | Projection capability rule: scope-key parameter-set disambiguation |
| `MethodVariantParameterSetCollision` | 53 | 9.33% | UnsupportedProjectionCapability=45; NeedsManualReview=8 | ExcludedByPolicy=45; NeedsManualReview=8 | Projection capability rule: HTTP-method parameter-set disambiguation |
| `ParameterSetIndistinguishability` | 57 | 10.04% | UnsupportedProjectionCapability=53; NeedsManualReview=4 | UnsupportedProjectionCapability=53; NeedsManualReview=4 | Manual product/UX decision; retain UnsupportedProjectionCapability until an explicit policy is evidenced |
| `LowConfidenceSemanticInference` | 617 | 100% | NeedsManualReview=617 | NeedsManualReview=617 | Manual semantic/product decision or evidence-backed correction; do not resolve by projection override alone |

## `ScopeProjectionAmbiguity`

Operations sharing a projected cmdlet and semantic parameter-set name have distinct normalized scope-binding signatures; the generic scope-key rule gives each binding a deterministic parameter-set identity.

- Evidence: normalized scope bindings are distinct within the projected cmdlet/parameter-set collision group
- Representative operations: `access-applications-add-an-application`, `access-applications-delete-an-access-application`, `access-applications-get-an-access-application`, `access-applications-list-access-applications`, `access-applications-revoke-service-tokens`
- Resource families: `load/balancers`=12, `access/apps`=10, `access/apps/policies`=10, `access/certificates`=10, `access/groups`=10, `access/identity/providers`=10, `access/service/tokens`=10, `custom/pages/assets`=10, `logpush/jobs`=10, `logs/explorer/datasets`=10
- Report reason codes: `LowSemanticConfidence`, `ProjectionParameterSetCollision`
- Possible resolution: Projection capability rule: scope-key parameter-set disambiguation

## `MethodVariantParameterSetCollision`

Operations sharing a projected cmdlet and semantic parameter-set name have distinct HTTP methods; the generic method rule gives each method a deterministic parameter-set identity.

- Evidence: normalized HTTP methods are distinct within the remaining collision group after scope-key resolution
- Representative operations: `account-billing-profile-update-billing-email`, `account-billing-profile-update-billing-profile`, `accounts-turnstile-widget-create`, `accounts-turnstile-widget-delete`, `accounts-turnstile-widget-get`
- Resource families: `vuln/scanner/target/environments`=5, `challenges/widgets`=4, `infrastructure/targets`=4, `ai/search/namespaces/instances/items`=2, `billing/profile`=2, `calls/apps`=2, `cloudforce/one/events`=2, `cloudforce/one/events/categories`=2, `cloudforce/one/events/dataset`=2, `cloudforce/one/events/queries`=2
- Report reason codes: `LowSemanticConfidence`, `ProjectionParameterSetCollision`
- Possible resolution: Projection capability rule: HTTP-method parameter-set disambiguation

## `ParameterSetIndistinguishability`

The remaining operations share the same projected cmdlet, semantic parameter-set name, and no unique generic scope or method discriminator; a public selector or noun decision would require product/UX evidence.

- Evidence: projection remains Conflict after deterministic scope-key and HTTP-method rules
- Representative operations: `access-applications-patch-update-access-application-settings`, `access-applications-put-update-access-application-settings`, `billable-usage-get-v1-account-usage`, `billable-usage-v2-get-account-usage`, `createAllowlistedPrefix`
- Resource families: `addressing/address/maps`=6, `gateway/lists`=6, `magic/advanced/tcp/protection/configs/allowlist`=6, `rules/lists`=5, `rules/lists/items`=5, `web3/hostnames/ipfs/universal/path/content/list/entries`=5, `access/apps/settings`=4, `devices/policy/exclude`=4, `devices/policy/fallback/domains`=4, `devices/policy/include`=4
- Report reason codes: `LowSemanticConfidence`, `ProjectionParameterSetCollision`
- Possible resolution: Manual product/UX decision; retain UnsupportedProjectionCapability until an explicit policy is evidenced

## `LowConfidenceSemanticInference`

The normalizer used only a method heuristic for semantic kind; automatic public verb/noun admission would guess action versus CRUD meaning.

- Evidence: semanticConfidence=Low and semanticSource=MethodHeuristic
- Representative operations: `access-applications-add-an-application`, `access-applications-revoke-service-tokens`, `access-applications-test-access-policies`, `access-custom-pages-validate-a-custom-page-template`, `access-gateway-ca-add-an-SSH-ca`
- Resource families: `addressing/address/maps`=4, `api/gateway/operations/labels`=4, `api/gateway/user/schemas`=4, `email/routing/dns`=4, `logpush/jobs`=4, `api/gateway/operations`=3, `dlp/document/fingerprints`=3, `access/apps`=2, `access/apps/revoke/tokens`=2, `access/apps/user/policy/checks`=2
- Report reason codes: `LowSemanticConfidence`
- Possible resolution: Manual semantic/product decision or evidence-backed correction; do not resolve by projection override alone

The taxonomy is diagnostic. A resolved projection identity does not auto-admit an operation to the public module; the separate admission policy remains authoritative.
