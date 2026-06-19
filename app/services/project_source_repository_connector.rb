# frozen_string_literal: true

class ProjectSourceRepositoryConnector
  ERROR_MESSAGE = "must come from an installation linked to this project"

  Result = Struct.new(:source_repository, :rejected, keyword_init: true) do
    def rejected?
      rejected
    end
  end

  def initialize(project:, attributes:, source_repository: nil)
    @project = project
    @attributes = attributes.to_h.symbolize_keys
    @source_repository = source_repository
  end

  def build
    if github_repository_id.blank?
      attributes[:github_repository_id] = nil if attributes.key?(:github_repository_id)
      return Result.new(source_repository: target_repository.tap { |repository| repository.assign_attributes(attributes) }, rejected: false)
    end

    return rejected_result unless github_repository

    attributes[:github_repository_id] = github_repository.id
    attributes[:github_installation_id] = github_repository.github_installation_id

    Result.new(source_repository: target_repository.tap { |repository| repository.assign_attributes(attributes) }, rejected: false)
  end

  private

  attr_reader :project, :attributes, :source_repository

  def github_repository_id
    attributes[:github_repository_id].presence
  end

  def github_repository
    @github_repository ||= GithubRepository.available_for_project(project).find_by(id: github_repository_id)
  end

  def target_repository
    source_repository || existing_manual_mapping || project.source_repositories.new
  end

  def existing_manual_mapping
    return unless github_repository

    project.source_repositories.github.find_by("LOWER(full_name) = ?", github_repository.full_name.downcase)
  end

  def rejected_result
    repository = source_repository || project.source_repositories.new(attributes.except(:github_repository_id, :github_installation_id))
    repository.errors.add(:github_repository, ERROR_MESSAGE)
    Result.new(source_repository: repository, rejected: true)
  end
end
