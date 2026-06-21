module ProjectsHelper
  INTEGRATION_PICKER_DETAILS = {
    "ruby" => {
      label: "Ruby gem",
      badge: "Gem",
      description: "Rails apps, Ruby services, jobs, and custom Ruby telemetry."
    },
    "dotnet" => {
      label: ".NET / ASP.NET Core",
      badge: "NuGet",
      description: "ASP.NET Core apps, C# workers, and custom .NET telemetry."
    },
    "cloudflare_pages" => {
      label: "Cloudflare Pages",
      badge: "HTTP",
      description: "Pages deployment and traffic signals through manual HTTP telemetry today."
    },
    "android" => {
      label: "Android app",
      badge: "Gradle",
      description: "Android telemetry through logister-android and backend-issued ingest tokens."
    },
    "ios" => {
      label: "iOS app",
      badge: "SPM",
      description: "iOS telemetry through logister-ios and backend-issued ingest tokens."
    },
    "cfml" => {
      label: "CFML",
      badge: "CFML",
      description: "ColdFusion and Lucee apps that send structured server errors."
    },
    "javascript" => {
      label: "JavaScript / TypeScript",
      badge: "npm",
      description: "Node, TypeScript, Express, workers, console logs, and browser timing with logister-js."
    },
    "python" => {
      label: "Python",
      badge: "PyPI",
      description: "FastAPI, Django, Flask, Celery, Python workers, and native logging with logister-python."
    },
    "http_api" => {
      label: "Manual / HTTP API",
      badge: "Manual",
      description: "Any runtime, script, worker, or custom client that posts JSON directly."
    }
  }.freeze

  def project_integration_picker_choices
    Project.integration_options.map do |_label, value|
      INTEGRATION_PICKER_DETAILS.fetch(value).merge(value: value)
    end
  end

  def project_integration_docs_path(project)
    return docs_site_url(:cfml_integration) if project&.integration_cfml?
    return docs_site_url(:dotnet_integration) if project&.integration_dotnet?
    return docs_site_url(:javascript_integration) if project&.integration_javascript?
    return docs_site_url(:python_integration) if project&.integration_python?
    return docs_site_url(:http_api) if project&.integration_http_api?
    return docs_site_url(:cloudflare_pages_integration) if project&.integration_cloudflare_pages?
    return docs_site_url(:android_integration) if project&.integration_android?
    return docs_site_url(:ios_integration) if project&.integration_ios?

    docs_site_url(:ruby_integration)
  end

  def project_integration_docs_label(project)
    return "CFML integration docs" if project&.integration_cfml?
    return ".NET integration docs" if project&.integration_dotnet?
    return "JavaScript integration docs" if project&.integration_javascript?
    return "Python integration docs" if project&.integration_python?
    return "HTTP API docs" if project&.integration_http_api?
    return "Cloudflare Pages docs" if project&.integration_cloudflare_pages?
    return "Android SDK docs" if project&.integration_android?
    return "iOS SDK docs" if project&.integration_ios?

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

  def project_setup_code_block_class
    responsive_scroll_classes("rounded-lg bg-slate-900 text-slate-100 p-4 text-sm font-mono")
  end
end
