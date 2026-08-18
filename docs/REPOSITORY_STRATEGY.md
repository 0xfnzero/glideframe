# Repository Strategy

Status: planning draft.

GlideFrame will use an open-core structure:

- Public repository: `glideframe`
- Private repository: `glideframe-commercial`

The public repository is for the Community Edition. The private repository is for the Commercial Edition.

## Community Repository

The community repository should include:

- Native macOS recording core.
- Local project format and project recovery.
- Community editor and local export.
- Public contracts, schemas, examples, and extension interfaces.
- Documentation, tests, issue templates, and contributor workflow.

It should avoid:

- Payment integrations.
- Hosted account and entitlement logic.
- Proprietary AI orchestration.
- Hosted cloud operations.
- Team administration and enterprise policy.
- Private analytics, customer operations, and support tooling.

## Commercial Repository

The commercial repository should include:

- Commercial desktop app packaging and release infrastructure.
- Advanced editor features and commercial workflows.
- Account, entitlement, payment, and update channels.
- Hosted AI, cloud sharing, media processing, and CDN playback.
- Team collaboration, enterprise controls, and private deployment tooling.

## Shared Code Flow

- Shared code flows from public to private.
- Community fixes should be upstreamed when they improve shared behavior.
- Private features should depend on public APIs or contracts whenever possible.
- Project files must remain compatible between editions.
- Secrets, signing identities, credentials, customer data, and private deployment files must never be committed to the public repository.

## Public Messaging

Public docs should describe the Community Edition honestly:

- It is local-first.
- It is useful without an account.
- It has an open project format.
- It can be extended.
- It does not promise that every hosted, AI, team, or enterprise feature will be open source.
