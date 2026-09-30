# frozen_string_literal: true

module ProjectExperiences::Setup
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
