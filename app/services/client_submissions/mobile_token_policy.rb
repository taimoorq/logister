# frozen_string_literal: true

module ClientSubmissions
  class MobileTokenPolicy
    ALLOWED_ENDPOINTS = %w[ingest check_in].freeze

    Result = Data.define(:allowed, :status, :error, :errors) do
      def allowed?
        allowed
      end
    end

    def self.endpoint_allowed?(endpoint)
      ALLOWED_ENDPOINTS.include?(endpoint.to_s)
    end

    def initialize(mobile_ingest_token)
      @mobile_ingest_token = mobile_ingest_token
    end

    def enforce_event(event_type:, context:)
      return allowed_result unless mobile_ingest_token

      normalized_event_type = normalize_event_type(event_type)
      unless mobile_ingest_token.allows_event_type?(normalized_event_type)
        return Result.new(
          allowed: false,
          status: :forbidden,
          error: "Mobile ingest token cannot send this event type",
          errors: [ "Mobile ingest token cannot send #{normalized_event_type} events" ]
        )
      end

      apply_context(context)
    end

    private

    attr_reader :mobile_ingest_token

    def apply_context(context)
      context = {} unless context.is_a?(Hash)
      conflicts = context_conflicts(context)
      if conflicts.any?
        return Result.new(
          allowed: false,
          status: :unprocessable_content,
          error: nil,
          errors: conflict_messages(conflicts)
        )
      end

      mobile_ingest_token.context_bindings.each do |key, value|
        context[key] = value
      end
      allowed_result
    end

    def context_conflicts(context)
      mobile_ingest_token.context_bindings.each_with_object({}) do |(key, bound_value), conflicts|
        submitted_value = context[key] || context[key.to_sym]
        next if submitted_value.blank?
        next if submitted_value.to_s == bound_value.to_s

        conflicts[key] = {
          submitted: submitted_value,
          bound: bound_value
        }
      end
    end

    def conflict_messages(conflicts)
      conflicts.map do |key, values|
        "#{key} must match the mobile ingest token binding (got #{values[:submitted].inspect}, expected #{values[:bound].inspect})"
      end
    end

    def normalize_event_type(event_type)
      event_type.to_s.strip.underscore.downcase
    end

    def allowed_result
      Result.new(allowed: true, status: nil, error: nil, errors: [])
    end
  end
end
