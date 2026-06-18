# frozen_string_literal: true

module Github
  class CodeownersResolver
    CODEOWNERS_PATHS = [ ".github/CODEOWNERS", "CODEOWNERS", "docs/CODEOWNERS" ].freeze

    Result = Data.define(:owners, :matched_users, :codeowners_path, :line_number) do
      def present?
        owners.present?
      end
    end

    def initialize(fetcher: ContentsClient.new)
      @fetcher = fetcher
    end

    def call(project:, repository:, source_path:, ref:)
      path, content = fetch_codeowners(repository, ref)
      return empty_result unless content

      entry = CodeownersFile.parse(content).match(source_path)
      return empty_result(codeowners_path: path) unless entry

      Result.new(
        owners: entry.owners,
        matched_users: matched_users(project, entry.owners),
        codeowners_path: path,
        line_number: entry.line_number
      )
    rescue Github::InstallationToken::NotConfigured, Github::ContentsClient::NotConfigured
      empty_result
    rescue StandardError => error
      Rails.logger.info("github codeowners resolution failed: #{error.class} #{error.message}")
      empty_result
    end

    private

    attr_reader :fetcher

    def fetch_codeowners(repository, ref)
      CODEOWNERS_PATHS.each do |path|
        fetched = Rails.cache.fetch([ "github_codeowners_file", repository.id, ref, path ], expires_in: 15.minutes) do
          fetcher.fetch(
            owner: repository.owner_name,
            repo: repository.repo_name,
            path: path,
            ref: ref,
            installation: repository.effective_github_installation,
            repository_id: repository.github_repository&.external_id || repository.external_id
          )
        end
        return [ path, fetched.content ] if fetched.present?
      end

      nil
    end

    def matched_users(project, owners)
      users_by_email = project.assignable_users.index_by { |user| user.email.to_s.downcase }

      owners.filter_map do |owner|
        next if owner.start_with?("@")

        users_by_email[owner.downcase]
      end.uniq
    end

    def empty_result(codeowners_path: nil)
      Result.new(owners: [], matched_users: [], codeowners_path: codeowners_path, line_number: nil)
    end
  end
end
