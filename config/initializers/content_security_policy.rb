# Be sure to restart your server when you modify this file.

# Application-wide Content-Security-Policy. Scripts must come from this origin,
# carry the per-session nonce, or come from one of the third-party hosts the
# layouts load (Turnstile, consent-gated analytics, and the Probo cookie banner).
#
# The policy is enforced by default. Set LOGISTER_CSP_REPORT_ONLY=1 to send it as
# Content-Security-Policy-Report-Only while diagnosing a self-hosted setup.
# See https://guides.rubyonrails.org/security.html#content-security-policy-header

Rails.application.configure do
  turnstile = "https://challenges.cloudflare.com"
  google_tag_manager = "https://www.googletagmanager.com"
  google_analytics = [
    "https://www.google-analytics.com",
    "https://*.google-analytics.com",
    "https://*.analytics.google.com",
    "https://*.googletagmanager.com"
  ]
  cloudflare_insights_script = "https://static.cloudflareinsights.com"
  cloudflare_insights_beacon = "https://cloudflareinsights.com"
  google_fonts_css = "https://fonts.googleapis.com"
  google_fonts_files = "https://fonts.gstatic.com"

  config.content_security_policy do |policy|
    policy.default_src :self
    policy.base_uri :self
    policy.object_src :none
    policy.frame_ancestors :self
    policy.form_action :self

    policy.script_src :self, turnstile, google_tag_manager, cloudflare_insights_script,
                      -> { Logister::ContentSecurityPolicySources.cookie_banner_script_sources }
    # Inline style attributes are part of the server-rendered UI, so styles allow
    # them; only scripts are nonce-gated.
    policy.style_src :self, :unsafe_inline, google_fonts_css
    policy.font_src :self, :data, google_fonts_files
    policy.img_src :self, :data, :blob, *google_analytics
    policy.connect_src :self, *google_analytics, cloudflare_insights_beacon,
                       -> { Logister::ContentSecurityPolicySources.cookie_banner_api_sources }
    policy.frame_src turnstile
    policy.worker_src :self, :blob
    policy.manifest_src :self
  end

  # Turbo Drive keeps the first page's CSP header for the life of the tab and
  # stamps scripts it inserts with the nonce from the current csp-nonce meta tag,
  # so the nonce must stay stable across navigations: keep one per session. API
  # responses render no HTML, so they get a throwaway nonce rather than a session.
  config.content_security_policy_nonce_generator = lambda do |request|
    if request.path.start_with?("/api/")
      SecureRandom.base64(16)
    else
      request.session[:csp_nonce] ||= SecureRandom.base64(16)
    end
  end
  config.content_security_policy_nonce_directives = %w[script-src]
  config.content_security_policy_nonce_auto = true

  config.content_security_policy_report_only = ActiveModel::Type::Boolean.new.cast(ENV["LOGISTER_CSP_REPORT_ONLY"]) || false
end
