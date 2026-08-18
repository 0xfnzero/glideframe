# GlideFrame License

This repository contains GlideFrame.

Code, services, assets, documentation, and configuration outside this repository are not licensed by this file.

Unless a file or directory says otherwise, files in this repository are licensed under:

```text
AGPL-3.0-or-later
```

The full license text is available at [LICENSES/AGPL-3.0-or-later.txt](LICENSES/AGPL-3.0-or-later.txt).

## License Map

| Path | License | Notes |
| --- | --- | --- |
| `apps/api/` | `AGPL-3.0-or-later` | Public API prototype and worker code kept in this repository |
| `apps/web/` | `AGPL-3.0-or-later` | Public web workspace prototype kept in this repository |
| `docker-compose.yml` | `AGPL-3.0-or-later` | Local development service deployment |
| `Sources/` | `MPL-2.0` | macOS desktop app and Swift shared logic |
| `Tests/` | `MPL-2.0` | Swift tests for the desktop/shared Swift code |
| `macos/` | `MPL-2.0` | macOS plist, entitlements, and app configuration |
| `Package.swift` | `MPL-2.0` | Swift package definition |
| `project.yml` | `MPL-2.0` | XcodeGen project definition |
| `packages/contracts/` | `Apache-2.0` | Shared schemas, TypeScript contracts, and integration surface |
| `docs/` | `Apache-2.0` | Documentation, roadmaps, and public project notes |
| `README.md`, `README.zh-CN.md` | `Apache-2.0` | Project documentation |

Directory-level `LICENSE` files repeat the applicable license for important subtrees.

## Brand Assets

The GlideFrame name, logos, icons, artwork, website identity, and other brand assets are not licensed under the software licenses above unless a file explicitly says otherwise. They are reserved for official project identity and covered by [TRADEMARKS.md](TRADEMARKS.md).

## License Texts

- [AGPL-3.0-or-later](LICENSES/AGPL-3.0-or-later.txt)
- [MPL-2.0](LICENSES/MPL-2.0.txt)
- [Apache-2.0](LICENSES/Apache-2.0.txt)

## SPDX Identifiers

New source files should include an SPDX license identifier where practical:

```text
SPDX-License-Identifier: AGPL-3.0-or-later
SPDX-License-Identifier: MPL-2.0
SPDX-License-Identifier: Apache-2.0
```

Use the identifier that matches the file's directory and purpose.
