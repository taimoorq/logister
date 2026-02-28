require_relative "context_helpers"
require_relative "context_store"

module Logister
  class Middleware
    FILTERED_HEADER_PLACEHOLDER = "[FILTERED]".freeze
    SENSITIVE_HEADERS = %w[authorization cookie set-cookie x-api-key x-csrf-token].freeze

    def initialize(app)
      @app = app
    end

    def call(env)
      Logister::ContextStore.reset_request_scope!
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @app.call(env)
    rescue StandardError => e
      request = ActionDispatch::Request.new(env)
      request_context = build_request_context(request, env, error: e, started_at: started_at)

      Logister.report_error(
        e,
        context: request_context
      )
      raise
    ensure
      request_id = env["action_dispatch.request_id"]
      Logister::ContextStore.clear_request_summary(request_id)
      Logister::ContextStore.reset_request_scope!
    end

    private

    def build_request_context(request, env, error:, started_at:)
      request_id = env["action_dispatch.request_id"].to_s.presence
      path = request.path.to_s
      method = request.request_method.to_s
      params = request.filtered_parameters.to_h
      headers = extract_headers(env)
      referer = request.referer.to_s.presence || headers["Referer"]
      http_version = env["HTTP_VERSION"].to_s.presence || env["SERVER_PROTOCOL"].to_s.presence
      rails_action = rails_action_name(params)
      response_status = response_status_for(error)
      duration_ms = elapsed_duration_ms(started_at)
      current_user = current_user(env)
      user_context = Logister::ContextHelpers.user_context_for(current_user)
      request_summary = Logister::ContextStore.request_summary(request_id) || {}
      dependencies = collected_dependencies(request: request, env: env)
      breadcrumbs = Logister::ContextStore.breadcrumbs
      feature_flags = Logister::ContextHelpers.resolve_feature_flags(request: request, env: env, user: current_user)
      trace_context = Logister::ContextHelpers.trace_context(headers: headers, env: env)
      client_ip = Logister::ContextHelpers.anonymize_ip(request.ip.to_s.presence)

      base_context = {
        request_id: request_id,
        path: path,
        method: method,
        clientIp: client_ip,
        headers: headers,
        httpMethod: method,
        httpVersion: http_version,
        params: params,
        railsAction: rails_action,
        referer: referer,
        requestId: request_id,
        url: request.original_url.to_s.presence,
        response: {
          status: request_summary[:status] || response_status,
          contentType: request.content_type.to_s.presence,
          format: request_summary[:format] || request.format&.to_s.presence,
          durationMs: duration_ms
        }.compact,
        route: {
          name: env["action_dispatch.route_name"].to_s.presence,
          pathTemplate: route_path_template(env),
          controller: request_summary[:controller] || route_value(params, "controller"),
          action: request_summary[:action] || route_value(params, "action")
        }.compact,
        performance: {
          dbRuntimeMs: request_summary[:dbRuntimeMs],
          viewRuntimeMs: request_summary[:viewRuntimeMs],
          allocations: request_summary[:allocations]
        }.compact,
        dependencyCalls: dependencies.presence,
        breadcrumbs: breadcrumbs.presence,
        request: {
          clientIp: client_ip,
          headers: headers,
          httpMethod: method,
          httpVersion: http_version,
          params: params,
          railsAction: rails_action,
          referer: referer,
          requestId: request_id,
          url: request.original_url.to_s.presence
        }.compact
      }.compact

      Logister::ContextHelpers.compact_deep(
        base_context
          .merge(trace_context)
          .merge(feature_flags)
          .merge(user_context)
          .merge(Logister::ContextHelpers.runtime_context)
          .merge(Logister::ContextHelpers.deployment_context)
      )
    end

    def rails_action_name(params)
      return nil unless params.is_a?(Hash)

      controller_name = params["controller"].to_s.presence || params[:controller].to_s.presence
      action_name = params["action"].to_s.presence || params[:action].to_s.presence
      return nil if controller_name.blank? || action_name.blank?

      "#{controller_name}##{action_name}"
    end

    def extract_headers(env)
      headers = {}

      env.each do |key, value|
        next unless value.is_a?(String)

        header_name = rack_env_to_header_name(key)
        next unless header_name

        headers[header_name] = filter_header_value(header_name, value)
      end

      headers.sort.to_h
    end

    def rack_env_to_header_name(key)
      if key.start_with?("HTTP_")
        key.delete_prefix("HTTP_").split("_").map(&:capitalize).join("-")
      elsif key == "CONTENT_TYPE"
        "Content-Type"
      elsif key == "CONTENT_LENGTH"
        "Content-Length"
      else
        nil
      end
    end

    def filter_header_value(name, value)
      return FILTERED_HEADER_PLACEHOLDER if SENSITIVE_HEADERS.include?(name.to_s.downcase)

      value
    end

    def current_user(env)
      controller = env["action_controller.instance"]
      return nil unless controller

      if controller.respond_to?(:current_user)
        controller.public_send(:current_user)
      elsif controller.respond_to?(:current_user, true)
        controller.send(:current_user)
      end
    rescue StandardError
      nil
    end

    def collected_dependencies(request:, env:)
      custom = Logister::ContextHelpers.resolve_dependency_context(request: request, env: env).fetch(:dependencyCalls, [])
      manual = Logister::ContextStore.dependencies
      Array(manual) + Array(custom)
    end

    def response_status_for(error)
      return 500 unless defined?(ActionDispatch::ExceptionWrapper)

      ActionDispatch::ExceptionWrapper.status_code_for_exception(error.class.name)
    rescue StandardError
      500
    end

    def elapsed_duration_ms(started_at)
      return nil unless started_at

      ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000.0).round(2)
    rescue StandardError
      nil
    end

    def route_path_template(env)
      pattern = env["action_dispatch.route_uri_pattern"]
      return pattern.spec.to_s.presence if pattern.respond_to?(:spec)

      pattern.to_s.presence
    rescue StandardError
      nil
    end

    def route_value(params, key)
      return nil unless params.is_a?(Hash)

      params[key].to_s.presence || params[key.to_sym].to_s.presence
    end
  end
end
