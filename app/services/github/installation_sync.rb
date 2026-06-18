# frozen_string_literal: true

module Github
  class InstallationSync
    Result = Data.define(:status, :installation, :repositories)

    class Error < StandardError; end

    def self.from_setup(installation_id:, installed_by:, app_client: AppClient.new, repositories_client: InstallationRepositoriesClient.new)
      new(app_client: app_client, repositories_client: repositories_client).from_setup(
        installation_id: installation_id,
        installed_by: installed_by
      )
    end

    def self.from_webhook(event:, payload:, repositories_client: InstallationRepositoriesClient.new)
      new(repositories_client: repositories_client).from_webhook(event: event, payload: payload)
    end

    def self.resync(installation:, repositories_client: InstallationRepositoriesClient.new)
      new(repositories_client: repositories_client).resync(installation: installation)
    end

    def initialize(app_client: nil, repositories_client:)
      @app_client = app_client
      @repositories_client = repositories_client
    end

    def from_setup(installation_id:, installed_by:)
      payload = app_client.installation(Integer(installation_id))
      installation = upsert_installation(payload, installed_by: installed_by)
      repositories = sync_repositories(installation, repositories_client.list(installation: installation), replace: true)

      Result.new(status: :synced, installation: installation, repositories: repositories)
    rescue ArgumentError
      raise Error, "Invalid GitHub installation id"
    end

    def resync(installation:)
      raise Error, "GitHub installation is unavailable" unless installation&.available?

      repositories = sync_repositories(installation, repositories_client.list(installation: installation), replace: true)
      Result.new(status: :synced, installation: installation, repositories: repositories)
    end

    def from_webhook(event:, payload:)
      case event.to_s
      when "ping"
        installation_payload = payload["installation"]
        installation = installation_payload.present? ? upsert_installation(installation_payload) : nil
        Result.new(status: :pong, installation: installation, repositories: [])
      when "installation"
        sync_installation_event(payload)
      when "installation_repositories"
        sync_installation_repositories_event(payload)
      else
        Result.new(status: :ignored, installation: nil, repositories: [])
      end
    end

    private

    attr_reader :app_client, :repositories_client

    def sync_installation_event(payload)
      installation = upsert_installation(payload.fetch("installation"))
      action = payload["action"].to_s

      case action
      when "created", "new_permissions_accepted"
        repositories = Array(payload["repositories"]).presence || repositories_client.list(installation: installation)
        synced = sync_repositories(installation, repositories, replace: true)
        Result.new(status: :synced, installation: installation, repositories: synced)
      when "deleted"
        installation.update!(active: false, suspended_at: Time.current)
        installation.github_repositories.update_all(active: false, updated_at: Time.current)
        Result.new(status: :deleted, installation: installation, repositories: [])
      when "suspend"
        installation.update!(suspended_at: Time.current)
        Result.new(status: :suspended, installation: installation, repositories: [])
      when "unsuspend"
        installation.update!(active: true, suspended_at: nil)
        Result.new(status: :unsuspended, installation: installation, repositories: [])
      else
        Result.new(status: :ignored, installation: installation, repositories: [])
      end
    end

    def sync_installation_repositories_event(payload)
      installation = upsert_installation(payload.fetch("installation"))
      removed_ids = Array(payload["repositories_removed"]).filter_map { |repository| repository["id"] }
      installation.github_repositories.where(external_id: removed_ids).update_all(active: false, updated_at: Time.current) if removed_ids.any?

      added = sync_repositories(installation, Array(payload["repositories_added"]), replace: false)
      Result.new(status: :synced, installation: installation, repositories: added)
    end

    def upsert_installation(payload, installed_by: nil)
      account = payload["account"].is_a?(Hash) ? payload["account"] : {}
      installation = GithubInstallation.find_or_initialize_by(installation_id: payload.fetch("id"))
      installation.assign_attributes(
        account_login: account["login"] || payload["account_login"] || "unknown",
        account_type: account["type"] || payload["account_type"],
        repository_selection: payload["repository_selection"],
        active: true,
        suspended_at: parse_time(payload["suspended_at"]),
        installed_by: installed_by || installation.installed_by,
        permissions: payload["permissions"].is_a?(Hash) ? payload["permissions"] : installation.permissions,
        events: payload["events"].is_a?(Array) ? payload["events"] : installation.events
      )
      installation.save!
      installation
    end

    def sync_repositories(installation, repository_payloads, replace:)
      now = Time.current
      active_ids = []
      repositories = Array(repository_payloads).filter_map do |payload|
        repository = upsert_repository(installation, payload, now: now)
        active_ids << repository.external_id
        repository
      end

      if replace
        stale_repositories = installation.github_repositories
        stale_repositories = stale_repositories.where.not(external_id: active_ids) if active_ids.any?
        stale_repositories.update_all(active: false, updated_at: now)
      end

      repositories
    end

    def upsert_repository(installation, payload, now:)
      full_name = payload["full_name"].presence || [ payload.dig("owner", "login"), payload["name"] ].compact_blank.join("/")
      repository = GithubRepository.find_or_initialize_by(external_id: payload.fetch("id"))
      repository.assign_attributes(
        github_installation: installation,
        full_name: full_name,
        default_branch: payload["default_branch"],
        html_url: payload["html_url"],
        private: payload.key?("private") ? payload["private"] : true,
        archived: payload.key?("archived") ? payload["archived"] : false,
        active: true,
        permissions: payload["permissions"].is_a?(Hash) ? payload["permissions"] : {},
        metadata: repository_metadata(payload),
        last_synced_at: now
      )
      repository.save!
      repository
    end

    def repository_metadata(payload)
      {
        "description" => payload["description"],
        "language" => payload["language"],
        "pushed_at" => payload["pushed_at"],
        "updated_at" => payload["updated_at"]
      }.compact
    end

    def parse_time(value)
      return if value.blank?

      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
