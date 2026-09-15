# frozen_string_literal: true

module ProjectLifecycle
  extend ActiveSupport::Concern

  included do
    before_destroy :require_purge_execution
  end

  def archived?
    archived_at.present?
  end

  def purge_pending?
    purge_requested_at.present?
  end

  def notifications_disabled?
    archived? || purge_pending?
  end

  def archive!
    archive_time = Time.current

    transaction do
      update!(archived_at: archive_time)
      api_keys.active.update_all(revoked_at: archive_time, updated_at: archive_time)
    end
  end

  def restore!
    if purge_pending?
      errors.add(:base, "cannot restore a project after permanent deletion has been requested")
      raise ActiveRecord::RecordInvalid, self
    end

    update!(archived_at: nil)
  end

  def destroy_for_purge!
    unless purge_pending? && project_purges.exists?
      errors.add(:base, "requires a durable project purge ledger before deletion")
      raise ActiveRecord::RecordInvalid, self
    end

    @purge_execution_authorized = true
    destroy!
  ensure
    @purge_execution_authorized = false
  end

  private

  def require_purge_execution
    return if @purge_execution_authorized

    errors.add(:base, "Must be deleted through the audited project purge lifecycle")
    throw :abort
  end
end
