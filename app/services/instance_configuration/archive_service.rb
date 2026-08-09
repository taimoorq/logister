# frozen_string_literal: true

require "active_storage/service/disk_service"
require "active_storage/service/s3_service"
require "digest"

module InstanceConfiguration
  module ArchiveService
    module_function

    def build(locator: nil)
      locator = normalize_locator(locator.presence || current_locator)
      return local_service(root: locator.fetch("root")) if locator.fetch("service") == "local"

      options = {
        bucket: locator.fetch("bucket"),
        access_key_id: InstanceConfiguration.value("archive_storage.access_key_id"),
        secret_access_key: InstanceConfiguration.value("archive_storage.secret_access_key"),
        region: locator.fetch("region"),
        force_path_style: locator.fetch("force_path_style")
      }
      endpoint = locator["endpoint"]
      options[:endpoint] = endpoint if endpoint.present?
      ActiveStorage::Service::S3Service.new(**options)
    end

    def current_locator
      payload = if InstanceConfiguration.value("archive_storage.service") == "s3"
        {
          "service" => "s3",
          "bucket" => InstanceConfiguration.value("archive_storage.bucket").to_s,
          "region" => InstanceConfiguration.value("archive_storage.region").to_s,
          "endpoint" => InstanceConfiguration.value("archive_storage.endpoint").presence,
          "force_path_style" => InstanceConfiguration.value("archive_storage.force_path_style") == true
        }
      else
        { "service" => "local", "root" => Rails.root.join("storage").to_s }
      end
      with_generation_id(payload)
    end

    def locator_for(service)
      if service.is_a?(ActiveStorage::Service::S3Service)
        with_generation_id(
          "service" => "s3",
          "bucket" => service.bucket.name.to_s,
          "region" => InstanceConfiguration.value("archive_storage.region").to_s,
          "endpoint" => InstanceConfiguration.value("archive_storage.endpoint").presence,
          "force_path_style" => InstanceConfiguration.value("archive_storage.force_path_style") == true
        )
      elsif service.is_a?(ActiveStorage::Service::DiskService)
        current_locator
      else
        with_generation_id("service" => "injected", "adapter" => service.class.name)
      end
    end

    def object_version_id(service, key)
      return unless s3_service?(service)

      service.client.client.head_object(bucket: service.bucket.name, key: key).version_id.presence
    end

    # S3 DELETE without a version only writes a delete marker. A project purge
    # must remove every recorded-key version and verify that no noncurrent copy
    # remains. Unique archive keys make exact-key enumeration safe.
    def delete_all_versions!(service, key)
      unless s3_service?(service)
        service.delete(key)
        raise "Archive object still exists after deletion: #{key}" if service.exist?(key)

        return { versions_deleted: 0, verified_absent: true }
      end

      client = service.client.client
      bucket = service.bucket.name
      deleted = 0
      key_marker = nil
      version_marker = nil
      loop do
        arguments = {
          bucket: bucket,
          prefix: key
        }
        arguments[:key_marker] = key_marker if key_marker.present?
        arguments[:version_id_marker] = version_marker if version_marker.present?
        page = client.list_object_versions(**arguments).then do |response|
          (response.versions.to_a + response.delete_markers.to_a).select { |entry| entry.key == key }
            .tap do |entries|
              unless entries.empty?
                client.delete_objects(
                  bucket: bucket,
                  delete: { objects: entries.map { |entry| { key: key, version_id: entry.version_id } }, quiet: true }
                )
                deleted += entries.size
              end
            end
          response
        end
        break unless page.is_truncated

        key_marker = page.next_key_marker
        version_marker = page.next_version_id_marker
      end

      remaining = client.list_object_versions(bucket: bucket, prefix: key)
      still_present = (remaining.versions.to_a + remaining.delete_markers.to_a).any? { |entry| entry.key == key }
      raise "Archive object versions still exist after deletion: #{key}" if still_present

      { versions_deleted: deleted, verified_absent: true }
    end

    def local_service(root: Rails.root.join("storage").to_s)
      ActiveStorage::Service::DiskService.new(root: root)
    end

    def normalize_locator(locator)
      value = locator.to_h.stringify_keys
      recorded_generation = value["generation_id"].presence
      service = value.fetch("service")
      case service
      when "local"
        value.fetch("root")
      when "s3"
        value.fetch("bucket")
        value["region"] = value["region"].presence || "us-east-1"
        value["force_path_style"] = ActiveModel::Type::Boolean.new.cast(value["force_path_style"])
      else
        raise ArgumentError, "Unsupported archive storage locator service: #{service.inspect}"
      end
      normalized = with_generation_id(value.except("generation_id"))
      if recorded_generation && recorded_generation != normalized.fetch("generation_id")
        raise ArgumentError, "Archive storage locator generation checksum does not match its coordinates"
      end

      normalized
    end

    def with_generation_id(payload)
      canonical = payload.stringify_keys.sort.to_h
      canonical.merge("generation_id" => Digest::SHA256.hexdigest(canonical.to_json))
    end

    def s3_service?(service)
      service.is_a?(ActiveStorage::Service::S3Service)
    end
  end
end
