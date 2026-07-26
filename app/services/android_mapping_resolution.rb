# frozen_string_literal: true

class AndroidMappingResolution
  Result = Data.define(:status, :mapping_file, :frames, :cause_chain) do
    def mapped?
      status == :mapped
    end

    def label
      {
        mapped: "Deobfuscated",
        missing: "Mapping missing",
        build_unknown: "Build not captured"
      }.fetch(status)
    end
  end

  class << self
    def call(project:, event:, presenter: ProjectEvents::AndroidEventPresenter.new(event))
      app = presenter.app_details
      version_code = app[:version_code]
      return Result.new(status: :build_unknown, mapping_file: nil, frames: presenter.all_frames, cause_chain: presenter.cause_chain) if version_code.blank?

      mapping = project.android_mapping_files.find_by(
        package_name: app[:package_name],
        version_code: version_code.to_s
      )
      return Result.new(status: :missing, mapping_file: nil, frames: presenter.all_frames, cause_chain: presenter.cause_chain) unless mapping

      mapper = AndroidStacktraceMapper.new(mapping)

      Result.new(
        status: :mapped,
        mapping_file: mapping,
        frames: mapper.map_frames(presenter.all_frames),
        cause_chain: presenter.cause_chain.map { |entry| entry.merge(frames: mapper.map_frames(entry[:frames])) }
      )
    end
  end
end
