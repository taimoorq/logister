# frozen_string_literal: true

require "rails_helper"

RSpec.describe AppleSymbols::ArtifactUploader, type: :model do
  class PurgeSafeSymbolStorage
    attr_reader :uploads

    def initialize
      @uploads = []
    end

    def upload(key, io, checksum:, content_type:)
      @uploads << { key: key, body: io.read, checksum: checksum, content_type: content_type }
    end
  end

  it "does not upload a private symbol object after project purge is tombstoned" do
    project = create(:project, :ios, purge_requested_at: Time.current)
    storage = PurgeSafeSymbolStorage.new

    Tempfile.create([ "AcmeShop.dSYM", ".zip" ]) do |file|
      file.binmode
      file.write("PK\x03\x04private-symbol-fixture")
      file.flush
      upload = Rack::Test::UploadedFile.new(
        file.path,
        "application/zip",
        true,
        original_filename: "AcmeShop.dSYM.zip"
      )

      expect {
        described_class.new(
          project: project,
          uploaded_by: project.user,
          attributes: {
            app_identifier: "com.acme.shop",
            version_name: "4.2.0",
            binary_uuid: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
            architecture: "arm64"
          },
          upload: upload,
          storage_service: storage
        ).call
      }.to raise_error(AppleSymbols::ArtifactUploader::Error, /purge is pending/)
    end

    expect(storage.uploads).to be_empty
    expect(project.apple_symbol_artifacts).to be_empty
  end
end
