# frozen_string_literal: true

module Logister
  # Sidekiq needs its capsules before Rails finishes booting.
  class SidekiqWorkloadConfiguration
    def self.apply!(config)
      return unless config[:logister_worker_role] == "core"
      return if config[:logister_workload_configured]

      total = config.concurrency
      projector = Integer(ENV.fetch("SIDEKIQ_PROJECTOR_CONCURRENCY") { [ total - 2, 1 ].max })
      unless projector.positive? && projector < total
        raise ArgumentError, "The core worker needs at least one projector and one general thread within its concurrency budget"
      end

      config.default_capsule do |capsule|
        capsule.concurrency = total - projector
        capsule.queues = config.queues.reject { |queue| queue == "projector" }.uniq.map { |queue| [ queue, 1 ] }
      end
      config.capsule("projector") do |capsule|
        capsule.concurrency = projector
        capsule.queues = [ "projector" ]
      end
      config[:logister_workload_configured] = true
    end
  end
end
