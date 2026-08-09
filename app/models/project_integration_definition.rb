# frozen_string_literal: true

class ProjectIntegrationDefinition < Data.define(
  :key,
  :version,
  :label,
  :picker_label,
  :picker_badge,
  :picker_description,
  :picker_order,
  :icon_key,
  :documentation_key,
  :documentation_label,
  :allowed_experience_keys,
  :default_experience_key
)
  DEFINITIONS = [
    new(
      key: "ruby",
      version: 1,
      label: "Ruby gem",
      picker_label: "Ruby gem",
      picker_badge: "Gem",
      picker_description: "Rails apps, Ruby services, jobs, and custom Ruby telemetry.",
      picker_order: 5,
      icon_key: :project_ruby,
      documentation_key: :ruby_integration,
      documentation_label: "Ruby integration docs",
      allowed_experience_keys: %i[server].freeze,
      default_experience_key: :server
    ).freeze,
    new(
      key: "cfml",
      version: 1,
      label: "CFML",
      picker_label: "CFML",
      picker_badge: "CFML",
      picker_description: "ColdFusion and Lucee apps that send structured server errors.",
      picker_order: 9,
      icon_key: :project_cfml,
      documentation_key: :cfml_integration,
      documentation_label: "CFML integration docs",
      allowed_experience_keys: %i[server].freeze,
      default_experience_key: :server
    ).freeze,
    new(
      key: "javascript",
      version: 1,
      label: "JavaScript / TypeScript",
      picker_label: "JavaScript / TypeScript (logister-js)",
      picker_badge: "npm",
      picker_description: "Node, TypeScript, Express, workers, console logs, and browser timing with logister-js.",
      picker_order: 7,
      icon_key: :project_javascript,
      documentation_key: :javascript_integration,
      documentation_label: "JavaScript integration docs",
      allowed_experience_keys: %i[server].freeze,
      default_experience_key: :server
    ).freeze,
    new(
      key: "python",
      version: 1,
      label: "Python",
      picker_label: "Python (logister-python)",
      picker_badge: "PyPI",
      picker_description: "FastAPI, Django, Flask, Celery, Python workers, and native logging with logister-python.",
      picker_order: 8,
      icon_key: :project_python,
      documentation_key: :python_integration,
      documentation_label: "Python integration docs",
      allowed_experience_keys: %i[server].freeze,
      default_experience_key: :server
    ).freeze,
    new(
      key: "dotnet",
      version: 1,
      label: ".NET / ASP.NET Core",
      picker_label: ".NET / ASP.NET Core (logister-dotnet)",
      picker_badge: "NuGet",
      picker_description: "ASP.NET Core apps, C# workers, and custom .NET telemetry.",
      picker_order: 6,
      icon_key: :project_dotnet,
      documentation_key: :dotnet_integration,
      documentation_label: ".NET integration docs",
      allowed_experience_keys: %i[server].freeze,
      default_experience_key: :server
    ).freeze,
    new(
      key: "cloudflare_pages",
      version: 1,
      label: "Cloudflare Pages",
      picker_label: "Cloudflare Pages",
      picker_badge: "HTTP",
      picker_description: "Pages deployment and traffic signals through manual HTTP telemetry today.",
      picker_order: 2,
      icon_key: :external,
      documentation_key: :cloudflare_pages_integration,
      documentation_label: "Cloudflare Pages docs",
      allowed_experience_keys: %i[edge].freeze,
      default_experience_key: :edge
    ).freeze,
    new(
      key: "android",
      version: 1,
      label: "Android app",
      picker_label: "Android app (logister-android)",
      picker_badge: "Gradle",
      picker_description: "One Android app/package, using logister-android with backend-issued tokens and configurable collection.",
      picker_order: 3,
      icon_key: :projects,
      documentation_key: :android_integration,
      documentation_label: "Android SDK docs",
      allowed_experience_keys: %i[android].freeze,
      default_experience_key: :android
    ).freeze,
    new(
      key: "ios",
      version: 1,
      label: "iOS app",
      picker_label: "iOS app (logister-ios)",
      picker_badge: "SPM",
      picker_description: "One Apple app/bundle, using logister-ios with backend-issued tokens and opt-in automatic diagnostics.",
      picker_order: 4,
      icon_key: :projects,
      documentation_key: :ios_integration,
      documentation_label: "iOS SDK docs",
      allowed_experience_keys: %i[ios].freeze,
      default_experience_key: :ios
    ).freeze,
    new(
      key: "http_api",
      version: 1,
      label: "Manual / HTTP API",
      picker_label: "Manual / HTTP API (custom client)",
      picker_badge: "Manual",
      picker_description: "Any runtime, script, worker, or custom client that posts JSON directly.",
      picker_order: 1,
      icon_key: :external,
      documentation_key: :http_api,
      documentation_label: "HTTP API docs",
      allowed_experience_keys: %i[custom].freeze,
      default_experience_key: :custom
    ).freeze
  ].freeze

  BY_KEY = DEFINITIONS.to_h { |definition| [ definition.key, definition ] }.freeze

  class << self
    def all
      DEFINITIONS
    end

    def all_for_picker
      @all_for_picker ||= DEFINITIONS.sort_by(&:picker_order).freeze
    end

    def keys
      BY_KEY.keys
    end

    def fetch(key)
      BY_KEY.fetch(key.to_s)
    end

    def find(key)
      BY_KEY[key.to_s]
    end

    def validate!
      duplicate_keys = DEFINITIONS.map(&:key).tally.select { |_key, count| count > 1 }.keys
      duplicate_orders = DEFINITIONS.map(&:picker_order).tally.select { |_order, count| count > 1 }.keys

      raise ArgumentError, "Duplicate project integration keys: #{duplicate_keys.join(', ')}" if duplicate_keys.any?
      raise ArgumentError, "Duplicate project integration picker orders: #{duplicate_orders.join(', ')}" if duplicate_orders.any?

      DEFINITIONS.each do |definition|
        raise ArgumentError, "Project integration key cannot be blank" if definition.key.blank?
        raise ArgumentError, "Project integration #{definition.key} must have a positive version" unless definition.version.to_i.positive?
        raise ArgumentError, "Project integration #{definition.key} must have a label" if definition.label.blank?
        raise ArgumentError, "Project integration #{definition.key} must allow an experience" if definition.allowed_experience_keys.empty?

        next if definition.allowed_experience_keys.include?(definition.default_experience_key)

        raise ArgumentError,
              "Project integration #{definition.key} default experience must be in its allowed experience keys"
      end

      true
    end
  end
end
