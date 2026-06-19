# GitHub Source Integration Plan

This is the historical phased roadmap for GitHub source lookup. The current project-scoped implementation plan and acceptance checklist live in [Project-Scoped GitHub Integration Plan](project-scoped-github-integration-plan.md).

## Goal

Let each Logister project connect to one or more GitHub repositories so error stack frames can resolve to the real source file, a nearby code excerpt, and a GitHub permalink. Projects without source repositories keep the current stacktrace view.

## Access Model

- Hosted Logister should use the official Logister GitHub App.
- Self-hosted Logister operators should create their own GitHub App and configure:
  - `LOGISTER_GITHUB_APP_ID`
  - `LOGISTER_GITHUB_APP_PRIVATE_KEY`
  - `LOGISTER_GITHUB_WEBHOOK_SECRET`
  - `LOGISTER_GITHUB_APP_SLUG` or `LOGISTER_GITHUB_APP_INSTALL_URL`
  - Optional: `LOGISTER_GITHUB_API_URL`, `LOGISTER_GITHUB_WEB_URL`, `LOGISTER_GITHUB_API_VERSION`
- The minimum permissions for the source excerpt MVP are `metadata:read` and `contents:read`.
- Logister stores installation and repository metadata, not long-lived repository tokens. Installation access tokens are generated on demand and cached briefly.
- Setup callbacks verify the `installation_id` through the GitHub App API before syncing repository metadata. The callback `state` is only used as a redirect hint.
- Webhooks must be signed with `X-Hub-Signature-256`; unsigned or incorrectly signed payloads are rejected before parsing.

## Developer Advantages

- Source excerpts beside stack frames, with a GitHub permalink to the exact file and line.
- Private repository support without storing user PATs or long-lived repository credentials.
- Faster triage because runtime paths can map through per-project `runtime_root` and `source_root` settings for monorepos and containers.
- More useful assignment through CODEOWNERS hints and matching Logister project members.
- Release-aware context by trying commit SHA, release, default branch, then `main`.
- Deployment-aware release lookup so plain version strings can resolve to the exact deployed commit.
- Future workflow hooks for issue creation, PR links, fix ownership, and deployment diff context.

## First Build Slice

- Add `github_installations` for GitHub App installation metadata.
- Add `project_source_repositories` so one project can map to many repos.
- Add owner-only settings UI for repo mappings:
  - GitHub repo full name.
  - Default branch.
  - Runtime path prefix seen in stack traces.
  - Optional source root inside the repo.
- Add a source frame resolver that:
  - Uses commit SHA, release, default branch, then `main` as ref candidates.
  - Maps runtime frame paths to repo-relative paths.
  - Fetches file contents through the GitHub App installation token.
  - Returns the same excerpt shape as the current local source helper.
  - Falls back to the current default view if anything cannot be resolved.

## Second Build Slice

- Add the GitHub App setup callback and webhook controller.
- Sync accessible repositories from installation events.
- Let owners pick repos from the installation instead of typing names manually.
- Validate repo access and show clear per-repo status.

## Third Build Slice

- Parse CODEOWNERS files and resolve owners for the selected source file.
- Fetch CODEOWNERS from `.github/CODEOWNERS`, root `CODEOWNERS`, then `docs/CODEOWNERS`.
- Show code owner chips beside resolved GitHub source excerpts.
- Match CODEOWNERS email owners to Logister project members and offer assignment actions.
- Show source lookup diagnostics when GitHub source cannot be resolved.

## Fourth Build Slice

- Add self-host GitHub App diagnostics to project source settings.
- Show whether the App ID, private key, webhook secret, and install URL are configured without exposing secret values.
- Display the exact setup callback URL and webhook URL operators should register in GitHub.
- Show visible GitHub App installations with active/unavailable status, active repository count, and last sync time.
- Add an owner-only manual repository sync action for installations so self-hosters can refresh repository access after GitHub App changes.

## Fifth Build Slice

- Add error group external links for GitHub issues and pull requests.
- Let project members attach and remove existing GitHub issue/PR URLs from the error detail pane.
- Parse and normalize GitHub issue/PR URLs into provider, link type, repository, and external number metadata.
- Show attached GitHub links inside the issue context panel.
- Add a prefilled GitHub draft issue link for source-connected projects without requiring `issues:write`.
- Keep the future API-created issue path separate so optional write permissions can be added deliberately.

## Sixth Build Slice

- Add `project_deployments` as a per-project index from GitHub repo, environment, and release to commit SHA.
- Add `POST /api/v1/deployments` so CI/CD can record deployments without exposing long-lived repository tokens.
- Opportunistically index deployments from normal telemetry when events include `release`, `commit_sha`, and a repository hint.
- Let source frame resolution try the indexed deployment commit before the raw release string, default branch, and `main`.
- Keep deployment indexing independent from GitHub write permissions; it only improves source lookup accuracy.

## Seventh Build Slice

- Add optional API-created GitHub issues for installations with `issues:write`.
- Keep the prefilled draft issue link as the no-write-permission fallback.
- Save created issue URLs as normal error group external links so the UI remains consistent.
- Add a project deployments page for recorded releases, repositories, environments, commits, PRs, releases, and compare links.
- Show deployment diff context on error details, including "this started after deploy X" when the first occurrence follows a recorded deployment.
- Extract PR, release, workflow run, and deployment URLs from GitHub metadata when deployment payloads include them.
- Document `repository`, `commit_sha`, and `branch` event fields plus the `/api/v1/deployments` payload for SDKs and CI/CD systems.
