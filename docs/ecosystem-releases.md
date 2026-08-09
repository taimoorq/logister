# Ecosystem releases

Logister’s backend, CLI, SDKs, container images, and package-manager metadata are independent open-source artifacts. They do not share a version number, but a backend contract change must make its effect on every consumer explicit.

## Sources of truth

- `VERSION` is the backend release version. The top changelog entry and OpenAPI `info.version` must match it.
- `config/ecosystem.yml` lists public contracts, consumers, version sources, release workflows, and channels.
- `config/release-impact/*.yml` records compatibility, activation order, exact contract hashes, and a bump decision for every affected consumer.
- `config/release-sets/v<version>.yml` records the independently chosen target version and public channels for the release set.
- `config/ecosystem-versions.json` contains only versions already verified from their public channels. Public docs read this catalog rather than local companion worktrees.

These are public release metadata. Never put credentials, customer data, private incident evidence, local paths, or workspace planning notes in them. GitHub Actions secret names may be documented; secret values stay in provider secret stores.

## Publication flow

1. Rails CI validates tests, public-source safety, release impact, release set, and version identity. CI does not deploy.
2. A successful current-`main` commit creates the new backend tag. The tag workflow builds one canonical image, copies that digest to public registry mirrors, deploys the same digest to Fly, and verifies the runtime identity before creating or repairing the GitHub Release.
3. After Rails CI, required add-ons receive an immutable, checksum-pinned release-set dispatch. A listener checks the add-on’s `main` version, changelog, and public-source scan. Missing work becomes a public readiness issue.
4. Updating an add-on’s functionality, tests, docs, version, and changelog and merging it to that repository’s protected `main` triggers its own tag and publication workflow.
5. The ecosystem reconciler re-reads GitHub Releases and every declared registry. CLI completion also requires npm, Homebrew, and Scoop to expose the same canonical tarball checksum.
6. Only a complete reconciliation attaches the public release-set receipt, updates the verified version catalog through a pull request, refreshes docs, and marks `release/ecosystem` successful on the backend release commit.

Publication workflows are idempotent. A missing downstream artifact is repaired from the already verified immutable source when possible. A conflicting immutable tag or artifact fails closed and requires a new version rather than overwriting public history.

## Local checks

```sh
bin/check-release-impact --all
bin/check-release-set
bin/release-identity
bin/sync-doc-versions --check
scripts/publication-safety-check.sh
```

`bin/reconcile-release-set` reads live public registries and is intended for the scheduled GitHub Actions reconciliation after releases have been published.
