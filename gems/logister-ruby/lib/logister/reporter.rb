require 'digest'
require 'time'

module Logister
  class Reporter
    def initialize(configuration)
      @configuration = configuration
      @client = Client.new(configuration)

      at_exit { shutdown }
    end

    def report_error(exception, context: {}, tags: {}, level: 'error', fingerprint: nil)
      return false if ignored_exception?(exception)
      return false if ignored_path?(context)

      payload = build_payload(
        event_type: 'error',
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

      payload = apply_before_notify(payload)
      return false unless payload

      @client.publish(payload)
    end

    def report_metric(message:, level: 'info', context: {}, tags: {}, fingerprint: nil)
      return false if ignored_environment?
      return false if ignored_path?(context)

      payload = build_payload(
        event_type: 'metric',
        level: level,
        message: message,
        fingerprint: fingerprint || Digest::SHA256.hexdigest(message.to_s)[0, 32],
        context: context.merge(tags: tags)
      )

      payload = apply_before_notify(payload)
      return false unless payload

      @client.publish(payload)
    end

    def flush(timeout: 2)
      @client.flush(timeout: timeout)
    end

    def shutdown
      @client.shutdown
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

    def apply_before_notify(payload)
      hook = @configuration.before_notify
      return payload unless hook.respond_to?(:call)

      result = hook.call(payload)
      return nil if result == false || result.nil?

      result
    rescue StandardError => e
      @configuration.logger.warn("logister before_notify failed: #{e.class} #{e.message}")
      nil
    end

    def ignored_exception?(exception)
      return true if ignored_environment?

      @configuration.ignore_exceptions.any? do |item|
        if item.is_a?(Class)
          exception.is_a?(item)
        else
          exception.class.name == item.to_s
        end
      end
    end

    def ignored_environment?
      env = @configuration.environment.to_s
      @configuration.ignore_environments.map(&:to_s).include?(env)
    end

    def ignored_path?(context)
      path = context[:path] || context['path']
      return false if path.to_s.empty?

      @configuration.ignore_paths.any? do |matcher|
        matcher.is_a?(Regexp) ? matcher.match?(path.to_s) : path.to_s.include?(matcher.to_s)
      end
    end

    def default_fingerprint(exception)
      Digest::SHA256.hexdigest("#{exception.class}|#{exception.message}")[0, 32]
    end
  end
end
