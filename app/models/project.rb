class Project < ApplicationRecord
  belongs_to :user
  has_many :api_keys, dependent: :destroy
  has_many :ingest_events, dependent: :destroy
  has_many :error_groups, dependent: :destroy
  has_many :check_in_monitors, dependent: :destroy
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

  # Stats for project index: total_events, open_groups, trend (7-day counts) per project.
  def self.stats_for(project_ids)
    return {} if project_ids.blank?

    stats = Hash.new { |h, k| h[k] = { total_events: 0, open_groups: 0, trend: Array.new(7, 0) } }
    project_error_groups = ErrorGroup.where(project_id: project_ids)
    project_events = IngestEvent.where(project_id: project_ids)

    project_error_groups.unresolved.group(:project_id).count.each do |pid, count|
      stats[pid][:open_groups] = count
    end

    project_events.group(:project_id).count.each do |pid, count|
      stats[pid][:total_events] = count
    end

    trend_dates = 7.times.map { |i| Date.current - (6 - i) }
    ErrorOccurrence
      .joins(:error_group)
      .where(error_groups: { project_id: project_ids })
      .where("error_occurrences.occurred_at >= ?", 7.days.ago)
      .group("error_groups.project_id", "DATE(error_occurrences.occurred_at)")
      .count
      .each do |(pid, date), count|
        idx = trend_dates.index(date.to_date)
        stats[pid][:trend][idx] = count if idx
      end

    stats
  end

  def self.stats_cache_version(project_ids)
    return [] if project_ids.blank?

    [
      ErrorGroup.where(project_id: project_ids).maximum(:updated_at)&.utc&.to_i || 0,
      IngestEvent.where(project_id: project_ids).maximum(:updated_at)&.utc&.to_i || 0,
      ErrorOccurrence.joins(:error_group)
                     .where(error_groups: { project_id: project_ids })
                     .maximum(:updated_at)&.utc&.to_i || 0
    ]
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
