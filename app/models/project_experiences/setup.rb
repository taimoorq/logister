# frozen_string_literal: true

module ProjectExperiences::Setup
  def setup_intro
    "Start with a token, send one event, then add source and release context when the basics are flowing."
  end

  def setup_steps(status:, manager:)
    [
      setup_step(:api_key, "API key", :key, status[:active_api_key], manager ? "Create a token for the app." : "Ask an admin for a token.", stage: :connect),
      setup_step(:first_event, "First event", :events, status[:has_events], "Send one error, log, metric, or transaction.", stage: :verify_delivery),
      setup_step(:source_repo, "Source repo", :source_code, status[:source_repository], "Connect GitHub for source-aware frames.", stage: :improve_evidence),
      setup_step(:deployments, "Deployments", :deployments, status[:deployments], "Record deploys from CI/CD.", stage: :external_sources)
    ]
  end

  def setup_ingest_example
    {
      event: {
        event_type: "error",
        level: "error",
        message: "NoMethodError in CheckoutService",
        fingerprint: "checkout-nomethoderror",
        occurred_at: "2026-02-14T12:00:00Z",
        context: { environment: "production" }
      }
    }
  end
end
