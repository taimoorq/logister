# frozen_string_literal: true

class AndroidMappingResolution
  LOOKUP_MAPPING = Object.new.freeze
  LOOKUP_ENRICHMENT = Object.new.freeze

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
    def call(project:, event:, presenter: ProjectEvents::AndroidEventPresenter.new(event), mapping_file: LOOKUP_MAPPING, enrichment: LOOKUP_ENRICHMENT)
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

      stored = if enrichment.equal?(LOOKUP_ENRICHMENT)
        project.mobile_event_enrichments.android_mapping.find_by(event_uuid: event.uuid)
      else
        enrichment
      end
      if stored && stored.artifact_checksum_sha256 == mapping.checksum_sha256 && stored.status.in?(%w[complete artifact_matched])
        return result_from_enrichment(stored, mapping, presenter)
      end

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

    private

    def result_from_enrichment(enrichment, mapping, presenter)
      data = enrichment.data.to_h.deep_symbolize_keys
      derived_causes = Array(data[:cause_chain]).index_by { |entry| entry[:depth].to_i }
      cause_chain = presenter.cause_chain.map do |entry|
        derived = derived_causes[entry[:depth].to_i]
        derived ? entry.merge(frames: Array(derived[:frames])) : entry
      end
      frames = Array(data[:frames]).presence || cause_chain.flat_map { |entry| entry[:frames] }
      status = enrichment.status == "complete" ? :mapped : :mapping_matched

      Result.new(status: status, mapping_file: mapping, frames: frames, cause_chain: cause_chain)
    end
  end
end
