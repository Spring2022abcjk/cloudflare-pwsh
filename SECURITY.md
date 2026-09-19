# Security Policy

## Reporting a vulnerability

This repository does not currently publish a dedicated security mailbox or
public security intake address. Do not open a public issue and do not include
tokens, private reports, or other secrets in a public pull request.

Before the first public release, maintainers must configure and verify a
private reporting channel, preferably GitHub Security Advisories for the
repository or an organization-controlled security contact. Until that channel
is configured, a report should be sent privately to the repository maintainers
through the hosting organization's existing private contact path; this file
does not invent an email address.

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
