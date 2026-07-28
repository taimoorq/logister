# frozen_string_literal: true

module InstanceConfiguration
  module Cipher
    PURPOSE = "logister-instance-settings-v1"

    module_function

    def seal(value)
      encryptor.encrypt_and_sign(value.to_s, purpose: PURPOSE)
    end

    def unseal(value)
      encryptor.decrypt_and_verify(value.to_s, purpose: PURPOSE)
    end

    def encryptor
      key = ActiveSupport::KeyGenerator.new(Rails.application.secret_key_base)
                                       .generate_key(PURPOSE, ActiveSupport::MessageEncryptor.key_len("aes-256-gcm"))
      ActiveSupport::MessageEncryptor.new(key, cipher: "aes-256-gcm")
    end
  end
end
