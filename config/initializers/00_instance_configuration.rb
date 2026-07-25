# frozen_string_literal: true

require Rails.root.join("app/services/instance_configuration/cipher")
require Rails.root.join("app/services/instance_configuration/registry")
require Rails.root.join("app/services/instance_configuration")
require Rails.root.join("app/models/application_record")
require Rails.root.join("app/models/instance_setting")
require Rails.root.join("app/models/instance_setting_change")
require Rails.root.join("app/services/instance_configuration/runtime")

Rails.application.config.after_initialize do
  InstanceConfiguration::Runtime.apply!
end
