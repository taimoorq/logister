# frozen_string_literal: true

module ProjectExperiences
  class Android < Base
    def key
      :android
    end

    def inbox_title
      "Stability issues"
    end

    def inbox_empty_message
      "No Android stability issues match this view."
    end

    def search_placeholder
      "Search exceptions, methods, releases..."
    end

    def default_sort
      "recommended"
    end

    def sort_options
      [
        [ "Recommended", "recommended" ],
        [ "Impact", "impact" ],
        [ "Velocity", "velocity" ],
        [ "Newest first", "last_seen" ]
      ]
    end

    def filters
      [
        FilterDefinition.new(key: :mechanism, label: "Failure type", kind: :select, options: %w[handled_exception unhandled_exception anr native_crash low_memory_kill unknown]),
        FilterDefinition.new(key: :mapping_status, label: "Mapping coverage", kind: :select, options: %w[mapping_matched missing build_unknown]),
        FilterDefinition.new(key: :release, label: "Release", kind: :text, options: []),
        FilterDefinition.new(key: :build_number, label: "Build", kind: :text, options: []),
        FilterDefinition.new(key: :track, label: "Play track", kind: :select, options: %w[internal closed open production non_play]),
        FilterDefinition.new(key: :environment, label: "Environment", kind: :text, options: []),
        FilterDefinition.new(key: :build_type, label: "Build type", kind: :text, options: []),
        FilterDefinition.new(key: :device_manufacturer, label: "Manufacturer", kind: :text, options: []),
        FilterDefinition.new(key: :device_model, label: "Device", kind: :text, options: []),
        FilterDefinition.new(key: :device_form_factor, label: "Form factor", kind: :text, options: []),
        FilterDefinition.new(key: :os_version, label: "Android version", kind: :text, options: []),
        FilterDefinition.new(key: :api_level, label: "API level", kind: :text, options: []),
        FilterDefinition.new(key: :screen, label: "Screen / activity", kind: :text, options: []),
        FilterDefinition.new(key: :foreground, label: "App state", kind: :select, options: %w[true false]),
        FilterDefinition.new(key: :time_range, label: "Evidence time range", kind: :select, options: %w[24h 7d 30d 90d all])
      ].freeze
    end

    def detail_sections(event:, occurrences_count:, related_logs_count:)
      return activity_detail_sections(event:, related_logs_count:, mobile: true) if activity_event?(event)

      presenter = event_presenter(event)
      evidence_label = {
        "anr" => "ANR evidence",
        "low_memory_kill" => "Exit evidence"
      }.fetch(presenter.mechanism, "Stack trace")
      [
        section(:stacktrace, evidence_label),
        section(:trail, "Trail"),
        section(:occurrences, "Occurrences (#{occurrences_count})"),
        section(:app_device, "App & device"),
        section(:raw, "Raw")
      ]
    end

    def stacktrace_partial(_event)
      "project_events/profiles/android/stacktrace"
    end

    def event_presenter(event)
      ProjectEvents::AndroidEventPresenter.new(event)
    end

    def setup_intro
      "Verify mobile authentication and one real app event, then add release, session, mapping, and Google Play evidence as your monitoring matures."
    end

    def setup_steps(status:, manager:)
      [
        setup_step(:mobile_token, "Mobile token", :key, status[:mobile_token], manager ? "Issue a short-lived mobile ingest token." : "Ask an admin to configure the token issuer.", stage: :connect),
        setup_step(:first_event, "First event", :events, status[:has_events], "Send an Android event from the app.", stage: :verify_delivery),
        setup_step(:release, "Release/build", :deployments, status[:release_metadata], "Capture version name and version code.", stage: :verify_delivery),
        setup_step(:sessions, "Sessions", :account, status[:sessions], "Enable lifecycle session tracking when consent permits."),
        setup_step(:automatic_handler, "Automatic handler", :warning, status[:automatic_capture], "Enable the uncaught-exception handler if appropriate."),
        setup_step(:source_repo, "Source repo", :source_code, status[:source_repository], "Connect GitHub for source-aware frames."),
        setup_step(:mapping, "R8 mapping", :source_code, status[:android_mapping], "Upload mapping.txt for the current release build."),
        setup_step(:google_play, "Google Play", :external, status[:google_play], "Connect Play reporting for store-side vitals.", stage: :external_sources)
      ]
    end
  end
end
