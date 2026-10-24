# Be sure to restart your server when you modify this file.

# Logister never needs device sensors or payments, so deny them to the app and
# to every embedded frame (Turnstile, analytics, the cookie banner).
#
# Rails' permissions_policy DSL still emits the legacy Feature-Policy header,
# which current browsers ignore, so send the standard header directly. The hash
# is shared with ActionDispatch::Response, so mutate it rather than replace it.
Rails.application.config.action_dispatch.default_headers["Permissions-Policy"] =
  "camera=(), microphone=(), geolocation=(), payment=(), usb=()"
