# frozen_string_literal: true

module SystemSignInHelpers
  # Signs in, then marks the given product tours as complete so they do not
  # open over the page under test.
  #
  # Sign in before the first visit. Devise's sign_in logs in whichever request
  # reaches the app next. The /up page has no icon link, so once it loads Chrome
  # requests /favicon.ico by itself. If sign_in runs after that visit, the
  # favicon request can arrive first and take the login, and its 404 never
  # saves the session, so the next visit lands on the sign-in page.
  def sign_in_with_completed_tours(user, *tour_groups)
    sign_in user
    visit rails_health_check_path
    page.execute_script("window.localStorage.setItem('tg_tours_complete', arguments[0])", tour_groups.join(","))
  end
end

RSpec.configure do |config|
  config.include SystemSignInHelpers, type: :system
end
