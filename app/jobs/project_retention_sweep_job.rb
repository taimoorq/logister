class ProjectRetentionSweepJob < ApplicationJob
  queue_as :default

  def perform(dry_run: false)
    Project.find_each do |project|
      ProjectRetentionJob.perform_later(project.id, dry_run: dry_run)
    end
  end
end
