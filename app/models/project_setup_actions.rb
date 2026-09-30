# frozen_string_literal: true

# One registered action per setup outcome: what the button says, and whether the
# work happens in Logister (`:form`) or in the project's own code or CI
# (`:guide`). Every action key emitted by the evidence loaders must be
# registered here so no step can ship without a label and a kind.
#
# Where the button goes is not decided here: every step opens its own page in
# the setup path (see ProjectSetupStepsController).
class ProjectSetupActions
  Action = Data.define(:key, :label, :kind)

  REGISTRY = {
    create_api_key: [ "Create API key", :form ],
    issue_mobile_token: [ "Open guide", :guide ],
    send_first_event: [ "Open guide", :guide ],
    capture_release_metadata: [ "Open guide", :guide ],
    send_performance: [ "Open guide", :guide ],
    configure_sessions: [ "Open guide", :guide ],
    configure_android_sessions: [ "Open guide", :guide ],
    configure_ios_sessions: [ "Open guide", :guide ],
    configure_installations: [ "Open guide", :guide ],
    configure_breadcrumbs: [ "Open guide", :guide ],
    configure_automatic_capture: [ "Open guide", :guide ],
    configure_metric_kit: [ "Open guide", :guide ],
    record_deployment: [ "Open guide", :guide ],
    configure_check_ins: [ "Open guide", :guide ],
    configure_mobile_check_ins: [ "Open guide", :guide ],
    connect_source_repository: [ "Connect repository", :form ],
    upload_android_mapping: [ "Upload mapping", :form ],
    upload_apple_symbols: [ "Upload symbols", :form ],
    configure_distribution_store: [ "Connect", :form ],
    repair_distribution_store: [ "Fix connection", :form ],
    import_distribution_store: [ "Import now", :form ],
    invite_teammate: [ "Invite teammates", :form ],
    review_alerts: [ "Review alerts", :form ],
    link_projects: [ "Link projects", :form ],
    review_archive_exports: [ "Review archives", :form ]
  }.freeze

  class << self
    def registered?(key)
      REGISTRY.key?(key&.to_sym)
    end

    def registered_keys
      REGISTRY.keys
    end

    def action_for(key)
      label, kind = REGISTRY.fetch(key.to_sym)
      Action.new(key: key.to_sym, label: label, kind: kind)
    end
  end
end
