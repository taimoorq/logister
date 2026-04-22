# frozen_string_literal: true

# Use headless Chrome for system specs so JavaScript and real browser behavior are exercised.
# Requires capybara + selenium-webdriver. For CI, Chrome is installed via the setup-chromedriver action or similar.
Capybara.register_driver :logister_selenium_chrome_headless do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument("--headless=new")
  options.add_argument("--disable-site-isolation-trials")
  options.add_argument("--window-size=1400,1400")

  configured_path = ENV["CHROMEDRIVER_PATH"].to_s.strip
  cached_drivers = Dir.glob(File.expand_path("~/.cache/selenium/chromedriver/**/*/chromedriver")).select do |path|
    File.file?(path) && File.executable?(path)
  end
  cached_path = cached_drivers.max_by do |path|
    Gem::Version.new(File.basename(File.dirname(path)))
  rescue ArgumentError
    Gem::Version.new("0")
  end

  driver_path = configured_path.presence || cached_path
  service = driver_path.present? ? Selenium::WebDriver::Service.chrome(path: driver_path) : nil

  Capybara::Selenium::Driver.new(app, browser: :chrome, options: options, service: service)
end

RSpec.configure do |config|
  config.before(:each, type: :system) do
    driven_by :logister_selenium_chrome_headless
  end
end
