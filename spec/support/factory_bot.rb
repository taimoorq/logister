# frozen_string_literal: true

# factory_bot_rails railtie already sets definition_file_paths to spec/factories and test/factories.

RSpec.configure do |config|
  config.include FactoryBot::Syntax::Methods
end
