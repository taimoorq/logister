require "digest"
require "time"

module Logister
  class Reporter
    def initialize(configuration)
      @configuration = configuration
      @client = Client.new(configuration)
    end

    def report_error(exception, context: {}, tags: {}, level: "error", fingerprint: nil)
      payload = build_payload(
        event_type: "error",
        level: level,
        message: "#{exception.class}: #{exception.message}",
        fingerprint: fingerprint || default_fingerprint(exception),
        context: context.merge(
          exception: {
            class: exception.class.to_s,
            message: exception.message.to_s,
            backtrace: Array(exception.backtrace).first(50)
          },
          tags: tags
        )
      )

      @client.publish(payload)
    end

    def report_metric(message:, level: "info", context: {}, tags: {}, fingerprint: nil)
      payload = build_payload(
        event_type: "metric",
        level: level,
        message: message,
        fingerprint: fingerprint || Digest::SHA256.hexdigest(message.to_s)[0, 32],
        context: context.merge(tags: tags)
      )

      @client.publish(payload)
    end

    private

    def build_payload(event_type:, level:, message:, fingerprint:, context:)
      {
        event_type: event_type,
        level: level,
        message: message,
        fingerprint: fingerprint,
        occurred_at: Time.now.utc.iso8601,
        context: context.merge(
          environment: @configuration.environment,
          service: @configuration.service,
          release: @configuration.release
        )
      }
    end

    def default_fingerprint(exception)
      Digest::SHA256.hexdigest("#{exception.class}|#{exception.message}")[0, 32]
    end
  end
end
