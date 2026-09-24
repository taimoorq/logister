class ProjectConnectionForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :direction, :string
  attribute :peer_project_uuid, :string
  attribute :source_environment, :string
  attribute :target_environment, :string
  attribute :custom_source_environment, :string
  attribute :custom_target_environment, :string

  attr_reader :project, :actor

  validates :direction, inclusion: { in: %w[incoming outgoing], message: "Choose whether to link an app or a backend." }
  validates :peer_project_uuid, presence: { message: "Choose a project to link." }
  validate :validate_environments
  validate :backend_receives_requests

  def initialize(project:, actor:, **attributes)
    @project = project
    @actor = actor
    super({ direction: mobile?(project) ? "outgoing" : "incoming" }.merge(attributes))
  end

  def incoming? = direction == "incoming"
  def source = incoming? ? peer : project
  def target = incoming? ? project : peer
  def can_receive_requests? = !mobile?(project)

  def candidates
    @candidates ||= begin
      scope = actor.manageable_projects.active.where(purge_requested_at: nil).where.not(id: project.id)
      scope = scope.where.not(integration_kind: %w[android ios]) if direction == "outgoing"
      scope.order(:name, :slug).to_a
    end
  end

  def peer
    return if peer_project_uuid.blank?
    @peer ||= candidates.find { |candidate| candidate.uuid == peer_project_uuid } || raise(ActiveRecord::RecordNotFound)
  end

  def project_options
    candidates.group_by { |candidate| mobile?(candidate) ? "Mobile apps" : "Web apps and services" }.sort.map do |group, projects|
      [ group, projects.map { |candidate| [ label(candidate), candidate.uuid, { disabled: linked_peer_ids.include?(candidate.id) } ] } ]
    end
  end

  def label(project)
    "#{project.name} — #{project.integration_label} (#{project.slug})"
  end

  def environment_groups(project)
    @environment_groups ||= {}
    @environment_groups[project.id] ||= ProjectConnectionEnvironments.new(project).groups
  end

  def save
    return false unless valid?
    ProjectLink.connect!(actor:, source:, target:, environment_pairs: [ {
      "source" => environment_for(:source), "target" => environment_for(:target)
    } ])
    true
  rescue ActiveRecord::RecordInvalid => error
    message = if error.record.errors.of_kind?(:target_project_id, :taken)
      "These projects are already linked. Disconnect the existing link before changing its environments."
    else
      error.record.errors.full_messages.to_sentence
    end
    errors.add(:base, message)
    false
  end

  private

  def mobile?(candidate)
    candidate.integration_android? || candidate.integration_ios?
  end

  def linked_peer_ids
    @linked_peer_ids ||= if incoming?
      ProjectLink.where(target_project: project).pluck(:source_project_id)
    else
      ProjectLink.where(source_project: project).pluck(:target_project_id)
    end
  end

  def environment_for(side)
    selected = public_send("#{side}_environment")
    selected == "__custom__" ? public_send("custom_#{side}_environment").to_s.strip : selected
  end

  def validate_environments
    %i[source target].each do |side|
      next if environment_for(side).to_s.match?(/\A[A-Za-z0-9._-]{1,100}\z/)
      name = side == :source ? "app" : "backend"
      errors.add(:base, "Choose the #{name} environment, or enter its exact name using letters, numbers, dots, underscores or hyphens.")
    end
  end

  def backend_receives_requests
    errors.add(:base, "Choose a backend project to receive requests from the mobile app.") if incoming? && mobile?(project)
  end
end
