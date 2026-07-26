# frozen_string_literal: true

class AndroidStacktraceMapper
  ClassMapping = Data.define(:original_name, :methods)
  MethodMapping = Data.define(:original_name, :obfuscated_start, :obfuscated_end, :original_start, :original_end)

  attr_reader :mapping_file

  def initialize(mapping_file)
    @mapping_file = mapping_file
  end

  def map_frames(frames)
    Array(frames).map { |frame| map_frame(frame) }
  end

  def map_frame(frame)
    mapping = classes[frame[:class_name].to_s]
    return frame unless mapping

    method = matching_method(mapping, frame[:method_name], frame[:line_number])
    mapped_line = original_line(method, frame[:line_number])
    extension = File.extname(frame[:file].to_s).presence || ".java"
    mapped_file = "#{mapping.original_name.split('.').last}#{extension}"

    frame.merge(
      obfuscated_class_name: frame[:class_name],
      obfuscated_method_name: frame[:method_name],
      obfuscated_line_number: frame[:line_number],
      class_name: mapping.original_name,
      method_name: method&.original_name || frame[:method_name],
      qualified_method: [ mapping.original_name, method&.original_name || frame[:method_name] ].compact_blank.join("."),
      file: mapped_file,
      line_number: mapped_line || frame[:line_number],
      deobfuscated: true
    )
  end

  private

  def classes
    @classes ||= parse_mapping
  end

  def parse_mapping
    result = {}
    current = nil

    mapping_file.content.to_s.each_line do |line|
      if (match = /\A(?<original>\S.+?) -> (?<obfuscated>\S+):\s*\z/.match(line))
        current = ClassMapping.new(original_name: match[:original], methods: Hash.new { |hash, key| hash[key] = [] })
        result[match[:obfuscated]] = current
      elsif current && (match = method_pattern.match(line))
        current.methods[match[:obfuscated]] << MethodMapping.new(
          original_name: match[:original],
          obfuscated_start: integer(match[:obfuscated_start]),
          obfuscated_end: integer(match[:obfuscated_end]),
          original_start: integer(match[:original_start]),
          original_end: integer(match[:original_end])
        )
      end
    end

    result
  end

  def method_pattern
    @method_pattern ||= /\A\s+(?:(?<obfuscated_start>\d+):(?<obfuscated_end>\d+):)?\S+\s+(?<original>[^.(]+)\([^)]*\)(?::(?<original_start>\d+)(?::(?<original_end>\d+))?)? -> (?<obfuscated>\S+)\s*\z/
  end

  def matching_method(mapping, name, line)
    candidates = mapping.methods[name.to_s]
    return if candidates.blank?

    candidates.find do |candidate|
      candidate.obfuscated_start.nil? || line.nil? || line.to_i.between?(candidate.obfuscated_start, candidate.obfuscated_end)
    end || candidates.first
  end

  def original_line(method, line)
    return unless method&.original_start
    return method.original_start unless method.obfuscated_start && line

    method.original_start + (line.to_i - method.obfuscated_start)
  end

  def integer(value)
    Integer(value, exception: false)
  end
end
