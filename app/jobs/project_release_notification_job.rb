class ProjectReleaseNotificationJob < ApplicationJob
  queue_as :notifications

  discard_on ActiveRecord::RecordNotFound

  def perform(project_deployment_id)
    deployment = ProjectDeployment.includes(:project).find(project_deployment_id)

    ProjectEmailNotificationDispatcher.call(
      project: deployment.project,
      kind: "release_summary",
      metadata: {
        "release" => deployment.release,
        "environment" => deployment.environment,
        "repository" => deployment.repository_full_name,
        "commit_sha" => deployment.short_commit_sha,
        "branch" => deployment.branch,
        "deployed_at" => deployment.deployed_at&.utc&.iso8601
      }.compact,
      subject_key: deployment.id
    )
  end
end
