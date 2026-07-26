# frozen_string_literal: true

require "digest"

class IosErrorGroupingEvidence
  VERSION = 1

  attr_reader :event, :context, :presenter

  def initialize(event)
    @event = event
    @context = MobileTelemetryNormalizer.normalize(event.context)
    @presenter = ProjectEvents::IosEventPresenter.new(event)
  end

  def evidence
    frame = presenter.top_in_app_frame
    termination = context["termination"].is_a?(Hash) ? context["termination"].stringify_keys : {}
    signature = context.dig("diagnostic", "signature").presence
    return { "diagnostic_signature" => signature } if signature

    frame_identity = stable_frame_identity(frame)

    {
      "diagnostic_kind" => context.dig("diagnostic", "kind").presence,
      "mechanism" => presenter.mechanism.presence,
      "exception_type" => known_exception_type,
      "termination_namespace" => termination["namespace"].presence,
      "termination_code" => termination["code"].to_s.presence,
      **frame_identity,
      "stack_shape" => frame_identity.empty? ? stack_shape : nil
    }.compact
  end

  def usable?
    values = evidence
    values["diagnostic_signature"].present? ||
      (values["exception_type"].present? && stable_frame_identity?(values)) ||
      (values["termination_namespace"].present? && values["termination_code"].present?)
  end

  def fingerprint
    return unless usable?

    "ios:v#{VERSION}:#{Digest::SHA256.hexdigest(evidence.to_json)}"
  end

  private

  def known_exception_type
    value = presenter.exception_type
    value unless value.blank? || value == "Unknown error"
  end

  def stable_frame_identity?(values)
    values["top_in_app_symbol"].present? ||
      (values["top_in_app_image_uuid"].present? && values["top_in_app_relative_address"].present?) ||
      values["stack_shape"].present?
  end

  def stable_frame_identity(frame)
    return {} unless frame

    if frame[:image_uuid].present? && frame[:relative_address].present?
      {
        "top_in_app_image_uuid" => frame[:image_uuid],
        "top_in_app_relative_address" => frame[:relative_address]
      }
    elsif frame[:symbol_identity].present?
      { "top_in_app_symbol" => frame[:symbol_identity] }
    else
      {}
    end
  end

  def stack_shape
    values = presenter.frames.filter_map do |frame|
      next unless frame[:application_frame]

      frame[:symbol_identity].presence || [ frame[:image_uuid], frame[:relative_address] ].compact_blank.join("@").presence
    end.first(5)
    values if values.present?
  end
end
