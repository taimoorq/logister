# frozen_string_literal: true

Rails.application.config.to_prepare do
  ProjectExperience.validate_registry!
end
