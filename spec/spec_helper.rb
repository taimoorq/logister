# frozen_string_literal: true

# Loaded by .rspec, including for specs that do not need Rails. Keep Rails and
# application support in rails_helper so isolated Ruby specs stay fast.
RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
    expectations.syntax = :expect
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.disable_monkey_patching!
  config.fail_if_no_examples = true
  config.example_status_persistence_file_path = "tmp/rspec-examples.txt"

  # Print the seed so order-dependent failures can be replayed with --seed.
  config.order = :random
  Kernel.srand config.seed
end
