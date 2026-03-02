# frozen_string_literal: true

# Use headless Chrome for system specs so JavaScript and real browser behavior are exercised.
# Requires capybara + selenium-webdriver. For CI, Chrome is installed via the setup-chromedriver action or similar.
RSpec.configure do |config|
  config.before(:each, type: :system) do
    driven_by :selenium_chrome_headless
  end
end
