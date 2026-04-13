class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  helper_method :admin_user?

  def default_url_options
    super.merge(Rails.application.routes.default_url_options)
  end

  private

  def admin_user?
    return false unless user_signed_in?

    admin_emails = ENV.fetch("LOGISTER_ADMIN_EMAILS", "")
                      .split(",")
                      .map { |email| email.to_s.strip.downcase }
                      .reject(&:blank?)
    return false if admin_emails.empty?

    admin_emails.include?(current_user.email.to_s.downcase)
  end

  def safe_cache_fetch(key, expires_in:, race_condition_ttl: 5.seconds, &block)
    Rails.cache.fetch(key, expires_in: expires_in, race_condition_ttl: race_condition_ttl, &block)
  rescue StandardError => e
    Rails.logger.warn("cache fetch failed key=#{key.inspect}: #{e.class} #{e.message}")
    block.call
  end
end
