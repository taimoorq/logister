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

  # Setup guidance for a page that has nothing to show yet. Pass a `section` to
  # use every step that fills it, or `steps` for the few that matter to this
  # page. Returns nil once those steps are done, so callers keep their own copy.
  def project_setup_prompt(project, section: nil, steps: nil, css: nil)
    plan = if steps
      ProjectSetupPlan.for_steps(project, steps, viewer: current_user)
    else
      ProjectSetupPlan.for_section(project, section, viewer: current_user)
    end
    item = plan.prompt_item(only: steps)
    return unless item

    render partial: "projects/setup_prompt", locals: { project: project, item: item, plan: plan, css: css }
  end

  # What a handed-off step says and where it goes; the page it opens shows a way
  # back (see `setup_return_step`).
  def setup_handoff(project, item, setup_return)
    case item.key
    when :linked_projects
      {
        title: "Link an app and its backend",
        body: "Choose the project on the other side. Logister then lets you follow one failed request across both. Linking never changes who can open either project.",
        action: "Open project links",
        path: project_project_links_path(project, setup_return: setup_return)
      }
    when :archive_exports
      {
        title: "Review archive exports",
        body: "Archive exports write retained telemetry to archive storage before it is deleted. Retention settings control when a run starts.",
        action: "Open data retention",
        path: settings_project_path(project, section: "data", anchor: "retention", setup_return: setup_return)
      }
    else
      raise ArgumentError, "No handoff for setup step #{item.key}"
    end
  end

  # Values chosen in earlier creation steps, carried forward as hidden fields.
  # `owns` names the fields this step edits itself, so they are not repeated.
  def project_creation_carry_fields(carried, owns:)
    fields = carried.reject { |name, _value| owns.any? { |field| name.start_with?("project[#{field}") } }
    safe_join(fields.map { |name, value| hidden_field_tag(name, value, id: nil) })
  end

  # A slim way back to the setup path for pages a step hands off to. Only shown
  # for a step this project's setup actually contains.
  def setup_return_step(project)
    group, step = params[:setup_return].to_s.split("/", 2)
    return if group.blank? || step.blank?

    experience = project.integration_definition.default_experience_key
    definition = ProjectSetupCatalog.steps_for(experience).find { |candidate| candidate.group_key.to_s == group && candidate.key.to_s == step }
    return unless definition

    { group: ProjectSetupCatalog.group(definition.group_key), step: definition }
  end

  # Forms shared with Settings carry this when they are shown inside a setup
  # wizard step, so the controller returns to the step instead of Settings.
  def setup_return_field
    hidden_field_tag(:setup_return, @setup_return) if @setup_return.present?
  end

  # A wizard form stays a normal Turbo form (progress, busy state, no full reload)
  # but targets the whole page, so the step re-renders with what just changed. An
  # embedded form can sit inside a Frame of its own, and without this only that
  # Frame would update while the step's Continue and completion state went stale.
  def setup_form_data
    @setup_return.present? ? { turbo_frame: "_top" } : {}
  end

  # The link for a section view. Inside Explore, Events, Charts and Connected share
  # one scope (time window, environment, release, and build for mobile), so it is
  # carried to the view you switch to rather than reset. Returns the path and the
  # scope that could not carry over, if any.
  def project_view_link(page_context, view)
    path = page_context.path_for(view)
    return [ path, [] ] unless page_context.navigation.current_tab&.key == :explore

    scope = ProjectTelemetryScope.from(project: page_context.project, source: request.query_parameters)
    params, dropped = case view.key
    when :activity, :insights, :connections
      projection = scope.project_for(view.key)
      [ projection.params, projection.dropped ]
    else
      [ {}, [] ]
    end

    [ params.present? ? "#{path}?#{params.to_query}" : path, dropped ]
  end

  # Where the project menu sends you for another project: the same section you
  # are in now (Issues stays Issues), or the overview outside a project.
  def project_switch_path(project)
    section = content_for(:project_section).presence
    section ? ProjectPageRoutes.section_path(project, section) : project_path(project)
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

  def capability_status_badge(status)
    case status.state
    when :configured
      { label: "Current", classes: "border-emerald-200 bg-emerald-50 text-emerald-800" }
    when :failed
      { label: "Sync failed", classes: "border-red-200 bg-red-50 text-red-800" }
    when :stale
      { label: "Stale", classes: "border-amber-200 bg-amber-50 text-amber-800" }
    when :partial
      { label: "Ready to sync", classes: "border-amber-200 bg-amber-50 text-amber-800" }
    else
      { label: status.state.to_s.humanize, classes: "border-slate-200 bg-slate-50 text-slate-600" }
    end
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
