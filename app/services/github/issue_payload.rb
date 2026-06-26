# frozen_string_literal: true

module Github
  class IssuePayload
    Result = Data.define(:title, :body)
    INLINE_CODE_DELIMITER = "`"

    def self.call(project:, group:, event: nil, source_excerpt: nil, deployment_context: nil, logister_url: nil)
      new(
        project: project,
        group: group,
        event: event,
        source_excerpt: source_excerpt,
        deployment_context: deployment_context,
        logister_url: logister_url
      ).call
    end

    def initialize(project:, group:, event:, source_excerpt:, deployment_context:, logister_url:)
      @project = project
      @group = group
      @event = event
      @source_excerpt = source_excerpt
      @deployment_context = deployment_context
      @logister_url = logister_url
    end

    def call
      Result.new(title: title, body: body)
    end

    private

    attr_reader :project, :group, :event, :source_excerpt, :deployment_context, :logister_url

    def title
      "[#{project.name}] #{group.title.to_s.squish}".first(180)
    end

    def body
      [
        "## Logister error",
        "",
        "- Project: #{project.name}",
        "- Error: #{group.title}",
        "- Status: #{group.status}",
        "- Occurrences: #{group.occurrence_count}",
        "- Fingerprint: #{inline_code(group.fingerprint)}",
        release_line,
        deployment_line,
        source_line,
        logister_line,
        "",
        "## Notes",
        ""
      ].compact_blank.join("\n")
    end

    def release_line
      release = (event ? IngestEvent.release(event).presence : nil) || group.last_seen_release.presence || group.introduced_in_release.presence
      return if release.blank?

      "- Release: #{inline_code(release)}"
    end

    def deployment_line
      deployment = deployment_context&.deployment
      return if deployment.blank?

      parts = [
        inline_code(deployment.release),
        deployment.environment,
        deployment.repository_full_name,
        deployment.short_commit_sha
      ].compact_blank

      "- Deployment: #{parts.join(' · ')}"
    end

    def source_line
      source_url = source_excerpt.is_a?(Hash) ? source_excerpt[:source_url].presence || source_excerpt["source_url"].presence : nil
      return if source_url.blank?

      "- Source: #{source_url}"
    end

    def logister_line
      return if logister_url.blank?

      "- Logister: #{logister_url}"
    end

    def inline_code(value)
      escaped = value.to_s.gsub(INLINE_CODE_DELIMITER, "\\#{INLINE_CODE_DELIMITER}")
      INLINE_CODE_DELIMITER + escaped + INLINE_CODE_DELIMITER
    end
  end
end
