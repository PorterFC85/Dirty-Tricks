# Third-Party Notices

This addon bundles third-party libraries in the `Libs` folder.

## Addon code

Unless otherwise noted, the Dirty Tricks addon code is licensed under the MIT License. See [LICENSE](LICENSE).

## Bundled libraries

### LibStub
- Path: `Libs/LibStub`
- Source: upstream LibStub package
- Included files preserve original upstream notices
- Stated license found in bundled source/toc: Public Domain

### CallbackHandler-1.0
- Path: `Libs/CallbackHandler-1.0`
- Source: official upstream CallbackHandler-1.0 CurseForge package
- Included files preserve original upstream notices and changelog file
- Stated license found in upstream package metadata reviewed here: `BSD-2.0`

### LibDataBroker-1.1
- Path: `Libs/LibDataBroker-1.1`
- Source: upstream LibDataBroker-1.1 package
- Included files preserve original upstream notices and changelog/readme files
- Upstream project guidance reviewed here indicates embedding/hard-embedding is intended for addon authors
- License status from bundled file set and reviewed pages: no explicit permissive license text was confirmed here
- Recommendation: keep attribution/provenance and verify upstream redistribution terms before public distribution

### LibDBIcon-1.0
- Path: `Libs/LibDBIcon-1.0`
- Source: upstream LibDBIcon-1.0 package (Ace3 project)
- Included files preserve original upstream notices and changelog file
- Upstream project guidance reviewed here indicates embedding is intended for addon authors
- Stated license: Ace3-style BSD-2-Clause (redistribution in source/binary forms permitted; see full license text in upstream package)
- License permits embedding in addons with appropriate attribution

## Packaging notes

- Third-party libraries are kept separate from addon code in the `Libs` folder.
- Upstream file names and folder structure were preserved.
- A `.pkgmeta` file is included to track upstream library sources for packaging updates.
- This notice file is provided to document provenance and review status; it is not legal advice.

## Release checklist for bundled libraries

- Update embedded libraries from their official upstream source/package.
- Preserve upstream folder names, file names, and in-file notices.
- Keep third-party libraries separate from addon source files.
- Record the source package, version, and any changelog/license files included.
- Re-check upstream project pages or package metadata for license changes.
- If a library license is unclear or restrictive, verify permission before public distribution.
- Update this file when adding, removing, or replacing any bundled library.
