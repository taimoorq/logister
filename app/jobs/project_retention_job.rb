class ProjectRetentionJob < ApplicationJob
  queue_as :archives

  discard_on ActiveRecord::RecordNotFound

  def perform(project_id, dry_run: false, run_id: nil)
    project = Project.find(project_id)
    run = if run_id
      ProjectRetentionRun.find(run_id).tap do |candidate|
        unless candidate.project_id == project.id && candidate.dry_run? == ActiveModel::Type::Boolean.new.cast(dry_run)
          raise ArgumentError, "Retention run does not match the serialized project/dry-run identity"
        end
      end
    else
      Logister::ProjectRetentionRunCoordinator.create_or_find!(
        project: project,
        scheduled_for: Time.current,
        dry_run: dry_run,
        trigger_kind: "legacy"
      ).run
    end

    outcome = Logister::ProjectRetentionRunRunner.new(run: run).call
    schedule_follow_up(project, run, outcome) if outcome[:action].in?(%i[continue retry])

    if outcome[:action] == :complete
      Rails.logger.info(
        "project_retention.complete project_id=#{project.id} project_uuid=#{project.uuid} " \
        "run_id=#{run.id} dry_run=#{dry_run} deleted=#{outcome.dig(:result, :deleted).inspect}"
      )
    end

    outcome
  end

  private

  def schedule_follow_up(project, run, outcome)
    self.class.set(wait: outcome.fetch(:wait)).perform_later(
      project.id,
      dry_run: run.dry_run?,
      run_id: run.id
    )
  end
end
