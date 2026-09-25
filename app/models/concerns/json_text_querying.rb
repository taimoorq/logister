# frozen_string_literal: true

module JsonTextQuerying
  extend ActiveSupport::Concern

  class_methods do
    # GIN containment narrows candidates; the text comparison preserves ->>
    # semantics for old numeric/boolean values and rejects containment supersets.
    def where_json_text(column, paths:, value:)
      raise ArgumentError, "Unknown JSON column" unless column.to_s.in?(%w[context dimensions])

      text = value.to_s
      candidates = [ text.to_json ]
      begin
        parsed = JSON.parse(text, decimal_class: BigDecimal)
        # Keep the original JSON literal: a Float round trip can lose numeric precision.
        candidates << text if !parsed.is_a?(String) && jsonb_literal_supported?(parsed)
      rescue JSON::ParserError
        # Most identifiers are plain strings, not JSON literals.
      end
      field = "#{quoted_table_name}.#{connection.quote_column_name(column)}"
      clauses = Array(paths).map do |path|
        keys = Array(path).map(&:to_s)
        raise ArgumentError, "Empty JSON path" if keys.empty?

        documents = candidates.map do |candidate|
          keys.reverse.reduce(candidate) { |nested, key| "{#{key.to_json}:#{nested}}" }
        end
        containment = documents.map { |document| sanitize_sql_array([ "#{field} @> ?::jsonb", document ]) }.join(" OR ")
        exact = sanitize_sql_array([ "#{field} #>> ARRAY[?]::text[] = ?", keys, text ])
        "((#{containment}) AND #{exact})"
      end
      clauses.empty? ? none : where(clauses.join(" OR "))
    end

    private

    # A search string may be legal JSON but invalid jsonb (NUL or an out-of-range
    # numeric). Such values can only match stored strings; never cast them.
    # https://www.postgresql.org/docs/16/datatype-json.html
    def jsonb_literal_supported?(value)
      case value
      when Hash then value.all? { |key, item| jsonb_literal_supported?(key) && jsonb_literal_supported?(item) }
      when Array then value.all? { |item| jsonb_literal_supported?(item) }
      when String then !value.include?("\u0000")
      when Integer then value.abs.to_s.length <= 131_072
      when BigDecimal
        value.finite? && value.exponent <= 131_072 && value.split[1].length - value.exponent <= 16_383
      else true
      end
    end
  end
end
