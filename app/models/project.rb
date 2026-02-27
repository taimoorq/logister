class Project < ApplicationRecord
  belongs_to :user
  has_many :api_keys, dependent: :destroy
  has_many :ingest_events, dependent: :destroy
  has_many :error_groups, dependent: :destroy
  has_many :project_memberships, dependent: :destroy
  has_many :members, through: :project_memberships, source: :user

  before_validation :ensure_uuid
  before_validation :normalize_slug

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: { scope: :user_id }
  validates :uuid, presence: true, uniqueness: true

  def to_param
    uuid
  end

  def self.accessible_to(user)
    # Use a subquery to avoid the PostgreSQL restriction that ORDER BY columns
    # must appear in the SELECT list when DISTINCT is used.
    ids = left_outer_joins(:project_memberships)
            .where("projects.user_id = :uid OR project_memberships.user_id = :uid", uid: user.id)
            .distinct
            .pluck(:id)
    where(id: ids)
  end

  def owned_by?(viewer)
    user_id == viewer.id
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
