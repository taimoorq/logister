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

  enum :integration_kind, { ruby: "ruby", cfml: "cfml", javascript: "javascript", python: "python", dotnet: "dotnet" }, default: :ruby, validate: true, prefix: :integration

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

  def integration_label
    {
      "ruby" => "Ruby gem",
      "cfml" => "CFML",
      "javascript" => "JavaScript / TypeScript",
      "python" => "Python",
      "dotnet" => ".NET / ASP.NET Core"
    }.fetch(integration_kind, integration_kind.to_s.humanize)
  end

  def self.integration_options
    [
      [ "Ruby gem", "ruby" ],
      [ ".NET / ASP.NET Core (logister-dotnet)", "dotnet" ],
      [ "CFML", "cfml" ],
      [ "JavaScript / TypeScript (logister-js)", "javascript" ],
      [ "Python (logister-python)", "python" ]
    ]
  end

  # Stats for project index: raw event volume, activity volume, open error groups,
  # total error groups, and 7-day raw event trend per project.
  def self.stats_for(project_ids)
    return {} if project_ids.blank?

    stats = Hash.new do |h, k|
      h[k] = { total_events: 0, activity_events: 0, open_groups: 0, all_groups: 0, trend: Array.new(7, 0) }
    end
    project_error_groups = ErrorGroup.where(project_id: project_ids)
    project_events = IngestEvent.where(project_id: project_ids)

    project_error_groups.group(:project_id).count.each do |pid, count|
      stats[pid][:all_groups] = count
    end

    project_error_groups.unresolved.group(:project_id).count.each do |pid, count|
      stats[pid][:open_groups] = count
    end

    project_events.group(:project_id).count.each do |pid, count|
      stats[pid][:total_events] = count
    end

    project_events.where.not(event_type: :error).group(:project_id).count.each do |pid, count|
      stats[pid][:activity_events] = count
    end

    trend_dates = 7.times.map { |i| Date.current - (6 - i) }
    project_events
      .where("occurred_at >= ?", trend_dates.first.beginning_of_day)
      .group(:project_id, "DATE(occurred_at)")
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
