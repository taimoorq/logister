class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :continue_incomplete_installation

  helper_method :admin_user?, :nav_active_projects, :nav_notifications

  def default_url_options
    super.merge(Rails.application.routes.default_url_options)
  end

  private

  def admin_user?
    return false unless user_signed_in?
    return true if current_user.application_admin?

    admin_emails = ENV.fetch("LOGISTER_ADMIN_EMAILS", "")
                      .split(",")
                      .map { |email| email.to_s.strip.downcase }
                      .reject(&:blank?)
    return false if admin_emails.empty?

    admin_emails.include?(current_user.email.to_s.downcase)
  end

  def continue_incomplete_installation
    return unless user_signed_in? && admin_user?
    return if controller_path.start_with?("admin/installation") || controller_path == "instance_setup"
    return if devise_controller?

    installation = Installation.current_if_available
    return unless installation&.claimed? && !installation.complete?

    redirect_to admin_installation_path, alert: "Finish the required installation checks before continuing."
  end

  def nav_active_projects
    return [] unless user_signed_in?

    @nav_active_projects ||= current_user.active_projects.order(:name).to_a
  end

  def nav_notifications
    return [] unless user_signed_in?

    @nav_notifications ||= NavigationNotifications.for(user: current_user, operator: admin_user?)
  end

  def safe_cache_fetch(key, expires_in:, race_condition_ttl: 5.seconds, &block)
    Rails.cache.fetch(key, expires_in: expires_in, race_condition_ttl: race_condition_ttl, &block)
  rescue StandardError => e
    Rails.logger.warn("cache fetch failed key=#{key.inspect}: #{e.class} #{e.message}")
    block.call
  end

  def cache_time_bucket(duration)
    Time.current.to_i / duration.to_i
  end
end
