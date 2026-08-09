# frozen_string_literal: true

class ProjectMobileArtifactIndex
  Artifact = Data.define(
    :record,
    :kind,
    :filename,
    :app_identifier,
    :version_name,
    :version_code,
    :binary_uuid,
    :architecture,
    :status,
    :status_label,
    :byte_size,
    :checksum,
    :uploaded_at,
    :uploader
  )
  Result = Data.define(:artifacts, :total_artifacts, :has_more, :status_counts, :observed_builds)
  PAGE_SIZE = 25

  attr_reader :project, :page

  def initialize(project, page: 1)
    raise ArgumentError, "Artifacts are available only for Android and iOS projects" unless project.integration_android? || project.integration_ios?

    @project = project
    @page = [ Integer(page), 1 ].max
  end

  def call
    relation = artifact_relation
    total = relation.count
    records = relation.limit(PAGE_SIZE + 1).offset((page - 1) * PAGE_SIZE).to_a
    visible = records.first(PAGE_SIZE)
    items = visible.map { |record| artifact_from(record) }.freeze
    counts = if project.integration_android?
      { verified: total }
    else
      relation.reorder(nil).group(:status).count.transform_keys(&:to_sym)
    end.freeze
    releases = ProjectMobileReleaseIndex.new(project, limit: ProjectMobileReleaseIndex::MAX_LIMIT).call.releases

    Result.new(
      artifacts: items,
      total_artifacts: total,
      has_more: records.size > PAGE_SIZE,
      status_counts: counts,
      observed_builds: releases
    ).freeze
  end

  private

  def artifact_relation
    if project.integration_android?
      project.android_mapping_files.recent_first.includes(:uploaded_by)
    else
      project.apple_symbol_artifacts.recent_first.includes(:uploaded_by)
    end
  end

  def artifact_from(record)
    if project.integration_android?
      Artifact.new(
        record:,
        kind: :r8_mapping,
        filename: record.filename,
        app_identifier: record.package_name,
        version_name: record.version_name,
        version_code: record.version_code,
        binary_uuid: nil,
        architecture: nil,
        status: :verified,
        status_label: "Mapping validated",
        byte_size: record.byte_size,
        checksum: record.checksum_sha256,
        uploaded_at: record.created_at,
        uploader: uploader_label(record)
      ).freeze
    else
      Artifact.new(
        record:,
        kind: :dsym,
        filename: record.filename,
        app_identifier: record.app_identifier,
        version_name: record.version_name,
        version_code: record.version_code,
        binary_uuid: record.binary_uuid,
        architecture: record.architecture,
        status: record.status.to_sym,
        status_label: record.verification_label,
        byte_size: record.byte_size,
        checksum: record.checksum_sha256,
        uploaded_at: record.created_at,
        uploader: uploader_label(record)
      ).freeze
    end
  end

  def artifact_status(record)
    project.integration_android? ? :verified : record.status.to_sym
  end

  def uploader_label(record)
    record.uploaded_by&.name.presence || record.uploaded_by&.email || "System / CI"
  end
end
