# frozen_string_literal: true

module Github
  class ConfigurationDiagnostics
    Check = Data.define(:key, :label, :ok, :message) do
      def ok?
        ok
      end
    end

    Result = Data.define(:checks, :setup_url, :webhook_url, :install_url) do
      def ready?
        checks.all?(&:ok?)
      end

      def missing_checks
        checks.reject(&:ok?)
      end
    end

    def self.call(config: Logister::GithubAppConfig, setup_url:, webhook_url:, install_url:)
      new(config: config, setup_url: setup_url, webhook_url: webhook_url, install_url: install_url).call
    end

    def initialize(config:, setup_url:, webhook_url:, install_url:)
      @config = config
      @setup_url = setup_url
      @webhook_url = webhook_url
      @install_url = install_url
    end

    def call
      Result.new(
        checks: checks,
        setup_url: setup_url,
        webhook_url: webhook_url,
        install_url: install_url
      )
    end

    private

    attr_reader :config, :setup_url, :webhook_url, :install_url

    def checks
      [
        check(:app_id, "App ID", config.app_id.present?, "LOGISTER_GITHUB_APP_ID"),
        check(:private_key, "Private key", config.private_key_pem.present?, "LOGISTER_GITHUB_APP_PRIVATE_KEY"),
        check(:webhook_secret, "Webhook secret", config.webhook_secret.present?, "LOGISTER_GITHUB_WEBHOOK_SECRET"),
        check(:install_url, "Install URL", install_url.present?, "LOGISTER_GITHUB_APP_SLUG or LOGISTER_GITHUB_APP_INSTALL_URL")
      ]
    end

    def check(key, label, ok, env_name)
      message = ok ? "#{env_name} is configured." : "#{env_name} is missing."
      Check.new(key: key, label: label, ok: ok, message: message)
    end
  end
end
