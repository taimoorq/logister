class ProjectLink < ApplicationRecord
  belongs_to :source_project, class_name: "Project"
  belongs_to :target_project, class_name: "Project"
  belongs_to :created_by, class_name: "User", optional: true
  validates :relation, inclusion: { in: [ "calls" ] }
  validates :target_project_id, uniqueness: { scope: [ :source_project_id, :relation ] }
  validate :valid_pair
  validate :valid_environments

  scope :touching, ->(project) { where(source_project: project).or(where(target_project: project)) }

  def to_param = uuid

  def peer_id(project)
    source_project_id == project.id ? target_project_id : source_project_id
  end

  def environments_for(project, environment)
    from, to = source_project_id == project.id ? [ "source", "target" ] : [ "target", "source" ]
    environment_pairs.filter_map { |pair| pair[to] if pair[from] == environment }.uniq
  end

  def self.connect!(actor:, source:, target:, environment_pairs:)
    raise ActiveRecord::RecordNotFound unless source.managed_by?(actor) && target.managed_by?(actor)
    transaction do
      # Serialize link changes against purge, and recheck project lifecycle.
      projects = Project.where(id: [ source.id, target.id ]).order(:id).lock.to_a
      raise ActiveRecord::RecordNotFound if projects.size != 2 || projects.any? { |p| p.archived? || p.purge_pending? || !p.managed_by?(actor) }
      link = create!(source_project: source, target_project: target, created_by: actor, environment_pairs:)
      link.audit!(actor, "connected")
      link
    end
  end

  def disconnect!(actor:)
    raise ActiveRecord::RecordNotFound unless source_project.managed_by?(actor) || target_project.managed_by?(actor)
    transaction do
      lock!
      raise ActiveRecord::RecordNotFound unless source_project.reload.managed_by?(actor) || target_project.reload.managed_by?(actor)
      audit!(actor, "disconnected")
      destroy!
    end
  end

  def audit!(actor, action)
    ProjectLinkAudit.create!(source_project:, target_project:, actor:, action:, environment_pairs:)
  end

  private

  def valid_pair
    errors.add(:target_project, "must be a different project") if source_project_id == target_project_id
  end

  def valid_environments
    valid = environment_pairs.is_a?(Array) && environment_pairs.length.between?(1, 20) && environment_pairs.all? do |pair|
      pair.is_a?(Hash) && pair.keys.sort == %w[source target] && pair.values.all? { |v| v.is_a?(String) && v.match?(/\A[A-Za-z0-9._-]{1,100}\z/) }
    end
    errors.add(:environment_pairs, "must contain 1–20 named source/target environments") unless valid
  end
end
