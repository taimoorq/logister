# frozen_string_literal: true

class ProjectGithubIntegrationState
  DashboardMetric = Data.define(:key, :label, :value, :detail, :icon, :tone)
  DashboardAction = Data.define(:key, :label, :description, :icon, :target, :external, :primary) do
    def external?
      external
    end

    def primary?
      primary
    end
  end

  def initialize(project:, user:, source_repositories: nil, app_diagnostics: nil)
    @project = project
    @user = user
    @source_repositories = source_repositories
    @app_diagnostics = app_diagnostics
  end

  def project_installations
    @project_installations ||= project.project_github_installations
                                      .includes(github_installation: :github_repositories)
                                      .order(created_at: :asc)
  end

  def linked_installations
    @linked_installations ||= project.github_installations
                                     .includes(:github_repositories)
                                     .order(updated_at: :desc)
  end

  def linkable_installations
    @linkable_installations ||= GithubInstallation.linkable_by(user)
                                                 .where.not(id: linked_installation_ids)
                                                 .includes(:github_repositories)
                                                 .order(updated_at: :desc)
  end

  def available_repositories
    @available_repositories ||= GithubRepository.available_for_project(project)
                                               .includes(:github_installation)
                                               .order(:full_name)
  end

  def connectable_repositories
    @connectable_repositories ||= available_repositories.reject do |repository|
      connected_repository_full_names.include?(repository.full_name.downcase)
    end
  end

  def app_connection_healthy?
    app_connection_status == :healthy
  end

  def app_connection_needs_attention?
    app_connection_status != :healthy
  end

  def app_access_details_open?
    app_connection_needs_attention?
  end

  def app_connection_label
    app_connection_healthy? ? "GitHub connection healthy" : "GitHub connection needs setup"
  end

  def app_connection_message
    return "GitHub App configuration is incomplete." unless app_configuration_ready?
    return "No GitHub App installation is linked to this project." if linked_installations.empty?
    return "Linked GitHub App installations are unavailable." if linked_installations.none?(&:available?)

    "Linked installations can sync repositories for this project."
  end

  def app_connection_status
    return :configuration_missing unless app_configuration_ready?
    return :missing_installation if linked_installations.empty?
    return :installation_unavailable if linked_installations.none?(&:available?)

    :healthy
  end

  def app_connection_status_label
    case app_connection_status
    when :healthy then "Healthy"
    when :configuration_missing then "Configuration incomplete"
    when :missing_installation then "App not installed"
    when :installation_unavailable then "Installation unavailable"
    else "Needs attention"
    end
  end

  def app_connection_tone
    case app_connection_status
    when :healthy then :success
    when :configuration_missing then :danger
    else :warning
    end
  end

  def dashboard_metrics
    [
      dashboard_metric(
        :app,
        "App health",
        app_connection_status_label,
        app_connection_message,
        :integrations,
        app_connection_tone
      ),
      dashboard_metric(
        :installations,
        "Installations",
        linked_installation_count.to_s,
        linkable_installation_detail,
        :settings,
        linked_installations.any?(&:available?) ? :success : :warning
      ),
      dashboard_metric(
        :repositories,
        "Connected repos",
        connected_repository_count.to_s,
        connectable_repository_detail,
        :source_code,
        connected_repository_count.positive? ? :success : :muted
      ),
      dashboard_metric(
        :synced,
        "Synced repos",
        available_repository_count.to_s,
        "Available from linked GitHub App installations.",
        :folder_open,
        available_repository_count.positive? ? :info : :muted
      )
    ]
  end

  def dashboard_actions
    case app_connection_status
    when :configuration_missing
      configuration_missing_actions
    when :missing_installation
      missing_installation_actions
    when :installation_unavailable
      unavailable_installation_actions
    else
      healthy_connection_actions
    end
  end

  def linked_installation_count
    linked_installations.size
  end

  def linkable_installation_count
    linkable_installations.size
  end

  def connected_repository_count
    source_repositories.size
  end

  def available_repository_count
    available_repositories.size
  end

  def connectable_repository_count
    connectable_repositories.size
  end

  private

  attr_reader :project, :user, :app_diagnostics

  def app_configuration_ready?
    app_diagnostics&.ready?
  end

  def linked_installation_ids
    linked_installations.map(&:id)
  end

  def source_repositories
    @source_repositories ||= project.source_repositories
                                    .includes(:github_installation, github_repository: :github_installation)
                                    .order(:provider, :full_name)
  end

  def connected_repository_full_names
    @connected_repository_full_names ||= source_repositories.map { |source_repository| source_repository.full_name.downcase }
  end

  def app_install_url_present?
    app_diagnostics&.install_url.present?
  end

  def dashboard_metric(key, label, value, detail, icon, tone)
    DashboardMetric.new(key: key, label: label, value: value, detail: detail, icon: icon, tone: tone)
  end

  def dashboard_action(key, label, description, icon, target, external: false, primary: false)
    DashboardAction.new(
      key: key,
      label: label,
      description: description,
      icon: icon,
      target: target,
      external: external,
      primary: primary
    )
  end

  def configuration_missing_actions
    [
      dashboard_action(
        :github_app_docs,
        "Open setup docs",
        "Configure the GitHub App credentials, webhook secret, install URL, callback, and webhook.",
        :guide,
        :github_app_docs,
        external: true,
        primary: true
      ),
      dashboard_action(
        :github_app_access,
        "View callback settings",
        "Copy the callback and webhook URLs into the GitHub App settings.",
        :settings,
        :github_app_access
      )
    ]
  end

  def missing_installation_actions
    actions = []
    if app_install_url_present?
      actions << dashboard_action(
        :install_github_app,
        "Install GitHub App",
        "Add a GitHub App installation and return here to link repositories.",
        :external,
        :github_app_install_url,
        external: true,
        primary: true
      )
    end
    if linkable_installations.any?
      actions << dashboard_action(
        :link_existing_installation,
        "Link existing installation",
        "Use a GitHub App installation you already added to this account.",
        :settings,
        :available_github_installations,
        primary: actions.empty?
      )
    end
    actions << dashboard_action(
      :github_app_docs,
      "Review setup docs",
      "Check the callback, webhook, permissions, and setup flow before installing.",
      :guide,
      :github_app_docs,
      external: true,
      primary: actions.empty?
    )
    actions
  end

  def unavailable_installation_actions
    actions = [
      dashboard_action(
        :review_installations,
        "Review linked installations",
        "Check suspended or unavailable installations before syncing repositories.",
        :warning,
        :linked_github_installations,
        primary: true
      )
    ]
    if app_install_url_present?
      actions << dashboard_action(
        :install_github_app,
        "Install another app",
        "Add an active GitHub App installation for this project.",
        :external,
        :github_app_install_url,
        external: true
      )
    end
    actions
  end

  def healthy_connection_actions
    if connectable_repository_count.positive?
      [
        dashboard_action(
          :connect_repositories,
          "Connect repositories",
          "Select synced repositories to power source lookup and GitHub issue actions.",
          :plus,
          :available_source_repositories,
          primary: true
        ),
        dashboard_action(
          :manage_app_access,
          "Manage App access",
          "Sync, link, or unlink GitHub App installations for this project.",
          :settings,
          :github_app_access
        )
      ]
    elsif connected_repository_count.zero?
      [
        dashboard_action(
          :add_repository,
          "Add repository",
          "Sync GitHub repositories or add a manual owner/repository mapping.",
          :plus,
          :available_source_repositories,
          primary: true
        ),
        dashboard_action(
          :manage_app_access,
          "Manage App access",
          "Sync linked installations to discover repositories.",
          :settings,
          :github_app_access
        )
      ]
    else
      [
        dashboard_action(
          :manage_repositories,
          "Manage repositories",
          "Edit branches, runtime prefixes, source roots, and repository access.",
          :source_code,
          :connected_source_repositories,
          primary: true
        ),
        dashboard_action(
          :manage_app_access,
          "Manage App access",
          "Sync, link, or unlink GitHub App installations for this project.",
          :settings,
          :github_app_access
        )
      ]
    end
  end

  def linkable_installation_detail
    return "#{linkable_installation_count} available to link." if linkable_installation_count.positive?
    return "No linked GitHub App installation yet." if linked_installation_count.zero?

    "Linked installations for this project."
  end

  def connectable_repository_detail
    return "#{connectable_repository_count} ready to connect." if connectable_repository_count.positive?
    return "No project repositories connected yet." if connected_repository_count.zero?

    "Source lookup can use these mappings."
  end
end
