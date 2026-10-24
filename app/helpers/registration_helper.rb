# frozen_string_literal: true

module RegistrationHelper
  # Hide sign-up entry points when the instance does not accept new accounts.
  def sign_up_available?
    RegistrationPolicy.current.sign_up_available?
  end
end
