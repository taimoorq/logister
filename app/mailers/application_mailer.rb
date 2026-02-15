class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("LOGISTER_EMAIL_FROM", "support@logister.org")
  layout "mailer"
end
