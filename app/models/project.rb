class Project < ApplicationRecord
  belongs_to :user
  has_many :api_keys, dependent: :destroy
  has_many :ingest_events, dependent: :destroy

  before_validation :ensure_uuid
  before_validation :normalize_slug

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: { scope: :user_id }
  validates :uuid, presence: true, uniqueness: true

  def to_param
    uuid
  end

  private

  def ensure_uuid
    self.uuid ||= SecureRandom.uuid
  end

  def normalize_slug
    base = slug.presence || name
    self.slug = base.to_s.parameterize
  end
end
