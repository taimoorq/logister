# frozen_string_literal: true

class AppleSymbolCoverage
  LOOKUP_ARTIFACTS = Object.new.freeze

  Requirement = Data.define(:image, :binary_uuid, :architecture)
  Result = Data.define(:status, :requirements, :matched_artifacts, :missing_requirements, :enrichment) do
    def label
      {
        symbols_included: "Symbols included",
        symbolicated: "Frames symbolicated",
        partial: "Partially symbolicated",
        failed: "Symbolication failed",
        artifact_matched: "Verified dSYM matched",
        partial_coverage: "Partial dSYM coverage",
        verification_pending: "dSYM verification pending",
        verification_failed: "dSYM verification failed",
        missing: "dSYM missing",
        build_unknown: "Build identity missing",
        not_applicable: "Symbols not applicable"
      }.fetch(status)
    end

    def artifact_matched?
      status == :artifact_matched
    end
  end

  class << self
    def call(project:, event:, presenter: ProjectEvents::IosEventPresenter.new(event), artifacts: LOOKUP_ARTIFACTS, enrichment: nil)
      new(project:, presenter:, artifacts:, enrichment:).call
    end
  end

  attr_reader :project, :presenter, :artifacts, :enrichment

  def initialize(project:, presenter:, artifacts: LOOKUP_ARTIFACTS, enrichment: nil)
    @project = project
    @presenter = presenter
    @artifacts = artifacts
    @enrichment = enrichment
  end

  def call
    return result(:not_applicable) unless project.integration_ios?

    requirements = address_only_requirements
    return result(:symbols_included) if requirements.empty?

    app = presenter.app_details
    return result(:build_unknown, requirements:) if app[:bundle_identifier].blank? || app[:version_code].blank?
    return result(:missing, requirements:, missing_requirements: requirements) if requirements.any? { |requirement| requirement.binary_uuid.blank? || requirement.architecture.blank? }

    build_artifacts = if artifacts.equal?(LOOKUP_ARTIFACTS)
      project.apple_symbol_artifacts.where(
        app_identifier: app[:bundle_identifier],
        version_code: app[:version_code].to_s
      ).to_a
    else
      artifacts
    end
    derived_status = current_enrichment_status(build_artifacts)
    return result(derived_status, requirements:) if derived_status

    matched = requirements.filter_map do |requirement|
      build_artifacts.find do |artifact|
        artifact.verified? &&
          artifact.binary_uuid == normalize_uuid(requirement.binary_uuid) &&
          artifact.architecture == requirement.architecture.to_s.downcase
      end
    end.uniq
    missing = requirements.reject do |requirement|
      matched.any? do |artifact|
        artifact.binary_uuid == normalize_uuid(requirement.binary_uuid) &&
          artifact.architecture == requirement.architecture.to_s.downcase
      end
    end

    return result(:artifact_matched, requirements:, matched_artifacts: matched) if missing.empty?
    return result(:partial_coverage, requirements:, matched_artifacts: matched, missing_requirements: missing) if matched.any?

    candidates = matching_candidates(build_artifacts, requirements)
    if candidates.any? { |artifact| %w[uploaded processing awaiting_tooling].include?(artifact.status) }
      result(:verification_pending, requirements:, missing_requirements: missing)
    elsif candidates.any? { |artifact| artifact.status == "failed" }
      result(:verification_failed, requirements:, missing_requirements: missing)
    else
      result(:missing, requirements:, missing_requirements: missing)
    end
  end

  private

  def result(status, requirements: [], matched_artifacts: [], missing_requirements: [])
    Result.new(status:, requirements:, matched_artifacts:, missing_requirements:, enrichment:).freeze
  end

  def address_only_requirements
    images_by_uuid = presenter.binary_images.index_by { |image| normalize_uuid(image[:uuid]) }
    images_by_name = presenter.binary_images.index_by { |image| image[:name].to_s }
    fallback_architecture = presenter.device_details[:architecture]

    presenter.all_frames.filter_map do |frame|
      next unless frame[:application_frame]
      next unless frame[:address].present? || frame[:relative_address].present?
      next if callable_symbol?(frame[:method_name])

      image = images_by_uuid[normalize_uuid(frame[:image_uuid])] || images_by_name[frame[:image].to_s]
      Requirement.new(
        image: frame[:image],
        binary_uuid: normalize_uuid(frame[:image_uuid] || image&.dig(:uuid)),
        architecture: (image&.dig(:architecture) || fallback_architecture).to_s.downcase.presence
      )
    end.uniq
  end

  def callable_symbol?(value)
    symbol = value.to_s.strip
    symbol.present? && !symbol.match?(/\A(?:0x[0-9a-f]+|\+?\s*\d+)\z/i)
  end

  def matching_candidates(artifacts, requirements)
    artifacts.select do |artifact|
      requirements.any? do |requirement|
        artifact.binary_uuid == normalize_uuid(requirement.binary_uuid) &&
          artifact.architecture == requirement.architecture.to_s.downcase
      end
    end
  end

  def normalize_uuid(value)
    value.to_s.delete("{}").upcase.presence
  end

  def current_enrichment_status(build_artifacts)
    return unless enrichment&.kind == "apple_symbolication"

    references = Array(enrichment.data&.dig("artifacts"))
    current = references.all? do |reference|
      build_artifacts.any? do |artifact|
        artifact.verified? && artifact.uuid == reference["uuid"] &&
          artifact.checksum_sha256 == reference["checksum_sha256"]
      end
    end
    return unless current

    case enrichment.status
    when "complete"
      "symbolicated" if enrichment.data.to_h["resolved_frame_count"].to_i.positive?
    when "partial" then :partial
    when "failed" then :failed
    end&.to_sym
  end
end
