# frozen_string_literal: true

class ProjectPurgeJob < ApplicationJob
  queue_as :maintenance

  discard_on ActiveRecord::RecordNotFound
  retry_on StandardError, wait: :polynomially_longer, attempts: 10

  def perform(project_purge_id)
    Logister::ProjectPurgeRunner.new(project_purge: ProjectPurge.find(project_purge_id)).call
  end
end
