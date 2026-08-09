# frozen_string_literal: true

require "digest"
require "openssl"

module AppleSymbols
  class ArtifactUploader
    Error = Class.new(StandardError)
    ZIP_MAGIC = "PK\x03\x04".b

    def initialize(project:, uploaded_by:, attributes:, upload:, storage_service: nil)
      @project = project
      @uploaded_by = uploaded_by
      @attributes = attributes.to_h.symbolize_keys
      @upload = upload
      @storage_service = storage_service || InstanceConfiguration::ArchiveService.build
    end

    def call
      validate_upload!
      checksums = checksums_for(upload)
      artifact = nil
      Project.transaction(requires_new: true) do
        locked_project = Project.lock.find_by(id: project.id)
        if locked_project.nil? || locked_project.purge_pending?
          raise Error, "Project purge is pending; symbol uploads are disabled"
        end

        artifact = locked_project.apple_symbol_artifacts.new(
          attributes.slice(:app_identifier, :version_name, :version_code, :release, :binary_uuid, :architecture).merge(
            uploaded_by: uploaded_by,
            checksum_sha256: checksums.fetch(:sha256),
            byte_size: upload.size,
            filename: upload.original_filename.to_s,
            content_type: upload.content_type.to_s,
            storage_key: storage_key,
            status: "uploaded",
            metadata: {
              "storage_locator" => InstanceConfiguration::ArchiveService.locator_for(storage_service)
            }
          )
        )
        artifact.save!
        upload_private_object!(artifact.storage_key, checksums.fetch(:md5))
        artifact.update!(
          metadata: artifact.metadata.merge(
            "object_version_id" => InstanceConfiguration::ArchiveService.object_version_id(
              storage_service,
              artifact.storage_key
            )
          )
        )
      end
      AppleSymbolArtifactProcessingJob.perform_later(artifact.id)
      artifact
    rescue StandardError
      artifact&.destroy if artifact&.persisted?
      raise
    ensure
      upload.rewind if upload.respond_to?(:rewind)
    end

    private

    attr_reader :project, :uploaded_by, :attributes, :upload, :storage_service

    def validate_upload!
      raise Error, "Choose a zipped dSYM archive" if upload.blank?
      raise Error, "dSYM archive is empty" unless upload.size.to_i.positive?
      raise Error, "dSYM archive exceeds #{AppleSymbolArtifact::MAX_BYTES / 1.megabyte} MB" if upload.size.to_i > AppleSymbolArtifact::MAX_BYTES
      raise Error, "dSYM upload must be a .zip archive" unless File.extname(upload.original_filename.to_s).downcase == ".zip"

      signature = upload.read(4)
      upload.rewind
      raise Error, "dSYM upload does not contain a ZIP archive" unless signature == ZIP_MAGIC
    end

    def checksums_for(io)
      sha256 = Digest::SHA256.new
      # S3's Content-MD5 transport-integrity header requires this legacy digest;
      # the SHA-256 digest below remains the artifact's security checksum.
      content_digest = OpenSSL::Digest.new("md5")
      while (chunk = io.read(1.megabyte))
        sha256.update(chunk)
        content_digest.update(chunk)
      end
      io.rewind
      { sha256: sha256.hexdigest, md5: content_digest.base64digest }
    end

    def storage_key
      @storage_key ||= [
        InstanceConfiguration.value("archive_storage.prefix").presence || "telemetry",
        "apple-symbols",
        "project=#{project.uuid}",
        "#{SecureRandom.uuid}.zip"
      ].join("/")
    end

    def upload_private_object!(key, checksum)
      storage_service.upload(key, upload, checksum: checksum, content_type: "application/zip")
    rescue StandardError => error
      raise Error, "Private dSYM upload failed: #{error.class}: #{error.message}"
    end
  end
end
