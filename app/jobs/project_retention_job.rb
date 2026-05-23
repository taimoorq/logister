class ProjectRetentionJob < ApplicationJob
  queue_as :default

  discard_on ActiveRecord::RecordNotFound

  def perform(project_id, dry_run: false)
    project = Project.find(project_id)
    result = Logister::ProjectRetentionRunner.new(project: project, dry_run: dry_run).call

    Rails.logger.info(
      "project_retention.complete project_id=#{project.id} project_uuid=#{project.uuid} " \
      "dry_run=#{dry_run} deleted=#{result.fetch(:deleted).inspect}"
    )
  end
end
