# frozen_string_literal: true

module ProjectEvents
  module PayloadSupport
    REQUEST_DETAIL_KEYS = {
      client_ip: [ [ "clientIp" ], [ "client_ip" ], [ "request", "clientIp" ], [ "request", "client_ip" ], [ "request", "ip" ], [ "request", "remote_ip" ] ],
      headers: [ [ "headers" ], [ "request", "headers" ] ],
      http_method: [ [ "httpMethod" ], [ "http_method" ], [ "method" ], [ "request", "httpMethod" ], [ "request", "http_method" ], [ "request", "method" ] ],
      http_version: [ [ "httpVersion" ], [ "http_version" ], [ "request", "httpVersion" ], [ "request", "http_version" ], [ "request", "version" ] ],
      params: [ [ "params" ], [ "request", "params" ] ],
      rails_action: [ [ "railsAction" ], [ "rails_action" ], [ "request", "railsAction" ], [ "request", "rails_action" ] ],
      referer: [ [ "referer" ], [ "referrer" ], [ "request", "referer" ], [ "request", "referrer" ] ],
      request_id: [ [ "requestId" ], [ "request_id" ], [ "request", "requestId" ], [ "request", "request_id" ], [ "request", "id" ] ],
      url: [ [ "url" ], [ "request", "url" ], [ "request", "original_url" ] ]
    }.freeze

    def parse_backtrace_frames(backtrace)
      Array(backtrace).filter_map do |line|
        parsed = if line.is_a?(Hash)
          parse_structured_backtrace_frame(line)
        else
          parse_backtrace_line(line.to_s)
        end
        next if parsed.blank?

        absolute_path = absolute_source_path(parsed[:file])
        app_frame = application_frame_path?(parsed[:file], absolute_path)

        {
          raw: line.to_s,
          file: parsed[:file],
          line_number: parsed[:line_number],
          column_number: parsed[:column_number],
          method_name: parsed[:method_name],
          code_context: parsed[:code_context],
          locals: parsed[:locals],
          absolute_path: absolute_path,
          application_frame: app_frame
        }
      end
    end

    def event_context_hash(event)
      raw = event.respond_to?(:context) ? event.context : event
      normalize_hash(raw)
    end

    def normalize_hash(value)
      value.is_a?(Hash) ? value : {}
    end

    def value_from_hash(hash, key)
      return nil unless hash.is_a?(Hash)

      hash[key].presence || hash[key.downcase].presence || hash[key.upcase].presence || hash[key.to_sym].presence
    end

    private

    def first_hash_value(context, key)
      REQUEST_DETAIL_KEYS.fetch(key).each do |path|
        value = dig_context(context, path)
        return value if value.is_a?(Hash)
      end

      {}
    end

    def first_scalar_value(context, key)
      REQUEST_DETAIL_KEYS.fetch(key).each do |path|
        value = dig_context(context, path)
        return value.to_s if scalarish?(value) && value.to_s.present?
      end

      nil
    end

    def dig_context(hash, path)
      current = hash
      path.each do |segment|
        return nil unless current.is_a?(Hash)

        current = current[segment] || current[segment.to_sym]
      end

      current
    end

    def scalarish?(value)
      value.is_a?(String) || value.is_a?(Numeric) || value == true || value == false
    end

    def parse_backtrace_line(line)
      patterns = [
        /\Aat (?:(?<method>.+?) )?\((?<file>.+?):(?<line>\d+):(?<column>\d+)\)\z/,
        /\Aat (?<file>.+?):(?<line>\d+):(?<column>\d+)\z/,
        /\A(?<method>[^@]+)@(?<file>.+?):(?<line>\d+):(?<column>\d+)\z/,
        /\A\s*File "(?<file>.+?)", line (?<line>\d+)(?:, in (?<method>.+))?\z/,
        /\A\s*at (?<method>.+?) in (?<file>.+?):line (?<line>\d+)\z/,
        /\A(?<file>.+?):(?<line>\d+)(?::in `(?<method>[^']+)')?\z/,
        /\A(?<file>.+?):(?<line>\d+)(?::in (?<method>.+))?\z/
      ]

      match = patterns.lazy.map { |pattern| pattern.match(line) }.find(&:present?)
      return nil unless match

      {
        file: match[:file].to_s,
        line_number: match[:line].to_i,
        method_name: match[:method].to_s.presence,
        column_number: match.names.include?("column") && match[:column].to_i.positive? ? match[:column].to_i : nil
      }
    end

    def parse_structured_backtrace_frame(frame)
      file = value_from_hash(frame, "filename") ||
        value_from_hash(frame, "template") ||
        value_from_hash(frame, "file") ||
        value_from_hash(frame, "path")
      line_number = value_from_hash(frame, "lineno") ||
        value_from_hash(frame, "line") ||
        value_from_hash(frame, "line_number") ||
        value_from_hash(frame, "lineNumber")
      return nil if file.blank? || line_number.to_i <= 0

      {
        file: file.to_s,
        line_number: line_number.to_i,
        column_number: value_from_hash(frame, "colno") ||
          value_from_hash(frame, "column") ||
          value_from_hash(frame, "column_number") ||
          value_from_hash(frame, "colNumber"),
        method_name: value_from_hash(frame, "function") ||
          value_from_hash(frame, "name") ||
          value_from_hash(frame, "method") ||
          value_from_hash(frame, "module") ||
          value_from_hash(frame, "type"),
        code_context: value_from_hash(frame, "codePrintPlain") ||
          value_from_hash(frame, "code_print_plain") ||
          value_from_hash(frame, "codePrintHTML") ||
          value_from_hash(frame, "line") ||
          value_from_hash(frame, "code_context") ||
          value_from_hash(frame, "context_line") ||
          value_from_hash(frame, "source") ||
          value_from_hash(frame, "code"),
        locals: normalize_hash(value_from_hash(frame, "locals")),
        raw: "#{file}:#{line_number}"
      }
    end

    def absolute_source_path(file_path)
      return nil if file_path.blank?

      root = Rails.root.to_s
      if file_path.start_with?("/")
        return file_path if file_path.start_with?(root)

        return nil
      end

      return nil unless file_path.start_with?("app/", "lib/", "config/", "db/")

      Rails.root.join(file_path).to_s
    end

    def application_frame_path?(relative_path, absolute_path)
      return true if relative_path.to_s.start_with?("app/")

      absolute_path.to_s.start_with?(Rails.root.join("app").to_s)
    end

    def request_scalar_value(context, key)
      first_scalar_value(context, key)
    end

    def request_hash_value(context, key)
      first_hash_value(context, key)
    end
  end
end
