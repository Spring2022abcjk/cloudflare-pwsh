# Security Policy

## Reporting a vulnerability

This repository does not publish a security mailbox. Do not open a public issue
and do not include tokens, private reports, or other secrets in a public pull
request.

GitHub private vulnerability reporting is enabled for this public repository.
Use the repository's **Security** tab and choose **Advisories** → **Report a
vulnerability**, or use the repository advisory page:

<https://github.com/Spring2022abcjk/cloudflare-pwsh/security/advisories/new>

This channel is the supported private intake path. If the link is unavailable,
do not disclose details publicly; contact the repository owner through a
private GitHub channel and include only a redacted summary until the advisory
channel is restored.

## Supported versions

There is currently no published or production-supported module version. The
`0.1.0` artifact is a non-published candidate and is not a supported public
release. The first release must add its support window and response target to
this policy before publication.

## Security scope

Reports are in scope for credential exposure, unsafe workflow permissions,
supply-chain or provenance bypasses, package tampering, schema-source
substitution, and vulnerabilities in the module/runtime code. Please include
the affected commit or candidate manifest when it is safe to do so, while
redacting credentials and account identifiers.

## Response boundary

Remote CI, real-account validation, Gallery publication, signing, and final
release approval are separate acceptance boundaries. A local build or mock
test is not a security response or a production-support claim.
