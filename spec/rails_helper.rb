# frozen_string_literal: true

require "spec_helper"
ENV["RAILS_ENV"] ||= "test"
abort "RSpec requires RAILS_ENV=test (got #{ENV['RAILS_ENV'].inspect})" unless ENV["RAILS_ENV"] == "test"
require_relative "../config/environment"
abort "RSpec requires the Rails test environment" unless Rails.env.test?
require "rspec/rails"

Rails.root.glob("spec/support/**/*.rb").sort_by(&:to_s).each { |file| require file }

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => error
  abort error.to_s.strip
end

RSpec.shared_context "application fixtures" do
  fixtures :all
end

RSpec.configure do |config|
  config.include ActiveSupport::Testing::TimeHelpers
  # Rails clears queued/performed jobs before every example and restores test
  # adapters afterwards, including when a model or request enqueues work.
  config.include ActiveJob::TestHelper
  config.before { ActionMailer::Base.deliveries.clear }
  config.fixture_paths = [ Rails.root.join("spec/fixtures") ]
  config.file_fixture_path = Rails.root.join("spec/fixtures/files")
  config.use_transactional_fixtures = true

  # Preserve the current directory conventions; services can opt into the
  # shared fixture graph with type: :model or include_context explicitly.
  config.infer_spec_type_from_file_location!
  %i[model request job system].each do |type|
    config.include_context "application fixtures", type: type
  end

  config.filter_rails_from_backtrace!
end
