require "digest"
require "socket"
require "ipaddr"

module Logister
  module ContextHelpers
    FILTERED_VALUE = "[FILTERED]".freeze

    module_function

    def runtime_context
      {
        runtime: {
          rubyVersion: RUBY_VERSION,
          railsVersion: defined?(Rails) ? Rails.version : nil,
          rackVersion: defined?(Rack) ? Rack.release : nil,
          platform: RUBY_PLATFORM
        }.compact
      }
    end

    def deployment_context
      config = Logister.configuration if Logister.respond_to?(:configuration)
      environment = config&.respond_to?(:environment) ? config.environment.to_s.presence : nil
      service = config&.respond_to?(:service) ? config.service.to_s.presence : nil
      release = config&.respond_to?(:release) ? config.release.to_s.presence : nil

      {
        deployment: {
          environment: environment || ENV["RAILS_ENV"].to_s.presence || ENV["RACK_ENV"].to_s.presence || "development",
          service: service || ENV["LOGISTER_SERVICE"].to_s.presence || "ruby-app",
          release: release || ENV["LOGISTER_RELEASE"].to_s.presence,
          region: ENV["FLY_REGION"].to_s.presence || ENV["RAILS_REGION"].to_s.presence || ENV["AWS_REGION"].to_s.presence,
          hostname: Socket.gethostname.to_s.presence,
          processPid: Process.pid
        }.compact
      }
    end

    def trace_context(headers:, env:)
      traceparent = header_value(headers, "Traceparent")
      b3_trace_id = header_value(headers, "X-B3-Traceid")
      b3_span_id = header_value(headers, "X-B3-Spanid")
      datadog_trace_id = header_value(headers, "X-Datadog-Trace-Id")
      datadog_parent_id = header_value(headers, "X-Datadog-Parent-Id")
      amzn_trace_id = header_value(headers, "X-Amzn-Trace-Id")

      parsed_trace_id, parsed_span_id, parsed_sampled = parse_traceparent(traceparent)

      {
        trace: {
          traceId: parsed_trace_id || b3_trace_id || datadog_trace_id,
          spanId: parsed_span_id || b3_span_id || datadog_parent_id,
          sampled: parsed_sampled,
          traceparent: traceparent,
          requestId: env["action_dispatch.request_id"].to_s.presence,
          amznTraceId: amzn_trace_id
        }.compact
      }
    end

    def resolve_feature_flags(request:, env:, user:)
      resolver = configuration_value(:feature_flags_resolver)
      return {} unless resolver.respond_to?(:call)

      raw = call_resolver(resolver, request: request, env: env, user: user)
      flags = normalize_flags_hash(raw)
      return {} if flags.empty?

      { featureFlags: flags }
    rescue StandardError
      {}
    end

    def resolve_dependency_context(request:, env:)
      resolver = configuration_value(:dependency_resolver)
      return {} unless resolver.respond_to?(:call)

      raw = call_resolver(resolver, request: request, env: env)
      list = normalize_dependency_list(raw)
      return {} if list.empty?

      { dependencyCalls: list }
    rescue StandardError
      {}
    end

    def anonymize_ip(ip)
      return nil if ip.to_s.strip.empty?
      return ip.to_s unless configuration_value(:anonymize_ip, false)

      parsed = IPAddr.new(ip.to_s)
      if parsed.ipv4?
        segments = ip.to_s.split(".")
        return ip.to_s if segments.size != 4

        "#{segments[0]}.#{segments[1]}.#{segments[2]}.0"
      else
        "#{parsed.mask(64).to_s}/64"
      end
    rescue StandardError
      ip.to_s
    end

    def user_context_for(user)
      return {} unless user

      {
        user: {
          id: safe_call(user, :id).to_s.presence,
          class: user.class.name.to_s.presence,
          email_hash: hashed_email(user),
          role: safe_call(user, :role).to_s.presence,
          account_id: safe_call(user, :account_id).to_s.presence || safe_call(user, :tenant_id).to_s.presence
        }.compact
      }
    end

    def filtered_job_arguments(job)
      arguments = Array(job.arguments)
      return arguments if arguments.empty?

      filter = ActiveSupport::ParameterFilter.new(
        Array(Rails.application.config.filter_parameters)
      )
      arguments.map { |argument| filter_argument(argument, filter) }
    rescue StandardError
      arguments
    end

    def safe_call(object, method_name)
      return nil unless object.respond_to?(method_name)

      object.public_send(method_name)
    rescue StandardError
      nil
    end

    def hash_value(value)
      return nil if value.to_s.strip.empty?

      Digest::SHA256.hexdigest(value.to_s.strip.downcase)
    end

    def compact_deep(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, nested), acc|
          compacted = compact_deep(nested)
          next if blank_value?(compacted)

          acc[key] = compacted
        end
      when Array
        value.map { |item| compact_deep(item) }.reject { |item| blank_value?(item) }
      else
        value
      end
    end

    def blank_value?(value)
      value.nil? || (value.respond_to?(:empty?) && value.empty?)
    end

    def hashed_email(user)
      email = safe_call(user, :email)
      hash_value(email)
    end
    private_class_method :hashed_email

    def filter_argument(argument, filter)
      case argument
      when Hash
        filter.filter(argument)
      when Array
        argument.map { |nested| filter_argument(nested, filter) }
      else
        argument
      end
    end
    private_class_method :filter_argument

    def header_value(headers, key)
      return nil unless headers.is_a?(Hash)

      headers[key].presence || headers[key.downcase].presence || headers[key.upcase].presence
    end
    private_class_method :header_value

    def parse_traceparent(traceparent)
      return [ nil, nil, nil ] if traceparent.to_s.empty?

      parts = traceparent.to_s.split("-")
      return [ nil, nil, nil ] unless parts.size == 4

      trace_id = parts[1].to_s
      span_id = parts[2].to_s
      flags = parts[3].to_s
      sampled = flags.end_with?("01")

      [ trace_id.presence, span_id.presence, sampled ]
    rescue StandardError
      [ nil, nil, nil ]
    end
    private_class_method :parse_traceparent

    def normalize_flags_hash(raw)
      case raw
      when Hash
        raw.each_with_object({}) do |(key, value), acc|
          acc[key.to_s] = value
        end
      else
        {}
      end
    end
    private_class_method :normalize_flags_hash

    def normalize_dependency_list(raw)
      list = case raw
      when Array then raw
      when Hash then [ raw ]
      else []
      end

      list.map do |item|
        next unless item.is_a?(Hash)

        {
          name: item[:name] || item["name"],
          host: item[:host] || item["host"],
          method: item[:method] || item["method"],
          status: item[:status] || item["status"],
          durationMs: item[:durationMs] || item["durationMs"] || item[:duration_ms] || item["duration_ms"],
          kind: item[:kind] || item["kind"],
          error: item[:error] || item["error"]
        }.compact
      end.compact
    end
    private_class_method :normalize_dependency_list

    def configuration_value(key, fallback = nil)
      return fallback unless Logister.respond_to?(:configuration)

      Logister.configuration.public_send(key)
    rescue StandardError
      fallback
    end
    private_class_method :configuration_value

    def call_resolver(resolver, **kwargs)
      if resolver.arity == 1
        resolver.call(kwargs)
      else
        resolver.call(**kwargs)
      end
    rescue ArgumentError
      resolver.call(kwargs[:request], kwargs[:env], kwargs[:user])
    end
    private_class_method :call_resolver
  end
end
