# frozen_string_literal: true

require "digest"

class AndroidErrorGroupingEvidence
  VERSION = 2

  attr_reader :event, :presenter

  def initialize(event)
    @event = event
    @presenter = ProjectEvents::AndroidEventPresenter.new(event)
  end

  def evidence
    root = presenter.root_cause || {}
    frame = root.fetch(:frames, []).find { |candidate| candidate[:application_frame] } || presenter.top_in_app_frame

    {
      "mechanism" => presenter.mechanism,
      "root_exception_type" => root[:type].presence || presenter.exception_type,
      "top_in_app_class" => frame&.dig(:class_name),
      "top_in_app_method" => frame&.dig(:method_name),
      "cause_types" => presenter.cause_chain.map { |entry| entry[:type] }
    }.compact
  end

  def usable?
    evidence["root_exception_type"].present? &&
      evidence["root_exception_type"] != "Unknown exception" &&
      evidence["top_in_app_class"].present? &&
      evidence["top_in_app_method"].present?
  end

  def fingerprint
    return unless usable?

    "android:v#{VERSION}:#{Digest::SHA256.hexdigest(evidence.to_json)}"
  end
end
