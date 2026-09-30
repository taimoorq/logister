# frozen_string_literal: true

# The setup checklist for one project, as one viewer sees it.
#
# Every step resolves to a single state, a single owner, and a single action.
# Completion comes only from project evidence; the one thing a person can record
# is that an optional step is not needed (`ProjectSetupStep`).
class ProjectSetupPlan
  DONE_STATES = %i[complete not_applicable skipped].freeze
  ATTENTION_STATES = %i[failed stale].freeze

  STATE_LABELS = {
    complete: "Complete",
    partial: "Partial",
    pending: "To do",
    stale: "Stale",
    blocked: "Blocked",
    failed: "Failed",
    not_applicable: "Not applicable",
    skipped: "Not needed"
  }.freeze

  # `action.kind` is :form or :guide when the viewer can do the work, :ask when
  # it belongs to someone else, and :admin when an instance setting is missing.
  ItemAction = Data.define(:label, :path, :kind, :note, :copy_path)

  Item = Data.define(
    :step, :state, :evidence, :observed_at, :owner, :owner_label, :blocker, :action, :skippable, :skipped
  ) do
    def key = step.key
    def label = step.label
    def icon = step.icon
    def summary = step.summary
    def group_key = step.group_key
    def state_label = STATE_LABELS.fetch(state)
    def done? = DONE_STATES.include?(state)
    def open? = !done?
    def attention? = ATTENTION_STATES.include?(state)
    def blocked? = state == :blocked
    def instance_blocked? = blocker == :instance

    # How a setup path presents this step to this viewer: the step's own kind
    # (:embedded, :guide, :handoff), or why the viewer cannot act on it yet.
    def presentation
      return :instance_blocked if instance_blocked?
      return :dependency_blocked if blocked?
      return :ask if action&.kind == :ask

      step.wizard
    end

    # Something the viewer can do right now.
    def actionable?
      open? && !blocked? && action.present? && %i[form guide].include?(action.kind)
    end
  end

  GroupView = Data.define(:group, :items) do
    def key = group.key
    def label = group.label
    def summary = group.summary
    def requirement = group.requirement
    def requirement_label = group.requirement_label
    def done_count = items.count(&:done?)
    def total = items.size
    def complete? = items.all?(&:done?)
  end

  attr_reader :project, :viewer

  def self.for(project, viewer: nil)
    new(project: project, viewer: viewer)
  end

  # A plan limited to the steps that fill a section (plus what they depend on).
  # It is for prompts inside that section; group, live, and next-step answers
  # only make sense on a full plan.
  def self.for_section(project, section_key, viewer: nil)
    experience_key = project.integration_definition.default_experience_key
    keys = ProjectSetupCatalog.steps_for(experience_key)
                              .select { |step| step.fills_sections.include?(section_key.to_sym) }
                              .map(&:key)
    new(project: project, viewer: viewer, only: keys)
  end

  def self.for_steps(project, step_keys, viewer: nil)
    new(project: project, viewer: viewer, only: step_keys)
  end

  def initialize(project:, viewer: nil, only: nil)
    @project = project
    @viewer = viewer
    @only = only&.map(&:to_sym)
    @experience_key = project.integration_definition.default_experience_key
  end

  def groups
    @groups ||= ProjectSetupCatalog::GROUPS.filter_map do |group|
      group_items = items.select { |item| item.group_key == group.key }
      GroupView.new(group: group, items: group_items.freeze) if group_items.any?
    end.freeze
  end

  def items
    @items ||= build_items.freeze
  end

  def item(key)
    items.find { |candidate| candidate.key == key.to_sym }
  end

  # The steps that fill an empty section, in setup order.
  def items_filling(section_key)
    items.select { |candidate| candidate.step.fills_sections.include?(section_key.to_sym) }
  end

  # What to show in place of an empty page: the first step, in setup order, that
  # is still open. `only` narrows it to the steps that matter for that page. A
  # step waiting on another step points at the step it is waiting on, so the
  # prompt always names something the person can do.
  def prompt_item(only: nil)
    wanted = only&.map(&:to_sym)
    candidate = items.find { |item| item.open? && (wanted.nil? || wanted.include?(item.key)) }
    candidate && resolve_dependency(candidate)
  end

  def group_view(key)
    groups.find { |group| group.key == key.to_sym }
  end

  # Where Continue goes: the next step still to do, in this path and then the
  # following ones. A step that is only waiting on this one counts, because it
  # becomes available the moment this one is done. Steps waiting on an instance
  # setting are skipped. Nil means there is nothing left, and the caller returns
  # to the hub.
  def continue_item_after(item)
    position = items.index(item)
    return unless position

    items.drop(position + 1).find { |candidate| candidate.actionable? || unlocked_by?(candidate, item) }
  end

  # The previous step in the same path, or nil for the first.
  def previous_item_before(item)
    group_items = group_view(item.group_key)&.items || []
    position = group_items.index(item)
    position&.positive? ? group_items[position - 1] : nil
  end

  # The project is live once every required step is complete.
  def live?
    required_items.all?(&:done?)
  end

  def required_items
    items.select { |candidate| candidate.step.group.required? }
  end

  def required_done_count = required_items.count(&:done?)
  def required_total = required_items.size

  # First thing to do: required steps first, then recommended. Optional steps are
  # never suggested, and steps waiting on an instance setting are not offered.
  def next_item
    @next_item ||= begin
      candidates = items.select(&:actionable?)
      candidates.find { |candidate| candidate.step.group.required? } ||
        candidates.find { |candidate| candidate.step.group.recommended? }
    end
  end

  def open_recommended_items
    items.select { |candidate| candidate.step.group.recommended? && candidate.actionable? }
  end

  # A configured integration that is failing or stale deserves attention even
  # when everything else is finished.
  def attention_item
    items.find(&:attention?)
  end

  def summary
    ProjectSetupSummary.from_plan(self)
  end

  # A viewer-less plan backs the shared header summary, which only points at the
  # Setup hub; the hub itself is always built for a real viewer.
  def manager?
    viewer.nil? || project.managed_by?(viewer)
  end

  def managers
    @managers ||= ([ project.user ] + project.project_memberships.admin.includes(:user).map(&:user)).compact.uniq
  end

  private

  def unlocked_by?(candidate, item)
    return false unless candidate.open? && candidate.blocker == :dependency

    candidate.step.depends_on.all? { |key| key == item.key || item(key)&.done? }
  end

  def resolve_dependency(candidate)
    return candidate unless candidate.blocker == :dependency

    waiting_on = candidate.step.depends_on.map { |key| item(key) }.compact.find { |dependency| !dependency.done? }
    waiting_on ? resolve_dependency(waiting_on) : candidate
  end

  # Personal steps only exist for a known viewer, so a viewer-less plan (used for
  # the shared header summary) never depends on who is looking.
  def experience_steps
    @experience_steps ||= begin
      steps = ProjectSetupCatalog.steps_for(@experience_key).select do |step|
        applies?(step) && (viewer.present? || !step.personal)
      end
      @only ? limit_to(steps) : steps
    end
  end

  # The requested steps and, transitively, the steps they wait on.
  def limit_to(steps)
    wanted = @only.to_set
    loop do
      before = wanted.size
      steps.each { |step| wanted.merge(step.depends_on) if wanted.include?(step.key) }
      break if wanted.size == before
    end
    steps.select { |step| wanted.include?(step.key) }
  end

  def applies?(step)
    case step.applies_when
    when nil then true
    when :archives_enabled then project.retention_policy&.archive_enabled? || false
    else raise ArgumentError, "Unknown setup condition: #{step.applies_when}"
    end
  end

  def evidence
    @evidence ||= begin
      keys = experience_steps.map(&:evidence_key).uniq - [ :alerts ]
      ProjectSetupStatus.new(project).call(keys: keys)
    end
  end

  def skipped_keys
    @skipped_keys ||= project.persisted? ? project.setup_steps.skipped.pluck(:key).map(&:to_sym) : []
  end

  def build_items
    resolved = {}
    experience_steps.each do |step|
      resolved[step.key] = build_item(step, resolved)
    end
    resolved.values
  end

  def build_item(step, resolved)
    status = step.evidence_key == :alerts ? alerts_status : evidence[step.evidence_key]
    state = state_from(status)
    evidence_text = status&.reason.presence || step.summary
    observed_at = status&.observed_at
    blocker = nil
    owner = step.owner

    if DONE_STATES.exclude?(state) && skippable?(step) && skipped_keys.include?(step.key)
      state = :skipped
    end

    if state == :pending
      waiting_on = step.depends_on.map { |key| resolved[key] }.compact.find { |dependency| !dependency.done? }
      if waiting_on
        state = :blocked
        blocker = :dependency
        evidence_text = "Finish #{waiting_on.label.downcase} first."
      end
    end

    # Alerts can never be delivered without email, whatever the preferences say.
    # Other steps keep any evidence they already have.
    prerequisite = ProjectSetupPrerequisites.for_step(step.key)
    if prerequisite && !prerequisite.met && (step.personal || DONE_STATES.exclude?(state))
      state = :blocked
      blocker = :instance
      owner = :instance_admin
      evidence_text = prerequisite.message
    end

    Item.new(
      step: step,
      state: state,
      evidence: evidence_text,
      observed_at: observed_at,
      owner: owner,
      owner_label: owner_label_for(step, owner),
      blocker: blocker,
      action: action_for(step, status, state, owner, prerequisite),
      skippable: skippable?(step),
      skipped: state == :skipped
    )
  end

  def skippable?(step)
    ProjectSetupCatalog.skippable?(step.key)
  end

  STATE_MAP = {
    available: :complete,
    configured: :complete,
    partial: :partial,
    stale: :stale,
    blocked: :blocked,
    failed: :failed,
    not_applicable: :not_applicable,
    unsupported: :not_applicable,
    unconfigured: :pending
  }.freeze

  def state_from(status)
    return :pending unless status

    STATE_MAP.fetch(status.state, :pending)
  end

  OWNER_LABELS = {
    anyone: "You",
    manager: "Project manager",
    code: "Your code or CI",
    instance_admin: "Logister admin"
  }.freeze

  def owner_label_for(step, owner)
    return OWNER_LABELS.fetch(owner) if owner != step.owner

    step.owner_label || OWNER_LABELS.fetch(owner)
  end

  # Your alerts is personal: it is about whether this viewer will be told.
  def alerts_status
    return nil unless viewer

    preference = ProjectNotificationPreference.find_by(user_id: viewer.id, project_id: project.id)
    delivers = preference.nil? || preference.delivers_any_alert?
    CapabilityStatus.new(
      key: :alerts,
      state: delivers ? :configured : :unconfigured,
      provenance: :setup_evidence,
      observed_at: preference&.updated_at,
      reason: delivers ? "Alerts are on for you." : "All alerts are off for you on this project.",
      action_key: :review_alerts
    )
  end

  def action_for(step, status, state, owner, prerequisite)
    key = status&.action_key || step.action_key
    return nil unless ProjectSetupActions.registered?(key)

    action = ProjectSetupActions.action_for(key)

    return admin_action(prerequisite, action) if state == :blocked && owner == :instance_admin
    return nil if state == :blocked

    if step.owner == :manager && !manager?
      return nil if DONE_STATES.include?(state)

      return ItemAction.new(label: "Ask a manager", path: nil, kind: :ask, note: ask_note, copy_path: nil)
    end

    label = state == :complete ? "Review" : action.label
    ItemAction.new(label: label, path: step_path(step), kind: action.kind, note: nil, copy_path: nil)
  end

  # Every step has a page in its setup path; the button opens that page.
  def step_path(step)
    Rails.application.routes.url_helpers.setup_step_project_path(project, group: step.group_key, step: step.key)
  end

  def ask_note
    names = managers.first(3).map { |user| user.name.presence || user.email }
    names.any? ? "Ask #{names.to_sentence(two_words_connector: ' or ', last_word_connector: ', or ')}." : "Ask a project manager."
  end

  def admin_action(prerequisite, action)
    section = prerequisite&.admin_section
    admin_path = section ? Rails.application.routes.url_helpers.admin_installation_section_path(section) : nil

    if viewer && admin_user?(viewer) && admin_path
      ItemAction.new(label: "Open admin settings", path: admin_path, kind: :admin, note: nil, copy_path: nil)
    else
      note = section ? "Your Logister admin needs to set up #{prerequisite.label.downcase}." : prerequisite&.message
      ItemAction.new(label: "Ask your admin", path: nil, kind: :ask, note: note, copy_path: admin_path)
    end
  end

  def admin_user?(user)
    return true if user.application_admin?

    admin_emails = ENV.fetch("LOGISTER_ADMIN_EMAILS", "").split(",").map { |email| email.strip.downcase }.reject(&:blank?)
    admin_emails.include?(user.email.to_s.downcase)
  end
end
