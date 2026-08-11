# frozen_string_literal: true

module CompositeReferenceQuerying
  extend ActiveSupport::Concern

  class_methods do
    def where_composite_references(reference_columns, pairs)
      reference_pairs = Array(pairs)
      return none if reference_pairs.empty?

      columns = Array(reference_columns).map(&:to_s)
      unknown_columns = columns - column_names
      raise ArgumentError, "unknown reference columns: #{unknown_columns.join(', ')}" if unknown_columns.any?
      unless reference_pairs.all? { |pair| Array(pair).length == columns.length }
        raise ArgumentError, "reference pairs must match the reference column count"
      end

      qualified_columns = columns.map do |column|
        "#{connection.quote_table_name(table_name)}.#{connection.quote_column_name(column)}"
      end
      tuple_placeholder = "(#{Array.new(columns.length, '?').join(', ')})"
      value_placeholders = Array.new(reference_pairs.length, tuple_placeholder).join(", ")
      condition = sanitize_sql_array(
        [ "(#{qualified_columns.join(', ')}) IN (#{value_placeholders})", *reference_pairs.flatten ]
      )

      where(condition)
    end
  end
end
