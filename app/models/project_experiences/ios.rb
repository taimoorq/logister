# frozen_string_literal: true

module ProjectExperiences
  class Ios < Base
    def key
      :ios
    end

    def inbox_title
      "Stability issues"
    end

    def inbox_empty_message
      "No iOS stability issues match this view."
    end

    def search_placeholder
      "Search errors, symbols, builds, termination codes..."
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
        FilterDefinition.new(key: :diagnostic_kind, label: "Diagnostic type", kind: :select, options: %w[reported_error crash hang cpu_exception excessive_cpu disk_write_exception excessive_disk_writes launch_failure slow_launch watchdog_termination memory_limit_termination memory_pressure_termination nonfatal_resource_diagnostic aggregate_exit_metric unknown_diagnostic]),
        FilterDefinition.new(key: :mechanism, label: "Capture mechanism", kind: :select, options: %w[handled_exception unhandled_exception native_crash hang resource_diagnostic performance_diagnostic watchdog_termination memory_termination disk_write_exception launch_failure unknown]),
        FilterDefinition.new(key: :release, label: "Release", kind: :text, options: []),
        FilterDefinition.new(key: :build_number, label: "Build", kind: :text, options: []),
        FilterDefinition.new(key: :distribution_channel, label: "Distribution", kind: :select, options: %w[app_store testflight enterprise development unknown]),
        FilterDefinition.new(key: :diagnostic_source, label: "Source", kind: :select, options: %w[sdk metrickit]),
        FilterDefinition.new(key: :symbolication_status, label: "Symbol coverage", kind: :select, options: %w[symbolicated partial failed symbols_included artifact_matched partial_coverage verification_pending verification_failed missing build_unknown not_applicable]),
        FilterDefinition.new(key: :apple_platform, label: "Apple platform", kind: :select, options: %w[ios ipados macos tvos watchos visionos]),
        FilterDefinition.new(key: :device_model, label: "Device", kind: :text, options: []),
        FilterDefinition.new(key: :device_family, label: "Device family", kind: :text, options: []),
        FilterDefinition.new(key: :architecture, label: "Architecture", kind: :select, options: %w[arm64 x86_64 arm]),
        FilterDefinition.new(key: :os_version, label: "OS version", kind: :text, options: []),
        FilterDefinition.new(key: :screen, label: "Screen", kind: :text, options: []),
        FilterDefinition.new(key: :foreground, label: "App state", kind: :select, options: %w[true false]),
        FilterDefinition.new(key: :time_range, label: "Evidence time range", kind: :select, options: %w[24h 7d 30d 90d all])
      ].freeze
    end

    def detail_sections(event:, occurrences_count:, related_logs_count:)
      return activity_detail_sections(event:, related_logs_count:, mobile: true) if activity_event?(event)

      presenter = event_presenter(event)
      evidence_label = case presenter.diagnostic_kind
      when "reported_error" then "Reporting stack"
      when "hang", "cpu_exception", "excessive_cpu", "disk_write_exception", "excessive_disk_writes", "launch_failure", "slow_launch" then "Sampled call tree"
      when "watchdog", "watchdog_termination" then "Termination & stack"
      when "memory_termination", "memory_limit_termination", "memory_pressure_termination" then "Memory evidence"
      when "aggregate_exit_metric" then "Aggregate evidence"
      else "Crash stack"
      end
      [
        section(:stacktrace, evidence_label),
        section(:trail, "Trail"),
        section(:occurrences, "Occurrences (#{occurrences_count})"),
        section(:app_device, "App & device"),
        section(:raw, "Raw")
      ]
    end

    def stacktrace_partial(_event)
      "project_events/profiles/ios/stacktrace"
    end

    def event_presenter(event)
      ProjectEvents::IosEventPresenter.new(event)
    end

    def setup_intro
      "Verify one real SDK diagnostic and its app/build context, then add the optional correlation, MetricKit, symbol, and App Store sources needed for production triage."
    end

    def setup_steps(status:, manager:)
      [
        setup_step(:mobile_token, "Mobile token", :key, status[:mobile_token], manager ? "Issue a short-lived mobile ingest token." : "Ask an admin to configure the token issuer.", stage: :connect),
        setup_step(:first_event, "First diagnostic", :events, status[:has_events], "Send a reported error from the Apple app.", stage: :verify_delivery),
        setup_step(:app_build, "App & build", :deployments, status[:app_build_metadata], "Capture bundle identifier, version, and build number.", stage: :verify_delivery),
        setup_step(:sessions, "Sessions", :account, status[:sessions], "Add opt-in session correlation before using session health metrics."),
        setup_step(:installations, "Installations", :account, status[:installations], "Send only a rotating random installation hash; never IDFA or raw IDFV."),
        setup_step(:breadcrumbs, "Breadcrumbs", :events, status[:breadcrumbs], "Attach a bounded app trail to explain what preceded an issue."),
        setup_step(:metrickit, "MetricKit", :warning, status[:metric_kit], "Enable the opt-in subscriber for crash, hang, excessive-CPU, excessive-disk-write, and slow-launch diagnostics."),
        setup_step(:source_repo, "Source repo", :source_code, status[:source_repository], "Connect GitHub for source-aware frames."),
        setup_step(:symbols, "dSYM coverage", :source_code, status[:apple_symbols], "Upload exact UUID/architecture symbols for address-only production frames."),
        setup_step(:app_store, "App Store", :external, status[:app_store], "Connect App Store reporting as a separate, freshness-labelled source.", stage: :external_sources)
      ]
    end

    def setup_ingest_example
      {
        event: {
          event_type: "error",
          level: "error",
          message: "Checkout request failed",
          occurred_at: "2026-07-26T12:00:00Z",
          context: {
            telemetry_schema_version: 2,
            platform: "ios",
            apple_platform: "ios",
            release: "com.acme.shop@4.2.0+310",
            diagnostic: { source: "sdk", kind: "reported_error" },
            error: { mechanism: "handled_exception", handled: true, fatal: false },
            app: { identifier: "com.acme.shop", version_name: "4.2.0", version_code: "310" },
            distribution: { channel: "testflight" },
            os: { name: "iOS", version: "19.0" },
            device: { family: "iPhone", architecture: "arm64" }
          }
        }
      }
    end
  end
end
