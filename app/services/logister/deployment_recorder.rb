# frozen_string_literal: true

module Logister
  # Retained for callers of the former self-test helper. Release identity is
  # attached to errors; this app no longer submits standalone deployments.
  class DeploymentRecorder
    def self.call(_payload, configuration: Logister.configuration)
      false
    end
  end
end
