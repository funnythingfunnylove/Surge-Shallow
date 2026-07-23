# Third-party references

Surge Shallow is an independent utility and is not affiliated with Surge Networks Inc.

The product workflow uses these public references and components:

- [EEliberto/SurgeRelay-macOS](https://github.com/EEliberto/SurgeRelay-macOS), Apache License 2.0. Surge Shallow adapts its module conversion, editing, merging, publishing, Web/Ponte management and synchronization code into the native `SurgeModuleManagement` feature; the upstream app shell and lifecycle are not compiled into Surge Shallow. Adapted from upstream commit `b19d0dd6d6b9593be9cdf01c578de76c55d43150`; the complete license is included at `Sources/SurgeModuleManagement/LICENSE`.
- [Surge configuration manual](https://manual.nssurge.com/overview/configuration.html), used to implement the INI-like profile structure, ordered `[Rule]` semantics, detached/linked profile awareness, managed-profile handling, requirements, and platform-specific configuration behavior.

“Surge” is a product name of its respective owner and is used only to describe compatibility.
