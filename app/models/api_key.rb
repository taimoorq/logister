class ApiKey < ApplicationRecord
  belongs_to :user
  belongs_to :project

  attr_reader :plain_token

  scope :active, -> { where(revoked_at: nil) }

  before_validation :ensure_token_digest, on: :create

  validates :name, presence: true
  validates :token_digest, presence: true, uniqueness: true

  def revoke!
    update!(revoked_at: Time.current)
  end

  def active?
    revoked_at.nil?
  end

  def touch_last_used!
    update_column(:last_used_at, Time.current)
  end

  def self.authenticate(token)
    return nil if token.blank?

    active.find_by(token_digest: digest(token))
  end

  def self.digest(token)
    Digest::SHA256.hexdigest(token.to_s)
  end

  private

  def ensure_token_digest
    return if token_digest.present?

    @plain_token = "logister_#{SecureRandom.hex(24)}"
    self.token_digest = self.class.digest(@plain_token)
  end
end
