# frozen_string_literal: true

class ErrorGroupRegressionPresenter
  REASON_LABELS = {
    "after_resolved" => "after resolution",
    "after_ignored" => "after mute",
    "after_archived" => "after archive",
    "legacy_regression" => "previously reopened"
  }.freeze

  attr_reader :group, :evidence

  def initialize(group)
    @group = group
    @evidence = group.current_regression.to_h.stringify_keys
  end

  def present?
    evidence.present? || group.regression_count.to_i.positive?
  end

  def reason_label
    REASON_LABELS.fetch(evidence["reason"].to_s, "after a confirmed recurrence")
  end

  def concise_label
    [ reason_label, time_label ].compact_blank.join(" · ")
  end

  def title
    facts = [ "Regressed #{reason_label}" ]
    facts << time_title
    facts << "Release #{evidence['release']}" if evidence["release"].present?
    facts.compact_blank.join(". ")
  end

  private

  def time_label
    time = proof_time || received_time || detected_time
    return unless time

    prefix = case evidence["time_precision"]
    when "exact" then "occurred"
    when "reporting_interval" then "reporting interval began"
    when "received_only" then "received"
    else "detected"
    end
    "#{prefix} #{helpers.time_ago_in_words(time)} ago"
  end

  def time_title
    if proof_time
      label = evidence["time_precision"] == "reporting_interval" ? "Proving reporting interval began" : "Proving occurrence"
      "#{label} #{I18n.l(proof_time, format: :long)}"
    elsif received_time
      "Received #{I18n.l(received_time, format: :long)}"
    elsif detected_time
      "Detected #{I18n.l(detected_time, format: :long)}"
    end
  end

  def proof_time
    parse_time(evidence["proof_at"])
  end

  def received_time
    parse_time(evidence["received_at"])
  end

  def detected_time
    parse_time(evidence["detected_at"])
  end

  def parse_time(value)
    Time.zone.parse(value.to_s) if value.present?
  rescue ArgumentError
    nil
  end

  def helpers
    ActionController::Base.helpers
  end
end
