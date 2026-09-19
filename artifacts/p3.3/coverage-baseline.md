# P3.3 Coverage Baseline

- Source revision: `4.0.0`
- Source: `ref/api-schemas/openapi.json`
- Normalized schema count: `67486`
- Operations: `3407`
- Runtime-ready stage count (operations): `3382`
- Final `UnsupportedRuntimeCapability` classification count: `10`
- Input identity: source `ref/api-schemas/openapi.json` revision `4.0.0` SHA-256 `f71c82b532b284e41a0e9de41ac1ee398e1b7b658f521e7f8ee478ce922fbf45`
- Input identity: corrections `overrides/api-corrections.json` SHA-256 `ff65a8757fad81bfe22e455580976a32fdf8a01b0c6b3d73d803e9e8f1fb496a`
- Input identity: projection policy `overrides/powershell-projection.json` SHA-256 `e07a129b9e80b9efaa5653046214cb1c34ac04ee5f55e97ab356d0238e1bdd60`
- Input identity: current public artifact `artifacts/p3.2/CmdletModel.json` SHA-256 `38ac91cd945698b24b39566ecdbff8abf9e475360610e1d7f54ab777d84e65e7`
- Deterministic artifact: `true`; generation timestamp intentionally omitted

## Stage counts

| Stage | Count |
| --- | ---: |
| normalizedSucceeded | 3407 |
| correctionApplied | 2 |
| projectionReady | 3350 |
| projectionConflicts | 57 |
| runtimeReady | 3382 |
| runtimeGaps | 25 |
| currentPublicSurface | 8 |
| fullyEligibleCurrentOperations | 8 |

## Final classification

| Classification | Count |
| --- | ---: |
| ExcludedByPolicy | 2719 |
| NeedsManualReview | 617 |
| SupportedWithOverride | 8 |
| UnsupportedProjectionCapability | 53 |
| UnsupportedRuntimeCapability | 10 |

## Capability gaps and review reasons

| Reason | Operations |
| --- | ---: |
| `CurrentPublicSurface` | 8 |
| `ExplicitPolicyOrCorrection` | 8 |
| `LowSemanticConfidence` | 617 |
| `NoPublicProjectionPolicy` | 2709 |
| `OutsideCurrentPublicSurface` | 2719 |
| `ProjectionParameterSetCollision` | 53 |
| `ProjectionPolicyPresent` | 10 |
| `UnsupportedRequestContentType:application/merge-patch+json` | 4 |
| `UnsupportedRequestContentType:application/scim+json` | 4 |
| `UnsupportedRequestContentType:text/plain;charset=UTF-8` | 2 |

## Resource families

| Resource family | Operations | Classification counts |
| --- | ---: | --- |
| `abuse/reports` | 3 | ExcludedByPolicy=2; NeedsManualReview=1 |
| `abuse/reports/appeals/eligibility` | 1 | NeedsManualReview=1 |
| `abuse/reports/emails` | 1 | ExcludedByPolicy=1 |
| `abuse/reports/mitigations` | 1 | ExcludedByPolicy=1 |
| `abuse/reports/mitigations/appeal` | 1 | NeedsManualReview=1 |
| `access` | 5 | ExcludedByPolicy=5 |
| `access/active/sessions` | 2 | ExcludedByPolicy=2 |
| `access/ai/controls/mcp/analytics/portals/tool/calls/timeseries` | 1 | NeedsManualReview=1 |
| `access/ai/controls/mcp/analytics/servers/tool/calls/timeseries` | 1 | NeedsManualReview=1 |
| `access/ai/controls/mcp/analytics/tool/calls/timeseries` | 1 | NeedsManualReview=1 |
| `access/ai/controls/mcp/portals` | 5 | ExcludedByPolicy=4; NeedsManualReview=1 |
| `access/ai/controls/mcp/portals/servers/effective/redirect/uri` | 1 | NeedsManualReview=1 |
| `access/ai/controls/mcp/servers` | 5 | ExcludedByPolicy=4; NeedsManualReview=1 |
| `access/ai/controls/mcp/servers/sync` | 1 | NeedsManualReview=1 |
| `access/apps` | 10 | ExcludedByPolicy=8; NeedsManualReview=2 |
| `access/apps/ca` | 8 | ExcludedByPolicy=8 |
| `access/apps/policies` | 10 | ExcludedByPolicy=10 |
| `access/apps/policies/make/reusable` | 1 | NeedsManualReview=1 |
| `access/apps/revoke/tokens` | 2 | NeedsManualReview=2 |
| `access/apps/settings` | 4 | UnsupportedProjectionCapability=4 |
| `access/apps/user/policy/checks` | 2 | NeedsManualReview=2 |
| `access/authenticator/device/aaguids` | 1 | ExcludedByPolicy=1 |
| `access/bookmarks` | 5 | ExcludedByPolicy=5 |
| `access/certificates` | 10 | ExcludedByPolicy=8; NeedsManualReview=2 |
| `access/certificates/settings` | 4 | ExcludedByPolicy=4 |
| `access/custom/pages` | 5 | ExcludedByPolicy=5 |
| `access/custom/pages/validate` | 1 | NeedsManualReview=1 |
| `access/failed/logins` | 1 | ExcludedByPolicy=1 |
| `access/gateway/ca` | 3 | ExcludedByPolicy=2; NeedsManualReview=1 |
| `access/groups` | 10 | ExcludedByPolicy=10 |
| `access/identity/providers` | 10 | ExcludedByPolicy=8; NeedsManualReview=2 |
| `access/identity/providers/saml/certificate` | 1 | ExcludedByPolicy=1 |
| `access/identity/providers/scim` | 1 | ExcludedByPolicy=1 |
| `access/identity/providers/scim/groups` | 1 | ExcludedByPolicy=1 |
| `access/idp/federation/grants` | 4 | ExcludedByPolicy=4 |
| `access/keys` | 2 | ExcludedByPolicy=2 |
| `access/keys/rotate` | 1 | NeedsManualReview=1 |
| `access/last/seen/identity` | 1 | ExcludedByPolicy=1 |
| `access/logs/access/requests` | 1 | ExcludedByPolicy=1 |
| `access/logs/jit/requests` | 2 | ExcludedByPolicy=2 |
| `access/logs/scim/updates` | 1 | ExcludedByPolicy=1 |
| `access/mfa/authenticators` | 1 | ExcludedByPolicy=1 |
| `access/organizations` | 6 | ExcludedByPolicy=6 |
| `access/organizations/doh` | 2 | ExcludedByPolicy=2 |
| `access/organizations/revoke/user` | 2 | NeedsManualReview=2 |
| `access/policies` | 5 | ExcludedByPolicy=5 |
| `access/policy/tests` | 3 | ExcludedByPolicy=2; NeedsManualReview=1 |
| `access/saml/certificates` | 2 | ExcludedByPolicy=2 |
| `access/saml/certificates/pem` | 1 | ExcludedByPolicy=1 |
| `access/saml/certificates/rotate` | 1 | NeedsManualReview=1 |
| `access/seats` | 1 | ExcludedByPolicy=1 |
| `access/service/tokens` | 10 | ExcludedByPolicy=10 |
| `access/service/tokens/refresh` | 1 | NeedsManualReview=1 |
| `access/service/tokens/rotate` | 1 | NeedsManualReview=1 |
| `access/tags` | 5 | ExcludedByPolicy=5 |
| `accounts` | 5 | ExcludedByPolicy=3; NeedsManualReview=2 |
| `acm/custom/trust/store` | 4 | ExcludedByPolicy=4 |
| `acm/total/tls` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `activation/check` | 1 | NeedsManualReview=1 |
| `addressing/address/maps` | 9 | ExcludedByPolicy=3; NeedsManualReview=4; UnsupportedProjectionCapability=2 |
| `addressing/address/maps/ips` | 2 | NeedsManualReview=2 |
| `addressing/leases` | 1 | ExcludedByPolicy=1 |
| `addressing/loa/documents` | 1 | NeedsManualReview=1 |
| `addressing/loa/documents/download` | 1 | NeedsManualReview=1 |
| `addressing/prefixes` | 5 | ExcludedByPolicy=4; NeedsManualReview=1 |
| `addressing/prefixes/bgp/prefixes` | 5 | ExcludedByPolicy=4; NeedsManualReview=1 |
| `addressing/prefixes/bgp/status` | 2 | ExcludedByPolicy=2 |
| `addressing/prefixes/bindings` | 4 | ExcludedByPolicy=4 |
| `addressing/prefixes/delegations` | 3 | ExcludedByPolicy=3 |
| `addressing/prefixes/validate` | 1 | NeedsManualReview=1 |
| `addressing/regional/hostnames` | 5 | ExcludedByPolicy=4; NeedsManualReview=1 |
| `addressing/regional/hostnames/regions` | 1 | ExcludedByPolicy=1 |
| `addressing/services` | 1 | ExcludedByPolicy=1 |
| `agent/memory/namespaces` | 4 | ExcludedByPolicy=4 |
| `agent/memory/namespaces/profiles` | 1 | ExcludedByPolicy=1 |
| `agent/memory/namespaces/profiles/ingest` | 1 | NeedsManualReview=1 |
| `agent/memory/namespaces/profiles/memories` | 3 | ExcludedByPolicy=3 |
| `agent/memory/namespaces/profiles/recall` | 1 | NeedsManualReview=1 |
| `agent/memory/namespaces/profiles/remember` | 1 | NeedsManualReview=1 |
| `agent/memory/namespaces/profiles/sessions` | 1 | ExcludedByPolicy=1 |
| `agent/memory/namespaces/profiles/summary` | 1 | NeedsManualReview=1 |
| `ai/audit/robots` | 1 | ExcludedByPolicy=1 |
| `ai/audit/robots/bulk` | 1 | ExcludedByPolicy=1 |
| `ai/authors/search` | 1 | NeedsManualReview=1 |
| `ai/finetunes` | 3 | ExcludedByPolicy=3 |
| `ai/finetunes/finetune/assets` | 2 | NeedsManualReview=2 |
| `ai/finetunes/public` | 1 | ExcludedByPolicy=1 |
| `ai/gateway/billing/credit/balance` | 1 | ExcludedByPolicy=1 |
| `ai/gateway/billing/invoice/history` | 1 | ExcludedByPolicy=1 |
| `ai/gateway/billing/invoice/preview` | 1 | ExcludedByPolicy=1 |
| `ai/gateway/billing/spending/limit` | 3 | ExcludedByPolicy=2; NeedsManualReview=1 |
| `ai/gateway/billing/topup` | 1 | ExcludedByPolicy=1 |
| `ai/gateway/billing/topup/config` | 3 | ExcludedByPolicy=2; NeedsManualReview=1 |
| `ai/gateway/billing/topup/eligibility` | 1 | NeedsManualReview=1 |
| `ai/gateway/billing/topup/limits` | 1 | ExcludedByPolicy=1 |
| `ai/gateway/billing/topup/status` | 1 | NeedsManualReview=1 |
| `ai/gateway/billing/usage/history` | 1 | ExcludedByPolicy=1 |
| `ai/gateway/custom/providers` | 5 | ExcludedByPolicy=4; NeedsManualReview=1 |
| `ai/gateway/custom/providers/costs` | 5 | ExcludedByPolicy=4; NeedsManualReview=1 |
| `ai/gateway/evaluation/types` | 1 | ExcludedByPolicy=1 |
| `ai/gateway/gateways` | 5 | ExcludedByPolicy=4; NeedsManualReview=1 |
| `ai/gateway/gateways/custom/domains` | 4 | ExcludedByPolicy=3; NeedsManualReview=1 |
| `ai/gateway/gateways/datasets` | 5 | ExcludedByPolicy=4; NeedsManualReview=1 |
| `ai/gateway/gateways/evaluations` | 4 | ExcludedByPolicy=3; NeedsManualReview=1 |
| `ai/gateway/gateways/logs` | 4 | ExcludedByPolicy=4 |
| `ai/gateway/gateways/logs/request` | 1 | ExcludedByPolicy=1 |
| `ai/gateway/gateways/logs/response` | 1 | ExcludedByPolicy=1 |
| `ai/gateway/gateways/provider/configs` | 4 | ExcludedByPolicy=4 |
| `ai/gateway/gateways/routes` | 5 | ExcludedByPolicy=4; NeedsManualReview=1 |
| `ai/gateway/gateways/routes/deployments` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `ai/gateway/gateways/routes/versions` | 3 | ExcludedByPolicy=2; NeedsManualReview=1 |
| `ai/gateway/gateways/url` | 1 | ExcludedByPolicy=1 |
| `ai/gateway/logging/state` | 2 | ExcludedByPolicy=2 |
| `ai/models/schema` | 1 | ExcludedByPolicy=1 |
| `ai/models/search` | 1 | NeedsManualReview=1 |
| `ai/run` | 2 | NeedsManualReview=2 |
| `ai/search/instances` | 5 | ExcludedByPolicy=4; NeedsManualReview=1 |
| `ai/search/instances/chat/completions` | 1 | NeedsManualReview=1 |
| `ai/search/instances/jobs` | 4 | ExcludedByPolicy=3; NeedsManualReview=1 |
| `ai/search/instances/jobs/logs` | 1 | ExcludedByPolicy=1 |
| `ai/search/instances/search` | 1 | NeedsManualReview=1 |
| `ai/search/instances/stats` | 1 | NeedsManualReview=1 |
| `ai/search/namespaces` | 5 | ExcludedByPolicy=4; NeedsManualReview=1 |
| `ai/search/namespaces/chat/completions` | 1 | NeedsManualReview=1 |
| `ai/search/namespaces/instances` | 6 | ExcludedByPolicy=4; NeedsManualReview=2 |
| `ai/search/namespaces/instances/chat/completions` | 1 | NeedsManualReview=1 |
| `ai/search/namespaces/instances/items` | 6 | ExcludedByPolicy=4; NeedsManualReview=2 |
| `ai/search/namespaces/instances/items/chunks` | 1 | ExcludedByPolicy=1 |
| `ai/search/namespaces/instances/items/download` | 1 | ExcludedByPolicy=1 |
| `ai/search/namespaces/instances/items/logs` | 1 | NeedsManualReview=1 |
| `ai/search/namespaces/instances/jobs` | 4 | ExcludedByPolicy=3; NeedsManualReview=1 |
| `ai/search/namespaces/instances/jobs/logs` | 1 | ExcludedByPolicy=1 |
| `ai/search/namespaces/instances/purge/cache` | 1 | NeedsManualReview=1 |
| `ai/search/namespaces/instances/search` | 1 | NeedsManualReview=1 |
| `ai/search/namespaces/instances/stats` | 1 | NeedsManualReview=1 |
| `ai/search/namespaces/search` | 1 | NeedsManualReview=1 |
| `ai/search/tokens` | 5 | ExcludedByPolicy=4; NeedsManualReview=1 |
| `ai/security/custom/topics` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `ai/security/settings` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `ai/tasks/search` | 1 | NeedsManualReview=1 |
| `ai/tomarkdown` | 1 | NeedsManualReview=1 |
| `ai/tomarkdown/supported` | 1 | ExcludedByPolicy=1 |
| `alerting/v3/available/alerts` | 1 | ExcludedByPolicy=1 |
| `alerting/v3/destinations/eligible` | 1 | ExcludedByPolicy=1 |
| `alerting/v3/destinations/pagerduty` | 2 | ExcludedByPolicy=2 |
| `alerting/v3/destinations/pagerduty/connect` | 2 | NeedsManualReview=2 |
| `alerting/v3/destinations/webhooks` | 5 | ExcludedByPolicy=5 |
| `alerting/v3/history` | 1 | ExcludedByPolicy=1 |
| `alerting/v3/policies` | 5 | ExcludedByPolicy=5 |
| `alerting/v3/policies/email/unsubscribe` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `alerting/v3/policies/test` | 1 | NeedsManualReview=1 |
| `alerting/v3/silences` | 5 | ExcludedByPolicy=5 |
| `analytics/colos` | 1 | ExcludedByPolicy=1 |
| `analytics/dashboard` | 1 | ExcludedByPolicy=1 |
| `analytics/engine/sql` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `analytics/latency` | 1 | NeedsManualReview=1 |
| `analytics/latency/colos` | 1 | NeedsManualReview=1 |
| `analytics/query/data/security/content/findings/top/n` | 1 | NeedsManualReview=1 |
| `analytics/query/data/security/findings/summary` | 1 | NeedsManualReview=1 |
| `analytics/query/data/security/findings/timeseries` | 1 | NeedsManualReview=1 |
| `analytics/query/summary` | 1 | NeedsManualReview=1 |
| `analytics/query/timeseries` | 1 | NeedsManualReview=1 |
| `analytics/query/top/n` | 1 | NeedsManualReview=1 |
| `api/gateway/configuration` | 2 | NeedsManualReview=2 |
| `api/gateway/discovery` | 1 | NeedsManualReview=1 |
| `api/gateway/discovery/operations` | 4 | ExcludedByPolicy=2; NeedsManualReview=2 |
| `api/gateway/expression/template/fallthrough` | 1 | NeedsManualReview=1 |
| `api/gateway/labels` | 1 | ExcludedByPolicy=1 |
| `api/gateway/labels/managed` | 1 | ExcludedByPolicy=1 |
| `api/gateway/labels/managed/resources/operation` | 1 | NeedsManualReview=1 |
| `api/gateway/labels/user` | 6 | ExcludedByPolicy=5; NeedsManualReview=1 |
| `api/gateway/labels/user/resources/operation` | 1 | NeedsManualReview=1 |
| `api/gateway/operations` | 5 | ExcludedByPolicy=2; NeedsManualReview=3 |
| `api/gateway/operations/item` | 1 | NeedsManualReview=1 |
| `api/gateway/operations/labels` | 6 | ExcludedByPolicy=2; NeedsManualReview=4 |
| `api/gateway/operations/schema/validation` | 3 | ExcludedByPolicy=2; NeedsManualReview=1 |
| `api/gateway/schemas` | 1 | NeedsManualReview=1 |
| `api/gateway/settings/schema/validation` | 3 | ExcludedByPolicy=2; NeedsManualReview=1 |
| `api/gateway/user/schemas` | 5 | ExcludedByPolicy=1; NeedsManualReview=4 |
| `api/gateway/user/schemas/hosts` | 1 | NeedsManualReview=1 |
| `api/gateway/user/schemas/operations` | 1 | NeedsManualReview=1 |
| `api/v4/health` | 1 | NeedsManualReview=1 |
| `argo/smart/routing` | 2 | ExcludedByPolicy=2 |
| `argo/tiered/caching` | 2 | ExcludedByPolicy=2 |
| `artifacts/namespaces` | 2 | ExcludedByPolicy=2 |
| `artifacts/namespaces/repos` | 4 | ExcludedByPolicy=4 |
| `artifacts/namespaces/repos/blob` | 1 | ExcludedByPolicy=1 |
| `artifacts/namespaces/repos/commit` | 1 | ExcludedByPolicy=1 |
| `artifacts/namespaces/repos/file` | 1 | ExcludedByPolicy=1 |
| `artifacts/namespaces/repos/fork` | 1 | NeedsManualReview=1 |
| `artifacts/namespaces/repos/import` | 1 | ExcludedByPolicy=1 |
| `artifacts/namespaces/repos/log` | 1 | ExcludedByPolicy=1 |
| `artifacts/namespaces/repos/raw` | 1 | ExcludedByPolicy=1 |
| `artifacts/namespaces/repos/tokens` | 1 | ExcludedByPolicy=1 |
| `artifacts/namespaces/repos/tree` | 1 | ExcludedByPolicy=1 |
| `artifacts/namespaces/tokens` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `audit/logs` | 1 | ExcludedByPolicy=1 |
| `autorag/rags/ai/search` | 1 | NeedsManualReview=1 |
| `autorag/rags/files` | 1 | NeedsManualReview=1 |
| `autorag/rags/jobs` | 2 | ExcludedByPolicy=2 |
| `autorag/rags/jobs/logs` | 1 | ExcludedByPolicy=1 |
| `autorag/rags/search` | 1 | NeedsManualReview=1 |
| `autorag/rags/sync` | 1 | NeedsManualReview=1 |
| `available/plans` | 2 | ExcludedByPolicy=2 |
| `available/rate/plans` | 1 | ExcludedByPolicy=1 |
| `billable/usage` | 3 | NeedsManualReview=1; UnsupportedProjectionCapability=2 |
| `billable/usage/info` | 1 | ExcludedByPolicy=1 |
| `billing/address/validation` | 1 | NeedsManualReview=1 |
| `billing/bad/debt` | 1 | ExcludedByPolicy=1 |
| `billing/credits` | 1 | ExcludedByPolicy=1 |
| `billing/history` | 1 | ExcludedByPolicy=1 |
| `billing/profile` | 5 | ExcludedByPolicy=5 |
| `billing/profile/payment/method` | 1 | ExcludedByPolicy=1 |
| `billing/rate/plans` | 1 | ExcludedByPolicy=1 |
| `billing/unpaid/invoice` | 1 | ExcludedByPolicy=1 |
| `billing/usage` | 1 | ExcludedByPolicy=1 |
| `bot/management` | 2 | ExcludedByPolicy=2 |
| `bot/management/feedback` | 2 | ExcludedByPolicy=2 |
| `botnet/feed/asn/day/report` | 1 | ExcludedByPolicy=1 |
| `botnet/feed/asn/full/report` | 1 | ExcludedByPolicy=1 |
| `botnet/feed/configs/asn` | 2 | ExcludedByPolicy=2 |
| `brand/protection/alerts` | 2 | ExcludedByPolicy=2 |
| `brand/protection/alerts/clear` | 1 | ExcludedByPolicy=1 |
| `brand/protection/alerts/refute` | 1 | ExcludedByPolicy=1 |
| `brand/protection/alerts/verify` | 1 | ExcludedByPolicy=1 |
| `brand/protection/brands` | 3 | ExcludedByPolicy=2; NeedsManualReview=1 |
| `brand/protection/brands/patterns` | 3 | ExcludedByPolicy=2; NeedsManualReview=1 |
| `brand/protection/clear` | 1 | ExcludedByPolicy=1 |
| `brand/protection/domain/info` | 1 | ExcludedByPolicy=1 |
| `brand/protection/logo/matches` | 1 | ExcludedByPolicy=1 |
| `brand/protection/logo/matches/download` | 1 | ExcludedByPolicy=1 |
| `brand/protection/logos` | 4 | ExcludedByPolicy=3; NeedsManualReview=1 |
| `brand/protection/matches` | 1 | ExcludedByPolicy=1 |
| `brand/protection/matches/download` | 1 | ExcludedByPolicy=1 |
| `brand/protection/queries` | 4 | ExcludedByPolicy=3; NeedsManualReview=1 |
| `brand/protection/queries/bulk` | 1 | NeedsManualReview=1 |
| `brand/protection/queries/matches/dismiss` | 1 | NeedsManualReview=1 |
| `brand/protection/queries/matches/undismiss` | 1 | NeedsManualReview=1 |
| `brand/protection/recent/submissions` | 1 | ExcludedByPolicy=1 |
| `brand/protection/refute` | 1 | ExcludedByPolicy=1 |
| `brand/protection/scan/logo` | 1 | NeedsManualReview=1 |
| `brand/protection/scan/page` | 1 | NeedsManualReview=1 |
| `brand/protection/search` | 1 | NeedsManualReview=1 |
| `brand/protection/submission/info` | 1 | ExcludedByPolicy=1 |
| `brand/protection/submit` | 1 | NeedsManualReview=1 |
| `brand/protection/total/queries` | 1 | ExcludedByPolicy=1 |
| `brand/protection/tracked/domains` | 1 | ExcludedByPolicy=1 |
| `brand/protection/url/info` | 1 | ExcludedByPolicy=1 |
| `brand/protection/verify` | 1 | ExcludedByPolicy=1 |
| `browser/extension/config` | 4 | ExcludedByPolicy=2; NeedsManualReview=2 |
| `browser/rendering/accessibilityTree` | 1 | NeedsManualReview=1 |
| `browser/rendering/content` | 1 | NeedsManualReview=1 |
| `browser/rendering/crawl` | 3 | ExcludedByPolicy=2; NeedsManualReview=1 |
| `browser/rendering/devtools/browser` | 4 | ExcludedByPolicy=3; NeedsManualReview=1 |
| `browser/rendering/devtools/browser/json` | 1 | ExcludedByPolicy=1 |
| `browser/rendering/devtools/browser/json/activate` | 1 | ExcludedByPolicy=1 |
| `browser/rendering/devtools/browser/json/close` | 1 | ExcludedByPolicy=1 |
| `browser/rendering/devtools/browser/json/list` | 2 | ExcludedByPolicy=2 |
| `browser/rendering/devtools/browser/json/new` | 1 | NeedsManualReview=1 |
| `browser/rendering/devtools/browser/json/protocol` | 1 | ExcludedByPolicy=1 |
| `browser/rendering/devtools/browser/json/version` | 1 | ExcludedByPolicy=1 |
| `browser/rendering/devtools/browser/live/view` | 1 | NeedsManualReview=1 |
| `browser/rendering/devtools/browser/page` | 1 | ExcludedByPolicy=1 |
| `browser/rendering/devtools/session` | 2 | ExcludedByPolicy=2 |
| `browser/rendering/json` | 1 | NeedsManualReview=1 |
| `browser/rendering/links` | 1 | NeedsManualReview=1 |
| `browser/rendering/markdown` | 1 | NeedsManualReview=1 |
| `browser/rendering/pdf` | 1 | NeedsManualReview=1 |
| `browser/rendering/scrape` | 1 | NeedsManualReview=1 |
| `browser/rendering/screenshot` | 1 | NeedsManualReview=1 |
| `browser/rendering/snapshot` | 1 | NeedsManualReview=1 |
| `builds/account/limits` | 1 | ExcludedByPolicy=1 |
| `builds/builds` | 2 | ExcludedByPolicy=2 |
| `builds/builds/cancel` | 1 | NeedsManualReview=1 |
| `builds/builds/latest` | 1 | ExcludedByPolicy=1 |
| `builds/builds/logs` | 1 | ExcludedByPolicy=1 |
| `builds/repos/config/autofill` | 1 | ExcludedByPolicy=1 |
| `builds/repos/connections` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `builds/tokens` | 3 | ExcludedByPolicy=3 |
| `builds/triggers` | 3 | ExcludedByPolicy=3 |
| `builds/triggers/builds` | 1 | ExcludedByPolicy=1 |
| `builds/triggers/environment/variables` | 3 | ExcludedByPolicy=2; NeedsManualReview=1 |
| `builds/triggers/purge/build/cache` | 1 | NeedsManualReview=1 |
| `builds/workers` | 4 | ExcludedByPolicy=4 |
| `builds/workers/builds` | 1 | ExcludedByPolicy=1 |
| `builds/workers/deploy/hooks` | 5 | ExcludedByPolicy=5 |
| `builds/workers/triggers` | 1 | ExcludedByPolicy=1 |
| `bulk/subscriptions` | 1 | ExcludedByPolicy=1 |
| `cache/cache/reserve` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `cache/cache/reserve/clear` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `cache/origin/cloud/regions` | 5 | ExcludedByPolicy=4; NeedsManualReview=1 |
| `cache/origin/cloud/regions/batch` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `cache/origin/cloud/regions/supported/regions` | 1 | NeedsManualReview=1 |
| `cache/origin/post/quantum/encryption` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `cache/regional/tiered/cache` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `cache/tiered/cache/smart/topology/enable` | 4 | ExcludedByPolicy=4 |
| `cache/variants` | 3 | ExcludedByPolicy=2; NeedsManualReview=1 |
| `calls/apps` | 5 | ExcludedByPolicy=5 |
| `calls/turn/keys` | 5 | ExcludedByPolicy=5 |
| `certificate/authorities/hostname/associations` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `certificates` | 4 | ExcludedByPolicy=3; NeedsManualReview=1 |
| `cfd/tunnel` | 5 | ExcludedByPolicy=5 |
| `cfd/tunnel/configurations` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `cfd/tunnel/connections` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `cfd/tunnel/connectors` | 1 | ExcludedByPolicy=1 |
| `cfd/tunnel/management` | 1 | ExcludedByPolicy=1 |
| `cfd/tunnel/token` | 1 | ExcludedByPolicy=1 |
| `challenges/widgets` | 5 | ExcludedByPolicy=5 |
| `challenges/widgets/rotate/secret` | 1 | ExcludedByPolicy=1 |
| `client/certificates` | 5 | ExcludedByPolicy=5 |
| `client/secret` | 1 | ExcludedByPolicy=1 |
| `cloud/connector/rules` | 2 | NeedsManualReview=2 |
| `cloudforce/one/binary` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `cloudforce/one/events` | 4 | ExcludedByPolicy=4 |
| `cloudforce/one/events/aggregate` | 1 | ExcludedByPolicy=1 |
| `cloudforce/one/events/attackers` | 1 | ExcludedByPolicy=1 |
| `cloudforce/one/events/categories` | 5 | ExcludedByPolicy=5 |
| `cloudforce/one/events/categories/catalog` | 1 | ExcludedByPolicy=1 |
| `cloudforce/one/events/categories/create` | 1 | ExcludedByPolicy=1 |
| `cloudforce/one/events/countries` | 1 | ExcludedByPolicy=1 |
| `cloudforce/one/events/create` | 1 | ExcludedByPolicy=1 |
| `cloudforce/one/events/create/bulk` | 1 | ExcludedByPolicy=1 |
| `cloudforce/one/events/create/bulk/relationships` | 1 | ExcludedByPolicy=1 |
| `cloudforce/one/events/dataset` | 5 | ExcludedByPolicy=5 |
| `cloudforce/one/events/dataset/-/groups` | 5 | ExcludedByPolicy=5 |
| `cloudforce/one/events/dataset/-/groups/members` | 3 | ExcludedByPolicy=3 |
| `cloudforce/one/events/dataset/copy` | 1 | NeedsManualReview=1 |
| `cloudforce/one/events/dataset/create` | 1 | ExcludedByPolicy=1 |
| `cloudforce/one/events/dataset/events` | 1 | ExcludedByPolicy=1 |
| `cloudforce/one/events/dataset/indicators` | 4 | ExcludedByPolicy=4 |
| `cloudforce/one/events/dataset/indicators/bulk` | 1 | ExcludedByPolicy=1 |
| `cloudforce/one/events/dataset/indicators/create` | 1 | ExcludedByPolicy=1 |
| `cloudforce/one/events/dataset/indicators/relationships` | 4 | ExcludedByPolicy=4 |
| `cloudforce/one/events/dataset/indicators/tags` | 1 | ExcludedByPolicy=1 |
| `cloudforce/one/events/dataset/indicatorTypes/create` | 1 | ExcludedByPolicy=1 |
| `cloudforce/one/events/dataset/move` | 1 | NeedsManualReview=1 |
| `cloudforce/one/events/dataset/permissions` | 4 | ExcludedByPolicy=4 |
| `cloudforce/one/events/dataset/tags/indicators` | 1 | ExcludedByPolicy=1 |
| `cloudforce/one/events/dataset/targetIndustries` | 1 | ExcludedByPolicy=1 |
| `cloudforce/one/events/datasets/populate` | 1 | NeedsManualReview=1 |
| `cloudforce/one/events/delete` | 1 | ExcludedByPolicy=1 |
| `cloudforce/one/events/event/tag` | 1 | ExcludedByPolicy=1 |
| `cloudforce/one/events/event/tag/create` | 1 | ExcludedByPolicy=1 |
| `cloudforce/one/events/graph` | 1 | ExcludedByPolicy=1 |
| `cloudforce/one/events/graphql` | 1 | NeedsManualReview=1 |
| `cloudforce/one/events/indicator/types` | 1 | UnsupportedProjectionCapability=1 |
| `cloudforce/one/events/indicators` | 1 | ExcludedByPolicy=1 |
| `cloudforce/one/events/indicators/aggregate` | 1 | ExcludedByPolicy=1 |
| `cloudforce/one/events/indicatorTypes` | 1 | UnsupportedProjectionCapability=1 |
| `cloudforce/one/events/queries` | 5 | ExcludedByPolicy=5 |
| `cloudforce/one/events/queries/create` | 1 | ExcludedByPolicy=1 |
| `cloudforce/one/events/raw` | 4 | ExcludedByPolicy=4 |
| `cloudforce/one/events/relate` | 1 | ExcludedByPolicy=1 |
| `cloudforce/one/events/relate/create` | 1 | ExcludedByPolicy=1 |
| `cloudforce/one/events/relationships` | 1 | ExcludedByPolicy=1 |
| `cloudforce/one/events/relationships/create` | 1 | ExcludedByPolicy=1 |
| `cloudforce/one/events/tags` | 4 | ExcludedByPolicy=4 |
| `cloudforce/one/events/tags/categories` | 4 | ExcludedByPolicy=4 |
| `cloudforce/one/events/tags/categories/create` | 1 | ExcludedByPolicy=1 |
| `cloudforce/one/events/tags/create` | 1 | ExcludedByPolicy=1 |
| `cloudforce/one/events/tags/indicators` | 1 | ExcludedByPolicy=1 |
| `cloudforce/one/events/tags/relationships` | 4 | ExcludedByPolicy=4 |
| `cloudforce/one/events/targetIndustries` | 1 | ExcludedByPolicy=1 |
| `cloudforce/one/events/targetIndustries/catalog` | 1 | ExcludedByPolicy=1 |
| `cloudforce/one/events/update/bulk` | 1 | ExcludedByPolicy=1 |
| `cloudforce/one/requests` | 4 | ExcludedByPolicy=4 |
| `cloudforce/one/requests/asset` | 4 | ExcludedByPolicy=4 |
| `cloudforce/one/requests/asset/new` | 1 | NeedsManualReview=1 |
| `cloudforce/one/requests/constants` | 1 | NeedsManualReview=1 |
| `cloudforce/one/requests/message` | 3 | ExcludedByPolicy=3 |
| `cloudforce/one/requests/message/new` | 1 | NeedsManualReview=1 |
| `cloudforce/one/requests/new` | 1 | NeedsManualReview=1 |
| `cloudforce/one/requests/priority` | 4 | ExcludedByPolicy=4 |
| `cloudforce/one/requests/priority/new` | 1 | NeedsManualReview=1 |
| `cloudforce/one/requests/priority/quota` | 1 | NeedsManualReview=1 |
| `cloudforce/one/requests/quota` | 1 | NeedsManualReview=1 |
| `cloudforce/one/requests/types` | 1 | NeedsManualReview=1 |
| `cloudforce/one/rules` | 6 | ExcludedByPolicy=6 |
| `cloudforce/one/rules/approvals` | 2 | ExcludedByPolicy=2 |
| `cloudforce/one/rules/approvals/cancel` | 1 | NeedsManualReview=1 |
| `cloudforce/one/rules/approvals/resubmit` | 1 | NeedsManualReview=1 |
| `cloudforce/one/rules/exemptions` | 4 | ExcludedByPolicy=2; NeedsManualReview=2 |
| `cloudforce/one/rules/managed` | 1 | ExcludedByPolicy=1 |
| `cloudforce/one/rules/search` | 1 | NeedsManualReview=1 |
| `cloudforce/one/rules/stats` | 1 | ExcludedByPolicy=1 |
| `cloudforce/one/rules/structured` | 5 | ExcludedByPolicy=5 |
| `cloudforce/one/rules/structured/approvals` | 1 | ExcludedByPolicy=1 |
| `cloudforce/one/rules/structured/approvals/resubmit` | 1 | NeedsManualReview=1 |
| `cloudforce/one/rules/structured/schema` | 1 | ExcludedByPolicy=1 |
| `cloudforce/one/rules/structured/test` | 1 | NeedsManualReview=1 |
| `cloudforce/one/rules/structured/validate` | 1 | NeedsManualReview=1 |
| `cloudforce/one/rules/tree` | 1 | ExcludedByPolicy=1 |
| `cloudforce/one/rules/validate` | 1 | NeedsManualReview=1 |
| `cloudforce/one/scans/config` | 4 | ExcludedByPolicy=4 |
| `cloudforce/one/scans/results` | 1 | ExcludedByPolicy=1 |
| `cloudforce/one/v2/brand/protection/domain/matches` | 1 | ExcludedByPolicy=1 |
| `cloudforce/one/v2/brand/protection/domain/queries` | 4 | ExcludedByPolicy=3; NeedsManualReview=1 |
| `cloudforce/one/v2/brand/protection/letter/generate` | 1 | NeedsManualReview=1 |
| `cloudforce/one/v2/brand/protection/letter/templates` | 5 | ExcludedByPolicy=5 |
| `cloudforce/one/v2/brand/protection/letter/templates/examples` | 1 | ExcludedByPolicy=1 |
| `cloudforce/one/v2/brand/protection/logo/matches` | 1 | ExcludedByPolicy=1 |
| `cloudforce/one/v2/brand/protection/logo/queries` | 3 | ExcludedByPolicy=2; NeedsManualReview=1 |
| `cloudforce/one/v2/brand/protection/logo/search` | 1 | NeedsManualReview=1 |
| `cloudforce/one/v2/brand/protection/takedown/notices` | 5 | ExcludedByPolicy=5 |
| `cloudforce/one/v2/brand/protection/takedown/notices/letters` | 4 | ExcludedByPolicy=4 |
| `cloudforce/one/v2/brand/protection/takedown/notices/letters/pdf` | 1 | ExcludedByPolicy=1 |
| `cloudforce/one/v2/brand/protection/takedown/notices/lookup` | 1 | NeedsManualReview=1 |
| `cloudforce/one/v2/brand/protection/total/queries` | 1 | ExcludedByPolicy=1 |
| `cloudforce/one/v2/collections` | 5 | ExcludedByPolicy=5 |
| `cloudforce/one/v2/collections/columns` | 3 | ExcludedByPolicy=2; NeedsManualReview=1 |
| `cloudforce/one/v2/collections/export` | 1 | ExcludedByPolicy=1 |
| `cloudforce/one/v2/collections/items` | 5 | ExcludedByPolicy=5 |
| `cloudforce/one/v2/collections/search` | 1 | NeedsManualReview=1 |
| `cloudforce/one/v2/events/graphql` | 1 | NeedsManualReview=1 |
| `cni/cnis` | 5 | ExcludedByPolicy=5 |
| `cni/interconnects` | 4 | ExcludedByPolicy=4 |
| `cni/interconnects/loa` | 1 | ExcludedByPolicy=1 |
| `cni/interconnects/loa/default` | 1 | ExcludedByPolicy=1 |
| `cni/interconnects/status` | 1 | ExcludedByPolicy=1 |
| `cni/settings` | 2 | ExcludedByPolicy=2 |
| `cni/slots` | 2 | ExcludedByPolicy=2 |
| `connectivity/directory/services` | 5 | ExcludedByPolicy=3; NeedsManualReview=2 |
| `containers/applications` | 5 | ExcludedByPolicy=4; NeedsManualReview=1 |
| `containers/applications/instances` | 2 | ExcludedByPolicy=2 |
| `containers/applications/rollouts` | 1 | ExcludedByPolicy=1 |
| `containers/applications/versions` | 1 | ExcludedByPolicy=1 |
| `containers/image/preparations` | 1 | NeedsManualReview=1 |
| `containers/registries` | 3 | ExcludedByPolicy=3 |
| `containers/registries/credentials` | 1 | NeedsManualReview=1 |
| `content/upload/scan/disable` | 1 | NeedsManualReview=1 |
| `content/upload/scan/enable` | 1 | NeedsManualReview=1 |
| `content/upload/scan/payloads` | 4 | ExcludedByPolicy=3; NeedsManualReview=1 |
| `content/upload/scan/settings` | 2 | ExcludedByPolicy=2 |
| `ct/alerting` | 2 | ExcludedByPolicy=2 |
| `custom/certificates` | 5 | ExcludedByPolicy=5 |
| `custom/certificates/prioritize` | 1 | NeedsManualReview=1 |
| `custom/csrs` | 8 | ExcludedByPolicy=8 |
| `custom/hostnames` | 5 | ExcludedByPolicy=5 |
| `custom/hostnames/certificate/pack/certificates` | 2 | ExcludedByPolicy=2 |
| `custom/hostnames/fallback/origin` | 3 | ExcludedByPolicy=3 |
| `custom/hostnames/quota` | 1 | ExcludedByPolicy=1 |
| `custom/ns` | 5 | ExcludedByPolicy=3; NeedsManualReview=2 |
| `custom/pages` | 6 | ExcludedByPolicy=6 |
| `custom/pages/assets` | 10 | ExcludedByPolicy=10 |
| `custom/pages/preview/tokens` | 2 | ExcludedByPolicy=2 |
| `d1/database` | 6 | ExcludedByPolicy=6 |
| `d1/database/export` | 1 | ExcludedByPolicy=1 |
| `d1/database/import` | 1 | ExcludedByPolicy=1 |
| `d1/database/query` | 1 | NeedsManualReview=1 |
| `d1/database/raw` | 1 | NeedsManualReview=1 |
| `d1/database/time/travel/bookmark` | 1 | ExcludedByPolicy=1 |
| `d1/database/time/travel/restore` | 1 | NeedsManualReview=1 |
| `data/security/posture/content` | 1 | ExcludedByPolicy=1 |
| `data/security/posture/content/export` | 1 | ExcludedByPolicy=1 |
| `data/security/posture/exports` | 2 | ExcludedByPolicy=2 |
| `data/security/posture/finding/types` | 2 | ExcludedByPolicy=2 |
| `data/security/posture/finding/types/remediation/types` | 1 | ExcludedByPolicy=1 |
| `data/security/posture/findings` | 2 | ExcludedByPolicy=2 |
| `data/security/posture/findings/export` | 1 | ExcludedByPolicy=1 |
| `data/security/posture/findings/ignore` | 1 | NeedsManualReview=1 |
| `data/security/posture/findings/instances` | 2 | ExcludedByPolicy=2 |
| `data/security/posture/findings/instances/archive` | 1 | NeedsManualReview=1 |
| `data/security/posture/findings/instances/export` | 1 | ExcludedByPolicy=1 |
| `data/security/posture/findings/instances/unarchive` | 1 | NeedsManualReview=1 |
| `data/security/posture/findings/reset/finding/severity` | 1 | NeedsManualReview=1 |
| `data/security/posture/findings/tune/finding/severity` | 1 | NeedsManualReview=1 |
| `data/security/posture/findings/unignore` | 1 | NeedsManualReview=1 |
| `data/security/posture/policies` | 5 | ExcludedByPolicy=5 |
| `data/security/posture/policies/logs` | 1 | ExcludedByPolicy=1 |
| `data/security/posture/remediations/jobs` | 2 | ExcludedByPolicy=2 |
| `data/security/posture/remediations/jobs/export` | 1 | ExcludedByPolicy=1 |
| `data/security/posture/webhooks` | 5 | ExcludedByPolicy=5 |
| `data/security/posture/webhooks/evaluate` | 2 | NeedsManualReview=2 |
| `data/security/posture/webhooks/jobs` | 1 | ExcludedByPolicy=1 |
| `dcv/delegation/uuid` | 1 | ExcludedByPolicy=1 |
| `devices` | 2 | ExcludedByPolicy=2 |
| `devices/client/versions` | 1 | ExcludedByPolicy=1 |
| `devices/client/versions/target/environments` | 1 | ExcludedByPolicy=1 |
| `devices/deployment/groups` | 5 | ExcludedByPolicy=5 |
| `devices/ip/profiles` | 5 | ExcludedByPolicy=5 |
| `devices/networks` | 5 | ExcludedByPolicy=5 |
| `devices/override/codes` | 1 | ExcludedByPolicy=1 |
| `devices/physical/devices` | 3 | ExcludedByPolicy=3 |
| `devices/physical/devices/revoke` | 1 | NeedsManualReview=1 |
| `devices/policies` | 1 | ExcludedByPolicy=1 |
| `devices/policy` | 6 | ExcludedByPolicy=6 |
| `devices/policy/certificates` | 2 | ExcludedByPolicy=2 |
| `devices/policy/exclude` | 4 | UnsupportedProjectionCapability=4 |
| `devices/policy/fallback/domains` | 4 | UnsupportedProjectionCapability=4 |
| `devices/policy/include` | 4 | UnsupportedProjectionCapability=4 |
| `devices/posture` | 5 | ExcludedByPolicy=5 |
| `devices/posture/integration` | 5 | ExcludedByPolicy=5 |
| `devices/registrations` | 4 | ExcludedByPolicy=4 |
| `devices/registrations/override/codes` | 1 | ExcludedByPolicy=1 |
| `devices/registrations/revoke` | 1 | NeedsManualReview=1 |
| `devices/registrations/unrevoke` | 1 | NeedsManualReview=1 |
| `devices/resilience/disconnect` | 2 | NeedsManualReview=2 |
| `devices/revoke` | 1 | NeedsManualReview=1 |
| `devices/settings` | 4 | ExcludedByPolicy=4 |
| `devices/unrevoke` | 1 | NeedsManualReview=1 |
| `dex/colos` | 1 | ExcludedByPolicy=1 |
| `dex/commands` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `dex/commands/devices` | 1 | ExcludedByPolicy=1 |
| `dex/commands/downloads` | 1 | ExcludedByPolicy=1 |
| `dex/commands/quota` | 1 | ExcludedByPolicy=1 |
| `dex/devices/dex/tests` | 5 | ExcludedByPolicy=5 |
| `dex/devices/fleet/status/live` | 1 | NeedsManualReview=1 |
| `dex/devices/fleet/status/over/time` | 1 | NeedsManualReview=1 |
| `dex/devices/isps` | 1 | ExcludedByPolicy=1 |
| `dex/fleet/status/devices` | 1 | NeedsManualReview=1 |
| `dex/fleet/status/live` | 1 | NeedsManualReview=1 |
| `dex/fleet/status/over/time` | 1 | NeedsManualReview=1 |
| `dex/http/tests` | 1 | ExcludedByPolicy=1 |
| `dex/http/tests/percentiles` | 1 | NeedsManualReview=1 |
| `dex/rules` | 5 | ExcludedByPolicy=5 |
| `dex/tests/overview` | 1 | ExcludedByPolicy=1 |
| `dex/tests/unique/devices` | 1 | NeedsManualReview=1 |
| `dex/traceroute/test/results/network/path` | 1 | NeedsManualReview=1 |
| `dex/traceroute/tests` | 1 | ExcludedByPolicy=1 |
| `dex/traceroute/tests/network/path` | 1 | NeedsManualReview=1 |
| `dex/traceroute/tests/percentiles` | 1 | NeedsManualReview=1 |
| `dex/warp/change/events` | 1 | ExcludedByPolicy=1 |
| `diagnostics/endpoint/healthchecks` | 5 | ExcludedByPolicy=5 |
| `diagnostics/traceroute` | 1 | NeedsManualReview=1 |
| `dlp/custom/prompt/topics` | 5 | ExcludedByPolicy=5 |
| `dlp/data/classes` | 5 | ExcludedByPolicy=4; NeedsManualReview=1 |
| `dlp/data/tag/categories` | 5 | ExcludedByPolicy=4; NeedsManualReview=1 |
| `dlp/data/tag/categories/data/tags` | 5 | ExcludedByPolicy=4; NeedsManualReview=1 |
| `dlp/data/tag/category/templates` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `dlp/datasets` | 5 | ExcludedByPolicy=3; NeedsManualReview=2 |
| `dlp/datasets/upload` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `dlp/datasets/versions` | 1 | NeedsManualReview=1 |
| `dlp/datasets/versions/entries` | 1 | NeedsManualReview=1 |
| `dlp/document/fingerprints` | 6 | ExcludedByPolicy=3; NeedsManualReview=3 |
| `dlp/email/account/mapping` | 2 | ExcludedByPolicy=2 |
| `dlp/email/rules` | 6 | ExcludedByPolicy=6 |
| `dlp/entries` | 5 | ExcludedByPolicy=5 |
| `dlp/entries/custom` | 1 | ExcludedByPolicy=1 |
| `dlp/entries/integration` | 3 | ExcludedByPolicy=3 |
| `dlp/entries/predefined` | 3 | ExcludedByPolicy=3 |
| `dlp/limits` | 1 | ExcludedByPolicy=1 |
| `dlp/patterns/validate` | 1 | NeedsManualReview=1 |
| `dlp/payload/log` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `dlp/profiles` | 2 | ExcludedByPolicy=2 |
| `dlp/profiles/custom` | 5 | ExcludedByPolicy=5 |
| `dlp/profiles/predefined` | 4 | ExcludedByPolicy=4 |
| `dlp/profiles/predefined/config` | 3 | ExcludedByPolicy=3 |
| `dlp/sensitivity/groups` | 5 | ExcludedByPolicy=4; NeedsManualReview=1 |
| `dlp/sensitivity/groups/level/order` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `dlp/sensitivity/groups/levels` | 5 | ExcludedByPolicy=4; NeedsManualReview=1 |
| `dlp/sensitivity/groups/templates` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `dlp/settings` | 4 | ExcludedByPolicy=4 |
| `dls/regional/services/prefix/bindings` | 5 | ExcludedByPolicy=5 |
| `dls/regions` | 2 | ExcludedByPolicy=2 |
| `dns/analytics/report` | 1 | NeedsManualReview=1 |
| `dns/analytics/report/bytime` | 1 | NeedsManualReview=1 |
| `dns/firewall` | 5 | ExcludedByPolicy=5 |
| `dns/firewall/dns/analytics/report` | 1 | NeedsManualReview=1 |
| `dns/firewall/dns/analytics/report/bytime` | 1 | NeedsManualReview=1 |
| `dns/firewall/reverse/dns` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `dns/records` | 6 | SupportedWithOverride=6 |
| `dns/records/batch` | 1 | NeedsManualReview=1 |
| `dns/records/export` | 1 | ExcludedByPolicy=1 |
| `dns/records/import` | 1 | ExcludedByPolicy=1 |
| `dns/records/scan` | 1 | NeedsManualReview=1 |
| `dns/records/scan/review` | 2 | NeedsManualReview=2 |
| `dns/records/scan/trigger` | 1 | NeedsManualReview=1 |
| `dns/records/usage` | 2 | ExcludedByPolicy=2 |
| `dns/settings` | 4 | ExcludedByPolicy=4 |
| `dns/settings/views` | 5 | ExcludedByPolicy=5 |
| `dnssec` | 3 | ExcludedByPolicy=3 |
| `dnssec/zsk` | 1 | ExcludedByPolicy=1 |
| `email/auth/dmarc/reports` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `email/auth/spf/inspect` | 1 | NeedsManualReview=1 |
| `email/routing` | 3 | ExcludedByPolicy=2; NeedsManualReview=1 |
| `email/routing/addresses` | 5 | ExcludedByPolicy=5 |
| `email/routing/disable` | 1 | NeedsManualReview=1 |
| `email/routing/dns` | 4 | NeedsManualReview=4 |
| `email/routing/enable` | 1 | NeedsManualReview=1 |
| `email/routing/rules` | 6 | ExcludedByPolicy=6 |
| `email/routing/rules/catch/all` | 2 | ExcludedByPolicy=2 |
| `email/routing/rules/plan` | 1 | NeedsManualReview=1 |
| `email/routing/suppression` | 8 | ExcludedByPolicy=6; NeedsManualReview=2 |
| `email/routing/unlock` | 1 | NeedsManualReview=1 |
| `email/security/investigate` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `email/security/investigate/action/log` | 1 | ExcludedByPolicy=1 |
| `email/security/investigate/bulk` | 4 | ExcludedByPolicy=4 |
| `email/security/investigate/bulk/cancel` | 1 | NeedsManualReview=1 |
| `email/security/investigate/bulk/messages` | 1 | ExcludedByPolicy=1 |
| `email/security/investigate/detections` | 1 | ExcludedByPolicy=1 |
| `email/security/investigate/move` | 2 | NeedsManualReview=2 |
| `email/security/investigate/preview` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `email/security/investigate/raw` | 1 | ExcludedByPolicy=1 |
| `email/security/investigate/reclassify` | 1 | NeedsManualReview=1 |
| `email/security/investigate/release` | 1 | NeedsManualReview=1 |
| `email/security/investigate/trace` | 1 | ExcludedByPolicy=1 |
| `email/security/phishguard/reports` | 1 | ExcludedByPolicy=1 |
| `email/security/settings/allow/policies` | 6 | ExcludedByPolicy=5; NeedsManualReview=1 |
| `email/security/settings/allow/policies/batch` | 1 | NeedsManualReview=1 |
| `email/security/settings/block/senders` | 6 | ExcludedByPolicy=5; NeedsManualReview=1 |
| `email/security/settings/block/senders/batch` | 1 | NeedsManualReview=1 |
| `email/security/settings/content/policies` | 5 | ExcludedByPolicy=5 |
| `email/security/settings/content/policies/batch` | 1 | NeedsManualReview=1 |
| `email/security/settings/domains` | 7 | ExcludedByPolicy=6; NeedsManualReview=1 |
| `email/security/settings/domains/batch` | 1 | NeedsManualReview=1 |
| `email/security/settings/domains/verification` | 1 | ExcludedByPolicy=1 |
| `email/security/settings/impersonation/registry` | 5 | ExcludedByPolicy=5 |
| `email/security/settings/sending/domain/restrictions` | 5 | ExcludedByPolicy=5 |
| `email/security/settings/sending/domain/restrictions/batch` | 1 | NeedsManualReview=1 |
| `email/security/settings/trusted/domains` | 6 | ExcludedByPolicy=5; NeedsManualReview=1 |
| `email/security/settings/trusted/domains/batch` | 1 | NeedsManualReview=1 |
| `email/security/settings/url/ignore/patterns` | 5 | ExcludedByPolicy=5 |
| `email/security/settings/url/ignore/patterns/batch` | 1 | NeedsManualReview=1 |
| `email/security/submissions` | 1 | NeedsManualReview=1 |
| `email/sending/limits` | 1 | ExcludedByPolicy=1 |
| `email/sending/messages` | 1 | ExcludedByPolicy=1 |
| `email/sending/send` | 1 | NeedsManualReview=1 |
| `email/sending/send/raw` | 1 | NeedsManualReview=1 |
| `email/sending/subdomains` | 5 | ExcludedByPolicy=5 |
| `email/sending/subdomains/dns` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `email/sending/subdomains/dns/status` | 1 | ExcludedByPolicy=1 |
| `email/sending/subdomains/preview` | 1 | NeedsManualReview=1 |
| `email/sending/subdomains/reputation/complaints` | 1 | ExcludedByPolicy=1 |
| `email/sending/suppression` | 8 | ExcludedByPolicy=6; NeedsManualReview=2 |
| `email/sending/suppressions` | 5 | ExcludedByPolicy=5 |
| `email/sending/suppressions/bulk` | 1 | ExcludedByPolicy=1 |
| `entitlements` | 2 | ExcludedByPolicy=2 |
| `environments` | 5 | ExcludedByPolicy=5 |
| `environments/purge/cache` | 1 | NeedsManualReview=1 |
| `environments/rollback` | 1 | NeedsManualReview=1 |
| `event/notifications/r2/configuration` | 1 | ExcludedByPolicy=1 |
| `event/notifications/r2/configuration/queues` | 3 | ExcludedByPolicy=2; NeedsManualReview=1 |
| `event/subscriptions/subscriptions` | 5 | ExcludedByPolicy=5 |
| `filters` | 7 | ExcludedByPolicy=7 |
| `firewall/access/rules/rules` | 9 | ExcludedByPolicy=9 |
| `firewall/lockdowns` | 5 | ExcludedByPolicy=5 |
| `firewall/rules` | 9 | ExcludedByPolicy=5; UnsupportedProjectionCapability=4 |
| `firewall/ua/rules` | 5 | ExcludedByPolicy=5 |
| `firewall/waf/overrides` | 5 | ExcludedByPolicy=5 |
| `firewall/waf/packages` | 3 | ExcludedByPolicy=3 |
| `firewall/waf/packages/groups` | 3 | ExcludedByPolicy=3 |
| `firewall/waf/packages/rules` | 3 | ExcludedByPolicy=3 |
| `flagship/apps` | 5 | ExcludedByPolicy=5 |
| `flagship/apps/definitions` | 1 | ExcludedByPolicy=1 |
| `flagship/apps/evaluate` | 2 | NeedsManualReview=2 |
| `flagship/apps/flags` | 5 | ExcludedByPolicy=5 |
| `flagship/apps/flags/changelog` | 1 | ExcludedByPolicy=1 |
| `fraud/detection/settings` | 2 | ExcludedByPolicy=2 |
| `gateway` | 2 | ExcludedByPolicy=2 |
| `gateway/app/types` | 1 | ExcludedByPolicy=1 |
| `gateway/apps/review/status` | 2 | ExcludedByPolicy=2 |
| `gateway/audit/ssh/settings` | 2 | ExcludedByPolicy=2 |
| `gateway/audit/ssh/settings/rotate/seed` | 1 | NeedsManualReview=1 |
| `gateway/categories` | 1 | ExcludedByPolicy=1 |
| `gateway/certificates` | 4 | ExcludedByPolicy=4 |
| `gateway/certificates/activate` | 1 | NeedsManualReview=1 |
| `gateway/certificates/deactivate` | 1 | NeedsManualReview=1 |
| `gateway/configuration` | 3 | ExcludedByPolicy=3 |
| `gateway/configuration/custom/certificate` | 1 | ExcludedByPolicy=1 |
| `gateway/dns/destination/ips` | 1 | ExcludedByPolicy=1 |
| `gateway/egress/cidr/pairs` | 1 | ExcludedByPolicy=1 |
| `gateway/lists` | 6 | UnsupportedProjectionCapability=6 |
| `gateway/lists/items` | 1 | ExcludedByPolicy=1 |
| `gateway/lists/upload` | 1 | ExcludedByPolicy=1 |
| `gateway/locations` | 5 | ExcludedByPolicy=5 |
| `gateway/logging` | 2 | ExcludedByPolicy=2 |
| `gateway/operations` | 2 | ExcludedByPolicy=2 |
| `gateway/pacfiles` | 5 | ExcludedByPolicy=5 |
| `gateway/proxy/endpoints` | 5 | ExcludedByPolicy=5 |
| `gateway/rules` | 7 | ExcludedByPolicy=7 |
| `gateway/rules/reset/expiration` | 1 | NeedsManualReview=1 |
| `gateway/rules/tenant` | 1 | ExcludedByPolicy=1 |
| `healthchecks` | 6 | ExcludedByPolicy=6 |
| `healthchecks/preview` | 3 | ExcludedByPolicy=3 |
| `hold` | 5 | ExcludedByPolicy=4; NeedsManualReview=1 |
| `hostnames/settings` | 4 | ExcludedByPolicy=3; NeedsManualReview=1 |
| `hyperdrive/configs` | 6 | ExcludedByPolicy=6 |
| `hyperdrive/configs/restart` | 1 | NeedsManualReview=1 |
| `hyperdrive/integrationsOperations/createDatabaseSignature` | 1 | ExcludedByPolicy=1 |
| `iam/permission/groups` | 2 | ExcludedByPolicy=2 |
| `iam/resource/groups` | 5 | ExcludedByPolicy=5 |
| `iam/user/groups` | 5 | ExcludedByPolicy=5 |
| `iam/user/groups/members` | 5 | ExcludedByPolicy=5 |
| `images/v1` | 5 | ExcludedByPolicy=4; NeedsManualReview=1 |
| `images/v1/blob` | 1 | NeedsManualReview=1 |
| `images/v1/direct/upload` | 1 | ExcludedByPolicy=1 |
| `images/v1/keys` | 3 | ExcludedByPolicy=2; NeedsManualReview=1 |
| `images/v1/stats` | 1 | NeedsManualReview=1 |
| `images/v1/variants` | 5 | ExcludedByPolicy=5 |
| `images/v1/variants/flat` | 1 | ExcludedByPolicy=1 |
| `images/v2` | 1 | ExcludedByPolicy=1 |
| `images/v2/direct/upload` | 1 | ExcludedByPolicy=1 |
| `images/v2/sourcingkit/migrations` | 4 | ExcludedByPolicy=4 |
| `images/v2/sourcingkit/migrations/lifecycle` | 1 | ExcludedByPolicy=1 |
| `images/v2/sourcingkit/migrations/lifecycle/abort` | 1 | NeedsManualReview=1 |
| `images/v2/sourcingkit/migrations/lifecycle/start` | 1 | NeedsManualReview=1 |
| `images/v2/sourcingkit/migrations/logs` | 1 | ExcludedByPolicy=1 |
| `images/v2/sourcingkit/sources` | 5 | ExcludedByPolicy=5 |
| `images/v2/sourcingkit/sources/connectivity` | 1 | ExcludedByPolicy=1 |
| `images/v2/sourcingkit/sources/connectivity/precheck` | 1 | NeedsManualReview=1 |
| `infrastructure/targets` | 5 | ExcludedByPolicy=5 |
| `infrastructure/targets/batch` | 2 | ExcludedByPolicy=2 |
| `infrastructure/targets/batch/delete` | 1 | ExcludedByPolicy=1 |
| `intel/asn` | 1 | ExcludedByPolicy=1 |
| `intel/asn/subnets` | 1 | ExcludedByPolicy=1 |
| `intel/attack/surface/report/issue/types` | 1 | ExcludedByPolicy=1 |
| `intel/attack/surface/report/issues` | 1 | ExcludedByPolicy=1 |
| `intel/attack/surface/report/issues/class` | 1 | ExcludedByPolicy=1 |
| `intel/attack/surface/report/issues/dismiss` | 1 | NeedsManualReview=1 |
| `intel/attack/surface/report/issues/severity` | 1 | ExcludedByPolicy=1 |
| `intel/attack/surface/report/issues/type` | 1 | ExcludedByPolicy=1 |
| `intel/dns` | 1 | ExcludedByPolicy=1 |
| `intel/domain` | 1 | ExcludedByPolicy=1 |
| `intel/domain/bulk` | 1 | ExcludedByPolicy=1 |
| `intel/domain/history` | 1 | ExcludedByPolicy=1 |
| `intel/indicator/feeds` | 4 | ExcludedByPolicy=4 |
| `intel/indicator/feeds/data` | 1 | ExcludedByPolicy=1 |
| `intel/indicator/feeds/download` | 1 | NeedsManualReview=1 |
| `intel/indicator/feeds/permissions/add` | 1 | NeedsManualReview=1 |
| `intel/indicator/feeds/permissions/createProvider` | 1 | ExcludedByPolicy=1 |
| `intel/indicator/feeds/permissions/remove` | 1 | NeedsManualReview=1 |
| `intel/indicator/feeds/permissions/view` | 1 | NeedsManualReview=1 |
| `intel/indicator/feeds/snapshot` | 1 | ExcludedByPolicy=1 |
| `intel/indicator/feeds/uploads` | 1 | ExcludedByPolicy=1 |
| `intel/ip` | 1 | ExcludedByPolicy=1 |
| `intel/ip/lists` | 1 | ExcludedByPolicy=1 |
| `intel/miscategorization` | 1 | ExcludedByPolicy=1 |
| `intel/sinkholes` | 5 | ExcludedByPolicy=5 |
| `intel/sinkholes/ingresses` | 5 | ExcludedByPolicy=5 |
| `intel/url` | 1 | ExcludedByPolicy=1 |
| `intel/whois` | 1 | ExcludedByPolicy=1 |
| `internal/submit` | 1 | NeedsManualReview=1 |
| `invoices` | 1 | NeedsManualReview=1 |
| `ips` | 1 | ExcludedByPolicy=1 |
| `keyless/certificates` | 5 | ExcludedByPolicy=5 |
| `leaked/credential/checks` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `leaked/credential/checks/detections` | 5 | ExcludedByPolicy=5 |
| `live` | 1 | ExcludedByPolicy=1 |
| `load/balancers` | 12 | ExcludedByPolicy=12 |
| `load/balancers/monitor/groups` | 6 | ExcludedByPolicy=6 |
| `load/balancers/monitor/groups/references` | 1 | ExcludedByPolicy=1 |
| `load/balancers/monitors` | 6 | ExcludedByPolicy=6 |
| `load/balancers/monitors/preview` | 1 | NeedsManualReview=1 |
| `load/balancers/monitors/references` | 1 | ExcludedByPolicy=1 |
| `load/balancers/pools` | 7 | ExcludedByPolicy=7 |
| `load/balancers/pools/health` | 1 | ExcludedByPolicy=1 |
| `load/balancers/pools/preview` | 1 | NeedsManualReview=1 |
| `load/balancers/pools/references` | 1 | ExcludedByPolicy=1 |
| `load/balancers/preview` | 1 | NeedsManualReview=1 |
| `load/balancers/regions` | 2 | ExcludedByPolicy=2 |
| `load/balancers/search` | 1 | NeedsManualReview=1 |
| `load/balancers/usage` | 1 | ExcludedByPolicy=1 |
| `logpush/datasets/fields` | 2 | ExcludedByPolicy=2 |
| `logpush/datasets/jobs` | 2 | ExcludedByPolicy=2 |
| `logpush/edge/jobs` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `logpush/jobs` | 10 | ExcludedByPolicy=6; NeedsManualReview=4 |
| `logpush/ownership` | 2 | NeedsManualReview=2 |
| `logpush/ownership/validate` | 2 | NeedsManualReview=2 |
| `logpush/transformers` | 5 | ExcludedByPolicy=3; NeedsManualReview=2 |
| `logpush/transformers/content` | 1 | ExcludedByPolicy=1 |
| `logpush/transformers/preview` | 1 | NeedsManualReview=1 |
| `logpush/transformers/versions` | 1 | ExcludedByPolicy=1 |
| `logpush/validate/destination` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `logpush/validate/destination/exists` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `logpush/validate/origin` | 2 | NeedsManualReview=2 |
| `logs/audit` | 1 | ExcludedByPolicy=1 |
| `logs/audit/history` | 1 | ExcludedByPolicy=1 |
| `logs/audit/product/categories` | 1 | ExcludedByPolicy=1 |
| `logs/control/cmb/config` | 3 | ExcludedByPolicy=2; NeedsManualReview=1 |
| `logs/control/retention/flag` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `logs/explorer/datasets` | 10 | ExcludedByPolicy=10 |
| `logs/explorer/datasets/available` | 2 | ExcludedByPolicy=2 |
| `logs/explorer/query/sql` | 4 | ExcludedByPolicy=2; NeedsManualReview=2 |
| `logs/list` | 1 | ExcludedByPolicy=1 |
| `logs/rayids` | 1 | ExcludedByPolicy=1 |
| `logs/received` | 1 | ExcludedByPolicy=1 |
| `logs/received/fields` | 1 | ExcludedByPolicy=1 |
| `logs/retrieve` | 1 | NeedsManualReview=1 |
| `magic/advanced/dns/protection/configs/dns/protection/rules` | 6 | ExcludedByPolicy=6 |
| `magic/advanced/tcp/protection/configs/allowlist` | 6 | UnsupportedProjectionCapability=6 |
| `magic/advanced/tcp/protection/configs/prefixes` | 6 | ExcludedByPolicy=6 |
| `magic/advanced/tcp/protection/configs/prefixes/bulk` | 1 | ExcludedByPolicy=1 |
| `magic/advanced/tcp/protection/configs/syn/protection/filters` | 6 | ExcludedByPolicy=6 |
| `magic/advanced/tcp/protection/configs/syn/protection/rules` | 6 | ExcludedByPolicy=6 |
| `magic/advanced/tcp/protection/configs/tcp/flow/protection/filters` | 6 | ExcludedByPolicy=6 |
| `magic/advanced/tcp/protection/configs/tcp/flow/protection/rules` | 6 | ExcludedByPolicy=6 |
| `magic/advanced/tcp/protection/configs/tcp/protection/status` | 2 | ExcludedByPolicy=2 |
| `magic/apps` | 5 | ExcludedByPolicy=4; NeedsManualReview=1 |
| `magic/bgp/filter/profiles` | 5 | ExcludedByPolicy=5 |
| `magic/bgp/settings` | 2 | ExcludedByPolicy=2 |
| `magic/cf/interconnects` | 4 | ExcludedByPolicy=4 |
| `magic/cf1/sites` | 5 | ExcludedByPolicy=5 |
| `magic/cf1/sites/ramps` | 4 | ExcludedByPolicy=4 |
| `magic/cloud/catalog/syncs` | 6 | ExcludedByPolicy=5; NeedsManualReview=1 |
| `magic/cloud/catalog/syncs/prebuilt/policies` | 1 | ExcludedByPolicy=1 |
| `magic/cloud/catalog/syncs/refresh` | 1 | NeedsManualReview=1 |
| `magic/cloud/onramps` | 6 | ExcludedByPolicy=5; NeedsManualReview=1 |
| `magic/cloud/onramps/apply` | 1 | NeedsManualReview=1 |
| `magic/cloud/onramps/export` | 1 | ExcludedByPolicy=1 |
| `magic/cloud/onramps/magic/wan/address/space` | 3 | ExcludedByPolicy=2; NeedsManualReview=1 |
| `magic/cloud/onramps/plan` | 1 | NeedsManualReview=1 |
| `magic/cloud/providers` | 6 | ExcludedByPolicy=5; NeedsManualReview=1 |
| `magic/cloud/providers/discover` | 2 | NeedsManualReview=2 |
| `magic/cloud/providers/initial/setup` | 1 | NeedsManualReview=1 |
| `magic/cloud/resources` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `magic/cloud/resources/export` | 1 | ExcludedByPolicy=1 |
| `magic/cloud/resources/policy/preview` | 1 | NeedsManualReview=1 |
| `magic/connectors` | 6 | ExcludedByPolicy=6 |
| `magic/connectors/interrupts` | 2 | ExcludedByPolicy=2 |
| `magic/connectors/telemetry/events` | 2 | ExcludedByPolicy=2 |
| `magic/connectors/telemetry/events/latest` | 1 | ExcludedByPolicy=1 |
| `magic/connectors/telemetry/snapshots` | 2 | ExcludedByPolicy=2 |
| `magic/connectors/telemetry/snapshots/latest` | 1 | ExcludedByPolicy=1 |
| `magic/gre/tunnels` | 6 | ExcludedByPolicy=6 |
| `magic/ipsec/tunnels` | 6 | ExcludedByPolicy=6 |
| `magic/ipsec/tunnels/psk` | 1 | NeedsManualReview=1 |
| `magic/ipsec/tunnels/psk/generate` | 1 | NeedsManualReview=1 |
| `magic/redundancy/groups` | 5 | ExcludedByPolicy=5 |
| `magic/routes` | 7 | ExcludedByPolicy=7 |
| `magic/sites` | 6 | ExcludedByPolicy=6 |
| `magic/sites/acls` | 6 | ExcludedByPolicy=6 |
| `magic/sites/app/configs` | 5 | ExcludedByPolicy=4; NeedsManualReview=1 |
| `magic/sites/lans` | 6 | ExcludedByPolicy=6 |
| `magic/sites/netflow/config` | 5 | ExcludedByPolicy=5 |
| `magic/sites/wans` | 6 | ExcludedByPolicy=6 |
| `managed/headers` | 3 | ExcludedByPolicy=3 |
| `media/usage` | 2 | ExcludedByPolicy=2 |
| `members` | 5 | ExcludedByPolicy=3; NeedsManualReview=2 |
| `memberships` | 4 | ExcludedByPolicy=4 |
| `mnm/config` | 5 | ExcludedByPolicy=5 |
| `mnm/config/full` | 1 | ExcludedByPolicy=1 |
| `mnm/rules` | 6 | ExcludedByPolicy=6 |
| `mnm/rules/advertisement` | 1 | ExcludedByPolicy=1 |
| `mnm/rules/bulk` | 2 | ExcludedByPolicy=2 |
| `mnm/vpc/flows/token` | 1 | NeedsManualReview=1 |
| `moq/relays` | 5 | ExcludedByPolicy=5 |
| `moq/relays/tokens` | 3 | ExcludedByPolicy=3 |
| `move` | 2 | NeedsManualReview=2 |
| `mtls/certificates` | 4 | ExcludedByPolicy=3; NeedsManualReview=1 |
| `mtls/certificates/associations` | 1 | ExcludedByPolicy=1 |
| `oauth/clients` | 5 | ExcludedByPolicy=5 |
| `oauth/clients/rotate/secret` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `oauth/scopes` | 1 | ExcludedByPolicy=1 |
| `one/applications` | 2 | ExcludedByPolicy=2 |
| `one/applications/auth/methods` | 1 | ExcludedByPolicy=1 |
| `one/applications/setup/flows` | 1 | ExcludedByPolicy=1 |
| `one/integrations` | 5 | ExcludedByPolicy=3; UnsupportedRuntimeCapability=2 |
| `one/integrations/pause` | 1 | NeedsManualReview=1 |
| `one/integrations/resume` | 1 | NeedsManualReview=1 |
| `organizations` | 7 | ExcludedByPolicy=5; NeedsManualReview=2 |
| `organizations/billable/usage` | 1 | ExcludedByPolicy=1 |
| `organizations/logs/audit` | 1 | ExcludedByPolicy=1 |
| `organizations/logs/audit/history` | 1 | ExcludedByPolicy=1 |
| `organizations/members` | 4 | ExcludedByPolicy=3; NeedsManualReview=1 |
| `organizations/members:batchCreate` | 1 | ExcludedByPolicy=1 |
| `organizations/profile` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `organizations/shares` | 1 | ExcludedByPolicy=1 |
| `origin/cloud/regions` | 4 | ExcludedByPolicy=3; NeedsManualReview=1 |
| `origin/cloud/regions/batch` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `origin/cloud/regions/supported/regions` | 1 | NeedsManualReview=1 |
| `origin/tls/client/auth` | 4 | ExcludedByPolicy=3; NeedsManualReview=1 |
| `origin/tls/client/auth/hostnames` | 3 | ExcludedByPolicy=2; NeedsManualReview=1 |
| `origin/tls/client/auth/hostnames/certificates` | 4 | ExcludedByPolicy=3; NeedsManualReview=1 |
| `origin/tls/client/auth/settings` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `page/shield` | 2 | ExcludedByPolicy=2 |
| `page/shield/connections` | 2 | ExcludedByPolicy=2 |
| `page/shield/cookies` | 2 | ExcludedByPolicy=2 |
| `page/shield/policies` | 5 | ExcludedByPolicy=5 |
| `page/shield/scripts` | 2 | ExcludedByPolicy=2 |
| `pagerules` | 6 | ExcludedByPolicy=6 |
| `pagerules/settings` | 1 | ExcludedByPolicy=1 |
| `pages/assets/check/missing` | 1 | NeedsManualReview=1 |
| `pages/assets/upload` | 1 | NeedsManualReview=1 |
| `pages/assets/upsert/hashes` | 1 | NeedsManualReview=1 |
| `pages/projects` | 5 | ExcludedByPolicy=5 |
| `pages/projects/deployments` | 4 | ExcludedByPolicy=4 |
| `pages/projects/deployments/history/logs` | 1 | ExcludedByPolicy=1 |
| `pages/projects/deployments/retry` | 1 | NeedsManualReview=1 |
| `pages/projects/deployments/rollback` | 1 | NeedsManualReview=1 |
| `pages/projects/deployments/tails` | 2 | ExcludedByPolicy=2 |
| `pages/projects/domains` | 5 | ExcludedByPolicy=4; NeedsManualReview=1 |
| `pages/projects/purge/build/cache` | 1 | NeedsManualReview=1 |
| `pages/projects/source` | 2 | NeedsManualReview=2 |
| `pages/projects/upload/token` | 1 | ExcludedByPolicy=1 |
| `pay/bad/debt` | 1 | NeedsManualReview=1 |
| `pay/invoice` | 1 | NeedsManualReview=1 |
| `pay/per/crawl/can/be/enabled` | 1 | ExcludedByPolicy=1 |
| `pay/per/crawl/configuration` | 3 | ExcludedByPolicy=3 |
| `pay/per/crawl/crawler/stripe` | 3 | ExcludedByPolicy=3 |
| `pay/per/crawl/crawlers` | 1 | ExcludedByPolicy=1 |
| `pay/per/crawl/publisher/stripe` | 3 | ExcludedByPolicy=3 |
| `pay/per/crawl/signature/link` | 1 | ExcludedByPolicy=1 |
| `pay/per/crawl/terms` | 1 | ExcludedByPolicy=1 |
| `pay/per/crawl/terms/signature` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `pay/per/crawl/zones/can/be/enabled` | 1 | NeedsManualReview=1 |
| `pay/per/crawl/zones/can/be/enabled/query` | 1 | NeedsManualReview=1 |
| `payment/methods` | 5 | ExcludedByPolicy=5 |
| `payment/methods/set/as/default` | 1 | NeedsManualReview=1 |
| `pcaps` | 3 | ExcludedByPolicy=3 |
| `pcaps/download` | 1 | NeedsManualReview=1 |
| `pcaps/ownership` | 3 | ExcludedByPolicy=2; NeedsManualReview=1 |
| `pcaps/ownership/validate` | 1 | NeedsManualReview=1 |
| `pcaps/stop` | 1 | NeedsManualReview=1 |
| `pipelines` | 5 | ExcludedByPolicy=3; NeedsManualReview=2 |
| `pipelines/v1/pipelines` | 4 | ExcludedByPolicy=3; NeedsManualReview=1 |
| `pipelines/v1/sinks` | 4 | ExcludedByPolicy=3; NeedsManualReview=1 |
| `pipelines/v1/streams` | 5 | ExcludedByPolicy=4; NeedsManualReview=1 |
| `pipelines/v1/validate/sql` | 1 | NeedsManualReview=1 |
| `precursor` | 2 | ExcludedByPolicy=2 |
| `profile` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `purge/cache` | 1 | NeedsManualReview=1 |
| `queues` | 6 | ExcludedByPolicy=6 |
| `queues/consumers` | 5 | ExcludedByPolicy=5 |
| `queues/messages` | 1 | NeedsManualReview=1 |
| `queues/messages/ack` | 1 | NeedsManualReview=1 |
| `queues/messages/batch` | 1 | NeedsManualReview=1 |
| `queues/messages/extend` | 1 | NeedsManualReview=1 |
| `queues/messages/peek` | 1 | NeedsManualReview=1 |
| `queues/messages/preview` | 1 | NeedsManualReview=1 |
| `queues/messages/preview/ack` | 1 | NeedsManualReview=1 |
| `queues/messages/pull` | 1 | NeedsManualReview=1 |
| `queues/messages/purge` | 1 | NeedsManualReview=1 |
| `queues/metrics` | 1 | ExcludedByPolicy=1 |
| `queues/purge` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `r2/buckets` | 6 | ExcludedByPolicy=6 |
| `r2/buckets/cors` | 3 | ExcludedByPolicy=2; NeedsManualReview=1 |
| `r2/buckets/domains/custom` | 5 | ExcludedByPolicy=4; NeedsManualReview=1 |
| `r2/buckets/domains/managed` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `r2/buckets/jobs` | 2 | ExcludedByPolicy=2 |
| `r2/buckets/lifecycle` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `r2/buckets/local/uploads` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `r2/buckets/lock` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `r2/buckets/objects` | 5 | ExcludedByPolicy=4; NeedsManualReview=1 |
| `r2/buckets/sippy` | 3 | ExcludedByPolicy=2; NeedsManualReview=1 |
| `r2/catalog` | 2 | ExcludedByPolicy=2 |
| `r2/catalog/credential` | 1 | NeedsManualReview=1 |
| `r2/catalog/delete` | 1 | ExcludedByPolicy=1 |
| `r2/catalog/disable` | 1 | NeedsManualReview=1 |
| `r2/catalog/enable` | 1 | NeedsManualReview=1 |
| `r2/catalog/maintenance/configs` | 2 | ExcludedByPolicy=2 |
| `r2/catalog/namespaces` | 1 | ExcludedByPolicy=1 |
| `r2/catalog/namespaces/tables` | 2 | ExcludedByPolicy=2 |
| `r2/catalog/namespaces/tables/maintenance/configs` | 2 | ExcludedByPolicy=2 |
| `r2/metrics` | 1 | ExcludedByPolicy=1 |
| `r2/temp/access/credentials` | 1 | ExcludedByPolicy=1 |
| `radar/agent/readiness/summary` | 1 | ExcludedByPolicy=1 |
| `radar/ai/bots/summary` | 1 | ExcludedByPolicy=1 |
| `radar/ai/bots/summary/user/agent` | 1 | ExcludedByPolicy=1 |
| `radar/ai/bots/timeseries` | 1 | ExcludedByPolicy=1 |
| `radar/ai/bots/timeseries/groups` | 1 | ExcludedByPolicy=1 |
| `radar/ai/bots/timeseries/groups/user/agent` | 1 | ExcludedByPolicy=1 |
| `radar/ai/inference/summary` | 1 | ExcludedByPolicy=1 |
| `radar/ai/inference/summary/model` | 1 | ExcludedByPolicy=1 |
| `radar/ai/inference/summary/task` | 1 | ExcludedByPolicy=1 |
| `radar/ai/inference/timeseries/groups` | 1 | ExcludedByPolicy=1 |
| `radar/ai/inference/timeseries/groups/model` | 1 | ExcludedByPolicy=1 |
| `radar/ai/inference/timeseries/groups/task` | 1 | ExcludedByPolicy=1 |
| `radar/ai/markdown/for/agents/summary` | 1 | ExcludedByPolicy=1 |
| `radar/ai/markdown/for/agents/timeseries` | 1 | ExcludedByPolicy=1 |
| `radar/annotations` | 1 | ExcludedByPolicy=1 |
| `radar/annotations/outages` | 1 | ExcludedByPolicy=1 |
| `radar/annotations/outages/locations` | 1 | ExcludedByPolicy=1 |
| `radar/as112/summary` | 1 | ExcludedByPolicy=1 |
| `radar/as112/summary/dnssec` | 1 | ExcludedByPolicy=1 |
| `radar/as112/summary/edns` | 1 | ExcludedByPolicy=1 |
| `radar/as112/summary/ip/version` | 1 | ExcludedByPolicy=1 |
| `radar/as112/summary/protocol` | 1 | ExcludedByPolicy=1 |
| `radar/as112/summary/query/type` | 1 | ExcludedByPolicy=1 |
| `radar/as112/summary/response/codes` | 1 | ExcludedByPolicy=1 |
| `radar/as112/timeseries` | 1 | ExcludedByPolicy=1 |
| `radar/as112/timeseries/groups` | 1 | ExcludedByPolicy=1 |
| `radar/as112/timeseries/groups/dnssec` | 1 | ExcludedByPolicy=1 |
| `radar/as112/timeseries/groups/edns` | 1 | ExcludedByPolicy=1 |
| `radar/as112/timeseries/groups/ip/version` | 1 | ExcludedByPolicy=1 |
| `radar/as112/timeseries/groups/protocol` | 1 | ExcludedByPolicy=1 |
| `radar/as112/timeseries/groups/query/type` | 1 | ExcludedByPolicy=1 |
| `radar/as112/timeseries/groups/response/codes` | 1 | ExcludedByPolicy=1 |
| `radar/as112/top/locations` | 1 | ExcludedByPolicy=1 |
| `radar/as112/top/locations/dnssec` | 1 | ExcludedByPolicy=1 |
| `radar/as112/top/locations/edns` | 1 | ExcludedByPolicy=1 |
| `radar/as112/top/locations/ip/version` | 1 | ExcludedByPolicy=1 |
| `radar/attacks/layer3/summary` | 1 | ExcludedByPolicy=1 |
| `radar/attacks/layer3/summary/bitrate` | 1 | ExcludedByPolicy=1 |
| `radar/attacks/layer3/summary/duration` | 1 | ExcludedByPolicy=1 |
| `radar/attacks/layer3/summary/industry` | 1 | ExcludedByPolicy=1 |
| `radar/attacks/layer3/summary/ip/version` | 1 | ExcludedByPolicy=1 |
| `radar/attacks/layer3/summary/protocol` | 1 | ExcludedByPolicy=1 |
| `radar/attacks/layer3/summary/vector` | 1 | ExcludedByPolicy=1 |
| `radar/attacks/layer3/summary/vertical` | 1 | ExcludedByPolicy=1 |
| `radar/attacks/layer3/timeseries` | 1 | ExcludedByPolicy=1 |
| `radar/attacks/layer3/timeseries/groups` | 1 | ExcludedByPolicy=1 |
| `radar/attacks/layer3/timeseries/groups/bitrate` | 1 | ExcludedByPolicy=1 |
| `radar/attacks/layer3/timeseries/groups/duration` | 1 | ExcludedByPolicy=1 |
| `radar/attacks/layer3/timeseries/groups/industry` | 1 | ExcludedByPolicy=1 |
| `radar/attacks/layer3/timeseries/groups/ip/version` | 1 | ExcludedByPolicy=1 |
| `radar/attacks/layer3/timeseries/groups/protocol` | 1 | ExcludedByPolicy=1 |
| `radar/attacks/layer3/timeseries/groups/vector` | 1 | ExcludedByPolicy=1 |
| `radar/attacks/layer3/timeseries/groups/vertical` | 1 | ExcludedByPolicy=1 |
| `radar/attacks/layer3/top/attacks` | 1 | ExcludedByPolicy=1 |
| `radar/attacks/layer3/top/industry` | 1 | ExcludedByPolicy=1 |
| `radar/attacks/layer3/top/locations/origin` | 1 | ExcludedByPolicy=1 |
| `radar/attacks/layer3/top/locations/target` | 1 | ExcludedByPolicy=1 |
| `radar/attacks/layer3/top/vertical` | 1 | ExcludedByPolicy=1 |
| `radar/attacks/layer7/summary` | 1 | ExcludedByPolicy=1 |
| `radar/attacks/layer7/summary/http/method` | 1 | ExcludedByPolicy=1 |
| `radar/attacks/layer7/summary/http/version` | 1 | ExcludedByPolicy=1 |
| `radar/attacks/layer7/summary/industry` | 1 | ExcludedByPolicy=1 |
| `radar/attacks/layer7/summary/ip/version` | 1 | ExcludedByPolicy=1 |
| `radar/attacks/layer7/summary/managed/rules` | 1 | ExcludedByPolicy=1 |
| `radar/attacks/layer7/summary/mitigation/product` | 1 | ExcludedByPolicy=1 |
| `radar/attacks/layer7/summary/vertical` | 1 | ExcludedByPolicy=1 |
| `radar/attacks/layer7/timeseries` | 1 | ExcludedByPolicy=1 |
| `radar/attacks/layer7/timeseries/groups` | 1 | ExcludedByPolicy=1 |
| `radar/attacks/layer7/timeseries/groups/http/method` | 1 | ExcludedByPolicy=1 |
| `radar/attacks/layer7/timeseries/groups/http/version` | 1 | ExcludedByPolicy=1 |
| `radar/attacks/layer7/timeseries/groups/industry` | 1 | ExcludedByPolicy=1 |
| `radar/attacks/layer7/timeseries/groups/ip/version` | 1 | ExcludedByPolicy=1 |
| `radar/attacks/layer7/timeseries/groups/managed/rules` | 1 | ExcludedByPolicy=1 |
| `radar/attacks/layer7/timeseries/groups/mitigation/product` | 1 | ExcludedByPolicy=1 |
| `radar/attacks/layer7/timeseries/groups/vertical` | 1 | ExcludedByPolicy=1 |
| `radar/attacks/layer7/top/ases/origin` | 1 | ExcludedByPolicy=1 |
| `radar/attacks/layer7/top/attacks` | 1 | ExcludedByPolicy=1 |
| `radar/attacks/layer7/top/industry` | 1 | ExcludedByPolicy=1 |
| `radar/attacks/layer7/top/locations/origin` | 1 | ExcludedByPolicy=1 |
| `radar/attacks/layer7/top/locations/target` | 1 | ExcludedByPolicy=1 |
| `radar/attacks/layer7/top/vertical` | 1 | ExcludedByPolicy=1 |
| `radar/bgp/hijacks/events` | 1 | ExcludedByPolicy=1 |
| `radar/bgp/ips/timeseries` | 1 | ExcludedByPolicy=1 |
| `radar/bgp/ips/top/ases` | 1 | ExcludedByPolicy=1 |
| `radar/bgp/leaks/events` | 1 | ExcludedByPolicy=1 |
| `radar/bgp/routes/ases` | 1 | ExcludedByPolicy=1 |
| `radar/bgp/routes/moas` | 1 | ExcludedByPolicy=1 |
| `radar/bgp/routes/paths` | 1 | ExcludedByPolicy=1 |
| `radar/bgp/routes/pfx2as` | 1 | ExcludedByPolicy=1 |
| `radar/bgp/routes/realtime` | 1 | ExcludedByPolicy=1 |
| `radar/bgp/routes/stats` | 1 | ExcludedByPolicy=1 |
| `radar/bgp/routes/upstreams/timeseries` | 1 | ExcludedByPolicy=1 |
| `radar/bgp/rpki/aspa/changes` | 1 | ExcludedByPolicy=1 |
| `radar/bgp/rpki/aspa/snapshot` | 1 | ExcludedByPolicy=1 |
| `radar/bgp/rpki/aspa/timeseries` | 1 | ExcludedByPolicy=1 |
| `radar/bgp/rpki/roas/timeseries` | 1 | ExcludedByPolicy=1 |
| `radar/bgp/timeseries` | 1 | ExcludedByPolicy=1 |
| `radar/bgp/top/ases` | 1 | ExcludedByPolicy=1 |
| `radar/bgp/top/ases/prefixes` | 1 | ExcludedByPolicy=1 |
| `radar/bgp/top/prefixes` | 1 | ExcludedByPolicy=1 |
| `radar/bots` | 2 | ExcludedByPolicy=2 |
| `radar/bots/crawlers/summary` | 1 | ExcludedByPolicy=1 |
| `radar/bots/crawlers/timeseries/groups` | 1 | ExcludedByPolicy=1 |
| `radar/bots/summary` | 1 | ExcludedByPolicy=1 |
| `radar/bots/timeseries` | 1 | ExcludedByPolicy=1 |
| `radar/bots/timeseries/groups` | 1 | ExcludedByPolicy=1 |
| `radar/ct/authorities` | 2 | ExcludedByPolicy=2 |
| `radar/ct/logs` | 2 | ExcludedByPolicy=2 |
| `radar/ct/summary` | 1 | ExcludedByPolicy=1 |
| `radar/ct/timeseries` | 1 | ExcludedByPolicy=1 |
| `radar/ct/timeseries/groups` | 1 | ExcludedByPolicy=1 |
| `radar/datasets` | 2 | ExcludedByPolicy=2 |
| `radar/datasets/download` | 1 | NeedsManualReview=1 |
| `radar/dns/summary` | 1 | ExcludedByPolicy=1 |
| `radar/dns/summary/cache/hit` | 1 | ExcludedByPolicy=1 |
| `radar/dns/summary/dnssec` | 1 | ExcludedByPolicy=1 |
| `radar/dns/summary/dnssec/aware` | 1 | ExcludedByPolicy=1 |
| `radar/dns/summary/dnssec/e2e` | 1 | ExcludedByPolicy=1 |
| `radar/dns/summary/ip/version` | 1 | ExcludedByPolicy=1 |
| `radar/dns/summary/matching/answer` | 1 | ExcludedByPolicy=1 |
| `radar/dns/summary/protocol` | 1 | ExcludedByPolicy=1 |
| `radar/dns/summary/query/type` | 1 | ExcludedByPolicy=1 |
| `radar/dns/summary/response/code` | 1 | ExcludedByPolicy=1 |
| `radar/dns/summary/response/ttl` | 1 | ExcludedByPolicy=1 |
| `radar/dns/timeseries` | 1 | ExcludedByPolicy=1 |
| `radar/dns/timeseries/groups` | 1 | ExcludedByPolicy=1 |
| `radar/dns/timeseries/groups/cache/hit` | 1 | ExcludedByPolicy=1 |
| `radar/dns/timeseries/groups/dnssec` | 1 | ExcludedByPolicy=1 |
| `radar/dns/timeseries/groups/dnssec/aware` | 1 | ExcludedByPolicy=1 |
| `radar/dns/timeseries/groups/dnssec/e2e` | 1 | ExcludedByPolicy=1 |
| `radar/dns/timeseries/groups/ip/version` | 1 | ExcludedByPolicy=1 |
| `radar/dns/timeseries/groups/matching/answer` | 1 | ExcludedByPolicy=1 |
| `radar/dns/timeseries/groups/protocol` | 1 | ExcludedByPolicy=1 |
| `radar/dns/timeseries/groups/query/type` | 1 | ExcludedByPolicy=1 |
| `radar/dns/timeseries/groups/response/code` | 1 | ExcludedByPolicy=1 |
| `radar/dns/timeseries/groups/response/ttl` | 1 | ExcludedByPolicy=1 |
| `radar/dns/top/ases` | 1 | ExcludedByPolicy=1 |
| `radar/dns/top/locations` | 1 | ExcludedByPolicy=1 |
| `radar/email/routing/summary` | 1 | ExcludedByPolicy=1 |
| `radar/email/routing/summary/arc` | 1 | ExcludedByPolicy=1 |
| `radar/email/routing/summary/dkim` | 1 | ExcludedByPolicy=1 |
| `radar/email/routing/summary/dmarc` | 1 | ExcludedByPolicy=1 |
| `radar/email/routing/summary/encrypted` | 1 | ExcludedByPolicy=1 |
| `radar/email/routing/summary/ip/version` | 1 | ExcludedByPolicy=1 |
| `radar/email/routing/summary/spf` | 1 | ExcludedByPolicy=1 |
| `radar/email/routing/timeseries/groups` | 1 | ExcludedByPolicy=1 |
| `radar/email/routing/timeseries/groups/arc` | 1 | ExcludedByPolicy=1 |
| `radar/email/routing/timeseries/groups/dkim` | 1 | ExcludedByPolicy=1 |
| `radar/email/routing/timeseries/groups/dmarc` | 1 | ExcludedByPolicy=1 |
| `radar/email/routing/timeseries/groups/encrypted` | 1 | ExcludedByPolicy=1 |
| `radar/email/routing/timeseries/groups/ip/version` | 1 | ExcludedByPolicy=1 |
| `radar/email/routing/timeseries/groups/spf` | 1 | ExcludedByPolicy=1 |
| `radar/email/security/summary` | 1 | ExcludedByPolicy=1 |
| `radar/email/security/summary/arc` | 1 | ExcludedByPolicy=1 |
| `radar/email/security/summary/dkim` | 1 | ExcludedByPolicy=1 |
| `radar/email/security/summary/dmarc` | 1 | ExcludedByPolicy=1 |
| `radar/email/security/summary/malicious` | 1 | ExcludedByPolicy=1 |
| `radar/email/security/summary/spam` | 1 | ExcludedByPolicy=1 |
| `radar/email/security/summary/spf` | 1 | ExcludedByPolicy=1 |
| `radar/email/security/summary/spoof` | 1 | ExcludedByPolicy=1 |
| `radar/email/security/summary/threat/category` | 1 | ExcludedByPolicy=1 |
| `radar/email/security/summary/tls/version` | 1 | ExcludedByPolicy=1 |
| `radar/email/security/timeseries/groups` | 1 | ExcludedByPolicy=1 |
| `radar/email/security/timeseries/groups/arc` | 1 | ExcludedByPolicy=1 |
| `radar/email/security/timeseries/groups/dkim` | 1 | ExcludedByPolicy=1 |
| `radar/email/security/timeseries/groups/dmarc` | 1 | ExcludedByPolicy=1 |
| `radar/email/security/timeseries/groups/malicious` | 1 | ExcludedByPolicy=1 |
| `radar/email/security/timeseries/groups/spam` | 1 | ExcludedByPolicy=1 |
| `radar/email/security/timeseries/groups/spf` | 1 | ExcludedByPolicy=1 |
| `radar/email/security/timeseries/groups/spoof` | 1 | ExcludedByPolicy=1 |
| `radar/email/security/timeseries/groups/threat/category` | 1 | ExcludedByPolicy=1 |
| `radar/email/security/timeseries/groups/tls/version` | 1 | ExcludedByPolicy=1 |
| `radar/email/security/top/tlds` | 1 | ExcludedByPolicy=1 |
| `radar/email/security/top/tlds/malicious` | 1 | ExcludedByPolicy=1 |
| `radar/email/security/top/tlds/spam` | 1 | ExcludedByPolicy=1 |
| `radar/email/security/top/tlds/spoof` | 1 | ExcludedByPolicy=1 |
| `radar/entities/asns` | 2 | ExcludedByPolicy=2 |
| `radar/entities/asns/as/set` | 1 | ExcludedByPolicy=1 |
| `radar/entities/asns/botnet/threat/feed` | 1 | ExcludedByPolicy=1 |
| `radar/entities/asns/ip` | 1 | ExcludedByPolicy=1 |
| `radar/entities/asns/rel` | 1 | ExcludedByPolicy=1 |
| `radar/entities/ip` | 1 | ExcludedByPolicy=1 |
| `radar/entities/locations` | 2 | ExcludedByPolicy=2 |
| `radar/geolocations` | 2 | ExcludedByPolicy=2 |
| `radar/http/summary` | 1 | ExcludedByPolicy=1 |
| `radar/http/summary/bot/class` | 1 | ExcludedByPolicy=1 |
| `radar/http/summary/device/type` | 1 | ExcludedByPolicy=1 |
| `radar/http/summary/http/protocol` | 1 | ExcludedByPolicy=1 |
| `radar/http/summary/http/version` | 1 | ExcludedByPolicy=1 |
| `radar/http/summary/ip/version` | 1 | ExcludedByPolicy=1 |
| `radar/http/summary/os` | 1 | ExcludedByPolicy=1 |
| `radar/http/summary/post/quantum` | 1 | ExcludedByPolicy=1 |
| `radar/http/summary/tls/version` | 1 | ExcludedByPolicy=1 |
| `radar/http/timeseries` | 1 | ExcludedByPolicy=1 |
| `radar/http/timeseries/groups` | 1 | ExcludedByPolicy=1 |
| `radar/http/timeseries/groups/bot/class` | 1 | ExcludedByPolicy=1 |
| `radar/http/timeseries/groups/browser` | 1 | ExcludedByPolicy=1 |
| `radar/http/timeseries/groups/browser/family` | 1 | ExcludedByPolicy=1 |
| `radar/http/timeseries/groups/device/type` | 1 | ExcludedByPolicy=1 |
| `radar/http/timeseries/groups/http/protocol` | 1 | ExcludedByPolicy=1 |
| `radar/http/timeseries/groups/http/version` | 1 | ExcludedByPolicy=1 |
| `radar/http/timeseries/groups/ip/version` | 1 | ExcludedByPolicy=1 |
| `radar/http/timeseries/groups/os` | 1 | ExcludedByPolicy=1 |
| `radar/http/timeseries/groups/post/quantum` | 1 | ExcludedByPolicy=1 |
| `radar/http/timeseries/groups/tls/version` | 1 | ExcludedByPolicy=1 |
| `radar/http/top/ases` | 1 | ExcludedByPolicy=1 |
| `radar/http/top/ases/bot/class` | 1 | ExcludedByPolicy=1 |
| `radar/http/top/ases/browser/family` | 1 | ExcludedByPolicy=1 |
| `radar/http/top/ases/device/type` | 1 | ExcludedByPolicy=1 |
| `radar/http/top/ases/http/protocol` | 1 | ExcludedByPolicy=1 |
| `radar/http/top/ases/http/version` | 1 | ExcludedByPolicy=1 |
| `radar/http/top/ases/ip/version` | 1 | ExcludedByPolicy=1 |
| `radar/http/top/ases/os` | 1 | ExcludedByPolicy=1 |
| `radar/http/top/ases/tls/version` | 1 | ExcludedByPolicy=1 |
| `radar/http/top/browser` | 1 | ExcludedByPolicy=1 |
| `radar/http/top/browser/family` | 1 | ExcludedByPolicy=1 |
| `radar/http/top/locations` | 1 | ExcludedByPolicy=1 |
| `radar/http/top/locations/bot/class` | 1 | ExcludedByPolicy=1 |
| `radar/http/top/locations/browser/family` | 1 | ExcludedByPolicy=1 |
| `radar/http/top/locations/device/type` | 1 | ExcludedByPolicy=1 |
| `radar/http/top/locations/http/protocol` | 1 | ExcludedByPolicy=1 |
| `radar/http/top/locations/http/version` | 1 | ExcludedByPolicy=1 |
| `radar/http/top/locations/ip/version` | 1 | ExcludedByPolicy=1 |
| `radar/http/top/locations/os` | 1 | ExcludedByPolicy=1 |
| `radar/http/top/locations/tls/version` | 1 | ExcludedByPolicy=1 |
| `radar/leaked/credential/checks/summary` | 1 | ExcludedByPolicy=1 |
| `radar/leaked/credential/checks/summary/bot/class` | 1 | ExcludedByPolicy=1 |
| `radar/leaked/credential/checks/summary/compromised` | 1 | ExcludedByPolicy=1 |
| `radar/leaked/credential/checks/timeseries/groups` | 1 | ExcludedByPolicy=1 |
| `radar/leaked/credential/checks/timeseries/groups/bot/class` | 1 | ExcludedByPolicy=1 |
| `radar/leaked/credential/checks/timeseries/groups/compromised` | 1 | ExcludedByPolicy=1 |
| `radar/netflows/summary` | 2 | ExcludedByPolicy=2 |
| `radar/netflows/timeseries` | 1 | ExcludedByPolicy=1 |
| `radar/netflows/timeseries/groups` | 1 | ExcludedByPolicy=1 |
| `radar/netflows/top/ases` | 1 | ExcludedByPolicy=1 |
| `radar/netflows/top/locations` | 1 | ExcludedByPolicy=1 |
| `radar/origins` | 2 | ExcludedByPolicy=2 |
| `radar/origins/summary` | 1 | ExcludedByPolicy=1 |
| `radar/origins/timeseries` | 1 | ExcludedByPolicy=1 |
| `radar/origins/timeseries/groups` | 1 | ExcludedByPolicy=1 |
| `radar/post/quantum/origin/summary` | 1 | ExcludedByPolicy=1 |
| `radar/post/quantum/origin/timeseries/groups` | 1 | ExcludedByPolicy=1 |
| `radar/post/quantum/tls/support` | 1 | ExcludedByPolicy=1 |
| `radar/quality/iqi/summary` | 1 | ExcludedByPolicy=1 |
| `radar/quality/iqi/timeseries/groups` | 1 | ExcludedByPolicy=1 |
| `radar/quality/speed/histogram` | 1 | ExcludedByPolicy=1 |
| `radar/quality/speed/summary` | 1 | ExcludedByPolicy=1 |
| `radar/quality/speed/top/ases` | 1 | ExcludedByPolicy=1 |
| `radar/quality/speed/top/locations` | 1 | ExcludedByPolicy=1 |
| `radar/ranking/domain` | 1 | ExcludedByPolicy=1 |
| `radar/ranking/internet/services/categories` | 1 | ExcludedByPolicy=1 |
| `radar/ranking/internet/services/timeseries/groups` | 1 | ExcludedByPolicy=1 |
| `radar/ranking/internet/services/top` | 1 | ExcludedByPolicy=1 |
| `radar/ranking/timeseries/groups` | 1 | ExcludedByPolicy=1 |
| `radar/ranking/top` | 1 | ExcludedByPolicy=1 |
| `radar/robots/txt/top/domain/categories` | 1 | ExcludedByPolicy=1 |
| `radar/robots/txt/top/user/agents/directive` | 1 | ExcludedByPolicy=1 |
| `radar/search/global` | 1 | ExcludedByPolicy=1 |
| `radar/tcp/resets/timeouts/summary` | 1 | ExcludedByPolicy=1 |
| `radar/tcp/resets/timeouts/timeseries/groups` | 1 | ExcludedByPolicy=1 |
| `radar/tlds` | 2 | ExcludedByPolicy=2 |
| `radar/tlds/performance/summary` | 1 | ExcludedByPolicy=1 |
| `radar/tlds/performance/timeseries/groups` | 1 | ExcludedByPolicy=1 |
| `radar/traffic/anomalies` | 1 | ExcludedByPolicy=1 |
| `radar/traffic/anomalies/locations` | 1 | ExcludedByPolicy=1 |
| `radar/verified/bots/top/bots` | 1 | ExcludedByPolicy=1 |
| `radar/verified/bots/top/categories` | 1 | ExcludedByPolicy=1 |
| `rate/limit/analytics` | 1 | ExcludedByPolicy=1 |
| `rate/limits` | 5 | ExcludedByPolicy=5 |
| `ready` | 1 | ExcludedByPolicy=1 |
| `realtime/kit/analytics/daywise` | 1 | ExcludedByPolicy=1 |
| `realtime/kit/analytics/livestreams/daywise` | 1 | ExcludedByPolicy=1 |
| `realtime/kit/analytics/livestreams/overall` | 1 | ExcludedByPolicy=1 |
| `realtime/kit/apps` | 3 | ExcludedByPolicy=3 |
| `realtime/kit/livestreams` | 3 | ExcludedByPolicy=2; NeedsManualReview=1 |
| `realtime/kit/livestreams/active/livestream/session` | 1 | ExcludedByPolicy=1 |
| `realtime/kit/livestreams/sessions` | 1 | ExcludedByPolicy=1 |
| `realtime/kit/meetings` | 5 | ExcludedByPolicy=4; NeedsManualReview=1 |
| `realtime/kit/meetings/active/livestream` | 1 | ExcludedByPolicy=1 |
| `realtime/kit/meetings/active/livestream/stop` | 1 | NeedsManualReview=1 |
| `realtime/kit/meetings/active/session` | 1 | ExcludedByPolicy=1 |
| `realtime/kit/meetings/active/session/kick` | 1 | NeedsManualReview=1 |
| `realtime/kit/meetings/active/session/kick/all` | 1 | NeedsManualReview=1 |
| `realtime/kit/meetings/active/session/mute` | 1 | NeedsManualReview=1 |
| `realtime/kit/meetings/active/session/mute/all` | 1 | NeedsManualReview=1 |
| `realtime/kit/meetings/active/session/poll` | 1 | ExcludedByPolicy=1 |
| `realtime/kit/meetings/livestream` | 1 | ExcludedByPolicy=1 |
| `realtime/kit/meetings/livestreams` | 1 | NeedsManualReview=1 |
| `realtime/kit/meetings/participants` | 6 | ExcludedByPolicy=4; NeedsManualReview=2 |
| `realtime/kit/meetings/participants/token` | 1 | NeedsManualReview=1 |
| `realtime/kit/presets` | 6 | ExcludedByPolicy=4; NeedsManualReview=2 |
| `realtime/kit/recordings` | 4 | ExcludedByPolicy=2; NeedsManualReview=2 |
| `realtime/kit/recordings/active/recording` | 1 | ExcludedByPolicy=1 |
| `realtime/kit/recordings/track` | 1 | NeedsManualReview=1 |
| `realtime/kit/sessions` | 2 | ExcludedByPolicy=2 |
| `realtime/kit/sessions/chat` | 1 | ExcludedByPolicy=1 |
| `realtime/kit/sessions/livestream/sessions` | 1 | ExcludedByPolicy=1 |
| `realtime/kit/sessions/participants` | 2 | ExcludedByPolicy=2 |
| `realtime/kit/sessions/peer/report` | 1 | ExcludedByPolicy=1 |
| `realtime/kit/sessions/summary` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `realtime/kit/sessions/transcript` | 1 | ExcludedByPolicy=1 |
| `realtime/kit/webhooks` | 6 | ExcludedByPolicy=4; NeedsManualReview=2 |
| `realtime/kit/webhooks/all` | 1 | ExcludedByPolicy=1 |
| `receipts/pdf` | 1 | ExcludedByPolicy=1 |
| `registrar/domain/check` | 1 | NeedsManualReview=1 |
| `registrar/domain/search` | 1 | NeedsManualReview=1 |
| `registrar/domains` | 3 | ExcludedByPolicy=3 |
| `registrar/extensions` | 2 | ExcludedByPolicy=2 |
| `registrar/registrations` | 4 | ExcludedByPolicy=4 |
| `registrar/registrations/registration/status` | 1 | ExcludedByPolicy=1 |
| `registrar/registrations/update/status` | 1 | ExcludedByPolicy=1 |
| `registrar/sandbox/domain/check` | 1 | NeedsManualReview=1 |
| `registrar/sandbox/domain/search` | 1 | NeedsManualReview=1 |
| `registrar/sandbox/extensions` | 2 | ExcludedByPolicy=2 |
| `registrar/sandbox/registrations` | 4 | ExcludedByPolicy=4 |
| `registrar/sandbox/registrations/registration/status` | 1 | ExcludedByPolicy=1 |
| `registrar/sandbox/registrations/update/status` | 1 | ExcludedByPolicy=1 |
| `reporting/industry` | 2 | ExcludedByPolicy=2 |
| `reporting/policies` | 2 | ExcludedByPolicy=2 |
| `reporting/reports` | 2 | ExcludedByPolicy=2 |
| `request/tracer/trace` | 1 | NeedsManualReview=1 |
| `resource/library/applications` | 5 | ExcludedByPolicy=5 |
| `resource/library/categories` | 2 | ExcludedByPolicy=2 |
| `roles` | 2 | ExcludedByPolicy=2 |
| `rules/lists` | 5 | UnsupportedProjectionCapability=5 |
| `rules/lists/bulk/operations` | 1 | ExcludedByPolicy=1 |
| `rules/lists/items` | 5 | UnsupportedProjectionCapability=5 |
| `rulesets` | 10 | ExcludedByPolicy=10 |
| `rulesets/phases/entrypoint` | 4 | ExcludedByPolicy=4 |
| `rulesets/phases/entrypoint/versions` | 4 | ExcludedByPolicy=4 |
| `rulesets/rules` | 6 | ExcludedByPolicy=6 |
| `rulesets/versions` | 6 | ExcludedByPolicy=6 |
| `rulesets/versions/by/tag` | 2 | ExcludedByPolicy=2 |
| `rum/site/info` | 4 | ExcludedByPolicy=4 |
| `rum/site/info/list` | 1 | ExcludedByPolicy=1 |
| `rum/site/info/site/tag/list` | 1 | ExcludedByPolicy=1 |
| `rum/site/info/validate` | 1 | NeedsManualReview=1 |
| `rum/site/info/zone/tag/list` | 1 | ExcludedByPolicy=1 |
| `rum/v2/rule` | 3 | ExcludedByPolicy=3 |
| `rum/v2/rules` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `schema/validation/schemas` | 5 | ExcludedByPolicy=5 |
| `schema/validation/schemas/hosts` | 1 | ExcludedByPolicy=1 |
| `schema/validation/schemas/operations` | 1 | NeedsManualReview=1 |
| `schema/validation/settings` | 3 | ExcludedByPolicy=3 |
| `schema/validation/settings/operations` | 5 | ExcludedByPolicy=5 |
| `scim/v2/Groups` | 5 | ExcludedByPolicy=3; UnsupportedRuntimeCapability=2 |
| `scim/v2/ResourceTypes` | 2 | ExcludedByPolicy=2 |
| `scim/v2/Schemas` | 2 | ExcludedByPolicy=2 |
| `scim/v2/ServiceProviderConfig` | 1 | ExcludedByPolicy=1 |
| `scim/v2/Users` | 6 | ExcludedByPolicy=3; NeedsManualReview=1; UnsupportedRuntimeCapability=2 |
| `secondary/dns/acls` | 5 | ExcludedByPolicy=5 |
| `secondary/dns/force/axfr` | 1 | NeedsManualReview=1 |
| `secondary/dns/incoming` | 4 | ExcludedByPolicy=4 |
| `secondary/dns/outgoing` | 4 | ExcludedByPolicy=4 |
| `secondary/dns/outgoing/disable` | 1 | NeedsManualReview=1 |
| `secondary/dns/outgoing/enable` | 1 | NeedsManualReview=1 |
| `secondary/dns/outgoing/force/notify` | 1 | NeedsManualReview=1 |
| `secondary/dns/outgoing/status` | 1 | ExcludedByPolicy=1 |
| `secondary/dns/peers` | 5 | ExcludedByPolicy=5 |
| `secondary/dns/tsigs` | 5 | ExcludedByPolicy=5 |
| `secrets/store/quota` | 1 | NeedsManualReview=1 |
| `secrets/store/stores` | 4 | ExcludedByPolicy=4 |
| `secrets/store/stores/secrets` | 6 | ExcludedByPolicy=6 |
| `secrets/store/stores/secrets/duplicate` | 1 | NeedsManualReview=1 |
| `security/center/insights` | 2 | ExcludedByPolicy=2 |
| `security/center/insights/audit/log` | 4 | ExcludedByPolicy=4 |
| `security/center/insights/class` | 2 | ExcludedByPolicy=2 |
| `security/center/insights/classification` | 2 | ExcludedByPolicy=2 |
| `security/center/insights/context` | 1 | ExcludedByPolicy=1 |
| `security/center/insights/dismiss` | 2 | NeedsManualReview=2 |
| `security/center/insights/scans` | 4 | ExcludedByPolicy=2; NeedsManualReview=2 |
| `security/center/insights/severity` | 2 | ExcludedByPolicy=2 |
| `security/center/insights/type` | 2 | ExcludedByPolicy=2 |
| `security/center/securitytxt` | 3 | ExcludedByPolicy=3 |
| `security/center/state` | 2 | ExcludedByPolicy=2 |
| `settings` | 4 | ExcludedByPolicy=4 |
| `settings/aegis` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `settings/auto/origin/tls/kex` | 2 | ExcludedByPolicy=2 |
| `settings/automatic/platform/optimization` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `settings/binary/ast` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `settings/csam/scanner/third/party` | 2 | ExcludedByPolicy=2 |
| `settings/fonts` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `settings/google/tag/gateway/config` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `settings/h2/prioritization` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `settings/image/resizing` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `settings/nel` | 2 | ExcludedByPolicy=2 |
| `settings/origin/h2/max/streams` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `settings/origin/max/http/version` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `settings/origin/tls/compliance/modes` | 4 | ExcludedByPolicy=2; NeedsManualReview=2 |
| `settings/rum` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `settings/speed/brain` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `settings/ssl/automatic/mode` | 2 | ExcludedByPolicy=2 |
| `settings/transformations` | 1 | ExcludedByPolicy=1 |
| `settings/transformations/allowed/origins` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `settings/transformations/c2pa` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `settings/transformations/config` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `settings/ut/billing` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `settings/zaraz/config` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `settings/zaraz/default` | 1 | ExcludedByPolicy=1 |
| `settings/zaraz/export` | 1 | ExcludedByPolicy=1 |
| `settings/zaraz/history` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `settings/zaraz/history/configs` | 1 | ExcludedByPolicy=1 |
| `settings/zaraz/publish` | 1 | NeedsManualReview=1 |
| `settings/zaraz/workflow` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `shares` | 5 | ExcludedByPolicy=5 |
| `shares/excluded/recipients` | 5 | ExcludedByPolicy=5 |
| `shares/recipients` | 5 | ExcludedByPolicy=5 |
| `shares/resources` | 5 | ExcludedByPolicy=5 |
| `signed/url` | 1 | ExcludedByPolicy=1 |
| `slurper/jobs` | 4 | ExcludedByPolicy=4 |
| `slurper/jobs/abort` | 1 | NeedsManualReview=1 |
| `slurper/jobs/abortAll` | 1 | NeedsManualReview=1 |
| `slurper/jobs/logs` | 1 | ExcludedByPolicy=1 |
| `slurper/jobs/pause` | 1 | NeedsManualReview=1 |
| `slurper/jobs/progress` | 1 | ExcludedByPolicy=1 |
| `slurper/jobs/resume` | 1 | NeedsManualReview=1 |
| `slurper/source/connectivity/precheck` | 1 | NeedsManualReview=1 |
| `slurper/target/connectivity/precheck` | 1 | ExcludedByPolicy=1 |
| `smart/shield` | 2 | ExcludedByPolicy=2 |
| `smart/shield/cache/reserve/clear` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `smart/shield/healthchecks` | 6 | ExcludedByPolicy=6 |
| `snippets` | 4 | ExcludedByPolicy=4 |
| `snippets/content` | 1 | ExcludedByPolicy=1 |
| `snippets/snippet/rules` | 3 | ExcludedByPolicy=3 |
| `spectrum/analytics/aggregate/current` | 1 | ExcludedByPolicy=1 |
| `spectrum/analytics/events/bytime` | 1 | ExcludedByPolicy=1 |
| `spectrum/analytics/events/summary` | 1 | ExcludedByPolicy=1 |
| `spectrum/apps` | 5 | ExcludedByPolicy=5 |
| `spectrum/protocols` | 1 | ExcludedByPolicy=1 |
| `speed/api/availabilities` | 1 | ExcludedByPolicy=1 |
| `speed/api/pages` | 1 | ExcludedByPolicy=1 |
| `speed/api/pages/tests` | 4 | ExcludedByPolicy=4 |
| `speed/api/pages/trend` | 1 | ExcludedByPolicy=1 |
| `speed/api/schedule` | 3 | ExcludedByPolicy=3 |
| `ssl/analyze` | 1 | NeedsManualReview=1 |
| `ssl/certificate/packs` | 4 | ExcludedByPolicy=3; NeedsManualReview=1 |
| `ssl/certificate/packs/order` | 1 | NeedsManualReview=1 |
| `ssl/certificate/packs/quota` | 1 | ExcludedByPolicy=1 |
| `ssl/recommendation` | 1 | NeedsManualReview=1 |
| `ssl/universal/settings` | 2 | ExcludedByPolicy=2 |
| `ssl/verification` | 2 | ExcludedByPolicy=2 |
| `sso/connectors` | 5 | ExcludedByPolicy=4; NeedsManualReview=1 |
| `sso/connectors/begin/verification` | 1 | NeedsManualReview=1 |
| `storage/kv/namespaces` | 5 | ExcludedByPolicy=3; NeedsManualReview=2 |
| `storage/kv/namespaces/bulk` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `storage/kv/namespaces/bulk/delete` | 1 | ExcludedByPolicy=1 |
| `storage/kv/namespaces/bulk/get` | 1 | ExcludedByPolicy=1 |
| `storage/kv/namespaces/keys` | 1 | ExcludedByPolicy=1 |
| `storage/kv/namespaces/metadata` | 1 | NeedsManualReview=1 |
| `storage/kv/namespaces/values` | 3 | ExcludedByPolicy=1; NeedsManualReview=2 |
| `stream` | 5 | ExcludedByPolicy=4; NeedsManualReview=1 |
| `stream/audio` | 3 | ExcludedByPolicy=3 |
| `stream/audio/copy` | 1 | NeedsManualReview=1 |
| `stream/captions` | 4 | ExcludedByPolicy=3; NeedsManualReview=1 |
| `stream/captions/generate` | 1 | NeedsManualReview=1 |
| `stream/captions/vtt` | 1 | ExcludedByPolicy=1 |
| `stream/clip` | 1 | NeedsManualReview=1 |
| `stream/copy` | 1 | NeedsManualReview=1 |
| `stream/direct/upload` | 1 | NeedsManualReview=1 |
| `stream/downloads` | 5 | ExcludedByPolicy=5 |
| `stream/embed` | 1 | NeedsManualReview=1 |
| `stream/keys` | 3 | ExcludedByPolicy=3 |
| `stream/live/inputs` | 5 | ExcludedByPolicy=4; NeedsManualReview=1 |
| `stream/live/inputs/disable` | 1 | NeedsManualReview=1 |
| `stream/live/inputs/enable` | 1 | NeedsManualReview=1 |
| `stream/live/inputs/outputs` | 4 | ExcludedByPolicy=4 |
| `stream/live/inputs/rotate/keys` | 1 | NeedsManualReview=1 |
| `stream/storage/usage` | 1 | NeedsManualReview=1 |
| `stream/token` | 1 | ExcludedByPolicy=1 |
| `stream/usage` | 2 | ExcludedByPolicy=2 |
| `stream/watermarks` | 4 | ExcludedByPolicy=4 |
| `stream/webhook` | 3 | ExcludedByPolicy=2; NeedsManualReview=1 |
| `subscription` | 4 | ExcludedByPolicy=4 |
| `subscriptions` | 8 | ExcludedByPolicy=8 |
| `subscriptions/action/append` | 1 | NeedsManualReview=1 |
| `subscriptions/cancel/downgrade` | 1 | NeedsManualReview=1 |
| `subscriptions/cancel/reason` | 2 | ExcludedByPolicy=2 |
| `tags` | 6 | ExcludedByPolicy=4; NeedsManualReview=2 |
| `tags/keys` | 1 | ExcludedByPolicy=1 |
| `tags/resources` | 1 | ExcludedByPolicy=1 |
| `tags/summary` | 1 | ExcludedByPolicy=1 |
| `tags/values` | 1 | ExcludedByPolicy=1 |
| `teamnet/routes` | 5 | ExcludedByPolicy=5 |
| `teamnet/routes/ip` | 1 | ExcludedByPolicy=1 |
| `teamnet/routes/network` | 3 | ExcludedByPolicy=3 |
| `teamnet/virtual/networks` | 5 | ExcludedByPolicy=5 |
| `tenants` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `tenants/account/types` | 1 | NeedsManualReview=1 |
| `tenants/custom/ns` | 3 | ExcludedByPolicy=2; NeedsManualReview=1 |
| `tenants/entitlements` | 1 | ExcludedByPolicy=1 |
| `tenants/memberships` | 1 | ExcludedByPolicy=1 |
| `token/validation/config` | 5 | ExcludedByPolicy=5 |
| `token/validation/config/credentials` | 2 | ExcludedByPolicy=2 |
| `token/validation/rules` | 5 | ExcludedByPolicy=5 |
| `token/validation/rules/bulk` | 2 | ExcludedByPolicy=2 |
| `token/validation/rules/preview` | 1 | NeedsManualReview=1 |
| `tokens` | 5 | ExcludedByPolicy=5 |
| `tokens/permission/groups` | 1 | ExcludedByPolicy=1 |
| `tokens/value` | 1 | NeedsManualReview=1 |
| `tokens/verify` | 1 | NeedsManualReview=1 |
| `triggers` | 4 | ExcludedByPolicy=2; NeedsManualReview=2 |
| `tunnels` | 1 | ExcludedByPolicy=1 |
| `url/normalization` | 3 | ExcludedByPolicy=3 |
| `urlscanner/response` | 1 | ExcludedByPolicy=1 |
| `urlscanner/scan` | 3 | ExcludedByPolicy=2; NeedsManualReview=1 |
| `urlscanner/scan/har` | 1 | ExcludedByPolicy=1 |
| `urlscanner/scan/screenshot` | 1 | ExcludedByPolicy=1 |
| `urlscanner/v2/bulk` | 1 | ExcludedByPolicy=1 |
| `urlscanner/v2/dom` | 1 | ExcludedByPolicy=1 |
| `urlscanner/v2/har` | 1 | ExcludedByPolicy=1 |
| `urlscanner/v2/responses` | 1 | ExcludedByPolicy=1 |
| `urlscanner/v2/result` | 1 | ExcludedByPolicy=1 |
| `urlscanner/v2/scan` | 1 | ExcludedByPolicy=1 |
| `urlscanner/v2/screenshots` | 1 | ExcludedByPolicy=1 |
| `urlscanner/v2/search` | 1 | NeedsManualReview=1 |
| `user` | 2 | ExcludedByPolicy=2 |
| `user/analytics/dashboard` | 1 | ExcludedByPolicy=1 |
| `user/audit/logs` | 1 | ExcludedByPolicy=1 |
| `user/billing/history` | 1 | ExcludedByPolicy=1 |
| `user/billing/profile` | 1 | ExcludedByPolicy=1 |
| `user/communication/preferences` | 2 | ExcludedByPolicy=2 |
| `user/firewall/access/rules/rules` | 5 | ExcludedByPolicy=5 |
| `user/invites` | 3 | ExcludedByPolicy=2; NeedsManualReview=1 |
| `user/load/balancers/monitors` | 6 | ExcludedByPolicy=6 |
| `user/load/balancers/monitors/preview` | 1 | NeedsManualReview=1 |
| `user/load/balancers/monitors/references` | 1 | ExcludedByPolicy=1 |
| `user/load/balancers/pools` | 7 | ExcludedByPolicy=7 |
| `user/load/balancers/pools/health` | 1 | ExcludedByPolicy=1 |
| `user/load/balancers/pools/preview` | 1 | NeedsManualReview=1 |
| `user/load/balancers/pools/references` | 1 | ExcludedByPolicy=1 |
| `user/load/balancers/preview` | 1 | NeedsManualReview=1 |
| `user/load/balancers/regions` | 1 | ExcludedByPolicy=1 |
| `user/load/balancing/analytics/events` | 1 | ExcludedByPolicy=1 |
| `user/memberships` | 1 | ExcludedByPolicy=1 |
| `user/organizations` | 3 | ExcludedByPolicy=2; NeedsManualReview=1 |
| `user/spectrum/analytics/report` | 1 | ExcludedByPolicy=1 |
| `user/subscriptions` | 4 | ExcludedByPolicy=4 |
| `user/tenants` | 1 | ExcludedByPolicy=1 |
| `user/tokens` | 5 | ExcludedByPolicy=5 |
| `user/tokens/permission/groups` | 1 | ExcludedByPolicy=1 |
| `user/tokens/value` | 1 | NeedsManualReview=1 |
| `user/tokens/verify` | 1 | NeedsManualReview=1 |
| `v1/images` | 6 | ExcludedByPolicy=4; NeedsManualReview=2 |
| `v1/images/blob` | 1 | ExcludedByPolicy=1 |
| `v1/images/flows` | 2 | ExcludedByPolicy=2 |
| `v2/images` | 1 | ExcludedByPolicy=1 |
| `v2/images/direct/upload` | 1 | NeedsManualReview=1 |
| `vectorize/indexes` | 5 | ExcludedByPolicy=5 |
| `vectorize/indexes/delete/by/ids` | 1 | ExcludedByPolicy=1 |
| `vectorize/indexes/get/by/ids` | 1 | ExcludedByPolicy=1 |
| `vectorize/indexes/insert` | 1 | NeedsManualReview=1 |
| `vectorize/indexes/query` | 1 | NeedsManualReview=1 |
| `vectorize/indexes/upsert` | 1 | NeedsManualReview=1 |
| `vectorize/v2/indexes` | 4 | ExcludedByPolicy=4 |
| `vectorize/v2/indexes/delete/by/ids` | 1 | ExcludedByPolicy=1 |
| `vectorize/v2/indexes/get/by/ids` | 1 | ExcludedByPolicy=1 |
| `vectorize/v2/indexes/info` | 1 | NeedsManualReview=1 |
| `vectorize/v2/indexes/insert` | 1 | NeedsManualReview=1 |
| `vectorize/v2/indexes/list` | 1 | ExcludedByPolicy=1 |
| `vectorize/v2/indexes/metadata/index/create` | 1 | ExcludedByPolicy=1 |
| `vectorize/v2/indexes/metadata/index/delete` | 1 | ExcludedByPolicy=1 |
| `vectorize/v2/indexes/metadata/index/list` | 1 | ExcludedByPolicy=1 |
| `vectorize/v2/indexes/query` | 1 | NeedsManualReview=1 |
| `vectorize/v2/indexes/upsert` | 1 | NeedsManualReview=1 |
| `vuln/scanner/credential/sets` | 6 | ExcludedByPolicy=6 |
| `vuln/scanner/credential/sets/credentials` | 6 | ExcludedByPolicy=6 |
| `vuln/scanner/scans` | 4 | ExcludedByPolicy=4 |
| `vuln/scanner/target/environments` | 6 | ExcludedByPolicy=6 |
| `waiting/rooms` | 7 | ExcludedByPolicy=7 |
| `waiting/rooms/events` | 6 | ExcludedByPolicy=6 |
| `waiting/rooms/events/details` | 1 | ExcludedByPolicy=1 |
| `waiting/rooms/preview` | 1 | ExcludedByPolicy=1 |
| `waiting/rooms/rules` | 5 | ExcludedByPolicy=4; NeedsManualReview=1 |
| `waiting/rooms/settings` | 3 | ExcludedByPolicy=3 |
| `waiting/rooms/status` | 1 | ExcludedByPolicy=1 |
| `warp/connector` | 5 | ExcludedByPolicy=5 |
| `warp/connector/configurations` | 2 | ExcludedByPolicy=2 |
| `warp/connector/connections` | 1 | ExcludedByPolicy=1 |
| `warp/connector/connectors` | 1 | ExcludedByPolicy=1 |
| `warp/connector/failover` | 1 | NeedsManualReview=1 |
| `warp/connector/token` | 1 | ExcludedByPolicy=1 |
| `web3/hostnames` | 5 | ExcludedByPolicy=5 |
| `web3/hostnames/ipfs/universal/path/content/list` | 2 | ExcludedByPolicy=2 |
| `web3/hostnames/ipfs/universal/path/content/list/entries` | 5 | UnsupportedProjectionCapability=5 |
| `workers/account/settings` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `workers/assets/upload` | 1 | NeedsManualReview=1 |
| `workers/builds/deploy/hooks` | 1 | NeedsManualReview=1 |
| `workers/dispatch/namespaces` | 6 | ExcludedByPolicy=5; NeedsManualReview=1 |
| `workers/dispatch/namespaces/scripts` | 5 | ExcludedByPolicy=4; NeedsManualReview=1 |
| `workers/dispatch/namespaces/scripts/assets/upload/session` | 1 | ExcludedByPolicy=1 |
| `workers/dispatch/namespaces/scripts/bindings` | 1 | ExcludedByPolicy=1 |
| `workers/dispatch/namespaces/scripts/content` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `workers/dispatch/namespaces/scripts/secrets` | 4 | ExcludedByPolicy=3; NeedsManualReview=1 |
| `workers/dispatch/namespaces/scripts/secrets/bulk` | 1 | UnsupportedRuntimeCapability=1 |
| `workers/dispatch/namespaces/scripts/settings` | 2 | ExcludedByPolicy=2 |
| `workers/dispatch/namespaces/scripts/tags` | 4 | ExcludedByPolicy=2; NeedsManualReview=2 |
| `workers/domains` | 4 | ExcludedByPolicy=4 |
| `workers/durable/objects/namespaces` | 1 | ExcludedByPolicy=1 |
| `workers/durable/objects/namespaces/objects` | 1 | ExcludedByPolicy=1 |
| `workers/observability/destinations` | 4 | ExcludedByPolicy=4 |
| `workers/observability/metricsexport` | 3 | ExcludedByPolicy=3 |
| `workers/observability/queries` | 5 | ExcludedByPolicy=4; NeedsManualReview=1 |
| `workers/observability/shared/query` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `workers/observability/telemetry/keys` | 1 | ExcludedByPolicy=1 |
| `workers/observability/telemetry/live/tail` | 1 | NeedsManualReview=1 |
| `workers/observability/telemetry/live/tail/heartbeat` | 1 | ExcludedByPolicy=1 |
| `workers/observability/telemetry/query` | 1 | NeedsManualReview=1 |
| `workers/observability/telemetry/values` | 1 | ExcludedByPolicy=1 |
| `workers/observability/usage` | 1 | ExcludedByPolicy=1 |
| `workers/placement/regions` | 1 | ExcludedByPolicy=1 |
| `workers/routes` | 5 | ExcludedByPolicy=5 |
| `workers/scripts` | 4 | ExcludedByPolicy=2; NeedsManualReview=2 |
| `workers/scripts/assets/upload/session` | 1 | ExcludedByPolicy=1 |
| `workers/scripts/content` | 1 | NeedsManualReview=1 |
| `workers/scripts/content/v2` | 1 | ExcludedByPolicy=1 |
| `workers/scripts/deployments` | 4 | ExcludedByPolicy=4 |
| `workers/scripts/schedules` | 2 | ExcludedByPolicy=2 |
| `workers/scripts/script/settings` | 2 | ExcludedByPolicy=2 |
| `workers/scripts/search` | 1 | NeedsManualReview=1 |
| `workers/scripts/secrets` | 4 | ExcludedByPolicy=3; NeedsManualReview=1 |
| `workers/scripts/secrets/bulk` | 1 | UnsupportedRuntimeCapability=1 |
| `workers/scripts/settings` | 2 | ExcludedByPolicy=2 |
| `workers/scripts/subdomain` | 3 | ExcludedByPolicy=2; NeedsManualReview=1 |
| `workers/scripts/tails` | 3 | ExcludedByPolicy=2; NeedsManualReview=1 |
| `workers/scripts/usage/model` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `workers/scripts/versions` | 3 | ExcludedByPolicy=2; NeedsManualReview=1 |
| `workers/services/environments/content` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `workers/services/environments/settings` | 2 | ExcludedByPolicy=2 |
| `workers/subdomain` | 3 | ExcludedByPolicy=3 |
| `workers/workers` | 6 | ExcludedByPolicy=5; UnsupportedRuntimeCapability=1 |
| `workers/workers/versions` | 4 | ExcludedByPolicy=4 |
| `workers/workers/versions/latest` | 1 | UnsupportedRuntimeCapability=1 |
| `workflows` | 4 | ExcludedByPolicy=4 |
| `workflows/instances` | 4 | ExcludedByPolicy=3; NeedsManualReview=1 |
| `workflows/instances/batch` | 1 | ExcludedByPolicy=1 |
| `workflows/instances/batch/delete` | 1 | ExcludedByPolicy=1 |
| `workflows/instances/batch/terminate` | 1 | NeedsManualReview=1 |
| `workflows/instances/events` | 1 | NeedsManualReview=1 |
| `workflows/instances/status` | 1 | NeedsManualReview=1 |
| `workflows/instances/step` | 1 | ExcludedByPolicy=1 |
| `workflows/instances/subscribe` | 1 | NeedsManualReview=1 |
| `workflows/instances/terminate` | 1 | NeedsManualReview=1 |
| `workflows/settings` | 2 | ExcludedByPolicy=2 |
| `workflows/versions` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `workflows/versions/dag` | 1 | NeedsManualReview=1 |
| `workflows/versions/graph` | 1 | NeedsManualReview=1 |
| `zerotrust/connectivity/settings` | 2 | ExcludedByPolicy=2 |
| `zerotrust/routes/hostname` | 5 | ExcludedByPolicy=5 |
| `zerotrust/subnets` | 1 | ExcludedByPolicy=1 |
| `zerotrust/subnets/cloudflare/source` | 1 | ExcludedByPolicy=1 |
| `zerotrust/subnets/initial/resolved/ip` | 2 | ExcludedByPolicy=2 |
| `zerotrust/subnets/warp` | 4 | ExcludedByPolicy=4 |
| `zones` | 5 | ExcludedByPolicy=2; NeedsManualReview=1; SupportedWithOverride=2 |
| `zt/risk/scoring` | 1 | ExcludedByPolicy=1 |
| `zt/risk/scoring/behaviors` | 2 | ExcludedByPolicy=1; NeedsManualReview=1 |
| `zt/risk/scoring/integrations` | 5 | ExcludedByPolicy=5 |
| `zt/risk/scoring/integrations/reference/id` | 1 | ExcludedByPolicy=1 |
| `zt/risk/scoring/reset` | 1 | NeedsManualReview=1 |
| `zt/risk/scoring/summary` | 1 | ExcludedByPolicy=1 |

## Current supported operations

| Operation | Cmdlet | Classification |
| --- | --- | --- |
| `dns-records-for-a-zone-create-dns-record` | `New-CfDnsRecord` | SupportedWithOverride |
| `dns-records-for-a-zone-delete-dns-record` | `Remove-CfDnsRecord` | SupportedWithOverride |
| `dns-records-for-a-zone-dns-record-details` | `Get-CfDnsRecord` | SupportedWithOverride |
| `dns-records-for-a-zone-list-dns-records` | `Get-CfDnsRecord` | SupportedWithOverride |
| `dns-records-for-a-zone-patch-dns-record` | `Set-CfDnsRecord` | SupportedWithOverride |
| `dns-records-for-a-zone-update-dns-record` | `Set-CfDnsRecord` | SupportedWithOverride |
| `zones-0-get` | `Get-CfZone` | SupportedWithOverride |
| `zones-get` | `Get-CfZone` | SupportedWithOverride |

## Runtime gaps

The JSON report contains every affected operation. The table below shows the first 100 deterministically sorted examples.

| Operation | Resource family | Runtime gaps |
| --- | --- | --- |
| `accounts-logs-explorer-query-post` | `logs/explorer/query/sql` | UnsupportedRequestContentType:text/plain |
| `analytics-engine-sql-query-post` | `analytics/engine/sql` | UnsupportedRequestContentType:text/plain |
| `create_integration_v2` | `one/integrations` | UnsupportedRequestContentType:text/plain;charset=UTF-8 |
| `dlp-datasets-upload-dataset-column` | `dlp/datasets/versions/entries` | UnsupportedRequestContentType:application/octet-stream |
| `dlp-datasets-upload-version` | `dlp/datasets/upload` | UnsupportedRequestContentType:application/octet-stream |
| `editWorker` | `workers/workers` | UnsupportedRequestContentType:application/merge-patch+json |
| `namespace-worker-patch-script-secrets-bulk` | `workers/dispatch/namespaces/scripts/secrets/bulk` | UnsupportedRequestContentType:application/merge-patch+json |
| `namespace-worker-script-upload-worker-module` | `workers/dispatch/namespaces/scripts` | UnsupportedRequestContentType:application/javascript, UnsupportedRequestContentType:text/javascript |
| `patchLatestWorkerVersion` | `workers/workers/versions/latest` | UnsupportedRequestContentType:application/merge-patch+json |
| `postAccountsAccountIdBrandProtectionLogos` | `brand/protection/logos` | UnsupportedRequestContentType:application/x-www-form-urlencoded |
| `r2-put-object` | `r2/buckets/objects` | UnsupportedRequestContentType:application/octet-stream |
| `scim-groups-create` | `scim/v2/Groups` | UnsupportedRequestContentType:application/scim+json |
| `scim-groups-patch` | `scim/v2/Groups` | UnsupportedRequestContentType:application/scim+json |
| `scim-users-create` | `scim/v2/Users` | UnsupportedRequestContentType:application/scim+json |
| `scim-users-patch` | `scim/v2/Users` | UnsupportedRequestContentType:application/scim+json |
| `scim-users-put` | `scim/v2/Users` | UnsupportedRequestContentType:application/scim+json |
| `update_integration_v2` | `one/integrations` | UnsupportedRequestContentType:text/plain;charset=UTF-8 |
| `vectorize-(-deprecated)-insert-vector` | `vectorize/indexes/insert` | UnsupportedRequestContentType:application/x-ndjson |
| `vectorize-(-deprecated)-upsert-vector` | `vectorize/indexes/upsert` | UnsupportedRequestContentType:application/x-ndjson |
| `vectorize-insert-vector` | `vectorize/v2/indexes/insert` | UnsupportedRequestContentType:application/x-ndjson |
| `vectorize-upsert-vector` | `vectorize/v2/indexes/upsert` | UnsupportedRequestContentType:application/x-ndjson |
| `worker-patch-script-secrets-bulk` | `workers/scripts/secrets/bulk` | UnsupportedRequestContentType:application/merge-patch+json |
| `worker-script-upload-worker-module` | `workers/scripts` | UnsupportedRequestContentType:application/javascript, UnsupportedRequestContentType:text/javascript |
| `workers-kv-namespace-write-key-value-pair-with-metadata` | `storage/kv/namespaces/values` | UnsupportedRequestContentType:application/octet-stream |
| `zones-logs-explorer-query-post` | `logs/explorer/query/sql` | UnsupportedRequestContentType:text/plain |

## Projection gaps

The JSON report contains every affected operation. The table below shows the first 100 deterministically sorted examples.

| Operation | Resource family | Reason |
| --- | --- | --- |
| `access-applications-patch-update-access-application-settings` | `access/apps/settings` | ProjectionParameterSetCollision |
| `access-applications-put-update-access-application-settings` | `access/apps/settings` | ProjectionParameterSetCollision |
| `billable-usage-get-v1-account-usage` | `billable/usage` | ProjectionParameterSetCollision |
| `billable-usage-v2-get-account-usage` | `billable/usage` | ProjectionParameterSetCollision |
| `createAllowlistedPrefix` | `magic/advanced/tcp/protection/configs/allowlist` | ProjectionParameterSetCollision |
| `deleteAllowlistPrefix` | `magic/advanced/tcp/protection/configs/allowlist` | ProjectionParameterSetCollision |
| `deleteAllowlistPrefixesForAccount` | `magic/advanced/tcp/protection/configs/allowlist` | ProjectionParameterSetCollision |
| `devices-get-local-domain-fallback-list-for-a-device-settings-policy` | `devices/policy/fallback/domains` | ProjectionParameterSetCollision |
| `devices-get-local-domain-fallback-list` | `devices/policy/fallback/domains` | ProjectionParameterSetCollision |
| `devices-get-split-tunnel-exclude-list-for-a-device-settings-policy` | `devices/policy/exclude` | ProjectionParameterSetCollision |
| `devices-get-split-tunnel-exclude-list` | `devices/policy/exclude` | ProjectionParameterSetCollision |
| `devices-get-split-tunnel-include-list-for-a-device-settings-policy` | `devices/policy/include` | ProjectionParameterSetCollision |
| `devices-get-split-tunnel-include-list` | `devices/policy/include` | ProjectionParameterSetCollision |
| `devices-set-local-domain-fallback-list-for-a-device-settings-policy` | `devices/policy/fallback/domains` | ProjectionParameterSetCollision |
| `devices-set-local-domain-fallback-list` | `devices/policy/fallback/domains` | ProjectionParameterSetCollision |
| `devices-set-split-tunnel-exclude-list-for-a-device-settings-policy` | `devices/policy/exclude` | ProjectionParameterSetCollision |
| `devices-set-split-tunnel-exclude-list` | `devices/policy/exclude` | ProjectionParameterSetCollision |
| `devices-set-split-tunnel-include-list-for-a-device-settings-policy` | `devices/policy/include` | ProjectionParameterSetCollision |
| `devices-set-split-tunnel-include-list` | `devices/policy/include` | ProjectionParameterSetCollision |
| `firewall-rules-update-a-firewall-rule` | `firewall/rules` | ProjectionParameterSetCollision |
| `firewall-rules-update-firewall-rules` | `firewall/rules` | ProjectionParameterSetCollision |
| `firewall-rules-update-priority-of-a-firewall-rule` | `firewall/rules` | ProjectionParameterSetCollision |
| `firewall-rules-update-priority-of-firewall-rules` | `firewall/rules` | ProjectionParameterSetCollision |
| `get_IndicatorTypesList` | `cloudforce/one/events/indicator/types` | ProjectionParameterSetCollision |
| `get_LegacyIndicatorTypesList` | `cloudforce/one/events/indicatorTypes` | ProjectionParameterSetCollision |
| `getAllowlistPrefix` | `magic/advanced/tcp/protection/configs/allowlist` | ProjectionParameterSetCollision |
| `ip-address-management-address-maps-delete-address-map` | `addressing/address/maps` | ProjectionParameterSetCollision |
| `ip-address-management-address-maps-update-address-map` | `addressing/address/maps` | ProjectionParameterSetCollision |
| `listAllowlistPrefixesForAccount` | `magic/advanced/tcp/protection/configs/allowlist` | ProjectionParameterSetCollision |
| `lists-create-a-list` | `rules/lists` | ProjectionParameterSetCollision |
| `lists-create-list-items` | `rules/lists/items` | ProjectionParameterSetCollision |
| `lists-delete-a-list` | `rules/lists` | ProjectionParameterSetCollision |
| `lists-delete-list-items` | `rules/lists/items` | ProjectionParameterSetCollision |
| `lists-get-a-list-item` | `rules/lists/items` | ProjectionParameterSetCollision |
| `lists-get-a-list` | `rules/lists` | ProjectionParameterSetCollision |
| `lists-get-list-items` | `rules/lists/items` | ProjectionParameterSetCollision |
| `lists-get-lists` | `rules/lists` | ProjectionParameterSetCollision |
| `lists-update-a-list` | `rules/lists` | ProjectionParameterSetCollision |
| `lists-update-all-list-items` | `rules/lists/items` | ProjectionParameterSetCollision |
| `updateAllowlistPrefix` | `magic/advanced/tcp/protection/configs/allowlist` | ProjectionParameterSetCollision |
| `web3-hostname-create-ipfs-universal-path-gateway-content-list-entry` | `web3/hostnames/ipfs/universal/path/content/list/entries` | ProjectionParameterSetCollision |
| `web3-hostname-delete-ipfs-universal-path-gateway-content-list-entry` | `web3/hostnames/ipfs/universal/path/content/list/entries` | ProjectionParameterSetCollision |
| `web3-hostname-edit-ipfs-universal-path-gateway-content-list-entry` | `web3/hostnames/ipfs/universal/path/content/list/entries` | ProjectionParameterSetCollision |
| `web3-hostname-ipfs-universal-path-gateway-content-list-entry-details` | `web3/hostnames/ipfs/universal/path/content/list/entries` | ProjectionParameterSetCollision |
| `web3-hostname-list-ipfs-universal-path-gateway-content-list-entries` | `web3/hostnames/ipfs/universal/path/content/list/entries` | ProjectionParameterSetCollision |
| `zero-trust-lists-create-zero-trust-list` | `gateway/lists` | ProjectionParameterSetCollision |
| `zero-trust-lists-delete-zero-trust-list` | `gateway/lists` | ProjectionParameterSetCollision |
| `zero-trust-lists-list-zero-trust-lists` | `gateway/lists` | ProjectionParameterSetCollision |
| `zero-trust-lists-patch-zero-trust-list` | `gateway/lists` | ProjectionParameterSetCollision |
| `zero-trust-lists-update-zero-trust-list` | `gateway/lists` | ProjectionParameterSetCollision |
| `zero-trust-lists-zero-trust-list-details` | `gateway/lists` | ProjectionParameterSetCollision |
| `zone-level-access-applications-patch-update-access-application-settings` | `access/apps/settings` | ProjectionParameterSetCollision |
| `zone-level-access-applications-put-update-access-application-settings` | `access/apps/settings` | ProjectionParameterSetCollision |

## Normalization gaps

None in this baseline. The category remains part of the report contract for future schema/model failures.

## Operations with explicit projection policy

These operations have an entry in the current projection policy. Policy presence is not equivalent to current public admission.

| Operation | Projected cmdlet | Current public cmdlet | Classification |
| --- | --- | --- | --- |
| `ai-search-namespace-instance-change-job-status` | `Set-CfAiSearchJob` | `-` | NeedsManualReview |
| `ai-search-namespace-instance-create-job` | `New-CfAiSearchJob` | `-` | ExcludedByPolicy |
| `ai-search-namespace-instance-get-job` | `Get-CfAiSearchJob` | `-` | ExcludedByPolicy |
| `ai-search-namespace-instance-list-jobs` | `Get-CfAiSearchJob` | `-` | ExcludedByPolicy |
| `d1-create-database` | `New-CfD1Database` | `-` | ExcludedByPolicy |
| `d1-delete-database` | `Remove-CfD1Database` | `-` | ExcludedByPolicy |
| `d1-get-database` | `Get-CfD1Database` | `-` | ExcludedByPolicy |
| `d1-list-databases` | `Get-CfD1Database` | `-` | ExcludedByPolicy |
| `d1-update-database` | `Set-CfD1Database` | `-` | ExcludedByPolicy |
| `dns-records-for-a-zone-create-dns-record` | `New-CfDnsRecord` | `New-CfDnsRecord` | SupportedWithOverride |
| `dns-records-for-a-zone-delete-dns-record` | `Remove-CfDnsRecord` | `Remove-CfDnsRecord` | SupportedWithOverride |
| `dns-records-for-a-zone-dns-record-details` | `Get-CfDnsRecord` | `Get-CfDnsRecord` | SupportedWithOverride |
| `dns-records-for-a-zone-list-dns-records` | `Get-CfDnsRecord` | `Get-CfDnsRecord` | SupportedWithOverride |
| `dns-records-for-a-zone-patch-dns-record` | `Set-CfDnsRecord` | `Set-CfDnsRecord` | SupportedWithOverride |
| `dns-records-for-a-zone-update-dns-record` | `Set-CfDnsRecord` | `Set-CfDnsRecord` | SupportedWithOverride |
| `zones-0-delete` | `Remove-CfZone` | `-` | ExcludedByPolicy |
| `zones-0-get` | `Get-CfZone` | `Get-CfZone` | SupportedWithOverride |
| `zones-0-patch` | `Set-CfZone` | `-` | ExcludedByPolicy |
| `zones-get` | `Get-CfZone` | `Get-CfZone` | SupportedWithOverride |
| `zones-post` | `New-CfZone` | `-` | NeedsManualReview |

## Manual review

The JSON report contains every affected operation. The table below shows the first 100 deterministically sorted examples.

| Operation | Resource family | Reason |
| --- | --- | --- |
| `access-applications-add-an-application` | `access/apps` | LowSemanticConfidence |
| `access-applications-revoke-service-tokens` | `access/apps/revoke/tokens` | LowSemanticConfidence |
| `access-applications-test-access-policies` | `access/apps/user/policy/checks` | LowSemanticConfidence |
| `access-custom-pages-validate-a-custom-page-template` | `access/custom/pages/validate` | LowSemanticConfidence |
| `access-gateway-ca-add-an-SSH-ca` | `access/gateway/ca` | LowSemanticConfidence |
| `access-identity-providers-add-an-access-identity-provider` | `access/identity/providers` | LowSemanticConfidence |
| `access-key-configuration-rotate-access-keys` | `access/keys/rotate` | LowSemanticConfidence |
| `access-mtls-authentication-add-an-mtls-certificate` | `access/certificates` | LowSemanticConfidence |
| `access-policies-convert-reusable` | `access/apps/policies/make/reusable` | LowSemanticConfidence |
| `access-policy-tests` | `access/policy/tests` | LowSemanticConfidence |
| `access-saml-certificates-rotate-certificate` | `access/saml/certificates/rotate` | LowSemanticConfidence |
| `access-service-tokens-refresh-a-service-token` | `access/service/tokens/refresh` | LowSemanticConfidence |
| `access-service-tokens-rotate-a-service-token` | `access/service/tokens/rotate` | LowSemanticConfidence |
| `account-api-tokens-roll-token` | `tokens/value` | LowSemanticConfidence |
| `account-api-tokens-verify-token` | `tokens/verify` | LowSemanticConfidence |
| `account-billing-pay-bad-debt` | `pay/bad/debt` | LowSemanticConfidence |
| `account-billing-pay-invoice` | `pay/invoice` | LowSemanticConfidence |
| `account-billing-set-default-payment-method` | `payment/methods/set/as/default` | LowSemanticConfidence |
| `account-billing-toggle-pdf-invoices` | `invoices` | LowSemanticConfidence |
| `account-creation` | `accounts` | LowSemanticConfidence |
| `account-deletion` | `accounts` | LowSemanticConfidence |
| `account-level-custom-nameservers-add-account-custom-nameserver` | `custom/ns` | LowSemanticConfidence |
| `account-level-custom-nameservers-usage-for-a-zone-set-account-custom-nameserver-related-zone-metadata` | `custom/ns` | LowSemanticConfidence |
| `account-load-balancer-monitors-preview-monitor` | `load/balancers/monitors/preview` | LowSemanticConfidence |
| `account-load-balancer-monitors-preview-result` | `load/balancers/preview` | LowSemanticConfidence |
| `account-load-balancer-pools-preview-pool` | `load/balancers/pools/preview` | LowSemanticConfidence |
| `account-load-balancer-search-search-resources` | `load/balancers/search` | LowSemanticConfidence |
| `account-members-add-member` | `members` | LowSemanticConfidence |
| `account-members-remove-member` | `members` | LowSemanticConfidence |
| `account-request-tracer-request-trace` | `request/tracer/trace` | LowSemanticConfidence |
| `account-settings-change-ut-billing-setting` | `settings/ut/billing` | LowSemanticConfidence |
| `account-subscriptions-action-append-subscription` | `subscriptions/action/append` | LowSemanticConfidence |
| `account-subscriptions-cancel-delayed-downgrade` | `subscriptions/cancel/downgrade` | LowSemanticConfidence |
| `Accounts_batchMoveAccounts` | `move` | LowSemanticConfidence |
| `Accounts_modifyAccountProfile` | `profile` | LowSemanticConfidence |
| `Accounts_moveAccounts` | `move` | LowSemanticConfidence |
| `accounts-browser-extension-config-post` | `browser/extension/config` | LowSemanticConfidence |
| `accounts-browser-extension-config-put` | `browser/extension/config` | LowSemanticConfidence |
| `accounts-logs-explorer-query-post` | `logs/explorer/query/sql` | LowSemanticConfidence |
| `add_participant` | `realtime/kit/meetings/participants` | LowSemanticConfidence |
| `add-audio-track` | `stream/audio/copy` | LowSemanticConfidence |
| `addWebhook` | `realtime/kit/webhooks` | LowSemanticConfidence |
| `agent-memory-ingest` | `agent/memory/namespaces/profiles/ingest` | LowSemanticConfidence |
| `agent-memory-recall` | `agent/memory/namespaces/profiles/recall` | LowSemanticConfidence |
| `agent-memory-remember` | `agent/memory/namespaces/profiles/remember` | LowSemanticConfidence |
| `agent-memory-summary` | `agent/memory/namespaces/profiles/summary` | LowSemanticConfidence |
| `ai-search-fetch-instance` | `ai/search/instances` | LowSemanticConfidence |
| `ai-search-fetch-namespace` | `ai/search/namespaces` | LowSemanticConfidence |
| `ai-search-fetch-tokens` | `ai/search/tokens` | LowSemanticConfidence |
| `ai-search-instance-change-job-status` | `ai/search/instances/jobs` | LowSemanticConfidence |
| `ai-search-instance-chat-completion` | `ai/search/instances/chat/completions` | LowSemanticConfidence |
| `ai-search-instance-search` | `ai/search/instances/search` | LowSemanticConfidence |
| `ai-search-move-instance` | `ai/search/namespaces/instances` | LowSemanticConfidence |
| `ai-search-namespace-fetch-instance` | `ai/search/namespaces/instances` | LowSemanticConfidence |
| `ai-search-namespace-instance-change-job-status` | `ai/search/namespaces/instances/jobs` | LowSemanticConfidence |
| `ai-search-namespace-instance-chat-completion` | `ai/search/namespaces/instances/chat/completions` | LowSemanticConfidence |
| `ai-search-namespace-instance-logs-item` | `ai/search/namespaces/instances/items/logs` | LowSemanticConfidence |
| `ai-search-namespace-instance-search` | `ai/search/namespaces/instances/search` | LowSemanticConfidence |
| `ai-search-namespace-instance-sync-item` | `ai/search/namespaces/instances/items` | LowSemanticConfidence |
| `ai-search-namespace-instance-upload-item` | `ai/search/namespaces/instances/items` | LowSemanticConfidence |
| `ai-search-namespace-multi-instance-chat-completion` | `ai/search/namespaces/chat/completions` | LowSemanticConfidence |
| `ai-search-namespace-multi-instance-search` | `ai/search/namespaces/search` | LowSemanticConfidence |
| `ai-search-namespace-purge-instance-cache` | `ai/search/namespaces/instances/purge/cache` | LowSemanticConfidence |
| `ai-search-namespace-stats` | `ai/search/namespaces/instances/stats` | LowSemanticConfidence |
| `ai-search-stats` | `ai/search/instances/stats` | LowSemanticConfidence |
| `ai-security-custom-topics-put` | `ai/security/custom/topics` | LowSemanticConfidence |
| `ai-security-settings-put` | `ai/security/settings` | LowSemanticConfidence |
| `aig-billing-check-topup-status` | `ai/gateway/billing/topup/status` | LowSemanticConfidence |
| `aig-billing-set-spending-limit` | `ai/gateway/billing/spending/limit` | LowSemanticConfidence |
| `aig-billing-set-topup-config` | `ai/gateway/billing/topup/config` | LowSemanticConfidence |
| `aig-billing-topup-eligibility` | `ai/gateway/billing/topup/eligibility` | LowSemanticConfidence |
| `aig-config-fetch-account-provider-cost` | `ai/gateway/custom/providers/costs` | LowSemanticConfidence |
| `aig-config-fetch-account-provider` | `ai/gateway/custom/providers` | LowSemanticConfidence |
| `aig-config-fetch-custom-domain` | `ai/gateway/gateways/custom/domains` | LowSemanticConfidence |
| `aig-config-fetch-dataset` | `ai/gateway/gateways/datasets` | LowSemanticConfidence |
| `aig-config-fetch-evaluations` | `ai/gateway/gateways/evaluations` | LowSemanticConfidence |
| `aig-config-fetch-gateway` | `ai/gateway/gateways` | LowSemanticConfidence |
| `aig-config-post-gateway-dynamic-route-deployment` | `ai/gateway/gateways/routes/deployments` | LowSemanticConfidence |
| `aig-config-post-gateway-dynamic-route-version` | `ai/gateway/gateways/routes/versions` | LowSemanticConfidence |
| `aig-config-post-gateway-dynamic-route` | `ai/gateway/gateways/routes` | LowSemanticConfidence |
| `analytics-engine-sql-query-post` | `analytics/engine/sql` | LowSemanticConfidence |
| `analyze-certificate-analyze-certificate` | `ssl/analyze` | LowSemanticConfidence |
| `api-shield-api-discovery-retrieve-discovered-operation-by-id` | `api/gateway/discovery/operations` | LowSemanticConfidence |
| `api-shield-api-discovery-retrieve-discovered-operations-on-a-zone-as-openapi` | `api/gateway/discovery` | LowSemanticConfidence |
| `api-shield-api-discovery-retrieve-discovered-operations-on-a-zone` | `api/gateway/discovery/operations` | LowSemanticConfidence |
| `api-shield-endpoint-management-add-operation-to-a-zone` | `api/gateway/operations/item` | LowSemanticConfidence |
| `api-shield-endpoint-management-add-operations-to-a-zone` | `api/gateway/operations` | LowSemanticConfidence |
| `api-shield-endpoint-management-retrieve-information-about-all-operations-on-a-zone` | `api/gateway/operations` | LowSemanticConfidence |
| `api-shield-endpoint-management-retrieve-information-about-an-operation` | `api/gateway/operations` | LowSemanticConfidence |
| `api-shield-endpoint-management-retrieve-operations-and-features-as-open-api-schemas` | `api/gateway/schemas` | LowSemanticConfidence |
| `api-shield-expression-templates-fallthrough` | `api/gateway/expression/template/fallthrough` | LowSemanticConfidence |
| `api-shield-labels-replace-operations-attached-to-managed-label` | `api/gateway/labels/managed/resources/operation` | LowSemanticConfidence |
| `api-shield-labels-replace-operations-attached-to-user-label` | `api/gateway/labels/user/resources/operation` | LowSemanticConfidence |
| `api-shield-operations-bulk-post-labels-to-operations` | `api/gateway/operations/labels` | LowSemanticConfidence |
| `api-shield-operations-bulk-put-labels-to-operations` | `api/gateway/operations/labels` | LowSemanticConfidence |
| `api-shield-operations-post-labels-to-operation` | `api/gateway/operations/labels` | LowSemanticConfidence |
| `api-shield-operations-put-labels-to-operation` | `api/gateway/operations/labels` | LowSemanticConfidence |
| `api-shield-put-user-label` | `api/gateway/labels/user` | LowSemanticConfidence |
| `api-shield-schema-validation-enable-validation-for-a-schema` | `api/gateway/user/schemas` | LowSemanticConfidence |
| `api-shield-schema-validation-extract-operations-from-schema` | `api/gateway/user/schemas/operations` | LowSemanticConfidence |

## Scope interpretation

`Supported` and `SupportedWithOverride` mean current public-surface operations pass this discovery gate. `ExcludedByPolicy` means the operation is not admitted to the bounded P3.2 public policy; it is not a claim that the operation is permanently unsupported. Normalization success and projection construction are reported separately and are not sufficient for final support.
