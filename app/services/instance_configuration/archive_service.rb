# frozen_string_literal: true

require "active_storage/service/disk_service"
require "active_storage/service/s3_service"

module InstanceConfiguration
  module ArchiveService
    module_function

    def build
      return local_service unless InstanceConfiguration.value("archive_storage.service") == "s3"

      options = {
        bucket: InstanceConfiguration.value("archive_storage.bucket"),
        access_key_id: InstanceConfiguration.value("archive_storage.access_key_id"),
        secret_access_key: InstanceConfiguration.value("archive_storage.secret_access_key"),
        region: InstanceConfiguration.value("archive_storage.region"),
        force_path_style: InstanceConfiguration.value("archive_storage.force_path_style")
      }
      endpoint = InstanceConfiguration.value("archive_storage.endpoint")
      options[:endpoint] = endpoint if endpoint.present?
      ActiveStorage::Service::S3Service.new(**options)
    end

    def local_service
      ActiveStorage::Service::DiskService.new(root: Rails.root.join("storage"))
    end
  end
end
