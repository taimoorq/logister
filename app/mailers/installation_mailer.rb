# frozen_string_literal: true

class InstallationMailer < ApplicationMailer
  def configuration_test(recipient, delivery:)
    @delivery = delivery
    mail(to: recipient, subject: "Logister #{@delivery} email test")
  end
end
