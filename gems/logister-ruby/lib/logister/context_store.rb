module Logister
  module ContextStore
    REQUEST_SCOPE_KEY = :__logister_request_scope
    MAX_REQUEST_SUMMARIES = 200

    module_function

    def reset_request_scope!
      Thread.current[REQUEST_SCOPE_KEY] = {
        breadcrumbs: [],
        dependencies: []
      }
    end

    def add_breadcrumb(category:, message:, data: {}, level: "info", timestamp: Time.now.utc.iso8601)
      scope = request_scope
      breadcrumbs = scope[:breadcrumbs]
      breadcrumbs << {
        category: category.to_s,
        message: message.to_s,
        level: level.to_s,
        timestamp: timestamp,
        data: sanitize_hash(data)
      }.compact
      trim_collection!(breadcrumbs, max_breadcrumbs)
    end

    def breadcrumbs
      request_scope[:breadcrumbs].dup
    end

    def add_dependency(name:, host: nil, method: nil, status: nil, duration_ms: nil, kind: nil, data: {})
      scope = request_scope
      deps = scope[:dependencies]
      deps << sanitize_hash(
        {
          name: name.to_s.presence,
          host: host.to_s.presence,
          method: method.to_s.presence,
          status: status,
          durationMs: duration_ms && duration_ms.to_f.round(2),
          kind: kind.to_s.presence,
          data: sanitize_hash(data)
        }.compact
      )
      trim_collection!(deps, max_dependencies)
    end

    def dependencies
      request_scope[:dependencies].dup
    end

    def store_request_summary(request_id, summary)
      return if request_id.to_s.empty?

      cache = request_summaries
      cache[request_id.to_s] = sanitize_hash(summary)
      trim_hash!(cache, MAX_REQUEST_SUMMARIES)
    end

    def request_summary(request_id)
      return nil if request_id.to_s.empty?

      request_summaries[request_id.to_s]
    end

    def clear_request_summary(request_id)
      request_summaries.delete(request_id.to_s)
    end

    def add_manual_dependency(**kwargs)
      add_dependency(**kwargs)
    end

    def add_manual_breadcrumb(**kwargs)
      add_breadcrumb(**kwargs)
    end

    def request_scope
      Thread.current[REQUEST_SCOPE_KEY] ||= {
        breadcrumbs: [],
        dependencies: []
      }
    end
    private_class_method :request_scope

    def request_summaries
      Thread.current[:__logister_request_summaries] ||= {}
    end
    private_class_method :request_summaries

    def sanitize_hash(value)
      return {} unless value.is_a?(Hash)

      value.each_with_object({}) do |(key, nested), acc|
        acc[key] = nested
      end
    end
    private_class_method :sanitize_hash

    def max_breadcrumbs
      config_value(:max_breadcrumbs, 40).to_i.clamp(1, 500)
    end
    private_class_method :max_breadcrumbs

    def max_dependencies
      config_value(:max_dependencies, 20).to_i.clamp(1, 500)
    end
    private_class_method :max_dependencies

    def trim_collection!(array, max_size)
      overflow = array.size - max_size
      array.shift(overflow) if overflow.positive?
    end
    private_class_method :trim_collection!

    def trim_hash!(hash, max_size)
      overflow = hash.size - max_size
      return unless overflow.positive?

      hash.keys.first(overflow).each { |key| hash.delete(key) }
    end
    private_class_method :trim_hash!

    def config_value(key, fallback)
      return fallback unless Logister.respond_to?(:configuration)

      Logister.configuration.public_send(key)
    rescue StandardError
      fallback
    end
    private_class_method :config_value
  end
end
