class Project < ApplicationRecord
  belongs_to :user
  has_many :api_keys, dependent: :destroy
  has_many :ingest_events, dependent: :destroy
  has_many :error_groups, dependent: :destroy
  has_many :check_in_monitors, dependent: :destroy
  has_many :project_memberships, dependent: :destroy
  has_many :project_notification_preferences, dependent: :destroy
  has_many :email_notification_deliveries, dependent: :destroy
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

  def notification_recipients
    User.where(id: [ user_id, *project_memberships.pluck(:user_id) ]).distinct
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

  # Stats for project index: recent event volume, activity volume, open error groups,
  # total error groups, and 7-day raw event trend per project.
  def self.stats_for(project_ids)
    return {} if project_ids.blank?

    stats = project_ids.index_with do
      { total_events: 0, activity_events: 0, open_groups: 0, all_groups: 0, latest_event_at: nil, trend: Array.new(7, 0) }
    end
    project_error_groups = ErrorGroup.where(project_id: project_ids)
    project_events = IngestEvent.where(project_id: project_ids)
    trend_dates = 7.times.map { |i| Date.current - (6 - i) }
    recent_events = project_events.where("occurred_at >= ?", trend_dates.first.beginning_of_day)

    project_error_groups.group(:project_id).count.each do |pid, count|
      stats[pid][:all_groups] = count
    end

    project_error_groups.unresolved.group(:project_id).count.each do |pid, count|
      stats[pid][:open_groups] = count
    end

    recent_events.where.not(event_type: IngestEvent.event_types[:error]).group(:project_id).count.each do |pid, count|
      stats[pid][:activity_events] = count
    end

    latest_event_at_by_project(project_ids).each do |pid, occurred_at|
      stats[pid][:latest_event_at] = occurred_at
    end

    recent_events
      .group(:project_id, "DATE(occurred_at)")
      .count
      .each do |(pid, date), count|
        idx = trend_dates.index(date.to_date)
        next unless idx

        stats[pid][:trend][idx] = count
        stats[pid][:total_events] += count
      end

    stats
  end

  def self.latest_event_at_by_project(project_ids)
    ids = Array(project_ids).filter_map { |project_id| Integer(project_id, exception: false) }.uniq
    return {} if ids.blank?

    sql = sanitize_sql_array([
      <<~SQL.squish,
        SELECT requested_projects.project_id, latest_events.occurred_at
        FROM unnest(ARRAY[?]::bigint[]) AS requested_projects(project_id)
        LEFT JOIN LATERAL (
          SELECT occurred_at
          FROM ingest_events
          WHERE ingest_events.project_id = requested_projects.project_id
          ORDER BY occurred_at DESC
          LIMIT 1
        ) latest_events ON TRUE
      SQL
      ids
    ])

    connection.exec_query(sql).each_with_object({}) do |row, latest_events|
      occurred_at = row["occurred_at"]
      next if occurred_at.blank?

      latest_events[row["project_id"].to_i] = occurred_at
    end
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
