# frozen_string_literal: true

class AndroidMappingResolution
  LOOKUP_MAPPING = Object.new.freeze

  Result = Data.define(:status, :mapping_file, :frames, :cause_chain) do
    def mapped?
      status == :mapped
    end

    def label
      {
        mapped: "Frames deobfuscated",
        mapping_matched: "Mapping matched",
        missing: "Mapping missing",
        build_unknown: "Build not captured"
      }.fetch(status)
    end
  end

  class << self
    def call(project:, event:, presenter: ProjectEvents::AndroidEventPresenter.new(event), mapping_file: LOOKUP_MAPPING)
      app = presenter.app_details
      version_code = app[:version_code]
      return Result.new(status: :build_unknown, mapping_file: nil, frames: presenter.all_frames, cause_chain: presenter.cause_chain) if version_code.blank?

      mapping = if mapping_file.equal?(LOOKUP_MAPPING)
        project.android_mapping_files.find_by(
          package_name: app[:package_name],
          version_code: version_code.to_s
        )
      else
        mapping_file
      end
      return Result.new(status: :missing, mapping_file: nil, frames: presenter.all_frames, cause_chain: presenter.cause_chain) unless mapping

      mapper = AndroidStacktraceMapper.new(mapping)
      frames = mapper.map_frames(presenter.all_frames)
      cause_chain = presenter.cause_chain.map { |entry| entry.merge(frames: mapper.map_frames(entry[:frames])) }
      status = (frames + cause_chain.flat_map { |entry| entry[:frames] }).any? { |frame| frame[:deobfuscated] } ? :mapped : :mapping_matched

      Result.new(
        status: status,
        mapping_file: mapping,
        frames: frames,
        cause_chain: cause_chain
      )
    end
  end
end
