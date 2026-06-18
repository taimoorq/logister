# frozen_string_literal: true

module Github
  class CodeownersFile
    Entry = Data.define(:pattern, :owners, :line_number)

    FNMATCH_FLAGS = File::FNM_PATHNAME | File::FNM_DOTMATCH

    def self.parse(content)
      new(content)
    end

    def initialize(content)
      @entries = parse_entries(content)
    end

    attr_reader :entries

    def match(path)
      normalized_path = normalize_path(path)
      return if normalized_path.blank?

      entries.reverse.find { |entry| pattern_matches?(entry.pattern, normalized_path) }
    end

    def owners_for(path)
      match(path)&.owners || []
    end

    private

    def parse_entries(content)
      content.to_s.lines.each_with_index.filter_map do |line, index|
        parse_line(line, line_number: index + 1)
      end
    end

    def parse_line(line, line_number:)
      stripped = line.to_s.strip
      return if stripped.blank? || stripped.start_with?("#")

      tokens = stripped.split(/\s+/)
      pattern = tokens.shift.to_s
      return if invalid_pattern?(pattern)

      owners = tokens.take_while { |token| !token.start_with?("#") }
      Entry.new(pattern: pattern, owners: owners, line_number: line_number)
    end

    def invalid_pattern?(pattern)
      pattern.blank? || pattern.start_with?("!") || pattern.include?("[") || pattern.include?("]")
    end

    def pattern_matches?(pattern, path)
      anchored = pattern.start_with?("/")
      normalized_pattern = normalize_pattern(pattern)
      return false if normalized_pattern.blank?

      if directory_pattern?(pattern)
        directory_pattern_matches?(normalized_pattern.delete_suffix("/"), path, anchored: anchored)
      elsif normalized_pattern.exclude?("/")
        File.fnmatch?(normalized_pattern, File.basename(path), File::FNM_DOTMATCH)
      else
        path_pattern_matches?(normalized_pattern, path, anchored: anchored)
      end
    end

    def directory_pattern?(pattern)
      pattern.end_with?("/")
    end

    def directory_pattern_matches?(pattern, path, anchored:)
      return path.start_with?("#{pattern}/") if anchored || pattern.include?("/")

      segments = path.split("/")
      segments[0...-1].include?(pattern)
    end

    def path_pattern_matches?(pattern, path, anchored:)
      candidates = [ pattern, "#{pattern}/**/*" ]
      candidates += [ "**/#{pattern}", "**/#{pattern}/**/*" ] unless anchored || pattern.start_with?("**/")

      candidates.any? { |candidate| File.fnmatch?(candidate, path, FNMATCH_FLAGS) }
    end

    def normalize_pattern(pattern)
      pattern.to_s.tr("\\", "/").delete_prefix("/")
    end

    def normalize_path(path)
      path.to_s.tr("\\", "/").delete_prefix("/")
    end
  end
end
