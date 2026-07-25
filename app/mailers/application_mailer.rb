class ApplicationMailer < ActionMailer::Base
  default from: -> { InstanceConfiguration.value("general.email_from") }
  layout "mailer"
end
