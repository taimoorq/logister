module ProjectsHelper
  def project_page_context(project, page_key: nil)
    key = [ project.object_id, request.path, page_key, current_user&.id, respond_to?(:admin_user?) && admin_user? ]
    @project_page_contexts ||= {}
    @project_page_contexts[key] ||= ProjectPageContext.for(
      project: project,
      viewer: current_user,
      request_path: request.path,
      app_admin: respond_to?(:admin_user?) && admin_user?,
      page_key: page_key
    )
  end

  def project_integration_picker_choices
    ProjectIntegrationDefinition.all_for_picker.map do |definition|
      {
        value: definition.key,
        label: definition.label,
        badge: definition.picker_badge,
        description: definition.picker_description
      }
    end
  end

  def project_integration_docs_path(project)
    docs_site_url(integration_definition_for(project).documentation_key)
  end

  def project_integration_docs_label(project)
    integration_definition_for(project).documentation_label
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

  def profile_filter_hidden_fields(form, filters)
    safe_join(filters.filter_map { |key, value| form.hidden_field(key, value: value) })
  end

  def inbox_assignee_label(project, viewer, user)
    label = user_display_name(user)
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

  private def integration_definition_for(project)
    project&.integration_definition || ProjectIntegrationDefinition.fetch(:ruby)
  end

  def archive_status_badge_class(tone)
    {
      danger: "bg-red-50 text-red-700 border-red-200",
      info: "bg-blue-50 text-blue-700 border-blue-200",
      muted: "bg-slate-100 text-slate-600 border-slate-200",
      success: "bg-emerald-50 text-emerald-700 border-emerald-200",
      warning: "bg-amber-50 text-amber-700 border-amber-200"
    }.fetch(tone.to_sym, "bg-slate-100 text-slate-600 border-slate-200")
  end

  def archive_boolean_label(value, enabled:, disabled:)
    value ? enabled : disabled
  end

  def archive_count_or_dash(value)
    value.nil? ? "--" : number_with_delimiter(value)
  end

  def github_integration_status_classes(tone)
    {
      danger: "border-red-200 bg-red-50 text-red-800",
      info: "border-blue-200 bg-blue-50 text-blue-800",
      muted: "border-slate-200 bg-slate-50 text-slate-700",
      success: "border-emerald-200 bg-emerald-50 text-emerald-800",
      warning: "border-amber-200 bg-amber-50 text-amber-800"
    }.fetch(tone.to_sym, "border-slate-200 bg-slate-50 text-slate-700")
  end

  def github_integration_metric_classes(tone)
    {
      danger: "border-l-red-500 bg-red-50 ring-red-100",
      info: "border-l-blue-500 bg-blue-50 ring-blue-100",
      muted: "border-l-slate-400 bg-slate-50 ring-slate-200",
      success: "border-l-emerald-500 bg-emerald-50 ring-emerald-100",
      warning: "border-l-amber-500 bg-amber-50 ring-amber-100"
    }.fetch(tone.to_sym, "border-l-slate-400 bg-slate-50 ring-slate-200")
  end

  def github_integration_action_href(action)
    case action.target
    when :github_app_docs then docs_site_url(:github_app)
    when :github_app_install_url then @github_app_install_url
    when :github_app_access then "#github-app-access"
    when :linked_github_installations then "#linked-github-installations"
    when :available_github_installations then "#available-github-installations"
    when :available_source_repositories then "#available-source-repositories"
    when :connected_source_repositories then "#connected-source-repositories"
    else "#source-repositories"
    end
  end

  def github_integration_action_classes(action)
    base = "inline-flex items-center justify-center gap-2 rounded-lg px-4 py-2.5 text-sm font-semibold no-underline"
    return "#{base} bg-blue-600 text-white hover:bg-blue-700" if action.primary?

    "#{base} border border-slate-300 bg-white text-slate-700 hover:bg-slate-50 hover:text-slate-900"
  end

  def project_setup_code_block_class
    responsive_scroll_classes("rounded-lg bg-slate-900 text-slate-100 p-4 text-sm font-mono")
  end
end
