# frozen_string_literal: true

require "open3"

module AppleSymbols
  class Symbolicator
    ADAPTER_VERSION = "1"
    MAX_FRAMES = 500

    Result = Data.define(:status, :frames, :tool_name, :tool_version, :unresolved_count)

    def self.call(...)
      new(...).call
    end

    attr_reader :artifact, :frames

    def initialize(artifact:, frames:)
      @artifact = artifact
      @frames = Array(frames).first(MAX_FRAMES)
    end

    def call
      raise "Apple symbolication tooling is unavailable on this worker" unless tooling_available?

      resolved = AppleSymbols::ArchiveWorkspace.open(artifact:) do |directory|
        binary = matching_binary(directory)
        raise "Verified dSYM binary #{artifact.binary_uuid} (#{artifact.architecture}) was not found" unless binary

        frames.filter_map { |frame| resolve_frame(binary, frame) }
      end
      unresolved_count = frames.size - resolved.size
      status = if resolved.empty?
        :artifact_matched
      elsif unresolved_count.zero?
        :complete
      else
        :partial
      end
      Result.new(
        status:,
        frames: resolved,
        tool_name: "apple_atos",
        tool_version: tool_version,
        unresolved_count:
      )
    end

    private

    def tooling_available?
      %w[unzip dwarfdump atos].all? { |name| executable?(name) }
    end

    def executable?(name)
      ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? { |path| File.executable?(File.join(path, name)) }
    end

    def matching_binary(directory)
      candidates = Dir.glob(File.join(directory, "**", "*.dSYM", "Contents", "Resources", "DWARF", "*"))
        .select { |path| File.file?(path) }
      candidates.find do |path|
        output, status = Open3.capture2e("dwarfdump", "--uuid", path)
        status.success? && output.lines.any? do |line|
          match = /UUID: (?<uuid>[0-9A-F-]+) \((?<architecture>[^)]+)\)/i.match(line)
          match && match[:uuid].upcase == artifact.binary_uuid && match[:architecture].downcase == artifact.architecture
        end
      end
    end

    def resolve_frame(binary, frame)
      base = numeric_address(frame[:base_address] || frame["base_address"])
      return unless base

      absolute = numeric_address(frame[:address] || frame["address"])
      relative = numeric_address(frame[:relative_address] || frame["relative_address"])
      absolute ||= base + relative if relative
      return unless absolute

      address = format("0x%x", absolute)
      output, status = Open3.capture2e(
        "atos", "-o", binary, "-arch", artifact.architecture,
        "-l", format("0x%x", base), address
      )
      return unless status.success?

      parsed = parse_symbol(output.to_s.strip, address)
      return unless parsed

      {
        "image" => frame[:image] || frame["image"],
        "image_uuid" => normalize_uuid(frame[:image_uuid] || frame["image_uuid"]),
        "address" => frame[:address] || frame["address"],
        "relative_address" => frame[:relative_address] || frame["relative_address"],
        "base_address" => frame[:base_address] || frame["base_address"],
        "qualified_method" => parsed.fetch(:symbol),
        "symbol_identity" => parsed.fetch(:symbol),
        "method_name" => parsed.fetch(:symbol),
        "file" => parsed[:file],
        "line_number" => parsed[:line_number],
        "application_frame" => true,
        "symbolicated" => true
      }.compact
    end

    def parse_symbol(output, address)
      lines = output.lines.map(&:strip).reject(&:blank?)
      return unless lines.one?

      value = lines.sole
      return if value == address || value == "???"

      match = /\A(?<symbol>.+?) \(in [^)]+\)(?: \((?<file>.+):(?<line>\d+)\)| \+ \d+)?\z/.match(value)
      return unless match

      symbol = match[:symbol].to_s.strip
      return if symbol.blank? || symbol.match?(/\A(?:0x[0-9a-f]+|\?+)\z/i)

      {
        symbol:,
        file: match[:file].present? ? File.basename(match[:file]) : nil,
        line_number: match[:line].to_i.positive? ? match[:line].to_i : nil
      }.compact
    end

    def numeric_address(value)
      return value if value.is_a?(Integer) && value >= 0
      return unless value.to_s.match?(/\A(?:0x)?[0-9a-f]+\z/i)

      Integer(value.to_s, value.to_s.start_with?("0x", "0X") ? 0 : 16)
    rescue ArgumentError
      nil
    end

    def normalize_uuid(value)
      value.to_s.delete("{}").upcase.presence
    end

    def tool_version
      @tool_version ||= begin
        output, status = Open3.capture2e("xcodebuild", "-version")
        value = status.success? ? output.lines.map(&:strip).reject(&:blank?).join(" ") : nil
        "adapter-#{ADAPTER_VERSION}#{value.present? ? "; #{value.first(200)}" : ""}"
      rescue Errno::ENOENT
        "adapter-#{ADAPTER_VERSION}"
      end
    end
  end
end
