# frozen_string_literal: true

require "digest"

module InstanceConfiguration
  Entry = Struct.new(
    :definition, :effective_value, :saved_value, :environment_value, :active_environment_key, :source,
    keyword_init: true
  ) do
    delegate :key, :label, :env_key, :type, :secret?, :restart_required?, to: :definition

    def environment_override?
      source == :environment
    end

    def saved?
      !saved_value.nil?
    end
  end

  module_function

  def value(key, overrides: {})
    entry(key, overrides: overrides).effective_value
  end

  def entry(key, overrides: {})
    definition = Registry.definition!(key)
    saved_value = saved_value_for(definition.key)
    environment_value, active_environment_key = environment_resolution_for(definition)

    raw_value, source = if !environment_value.nil?
      [ environment_value, :environment ]
    elsif overrides.key?(definition.key)
      [ overrides.fetch(definition.key), :candidate ]
    elsif !saved_value.nil?
      [ saved_value, :database ]
    else
      [ definition.default, :default ]
    end

    Entry.new(
      definition: definition,
      effective_value: cast(definition, raw_value),
      saved_value: cast(definition, saved_value),
      environment_value: cast(definition, environment_value),
      active_environment_key: active_environment_key,
      source: source
    )
  end

  def entries_for(section, overrides: {})
    Registry.definitions_for(section).map { |definition| entry(definition.key, overrides: overrides) }
  end

  def values_for(section, overrides: {})
    entries_for(section, overrides: overrides).to_h { |entry| [ entry.key, entry.effective_value ] }
  end

  def fingerprint(section, overrides: {})
    values = values_for(section, overrides: overrides)
    if section.to_s.tr("-", "_") == "clickhouse"
      values["clickhouse.mode"] = values["clickhouse.mode"] == "disabled" ? "disabled" : "enabled_connection"
    end
    canonical = values.sort.to_h.transform_values { |value| Digest::SHA256.hexdigest(value.to_s) }
    Digest::SHA256.hexdigest(canonical.to_json)
  end

  def save_section!(section, values:, clear_keys:, actor:, request_id: nil)
    definitions = Registry.definitions_for(section)
    permitted_keys = definitions.map(&:key)
    clear_keys = Array(clear_keys) & permitted_keys

    InstanceSetting.transaction do
      definitions.each do |definition|
        if clear_keys.include?(definition.key)
          remove!(definition, actor: actor, request_id: request_id)
          next
        end

        next unless values.key?(definition.key)

        raw_value = values.fetch(definition.key)
        next if definition.secret? && raw_value.blank?

        if raw_value.blank?
          remove!(definition, actor: actor, request_id: request_id)
        else
          persist!(definition, raw_value, actor: actor, request_id: request_id)
        end
      end
    end
  end

  def candidate_overrides(section, values)
    Registry.definitions_for(section).each_with_object({}) do |definition, overrides|
      next unless values.key?(definition.key)

      raw_value = values.fetch(definition.key)
      next if definition.secret? && raw_value.blank?

      overrides[definition.key] = raw_value
    end
  end

  def audit!(key:, action:, actor:, request_id: nil, details: {})
    InstanceSettingChange.create!(
      key: key,
      action: action,
      actor: actor,
      request_id: request_id,
      details: details
    )
  end

  def environment_resolution_for(definition)
    value = ENV[definition.env_key]
    if definition.key == "archive_storage.service" && value.present?
      normalized = %w[amazon s3].include?(value.to_s) ? "s3" : "local"
      return [ normalized, definition.env_key ]
    end
    return [ value, definition.env_key ] if value.present?

    if definition.key == "clickhouse.mode" && ENV["LOGISTER_CLICKHOUSE_ENABLED"].present?
      value = ActiveModel::Type::Boolean.new.cast(ENV["LOGISTER_CLICKHOUSE_ENABLED"]) ? "dual_write" : "disabled"
      return [ value, "LOGISTER_CLICKHOUSE_ENABLED" ]
    end

    if definition.key == "archive_storage.service" && ENV["ACTIVE_STORAGE_SERVICE"].present?
      value = %w[amazon s3].include?(ENV["ACTIVE_STORAGE_SERVICE"].to_s) ? "s3" : "local"
      return [ value, "ACTIVE_STORAGE_SERVICE" ]
    end

    [ nil, nil ]
  end

  def cast(definition, value)
    return nil if value.nil?

    case definition.type
    when :boolean
      ActiveModel::Type::Boolean.new.cast(value)
    when :integer
      Integer(value, exception: false) || definition.default.to_i
    when :select
      allowed = Array(definition.options).map(&:last).map(&:to_s)
      normalized = value.to_s.strip
      allowed.find { |option| option.casecmp?(normalized) } || definition.default.to_s
    else
      value.to_s
    end
  end

  def saved_value_for(key)
    InstanceSetting.find_by(key: key)&.value
  rescue ActiveRecord::StatementInvalid, ActiveSupport::MessageEncryptor::InvalidMessage
    nil
  end
  private_class_method :saved_value_for

  def persist!(definition, raw_value, actor:, request_id:)
    setting = InstanceSetting.find_or_initialize_by(key: definition.key)
    setting.value = raw_value
    setting.updated_by_user = actor
    action = setting.new_record? ? "created" : "updated"
    setting.save!
    audit!(
      key: definition.key,
      action: action,
      actor: actor,
      request_id: request_id,
      details: { "section" => definition.section, "secret" => definition.secret?, "restart_required" => definition.restart_required? }
    )
  end
  private_class_method :persist!

  def remove!(definition, actor:, request_id:)
    setting = InstanceSetting.find_by(key: definition.key)
    return unless setting

    setting.destroy!
    audit!(
      key: definition.key,
      action: "removed",
      actor: actor,
      request_id: request_id,
      details: { "section" => definition.section, "secret" => definition.secret? }
    )
  end
  private_class_method :remove!
end
