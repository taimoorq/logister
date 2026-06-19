# frozen_string_literal: true

require "pathname"
require "socket"
require "uri"

module Logister
  class SourceContext
    SHA_PATTERN = /\A[0-9a-f]{7,40}\z/i
    REPOSITORY_PATTERN = %r{\A[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\z}

    class << self
      def current(root: default_root, env: ENV)
        new(root: root, env: env)
      end

      def enrich_payload(payload, source_context: current)
        return payload unless payload.is_a?(Hash)

        payload[:context] = deep_merge_without_overwrite(
          payload[:context].is_a?(Hash) ? payload[:context] : {},
          source_context.event_context
        )
        payload
      end

      private

      def default_root
        defined?(Rails) ? Rails.root : Pathname.new(Dir.pwd)
      end

      def deep_merge_without_overwrite(existing, additions)
        additions.each_with_object(existing.dup) do |(key, value), merged|
          next if blank_value?(value)

          existing_key = matching_key(merged, key)
          if existing_key && merged[existing_key].is_a?(Hash) && value.is_a?(Hash)
            merged[existing_key] = deep_merge_without_overwrite(merged[existing_key], value)
          elsif existing_key.nil?
            merged[key] = value
          end
        end
      end

      def matching_key(hash, key)
        return key if hash.key?(key)

        string_key = key.to_s
        symbol_key = key.to_sym
        return string_key if hash.key?(string_key)
        return symbol_key if hash.key?(symbol_key)

        nil
      end

      def blank_value?(value)
        value.nil? || (value.respond_to?(:empty?) && value.empty?)
      end
    end

    def initialize(root:, env:)
      @root = Pathname.new(root.to_s)
      @env = env
    end

    def environment
      env_value("LOGISTER_ENVIRONMENT", "RAILS_ENV", "RACK_ENV") || (defined?(Rails) ? Rails.env.to_s : nil)
    end

    def service
      env_value("LOGISTER_SERVICE") || rails_service_name || "logister"
    end

    def release
      env_value(
        "LOGISTER_RELEASE",
        "FLY_RELEASE_VERSION",
        "HEROKU_RELEASE_VERSION",
        "RENDER_SERVICE_VERSION",
        "SOURCE_VERSION"
      ) || commit_sha&.then { |sha| "logister@#{sha[0, 7]}" }
    end

    def repository
      @repository ||= normalize_repository(
        env_value("LOGISTER_REPOSITORY", "GITHUB_REPOSITORY") || origin_repository
      )
    end

    def commit_sha
      @commit_sha ||= normalize_sha(
        env_value(
          "LOGISTER_COMMIT_SHA",
          "GITHUB_SHA",
          "SOURCE_VERSION",
          "HEROKU_SLUG_COMMIT",
          "RENDER_GIT_COMMIT",
          "VERCEL_GIT_COMMIT_SHA",
          "CF_PAGES_COMMIT_SHA",
          "COMMIT_SHA",
          "REVISION"
        ) || git_head_sha
      )
    end

    def branch
      @branch ||= env_value(
        "LOGISTER_BRANCH",
        "GITHUB_HEAD_REF",
        "GITHUB_REF_NAME",
        "BRANCH",
        "HEROKU_BRANCH",
        "RENDER_GIT_BRANCH",
        "VERCEL_GIT_COMMIT_REF",
        "CF_PAGES_BRANCH"
      ) || git_head_branch
    end

    def event_context
      compact(
        environment: environment,
        service: service,
        release: release,
        repository: repository,
        commit_sha: commit_sha,
        branch: branch,
        deployment: deployment_context,
        git: git_context,
        github: github_context
      )
    end

    def deployment_payload
      compact(
        release: release,
        environment: environment,
        repository: repository,
        commit_sha: commit_sha,
        branch: branch,
        deployed_at: deployed_at,
        workflow_run_url: workflow_run_url,
        compare_url: commit_url,
        release_tag: release_tag,
        release_url: release_url
      )
    end

    def deployment_context
      compact(
        environment: environment,
        service: service,
        release: release,
        repository: repository,
        commit_sha: commit_sha,
        branch: branch,
        region: env_value("FLY_REGION", "RAILS_REGION", "AWS_REGION", "REGION"),
        hostname: Socket.gethostname.to_s.presence,
        processPid: Process.pid,
        workflowRunUrl: workflow_run_url,
        commitUrl: commit_url
      )
    end

    def git_context
      compact(
        repository: repository,
        commit_sha: commit_sha,
        sha: commit_sha,
        branch: branch
      )
    end

    def github_context
      compact(
        repository: repository,
        commit_sha: commit_sha,
        sha: commit_sha,
        branch: branch,
        workflow_run_url: workflow_run_url,
        commit_url: commit_url
      )
    end

    private

    attr_reader :root, :env

    def rails_service_name
      return unless defined?(Rails)

      Rails.application.class.module_parent_name.underscore
    rescue StandardError
      nil
    end

    def deployed_at
      env_value("LOGISTER_DEPLOYED_AT", "FLY_RELEASE_CREATED_AT", "RENDER_DEPLOY_CREATED_AT")
    end

    def release_tag
      return branch if env_value("GITHUB_REF_TYPE") == "tag"

      nil
    end

    def release_url
      tag = release_tag
      return if repository.blank? || tag.blank?

      "#{github_web_url}/#{repository}/releases/tag/#{tag}"
    end

    def workflow_run_url
      return env_value("LOGISTER_WORKFLOW_RUN_URL") if env_value("LOGISTER_WORKFLOW_RUN_URL")
      return if repository.blank?

      run_id = env_value("GITHUB_RUN_ID")
      return if run_id.blank?

      "#{github_web_url}/#{repository}/actions/runs/#{run_id}"
    end

    def commit_url
      return env_value("LOGISTER_COMMIT_URL") if env_value("LOGISTER_COMMIT_URL")
      return if repository.blank? || commit_sha.blank?

      "#{github_web_url}/#{repository}/commit/#{commit_sha}"
    end

    def github_web_url
      env_value("LOGISTER_GITHUB_WEB_URL", "GITHUB_SERVER_URL") || "https://github.com"
    end

    def env_value(*names)
      names.each do |name|
        value = env[name].to_s.strip
        return value if value.present?
      end

      nil
    end

    def normalize_repository(value)
      candidate = value.to_s.strip.delete_suffix(".git")
      return candidate if candidate.match?(REPOSITORY_PATTERN)

      nil
    end

    def normalize_sha(value)
      candidate = value.to_s.strip
      return candidate if candidate.match?(SHA_PATTERN)

      nil
    end

    def origin_repository
      config = git_file("config")
      return unless config&.file?

      section = config.read.match(/\[remote "origin"\](.*?)(?=^\[|\z)/m)&.[](1)
      url = section&.match(/^\s*url\s*=\s*(.+)$/)&.[](1)
      repository_from_remote_url(url)
    rescue StandardError
      nil
    end

    def repository_from_remote_url(url)
      value = url.to_s.strip.delete_suffix(".git")
      path = if value.include?("://")
        URI.parse(value).path
      elsif value.include?(":")
        value.split(":", 2).last
      else
        value
      end

      path.to_s.delete_prefix("/").split("/").last(2).join("/")
    rescue StandardError
      nil
    end

    def git_head_sha
      head = git_head
      return normalize_sha(head) unless head.to_s.start_with?("ref:")

      ref = head.delete_prefix("ref:").strip
      ref_file_value(ref) || packed_ref_value(ref)
    end

    def git_head_branch
      head = git_head
      return unless head.to_s.start_with?("ref:")

      head.delete_prefix("ref:").strip.delete_prefix("refs/heads/")
    end

    def git_head
      head_file = git_file("HEAD")
      return unless head_file&.file?

      head_file.read.strip
    rescue StandardError
      nil
    end

    def ref_file_value(ref)
      ref_file = git_file(ref)
      return unless ref_file&.file?

      normalize_sha(ref_file.read.strip)
    rescue StandardError
      nil
    end

    def packed_ref_value(ref)
      packed_refs = git_file("packed-refs")
      return unless packed_refs&.file?

      packed_refs.each_line do |line|
        next if line.start_with?("#", "^")

        sha, packed_ref = line.strip.split(/\s+/, 2)
        return normalize_sha(sha) if packed_ref == ref
      end

      nil
    rescue StandardError
      nil
    end

    def git_file(path)
      git_dir&.join(path)
    end

    def git_dir
      @git_dir ||= begin
        dot_git = root.join(".git")
        if dot_git.directory?
          dot_git
        elsif dot_git.file?
          raw = dot_git.read.strip
          relative_git_dir = raw.delete_prefix("gitdir:").strip if raw.start_with?("gitdir:")
          relative_git_dir.present? ? root.join(relative_git_dir).cleanpath : nil
        end
      end
    rescue StandardError
      nil
    end

    def compact(hash)
      hash.each_with_object({}) do |(key, value), result|
        next if value.nil?
        next if value.respond_to?(:empty?) && value.empty?

        result[key] = value
      end
    end
  end
end
