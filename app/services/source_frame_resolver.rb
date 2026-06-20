# frozen_string_literal: true

class SourceFrameResolver
  DEFAULT_RADIUS = 4
  SHA_PATTERN = /\A[0-9a-f]{7,40}\z/i
  BRANCH_CONTEXT_PATHS = [
    [ "branch" ],
    [ "git", "branch" ],
    [ "github", "branch" ],
    [ "deployment", "branch" ],
    [ "ref" ],
    [ "github", "ref" ]
  ].freeze
  Result = Data.define(:excerpt, :diagnostics)

  def self.call(project:, event:, frame:, radius: DEFAULT_RADIUS, fetcher: Github::ContentsClient.new, codeowners_resolver: nil)
    resolve(
      project: project,
      event: event,
      frame: frame,
      radius: radius,
      fetcher: fetcher,
      codeowners_resolver: codeowners_resolver
    ).excerpt
  end

  def self.resolve(project:, event:, frame:, radius: DEFAULT_RADIUS, fetcher: Github::ContentsClient.new, codeowners_resolver: nil)
    new(
      project: project,
      event: event,
      frame: frame,
      radius: radius,
      fetcher: fetcher,
      codeowners_resolver: codeowners_resolver
    ).resolve
  end

  def initialize(project:, event:, frame:, radius:, fetcher:, codeowners_resolver: nil)
    @project = project
    @event = event
    @frame = frame
    @radius = radius
    @fetcher = fetcher
    @codeowners_resolver = codeowners_resolver
  end

  def call
    resolve.excerpt
  end

  def resolve
    return unresolved(:invalid_frame, "Selected frame does not include a resolvable file and line.") unless frame.is_a?(Hash)
    return unresolved(:invalid_frame, "Selected frame does not include a resolvable file and line.") if line_number <= 0 || frame_path.blank?

    repositories = candidate_repositories
    return unresolved(*repository_status) if repositories.empty?

    attempts = []
    repositories.each do |repository|
      source_path = source_path_for(repository)
      attempts << { repository: repository.full_name, reason: "frame_path_not_under_runtime_root" } if source_path.blank?
      next if source_path.blank?

      refs_for(repository).each do |ref|
        fetched = fetch_source(repository, source_path, ref)
        attempts << { repository: repository.full_name, path: source_path, ref: ref, reason: "not_found" } if fetched.blank?
        next if fetched.blank?

        return resolved(
          repository: repository,
          source_path: source_path,
          ref: ref,
          source: fetched.content,
          html_url: fetched.html_url
        )
      end
    end

    unresolved(
      :not_found,
      "GitHub source file was not found for the configured repository mappings and refs.",
      attempts: attempts
    )
  end

  private

  attr_reader :project, :event, :frame, :radius, :fetcher, :codeowners_resolver

  def candidate_repositories
    repositories = project.source_repositories.github.enabled
                          .includes(:github_installation, github_repository: :github_installation)
                          .select(&:configured?)
    hinted = repository_hint
    return repositories if hinted.blank?

    repositories.sort_by { |repository| repository.full_name.casecmp?(hinted) ? 0 : 1 }
  end

  def repository_status
    repositories = project.source_repositories.github.enabled
    return [ :no_repositories, "No GitHub source repository mapping is enabled for this project." ] if repositories.none?

    [ :not_configured, "GitHub source repository mappings are waiting for App access or synced repository metadata." ]
  end

  def fetch_source(repository, source_path, ref)
    Rails.cache.fetch([ "github_source_file", repository.id, ref, source_path ], expires_in: 15.minutes) do
      fetcher.fetch(
        owner: repository.owner_name,
        repo: repository.repo_name,
        path: source_path,
        ref: ref,
        installation: repository.effective_github_installation,
        repository_id: repository.github_repository&.external_id || repository.external_id
      )
    end
  rescue Github::InstallationToken::NotConfigured, Github::ContentsClient::NotConfigured
    nil
  rescue StandardError => error
    Rails.logger.info("github source resolution failed: #{error.class} #{error.message}")
    nil
  end

  def resolved(repository:, source_path:, ref:, source:, html_url:)
    Result.new(
      excerpt: excerpt_for(
        repository: repository,
        source_path: source_path,
        ref: ref,
        source: source,
        html_url: html_url
      ),
      diagnostics: {
        status: :resolved,
        repository: repository.full_name,
        source_path: source_path,
        ref: ref
      }
    )
  end

  def unresolved(status, message, **details)
    Result.new(
      excerpt: nil,
      diagnostics: {
        status: status,
        message: message
      }.merge(details)
    )
  end

  def excerpt_for(repository:, source_path:, ref:, source:, html_url:)
    lines = source.to_s.lines(chomp: true)
    return nil if lines.empty?

    start_line = [ line_number - radius, 1 ].max
    end_line = [ line_number + radius, lines.length ].min

    {
      path: "#{repository.full_name}:#{source_path}",
      highlight_line: line_number,
      lines: (start_line..end_line).map { |n| { number: n, code: lines[n - 1].to_s } },
      provider: "github",
      repository: repository.full_name,
      ref: ref,
      source_url: github_line_url(html_url, line_number),
      codeowners: codeowners_for(repository, source_path, ref)
    }
  end

  def codeowners_for(repository, source_path, ref)
    resolver = codeowners_resolver || Github::CodeownersResolver.new(fetcher: fetcher)
    resolver.call(project: project, repository: repository, source_path: source_path, ref: ref)
  end

  def github_line_url(html_url, line)
    return nil if html_url.blank?

    "#{html_url}#L#{line}"
  end

  def refs_for(repository)
    [
      commit_sha_hint,
      indexed_deployment_commit_sha(repository),
      branch_hint,
      release_hint,
      repository.default_branch,
      "main"
    ].compact_blank.uniq
  end

  def source_path_for(repository)
    path = strip_runtime_root(normalized_frame_path, repository.runtime_root)
    return nil if path.blank?

    path = path.delete_prefix("/")
    path = join_source_root(repository.source_root, path)
    return nil unless safe_relative_path?(path)

    path
  end

  def strip_runtime_root(path, runtime_root)
    return path if runtime_root.blank?

    root = runtime_root.to_s.tr("\\", "/").delete_suffix("/")
    return path.delete_prefix(root).delete_prefix("/") if path == root || path.start_with?("#{root}/")

    root_without_slash = root.delete_prefix("/")
    marker = "/#{root_without_slash}/"
    return path.split(marker, 2).last if root_without_slash.present? && path.include?(marker)

    nil
  end

  def join_source_root(source_root, path)
    return path if source_root.blank?

    [ source_root, path ].join("/").squeeze("/")
  end

  def normalized_frame_path
    @normalized_frame_path ||= begin
      path = frame_path.to_s.tr("\\", "/")
      path = path.sub(/\Awebpack:\/+/, "")
      path = path.sub(/\Afile:\/+/, "/")
      path = path.split("?").first.to_s
      path.delete_prefix("./")
    end
  end

  def safe_relative_path?(path)
    path.present? && !path.start_with?("/") && !path.split("/").include?("..")
  end

  def frame_path
    frame[:file].presence || frame["file"].presence
  end

  def line_number
    @line_number ||= (frame[:line_number] || frame["line_number"]).to_i
  end

  def commit_sha_hint
    first_context_value(
      [ "commit_sha" ],
      [ "commitSha" ],
      [ "git_sha" ],
      [ "gitSha" ],
      [ "sha" ],
      [ "git", "sha" ],
      [ "git", "commit_sha" ],
      [ "github", "sha" ],
      [ "github", "commit_sha" ],
      [ "deployment", "commit_sha" ]
    ).to_s.presence&.then { |value| value.match?(SHA_PATTERN) ? value : nil }
  end

  def release_hint
    event ? IngestEvent.release(event) : nil
  end

  def branch_hint
    normalize_ref_hint(first_context_value(*BRANCH_CONTEXT_PATHS))
  end

  def indexed_deployment_commit_sha(repository)
    ProjectDeployment.resolve_commit(
      project: project,
      repository: repository,
      release: release_hint,
      environment: event_environment
    )
  end

  def event_environment
    event ? IngestEvent.environment(event) : nil
  end

  def repository_hint
    first_context_value(
      [ "repository" ],
      [ "repo" ],
      [ "github_repository" ],
      [ "githubRepository" ],
      [ "github", "repository" ],
      [ "github", "repo" ],
      [ "git", "repository" ],
      [ "deployment", "repository" ]
    ).to_s.strip.presence
  end

  def normalize_ref_hint(value)
    ref = value.to_s.strip
    ref = ref.delete_prefix("refs/heads/")
    ref = ref.delete_prefix("origin/")
    ref.presence
  end

  def first_context_value(*paths)
    paths.each do |path|
      value = dig_context(context_hash, path)
      return value if value.present?
    end

    nil
  end

  def context_hash
    @context_hash ||= event&.context.is_a?(Hash) ? event.context : {}
  end

  def dig_context(hash, path)
    current = hash
    path.each do |segment|
      return nil unless current.is_a?(Hash)

      current = current[segment] || current[segment.to_sym]
    end
    current
  end
end
