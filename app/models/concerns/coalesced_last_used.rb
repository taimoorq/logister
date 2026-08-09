module CoalescedLastUsed
  extend ActiveSupport::Concern

  LAST_USED_TOUCH_INTERVAL = 5.minutes

  def touch_last_used!(now: Time.current, interval: LAST_USED_TOUCH_INTERVAL)
    cutoff = now - interval
    updated = self.class
      .where(self.class.primary_key => id)
      .where("last_used_at IS NULL OR last_used_at < ?", cutoff)
      .update_all(last_used_at: now)

    self.last_used_at = now if updated.positive?
    updated.positive?
  end
end
