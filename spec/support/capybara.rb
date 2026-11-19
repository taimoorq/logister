# frozen_string_literal: true

# Use headless Chrome for system specs so JavaScript and real browser behavior are exercised.
# Requires capybara + selenium-webdriver. For CI, Chrome is installed via the setup-chromedriver action or similar.
Capybara.register_driver :logister_selenium_chrome_headless do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument("--headless=new")
  options.add_argument("--disable-site-isolation-trials")
  options.add_argument("--window-size=1400,1400")
  # Turbo wraps each navigation in a view transition unless the browser prefers
  # reduced motion. While a transition runs, its ::view-transition overlay sits
  # over the page and receives every click, so a click sent right after a page
  # changes can land on <html> instead of the link and be lost. Reduced motion
  # turns the transitions off and runs the app's reduced-motion styles.
  options.add_argument("--force-prefers-reduced-motion")

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

# Capybara 3.40.0 ends every Chrome session reset with
# Storage.clearDataForOrigin(origin: "*"). Chrome 158 validates that origin and
# answers "invalid argument: * is not a valid URL", which fails every system
# spec in teardown. Until a Capybara release stops sending the wildcard
# (teamcapybara/capybara#2865), do the same clearing with calls every Chrome
# accepts: drop all cookies, then clear the remaining storage types for the
# app server's origin. A spec that writes storage on another origin has to
# clear it itself. This never runs once Capybara stops sending "*", so it can
# be deleted after upgrading.
module LogisterChromeResetWithoutWildcardOrigin
  private

  def execute_cdp(cmd, params = {})
    return super unless cmd == "Storage.clearDataForOrigin" && params[:origin] == "*"

    storage_types = params[:storageTypes].to_s.split(",")
    super("Network.clearBrowserCookies") if storage_types.delete("cookies")

    origin = session&.server&.base_url
    return if origin.blank? || storage_types.empty?

    super(cmd, params.merge(origin: origin, storageTypes: storage_types.join(",")))
  end
end
Capybara::Selenium::Driver::ChromeDriver.prepend(LogisterChromeResetWithoutWildcardOrigin)

RSpec.configure do |config|
  config.before(:each, type: :system) do
    driven_by :logister_selenium_chrome_headless
    page.current_window.resize_to(1400, 1400)
    # Selenium reuses the browser between examples; console assertions should
    # only see this example's messages, including resource errors.
    page.driver.browser.logs.get(:browser)
  end
end
