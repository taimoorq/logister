# frozen_string_literal: true

module ProjectEvents
  class RequestContextPresenter
    include PayloadSupport

    def initialize(event)
      @event = event
    end

    def details
      headers = normalize_hash(request_hash_value(context, :headers))
      params = normalize_hash(request_hash_value(context, :params))

      rails_action = request_scalar_value(context, :rails_action)
      if rails_action.blank?
        controller_name = value_from_hash(params, "controller")
        action_name = value_from_hash(params, "action")
        rails_action = "#{controller_name}##{action_name}" if controller_name.present? && action_name.present?
      end

      referer = request_scalar_value(context, :referer)
      referer ||= value_from_hash(headers, "Referer")
      referer ||= value_from_hash(headers, "Referrer")

      http_version = request_scalar_value(context, :http_version)
      http_version ||= value_from_hash(headers, "Version")

      {
        client_ip: request_scalar_value(context, :client_ip),
        headers: headers,
        http_method: request_scalar_value(context, :http_method),
        http_version: http_version,
        params: params,
        rails_action: rails_action,
        referer: referer,
        request_id: request_scalar_value(context, :request_id),
        url: request_scalar_value(context, :url)
      }
    end

    private

    def context
      @context ||= event_context_hash(@event)
    end
  end
end
