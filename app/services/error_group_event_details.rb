# frozen_string_literal: true

class ErrorGroupEventDetails
  def self.title(event, fallback:)
    event.message.to_s.lines.first.to_s.strip.presence || fallback.presence || "Untitled error"
  end

  def self.subtitle(event)
    exception = event_context(event)["exception"] || event_context(event)[:exception]
    return unless exception.is_a?(Hash)

    exception["class"].presence || exception[:class].presence
  end

  def self.stage(event)
    context = event_context(event)
    context["environment"].presence || context[:environment].presence || "production"
  end

  def self.event_context(event)
    event.context.is_a?(Hash) ? event.context : {}
  end
  private_class_method :event_context
end
