# frozen_string_literal: true

class InstanceSetting < ApplicationRecord
  belongs_to :updated_by_user, class_name: "User", optional: true

  validates :key, presence: true, uniqueness: true
  validates :encrypted_value, presence: true

  self.filter_attributes += [ :encrypted_value ]

  def value
    InstanceConfiguration::Cipher.unseal(encrypted_value)
  end

  def value=(plain_value)
    self.encrypted_value = InstanceConfiguration::Cipher.seal(plain_value.to_s)
  end
end
