# frozen_string_literal: true

module GithubTokenHelpers
  def github_stateless_installation_token
    "ghs_123456_#{'a_' * 90}.#{'b-' * 90}.#{'c' * 180}"
  end
end

RSpec.configure do |config|
  config.include GithubTokenHelpers
end
