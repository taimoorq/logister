class ApiKey < ApplicationRecord
  DEFAULT_TOKEN_PREFIX = "logister".freeze

  belongs_to :user
  belongs_to :project
  has_many :ingest_events, dependent: :destroy

  attr_reader :plain_token

  scope :active, -> { where(revoked_at: nil) }

  before_validation :ensure_uuid
  before_validation :ensure_token_digest, on: :create

  validates :uuid, presence: true, uniqueness: true
  validates :name, presence: true
  validates :token_digest, presence: true, uniqueness: true

  def to_param
    uuid
  end

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

    @plain_token = generated_plain_token
    self.token_digest = self.class.digest(@plain_token)
  end

  def ensure_uuid
    self.uuid ||= SecureRandom.uuid
  end

  def generated_plain_token
    [ token_prefix, SecureRandom.hex(24) ].join("_")
  end

  def token_prefix
    ENV.fetch("LOGISTER_API_KEY_PREFIX", DEFAULT_TOKEN_PREFIX)
  end
end
