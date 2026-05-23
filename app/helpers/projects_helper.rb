module ProjectsHelper
  def project_integration_docs_path(project)
    return docs_site_url(:cfml_integration) if project&.integration_cfml?
    return docs_site_url(:dotnet_integration) if project&.integration_dotnet?
    return docs_site_url(:javascript_integration) if project&.integration_javascript?
    return docs_site_url(:python_integration) if project&.integration_python?
    return docs_site_url(:http_api) if project&.integration_http_api?

    docs_site_url(:ruby_integration)
  end

  def project_integration_docs_label(project)
    return "CFML integration docs" if project&.integration_cfml?
    return ".NET integration docs" if project&.integration_dotnet?
    return "JavaScript integration docs" if project&.integration_javascript?
    return "Python integration docs" if project&.integration_python?
    return "HTTP API docs" if project&.integration_http_api?

    "Ruby integration docs"
  end

  def project_collection_path(project)
    project&.archived? ? projects_path(filter: "archived") : projects_path
  end

  def inbox_assignee_options(project, viewer, users = nil)
    assignable_users = users || project.assignable_users
    [
      [ "Everyone", "all" ],
      [ "Assigned to me", "me" ],
      [ "Unassigned", "unassigned" ],
      *assignable_users.map { |user| [ inbox_assignee_label(project, viewer, user), user.uuid ] }
    ]
  end

  def inbox_assignee_label(project, viewer, user)
    label = user.name.presence || user.email
    suffixes = []
    suffixes << "owner" if project.owned_by?(user)
    suffixes << "you" if viewer == user

    suffixes.any? ? "#{label} (#{suffixes.join(", ")})" : label
  end

  def retention_day_options(include_forever: false)
    options = ProjectRetentionPolicy::RETENTION_DAY_OPTIONS.map { |days| [ pluralize(days, "day"), days ] }
    include_forever ? [ [ "Keep error groups forever", "" ], *options ] : options
  end

  def retention_archive_scope_label(scope)
    {
      "hot_events" => "Activity events",
      "trace_spans" => "Trace spans",
      "error_events" => "Error events"
    }.fetch(scope.to_s, scope.to_s.humanize)
  end

  def retention_timestamp(timestamp)
    timestamp.present? ? l(timestamp, format: :long) : "Never"
  end
end
