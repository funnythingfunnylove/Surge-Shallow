# Third-party references

Surge Shallow is an independent utility and is not affiliated with Surge Networks Inc.

The product workflow was informed by these public references:

- [EEliberto/SurgeRelay-macOS](https://github.com/EEliberto/SurgeRelay-macOS), Apache License 2.0. The project demonstrated a useful management pattern built around conditional upstream checks, last-known-good caches, atomic iCloud writes, and stable generated artifacts. Surge Shallow is a separate implementation for full profile rule merging and does not bundle Surge Relay source code.
- [Surge configuration manual](https://manual.nssurge.com/overview/configuration.html), used to implement the INI-like profile structure, ordered `[Rule]` semantics, detached/linked profile awareness, managed-profile handling, requirements, and platform-specific configuration behavior.

“Surge” is a product name of its respective owner and is used only to describe compatibility.
