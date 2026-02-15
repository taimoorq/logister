class Project < ApplicationRecord
  belongs_to :user
  has_many :api_keys, dependent: :destroy
  has_many :ingest_events, dependent: :destroy

  before_validation :normalize_slug

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: { scope: :user_id }

  private

  def normalize_slug
    base = slug.presence || name
    self.slug = base.to_s.parameterize
  end
end
