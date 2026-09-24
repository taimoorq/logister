class ProjectConnectionEnvironments
  COMMON = %w[production staging development].freeze
  SAMPLE_LIMIT = 500

  def initialize(project)
    @project = project
  end

  def groups
    recent = [
      *@project.ingest_events.order(occurred_at: :desc, id: :desc).limit(SAMPLE_LIMIT).pluck(Arel.sql("context->>'environment'")),
      *@project.trace_spans.order(started_at: :desc, id: :desc).limit(SAMPLE_LIMIT).pluck(Arel.sql("context->>'environment'"))
    ].map { |value| value.presence || "production" }
    deployments = @project.deployments.order(deployed_at: :desc).limit(50).pluck(:environment)
    known = (recent + deployments).select { |value| value.is_a?(String) && value.match?(/\A[A-Za-z0-9._-]{1,100}\z/) }.uniq.sort
    [ [ "Seen in recent data", known ], [ "Common names — verify your app configuration", COMMON - known ] ].reject { |_, values| values.empty? }
  end
end
