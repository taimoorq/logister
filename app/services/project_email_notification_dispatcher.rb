class ProjectEmailNotificationDispatcher
  GROUP_KINDS = %w[
    first_occurrence
    regression
    frequent_error
    error_milestone
    assignment
    status_change
  ].freeze
  MONITOR_KINDS = %w[monitor_missed monitor_recovered].freeze

  def self.call(...)
    new(...).call
  end

  def initialize(project:, kind:, error_group: nil, monitor: nil, recipients: nil, metadata: {}, subject_key: nil, bucket: nil, now: Time.current)
    @project = project
    @kind = kind.to_s
    @error_group = error_group
    @monitor = monitor
    @recipients = recipients
    @metadata = metadata.stringify_keys
    @subject_key = subject_key
    @bucket = bucket
    @now = now
  end

  def call
    return [] if @project.archived?

    recipient_scope.filter_map do |user|
      next if user.respond_to?(:confirmed?) && !user.confirmed?

      preference = ProjectNotificationPreference.for(user: user, project: @project)
      next unless preference.immediate_email_enabled_for?(@kind, error_group: @error_group, metadata: @metadata, now: @now)
      next unless preference.immediate_rate_limit_available?(@kind, now: @now)
      next unless threshold_passes?(preference)

      delivery = build_delivery(user)
      deliver(delivery)
      delivery
    end
  end

  private

  def recipient_scope
    @recipients || @project.notification_recipients
  end

  def build_delivery(user)
    EmailNotificationDelivery.find_or_create_by!(
      dedup_key: dedup_key_for(user)
    ) do |record|
      record.user = user
      record.project = @project
      record.error_group = @error_group
      record.notification_kind = @kind
      record.status = "pending"
      record.period_start_at = period_start_from_metadata
      record.period_end_at = period_end_from_metadata
      record.metadata = @metadata
    end
  end

  def deliver(delivery)
    delivery.with_lock do
      return if delivery.sent? || delivery.sending_recent?

      delivery.mark_sending!
    end

    mail_for(delivery).deliver_now
    delivery.mark_sent!
  rescue StandardError => e
    delivery.mark_failed!(e) if delivery&.persisted?
    raise
  end

  def mail_for(delivery)
    return ProjectErrorMailer.first_occurrence(delivery) if @kind == "first_occurrence"

    if GROUP_KINDS.include?(@kind)
      ProjectErrorMailer.group_alert(delivery)
    elsif MONITOR_KINDS.include?(@kind)
      ProjectErrorMailer.monitor_alert(delivery)
    else
      ProjectErrorMailer.project_alert(delivery)
    end
  end

  def subject_key
    @subject_key.presence || @error_group&.id || @monitor&.id || @project.id
  end

  def dedup_key_for(user)
    return EmailNotificationDelivery.first_occurrence_key(user: user, error_group: @error_group) if @kind == "first_occurrence" && @error_group

    EmailNotificationDelivery.notification_key(
      kind: @kind,
      user: user,
      project: @project,
      subject: subject_key,
      bucket: @bucket
    )
  end

  def threshold_passes?(preference)
    case @kind
    when "frequent_error"
      frequent_error_count(preference) >= preference.frequent_error_threshold_count
    when "project_spike"
      project_error_count(preference) >= preference.project_spike_threshold_count
    when "performance_threshold"
      project_transaction_p95_ms >= preference.performance_p95_threshold_ms
    else
      true
    end
  end

  def frequent_error_count(preference)
    return 0 unless @error_group

    since = @now - preference.frequent_error_window_minutes.minutes
    @error_group.error_occurrences.where("occurred_at >= ?", since).count
  end

  def project_error_count(preference)
    since = @now - preference.project_spike_window_minutes.minutes
    ErrorOccurrence.joins(:error_group)
                   .where(error_groups: { project_id: @project.id })
                   .where("error_occurrences.occurred_at >= ?", since)
                   .count
  end

  def project_transaction_p95_ms
    @project_transaction_p95_ms ||= begin
      contexts = @project.ingest_events
                         .transactions
                         .where("occurred_at >= ?", @now - 15.minutes)
                         .order(occurred_at: :desc)
                         .limit(1_000)
                         .pluck(:context)
      durations = contexts.filter_map do |context|
        next unless context.is_a?(Hash)

        value = context["duration_ms"] || context[:duration_ms] || context["duration"] || context[:duration]
        duration = Float(value, exception: false)
        duration if duration&.positive?
      end.sort
      if durations.empty?
        0
      else
        index = [ (durations.length * 0.95).ceil - 1, 0 ].max
        durations[index]
      end
    end
  end

  def period_start_from_metadata
    Time.zone.parse(@metadata["period_start_at"].to_s) if @metadata["period_start_at"].present?
  end

  def period_end_from_metadata
    Time.zone.parse(@metadata["period_end_at"].to_s) if @metadata["period_end_at"].present?
  end
end
