# frozen_string_literal: true

# What a project needs, grouped by the outcome each group unlocks.
#
# The four groups are the same for every project type; the steps inside them
# differ. A step names who does it (owner), which project evidence completes it,
# and which sections of the product depend on it. Completion is never stored:
# `ProjectSetupPlan` derives it from project evidence.
class ProjectSetupCatalog
  Group = Data.define(:key, :label, :requirement, :summary) do
    def required? = requirement == :required
    def recommended? = requirement == :recommended
    def optional? = requirement == :optional
    def requirement_label = requirement.to_s.capitalize
  end

  # owner:
  #   :anyone          any project member, done in Logister
  #   :manager         a project owner or admin, done in Logister
  #   :code            done in the project's own code, CI, or backend; Logister verifies
  #   :instance_admin  needs an instance setting (used when a prerequisite is missing)
  Step = Data.define(
    :key, :group_key, :owner, :owner_label, :label, :icon, :summary,
    :evidence_key, :action_key, :depends_on, :fills_sections, :personal, :applies_when, :chip_label, :wizard
  ) do
    # wizard:
    #   :embedded  the step is the same form used in Settings, shown inside the path
    #   :guide     done in the project's own code or CI; the path shows how and verifies it
    #   :handoff   opens an existing page, then returns to the path
    def initialize(owner_label: nil, depends_on: [], fills_sections: [], personal: false, applies_when: nil, chip_label: nil, wizard: nil, **attributes)
      super(
        owner_label:, depends_on: depends_on.freeze, fills_sections: fills_sections.freeze, personal:, applies_when:,
        chip_label: chip_label || "Finish #{attributes.fetch(:label).downcase}",
        wizard: wizard || (attributes.fetch(:owner) == :code ? :guide : :handoff),
        **attributes
      )
      freeze
    end

    def group = ProjectSetupCatalog.group(group_key)
  end

  GROUPS = [
    Group.new(key: :receive_data, label: "Start receiving data", requirement: :required,
              summary: "Finish this path and the project is live."),
    Group.new(key: :actionable, label: "Make issues actionable", requirement: :recommended,
              summary: "Source, releases, and timing so each issue says where and when."),
    Group.new(key: :team, label: "Bring in your team", requirement: :recommended,
              summary: "Give the right people access and make sure alerts reach them."),
    Group.new(key: :extend, label: "Extend coverage", requirement: :optional,
              summary: "Add related projects, scheduled checks, and outside sources when you need them.")
  ].map(&:freeze).freeze

  STEPS = [
    # Start receiving data
    Step.new(key: :api_key, group_key: :receive_data, owner: :manager, label: "API key", icon: :key,
             summary: "Create a project key and keep it in the sending service's secret store.",
             chip_label: "Create an API key",
             wizard: :embedded,
             evidence_key: :active_api_key, action_key: :create_api_key),
    Step.new(key: :mobile_token, group_key: :receive_data, owner: :code, owner_label: "Your backend", label: "Mobile token", icon: :key,
             summary: "Have your backend issue short-lived mobile ingest tokens. Never ship the project API key in the app.",
             chip_label: "Issue a mobile token",
             evidence_key: :mobile_token, action_key: :issue_mobile_token),
    Step.new(key: :first_event, group_key: :receive_data, owner: :code, label: "First event", icon: :events,
             summary: "Send one error, log, metric, or transaction.",
             chip_label: "Waiting for first event",
             evidence_key: :has_events, action_key: :send_first_event, depends_on: [ :api_key ],
             fills_sections: %i[overview issues explore]),
    Step.new(key: :first_diagnostic, group_key: :receive_data, owner: :code, owner_label: "Your app code", label: "First diagnostic", icon: :events,
             summary: "Send one reported error from the app.",
             chip_label: "Waiting for first diagnostic",
             evidence_key: :has_events, action_key: :send_first_event, depends_on: [ :mobile_token ],
             fills_sections: %i[overview issues explore]),
    Step.new(key: :release, group_key: :receive_data, owner: :code, owner_label: "Your app code", label: "Release and build", icon: :deployments,
             summary: "Include version name and version code with each diagnostic.",
             chip_label: "Waiting for release and build",
             evidence_key: :release_metadata, action_key: :capture_release_metadata, depends_on: [ :first_diagnostic ],
             fills_sections: %i[releases]),
    Step.new(key: :app_build, group_key: :receive_data, owner: :code, owner_label: "Your app code", label: "App and build", icon: :deployments,
             summary: "Include bundle identifier, version, and build number with each diagnostic.",
             chip_label: "Waiting for app and build",
             evidence_key: :app_build_metadata, action_key: :capture_release_metadata, depends_on: [ :first_diagnostic ],
             fills_sections: %i[releases]),

    # Make issues actionable
    Step.new(key: :source_repo, group_key: :actionable, owner: :manager, label: "Source repository", icon: :source_code,
             summary: "Connect GitHub so stack frames open the exact line on your default branch.",
             wizard: :embedded,
             evidence_key: :source_repository, action_key: :connect_source_repository,
             fills_sections: %i[issues]),
    Step.new(key: :deployments, group_key: :actionable, owner: :code, owner_label: "Your CI", label: "Deployments", icon: :deployments,
             summary: "Record deploys from CI/CD so issues can be tied to a release.",
             evidence_key: :deployments, action_key: :record_deployment,
             fills_sections: %i[releases]),
    Step.new(key: :performance, group_key: :actionable, owner: :code, label: "Performance instrumentation", icon: :performance,
             summary: "Send transactions or spans so slow and failing requests show up.",
             evidence_key: :performance, action_key: :send_performance,
             fills_sections: %i[performance]),
    Step.new(key: :mapping, group_key: :actionable, owner: :manager, label: "R8 mapping", icon: :source_code,
             summary: "Upload mapping.txt so obfuscated frames resolve for each release build.",
             wizard: :embedded,
             evidence_key: :android_mapping, action_key: :upload_android_mapping,
             fills_sections: %i[issues releases]),
    Step.new(key: :symbols, group_key: :actionable, owner: :manager, label: "dSYM coverage", icon: :source_code,
             summary: "Upload exact UUID and architecture symbols for address-only production frames.",
             wizard: :embedded,
             evidence_key: :apple_symbols, action_key: :upload_apple_symbols,
             fills_sections: %i[issues releases]),
    Step.new(key: :automatic_handler, group_key: :actionable, owner: :code, owner_label: "Your app code", label: "Automatic crash handler", icon: :warning,
             summary: "Enable the uncaught-exception handler if it suits the app.",
             evidence_key: :automatic_capture, action_key: :configure_automatic_capture),
    Step.new(key: :sessions, group_key: :actionable, owner: :code, owner_label: "Your app code", label: "Sessions", icon: :account,
             summary: "Add opt-in session correlation before using session health.",
             evidence_key: :sessions, action_key: :configure_sessions,
             fills_sections: %i[performance]),
    Step.new(key: :installations, group_key: :actionable, owner: :code, owner_label: "Your app code", label: "Installations", icon: :account,
             summary: "Send only a rotating random installation hash; never IDFA or raw IDFV.",
             evidence_key: :installations, action_key: :configure_installations),
    Step.new(key: :breadcrumbs, group_key: :actionable, owner: :code, owner_label: "Your app code", label: "Breadcrumbs", icon: :events,
             summary: "Attach a bounded app trail that explains what preceded an issue.",
             evidence_key: :breadcrumbs, action_key: :configure_breadcrumbs),
    Step.new(key: :metrickit, group_key: :actionable, owner: :code, owner_label: "Your app code", label: "MetricKit", icon: :warning,
             summary: "Enable the opt-in subscriber for crash, hang, CPU, disk-write, and launch diagnostics.",
             evidence_key: :metric_kit, action_key: :configure_metric_kit,
             fills_sections: %i[performance]),

    # Bring in your team
    Step.new(key: :teammates, group_key: :team, owner: :manager, label: "Invite teammates", icon: :team,
             summary: "Give at least one other person access so issues have owners.",
             wizard: :embedded,
             evidence_key: :teammates, action_key: :invite_teammate),
    Step.new(key: :alerts, group_key: :team, owner: :anyone, label: "Your alerts", icon: :notifications,
             summary: "Make sure alerts can reach you when something breaks.",
             wizard: :embedded,
             evidence_key: :alerts, action_key: :review_alerts, personal: true),

    # Extend coverage
    Step.new(key: :linked_projects, group_key: :extend, owner: :manager, label: "Link related projects", icon: :integrations,
             summary: "Follow a failed request between this project and the apps or backends it talks to.",
             evidence_key: :project_links, action_key: :link_projects,
             fills_sections: %i[explore]),
    Step.new(key: :check_ins, group_key: :extend, owner: :code, label: "Check-in monitors", icon: :monitors,
             summary: "Report scheduled jobs and heartbeats so missed runs are noticed.",
             evidence_key: :check_ins, action_key: :configure_check_ins,
             fills_sections: %i[monitors]),
    Step.new(key: :google_play, group_key: :extend, owner: :manager, label: "Google Play", icon: :external,
             summary: "Connect Play reporting as a separate, freshness-labelled source of store vitals.",
             wizard: :embedded,
             evidence_key: :google_play, action_key: :configure_distribution_store,
             fills_sections: %i[releases]),
    Step.new(key: :app_store, group_key: :extend, owner: :manager, label: "App Store", icon: :external,
             summary: "Connect App Store reporting as a separate, freshness-labelled source.",
             wizard: :embedded,
             evidence_key: :app_store, action_key: :configure_distribution_store,
             fills_sections: %i[releases]),
    Step.new(key: :archive_exports, group_key: :extend, owner: :manager, label: "Archive exports", icon: :archive,
             summary: "Write retained telemetry to archive storage before it is deleted.",
             evidence_key: :archive_exports, action_key: :review_archive_exports,
             fills_sections: %i[explore], applies_when: :archives_enabled)
  ].freeze

  BY_KEY = STEPS.to_h { |step| [ step.key, step ] }.freeze
  GROUPS_BY_KEY = GROUPS.to_h { |group| [ group.key, group ] }.freeze

  WIZARD_KINDS = %i[embedded guide handoff].freeze

  STEP_KEYS_BY_EXPERIENCE = {
    server: %i[api_key first_event source_repo deployments performance teammates alerts linked_projects check_ins archive_exports],
    edge: %i[api_key first_event source_repo deployments teammates alerts linked_projects check_ins archive_exports],
    custom: %i[api_key first_event source_repo deployments teammates alerts linked_projects check_ins archive_exports],
    android: %i[mobile_token first_diagnostic release source_repo mapping automatic_handler sessions
                teammates alerts linked_projects check_ins google_play archive_exports],
    ios: %i[mobile_token first_diagnostic app_build source_repo symbols sessions installations breadcrumbs metrickit
            teammates alerts linked_projects check_ins app_store archive_exports]
  }.freeze

  class << self
    def group(key)
      GROUPS_BY_KEY.fetch(key.to_sym)
    end

    def step(key)
      BY_KEY[key.to_sym] if key.present?
    end

    # Steps for an experience in group order, then catalog order within a group.
    def steps_for(experience_key)
      keys = STEP_KEYS_BY_EXPERIENCE.fetch(experience_key.to_sym)
      steps = keys.map { |key| BY_KEY.fetch(key) }
      GROUPS.flat_map { |group| steps.select { |step| step.group_key == group.key } }
    end

    def evidence_keys_for(experience_key)
      steps_for(experience_key).map(&:evidence_key).uniq
    end

    # Personal steps (a viewer's own alerts) are not a project decision, and
    # required steps are never optional.
    def skippable?(key)
      step = step(key)
      step.present? && !step.personal && !step.group.required?
    end

    def validate!
      duplicates = STEPS.map(&:key).tally.select { |_key, count| count > 1 }.keys
      raise ArgumentError, "Duplicate setup steps: #{duplicates.join(', ')}" if duplicates.any?

      STEPS.each do |step|
        raise ArgumentError, "Setup step #{step.key} has an unknown group" unless GROUPS_BY_KEY.key?(step.group_key)
        raise ArgumentError, "Setup step #{step.key} has an unknown owner" unless %i[anyone manager code instance_admin].include?(step.owner)
        raise ArgumentError, "Setup step #{step.key} must name an action" if step.action_key.blank?
        raise ArgumentError, "Setup step #{step.key} has an unknown wizard kind" unless WIZARD_KINDS.include?(step.wizard)
        raise ArgumentError, "Setup step #{step.key} is done in code, so it must be a guide" if step.owner == :code && step.wizard != :guide

        (step.depends_on).each do |dependency|
          raise ArgumentError, "Setup step #{step.key} depends on unknown step #{dependency}" unless BY_KEY.key?(dependency)
        end
        step.fills_sections.each do |section|
          raise ArgumentError, "Setup step #{step.key} fills unknown section #{section}" unless ProjectNavSection.key?(section)
        end
      end

      STEP_KEYS_BY_EXPERIENCE.each do |experience_key, keys|
        ProjectExperienceDefinition.fetch(experience_key)
        raise ArgumentError, "Duplicate setup steps for #{experience_key}" if keys.uniq.size != keys.size

        keys.each { |key| raise ArgumentError, "Unknown setup step #{key} for #{experience_key}" unless BY_KEY.key?(key) }
        steps = keys.map { |key| BY_KEY.fetch(key) }
        unless steps.any? { |step| step.group.required? }
          raise ArgumentError, "Setup for #{experience_key} has no required step"
        end
        steps.each do |step|
          missing = step.depends_on - keys
          raise ArgumentError, "Setup step #{step.key} for #{experience_key} depends on #{missing.join(', ')}, which it does not include" if missing.any?
        end
      end

      unmapped = ProjectExperienceDefinition.keys - STEP_KEYS_BY_EXPERIENCE.keys
      raise ArgumentError, "No setup steps for experiences: #{unmapped.join(', ')}" if unmapped.any?

      true
    end
  end
end
