# Error Assignment Plan

This is a planning note for assigning project errors to users without changing the product yet.

## Goals

- Let project members assign an error group to a user who has access to the project.
- Add inbox filters for `Assigned to me`, `Unassigned`, and a selected teammate.
- Keep the inbox fast for large projects by making assignment filters server-side and indexed.
- Use Hotwire and Stimulus in the same style as the current project inbox: Turbo owns navigation and partial replacement; Stimulus handles small interaction details.

## Data Model

Assignment should live on `error_groups`, not on individual events. An error group is the durable issue users triage, while occurrences are the event history behind that issue.

Add nullable columns to `error_groups`:

- `assigned_user_id`
- `assigned_by_user_id`
- `assigned_at`

Model associations:

- `ErrorGroup belongs_to :assignee, class_name: "User", optional: true`
- `ErrorGroup belongs_to :assigned_by, class_name: "User", optional: true`
- `User has_many :assigned_error_groups, class_name: "ErrorGroup", foreign_key: :assigned_user_id`

Validation rules:

- The assignee must be the project owner or an active project member.
- Assignments should be cleared if that user loses access to the project.
- Archived project-level behavior should remain unchanged: archived projects keep their data, but are not part of active dashboard and project lists unless the user chooses archived/all views.

## Indexes

The inbox commonly filters by project, status, assignee, and recent activity. Add composite indexes that match those access paths:

```ruby
add_index :error_groups,
  [ :project_id, :assigned_user_id, :status, :last_seen_at ],
  name: "index_error_groups_on_project_assignee_status_last_seen"

add_index :error_groups,
  [ :project_id, :status, :assigned_user_id, :last_seen_at ],
  name: "index_error_groups_on_project_status_assignee_last_seen"
```

Keep the existing query-search indexes for text filtering. If assignment filters and text search are combined, apply the project/status/assignee scope first and then the sanitized text condition.

## Server Flow

Add an `ErrorGroupAssignmentsController` nested under projects:

```ruby
resources :error_groups, only: [], param: :uuid do
  resource :assignment, only: [ :update, :destroy ], controller: "error_group_assignments"
end
```

Controller responsibilities:

- Resolve the project through `ProjectScope` so existing authorization rules apply.
- Resolve the error group through `@project.error_groups.find_by!(uuid: params[:error_group_uuid])`.
- Resolve the assignee through project-accessible users only.
- `PATCH` assigns or reassigns the group.
- `DELETE` clears the assignment.
- Respond with Turbo Streams for the inbox row, detail panel, and counts when the request came from the inbox.

## Inbox Filtering

Keep the current status filter and add an assignment filter:

- `assignee=all`
- `assignee=me`
- `assignee=unassigned`
- `assignee=<user_uuid>`

Update `ProjectInboxData#inbox_groups` and `#inbox_counts` to accept `assignee:`. Counts should either remain status-only by default or expose a second small count set for assignment chips if the UI needs it.

Cache keys must include the normalized assignment filter:

```ruby
[
  "project",
  project.id,
  "inbox_groups",
  normalized_filter,
  normalized_assignee_filter,
  Digest::SHA256.hexdigest(normalized_query),
  inbox_cache_version(project)
]
```

The cache version can continue to use `error_groups.maximum(:updated_at)` because assignment changes update the group.

## UI

Project inbox:

- Add a compact assignee control beside the search/status filters.
- Use options for Everyone, Mine, Unassigned, and project users.
- Show assignee chips in the inbox row and detail panel.
- Prefer one-click self-assignment from the detail panel for the common case.

Project settings:

- No broad assignment configuration is needed initially.
- The existing project access section remains the source of who can be assigned.

Hotwire and Stimulus:

- Let Turbo reload the inbox frame when filters change.
- Use Stimulus only for combobox/open-close behavior if the assignee picker needs it.
- Preserve deep links by keeping `filter`, `assignee`, and `q` in the query string.

## Notifications

Do not send new assignment emails in the first version unless users explicitly ask for them. The current email plan already covers first occurrence and digest summaries. Assignment changes can be added later as a separate notification preference so teams are not surprised by extra mail.

## Tests

Model tests:

- Assign to owner.
- Assign to project member.
- Reject assignment to a user without project access.
- Clear assignment when access is removed.

Request tests:

- Owner/member can assign and unassign.
- Unauthorized users cannot assign.
- Inbox supports `assignee=me`, `assignee=unassigned`, and teammate filters.
- Turbo Stream response updates the expected targets.

Performance checks:

- Confirm the assignment-filtered inbox uses the composite indexes with realistic row counts.
- Keep inbox result limits in place and load details only for visible groups.

## Rollout

1. Add the columns, associations, validations, and indexes.
2. Add assignment routes and controller behavior.
3. Add inbox filtering in `ProjectInboxData`.
4. Add inbox row/detail UI and Turbo Stream updates.
5. Add tests and verify query plans with seeded or restored production-like data.
