class NavigationNotifications
  Notification = Struct.new(:key, :icon, :title, :body, :url, :action_label, keyword_init: true)

  def self.for(user:, operator:)
    new(user:, operator:).to_a
  end

  def initialize(user:, operator:)
    @user = user
    @operator = operator
  end

  def to_a
    return [] unless eligible_for_update_notifications?

    [ release_update_notification ].compact
  end

  private

  attr_reader :user, :operator

  def eligible_for_update_notifications?
    operator || user.projects.exists?
  end

  def release_update_notification
    update = Logister::ReleaseUpdateChecker.call
    return nil if update.blank?
    return nil if dismissed?(update.notification_key)

    Notification.new(
      key: update.notification_key,
      icon: :notifications,
      title: "Update available",
      body: "Logister #{tag(update.latest_version)} is available. This instance is running #{tag(update.current_version)}.",
      url: update.release_url,
      action_label: "View release"
    )
  end

  def dismissed?(key)
    user.user_notification_dismissals.exists?(notification_key: key)
  end

  def tag(version)
    "v#{version.to_s.delete_prefix("v")}"
  end
end
