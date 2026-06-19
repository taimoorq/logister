# Project-Scoped GitHub Integration Plan

Status: implemented on 2026-06-19.

## Summary

The Logister project is the GitHub integration boundary. A GitHub App installation still belongs to a GitHub user, organization, or enterprise account and can be reused across Logister projects, but each Logister project explicitly links an installation and explicitly connects repositories from that installation.

No repository is auto-connected by project name, sole synced repository, or telemetry. Project owners and project admins choose from all active repositories exposed by installations linked to the project. Viewers can see project data they are allowed to access, but they cannot manage GitHub integration state or source repository mappings.

## Design Decisions

- Keep `GithubInstallation` scoped to the GitHub account or organization where the App is installed.
- Add `ProjectGithubInstallation` as the project-level join between a Logister project and a GitHub App installation.
- Use `ProjectSourceRepository` as the explicit project-to-repository source mapping.
- Keep `GithubInstallation#installed_by` as audit and provenance, not the main project authorization boundary.
- Treat project managers as project owners plus project admins.
- Allow one GitHub installation to be linked to many Logister projects.
- Keep source repository mappings independent per project, even when multiple projects use the same GitHub installation and repository.
- Keep manual `owner/repo` source mappings as an advanced fallback for self-hosted operators.

## Authorization

Project managers can manage day-to-day project configuration:

- integrations
- team invitations and membership roles
- API keys
- notifications
- data and retention settings
- source repository mappings
- GitHub installation links and syncs

Only project owners can perform destructive ownership-level actions:

- delete
- archive
- transfer ownership
- danger-zone settings

Project viewers cannot access integration management routes or mutate source repository mappings.

## Data Model

- `ProjectMembership.role` supports `viewer` and `admin`.
- `ProjectGithubInstallation` joins `Project` to `GithubInstallation` and records `linked_by`.
- `GithubInstallation` remains reusable and account-scoped.
- `GithubRepository` stores synced repository metadata for a GitHub installation.
- `ProjectSourceRepository` stores the project-specific source lookup mapping, including runtime root, source root, default branch, and optional synced GitHub repository metadata.

Backfill links only from existing source repository mappings that already reference a GitHub installation or synced GitHub repository. Do not infer links from matching names or telemetry.

## Setup And Sync

- GitHub setup callbacks verify and sync the installation through the GitHub App API.
- When callback `state` points to a manageable project, Logister links the synced installation to that project.
- Setup sync does not create `ProjectSourceRepository` rows.
- Manual sync is available to project managers only.
- Sync is allowed only for installations already linked to the project.
- Webhook and GitHub permission changes continue to update the account-scoped installation and repository metadata.

## Project Settings UI

The project integrations settings page owns the GitHub workflow:

- Show GitHub App configuration diagnostics without exposing secrets.
- Show linked GitHub App installations for the project, including active/unavailable status, active repository count, last sync time, sync, and unlink controls.
- Show eligible existing installations with an explicit `Link to project` action.
- Disable link and sync actions for unavailable installations.
- Show all active synced repositories from linked installations in an "Available repositories" list.
- Show `Connect` only for repositories not already connected to the project.
- Show connected repositories separately, with runtime root, source root, default branch, enabled, and remove controls.
- Keep the advanced manual `owner/repo` form available for fallback cases.
- Keep validation errors on the same settings page and open the advanced manual form when manual entry fails.

## Source Repository Connection

Repository connection is centralized in `ProjectSourceRepositoryConnector`:

- If no synced repository is selected, build or update a manual mapping.
- If a synced repository is selected, require it to come from an installation linked to the project.
- If a manual mapping already exists for the same `owner/repo`, upgrade that mapping by attaching the synced `GithubRepository` and installation metadata.
- Reject attempts to connect repositories from unlinked installations.
- Never create mappings automatically after setup, sync, or telemetry ingestion.

## Shared Logic

The implementation keeps policy out of views and controllers:

- `Project#managed_by?`, `Project.manageable_by`, and `User#manageable_projects` centralize project manager access.
- `ProjectSettingsNavigation` centralizes settings tab visibility and selected-section fallback.
- `ProjectGithubIntegrationState` centralizes linked installations, linkable installations, available repositories, and connectable repositories.
- `ProjectSourceRepositoryConnector` centralizes source repository build, upgrade, and rejection behavior.

## Edge Cases

- A project admin who did not install the GitHub App can manage repos from installations already linked to the project.
- Project admins can link their own eligible existing installations to a project they manage.
- Viewers cannot link, sync, connect, update, or remove source repositories.
- Unlinked installation repositories never appear in the project repo picker.
- Inactive, suspended, or archived repositories are hidden from available repository choices.
- Unavailable installations remain visible but cannot be synced or linked.
- Connected repositories are removed from the available connect list.
- A single GitHub installation can be linked to multiple projects.
- Each project maintains independent source repository mappings even when using the same installation and repository.
- Source lookup diagnostics continue to show a missing mapping warning until a repository is explicitly connected.
- Source lookup resolves after an explicit mapping is connected and runtime/source root settings match the stack frame.

## Test Coverage

- `spec/models/project_membership_spec.rb`: project admin role options and normalization.
- `spec/models/project_spec.rb`: project manager scopes and ownership/admin checks.
- `spec/models/user_spec.rb`: manageable project access.
- `spec/models/project_settings_navigation_spec.rb`: manager tabs, owner-only danger controls, and app-admin settings.
- `spec/models/project_github_integration_state_spec.rb`: linked installations, linkable installations, available repos, and connectable repos.
- `spec/models/project_github_installation_spec.rb`: project-installation join behavior.
- `spec/services/project_source_repository_connector_spec.rb`: manual mappings, linked repo connections, manual mapping upgrades, unlinked repo rejection, and independent mappings across projects.
- `spec/services/source_frame_resolver_spec.rb`: source diagnostics before explicit connection and source resolution after connection.
- `spec/requests/github_setup_spec.rb`: setup sync creates a project link without auto-connecting repos.
- `spec/requests/github_installations_spec.rb`: linked installation sync, explicit installation linking, admin linking, viewer rejection, and linked repo exposure.
- `spec/requests/project_source_repositories_spec.rb`: settings UI, project admin management, connect actions, unlinked repo hiding, unavailable action disabling, validation UI, and viewer rejection.
- `spec/requests/project_memberships_spec.rb`: owners and admins managing team roles.
- `spec/requests/api_keys_spec.rb`, `spec/requests/project_integration_settings_spec.rb`, `spec/requests/project_retention_policies_spec.rb`: project admin management permissions outside GitHub.

## Operator Docs

The public GitHub App guide in `cloudflare-docs/github-app/index.html` should describe this project-scoped model:

- install or link a GitHub App installation from project settings
- sync repository metadata
- connect repositories explicitly from linked installations
- configure runtime root, source root, and default branch on connected mappings
- do not expect setup, sync, or telemetry to auto-connect repositories

Run `bin/build-cloudflare-docs` after changing the public docs so sitemap, robots, and discovery metadata stay current.
