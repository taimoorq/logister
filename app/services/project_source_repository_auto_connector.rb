# frozen_string_literal: true

class ProjectSourceRepositoryAutoConnector
  Result = Struct.new(:source_repository, :reason, keyword_init: true) do
    def connected?
      source_repository.present?
    end
  end

  def self.call(project:, github_repositories:)
    new(project: project, github_repositories: github_repositories).call
  end

  def initialize(project:, github_repositories:)
    @project = project
    @github_repositories = Array(github_repositories).compact
  end

  def call
    return Result.new(reason: :missing_project) unless project
    return Result.new(reason: :no_repositories) if available_repositories.empty?

    existing_pair = existing_mapping_pair
    return connect(existing_pair.first, existing_pair.last, reason: :linked_existing_mapping) if existing_pair

    return Result.new(reason: :already_mapped) if project.source_repositories.github.exists?

    github_repository = inferred_github_repository
    return Result.new(reason: :no_match) unless github_repository

    connect(
      project.source_repositories.github.new,
      github_repository,
      reason: :created_mapping
    )
  end

  private

  attr_reader :project, :github_repositories

  def existing_mapping_pair
    mappings_by_full_name = project.source_repositories.github.enabled.index_by { |repository| repository.full_name.to_s.downcase }

    available_repositories.each do |github_repository|
      mapping = mappings_by_full_name[github_repository.full_name.to_s.downcase]
      next unless mapping
      next if mapping.configured? && mapping.github_repository == github_repository

      return [ mapping, github_repository ]
    end

    nil
  end

  def inferred_github_repository
    return available_repositories.first if available_repositories.one?

    matches = available_repositories.select do |repository|
      project_identifiers.include?(normalized_identifier(repository.repo_name))
    end

    matches.one? ? matches.first : nil
  end

  def connect(source_repository, github_repository, reason:)
    source_repository.assign_attributes(
      provider: ProjectSourceRepository::PROVIDERS[:github],
      github_repository: github_repository,
      github_installation: github_repository.github_installation,
      external_id: github_repository.external_id,
      full_name: github_repository.full_name
    )
    source_repository.enabled = true if source_repository.new_record?
    source_repository.default_branch ||= github_repository.default_branch
    source_repository.save!

    Result.new(source_repository: source_repository, reason: reason)
  end

  def available_repositories
    @available_repositories ||= github_repositories.select(&:available?).uniq { |repository| repository.id || repository.full_name }
  end

  def project_identifiers
    @project_identifiers ||= [ project.slug, project.name ].filter_map do |value|
      normalized_identifier(value).presence
    end.uniq
  end

  def normalized_identifier(value)
    value.to_s.downcase.gsub(/[^a-z0-9]/, "")
  end
end
