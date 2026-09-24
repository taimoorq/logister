# frozen_string_literal: true

# One precedence contract for current SDKs and historical payloads. IDs are data,
# never credentials. SQL builders accept only internal column names/known keys.
class CorrelationContext
  PATHS = {
    "trace_id" => [ %w[trace_id], %w[traceId], %w[trace trace_id], %w[trace traceId], %w[trace id], %w[request trace_id], %w[request traceId] ],
    "request_id" => [ %w[request_id], %w[requestId], %w[trace request_id], %w[trace requestId], %w[request request_id], %w[request requestId], %w[request id] ],
    "span_id" => [ %w[span_id], %w[spanId], %w[trace span_id], %w[trace spanId], %w[request span_id], %w[request spanId] ],
    "parent_span_id" => [ %w[parent_span_id], %w[parentSpanId], %w[trace parent_span_id], %w[trace parentSpanId], %w[request parent_span_id] ]
  }.freeze

  def initialize(context)
    @context = context.is_a?(Hash) ? context.deep_stringify_keys : {}
  end

  def value(key)
    values(key).first
  end

  def matchable(key)
    value(key) unless conflicts.include?(key)
  end

  def conflicts
    PATHS.keys.select { |key| values(key).uniq.length > 1 }
  end

  def normalized
    result = @context.deep_dup
    PATHS.each_key { |key| result[key] = value(key) if value(key) }
    if conflicts.any?
      metadata = result["correlation"].is_a?(Hash) ? result["correlation"] : {}
      result["correlation"] = metadata.merge("conflicts" => conflicts)
    end
    result
  end

  def self.postgres(key, column: "context", matchable: false)
    raise ArgumentError, "invalid context column" unless column.match?(/\A[a-z_]+(?:\.[a-z_]+)?\z/)
    parts = PATHS.fetch(key).map do |path|
      value = "#{column} #>> '{#{path.join(',')}}'"
      "CASE WHEN jsonb_typeof(#{column} #> '{#{path.join(',')}}') = 'string' AND (#{value}) ~ '^[A-Za-z0-9._:-]{1,#{key == 'request_id' ? 200 : 128}}$' THEN #{value} END"
    end
    canonical = "COALESCE(#{parts.join(', ')})"
    return canonical unless matchable

    "CASE WHEN cardinality(ARRAY(SELECT DISTINCT v FROM unnest(ARRAY[#{parts.join(', ')}]) v WHERE v IS NOT NULL)) = 1 THEN #{canonical} END"
  end

  def self.clickhouse(key, column: "context_json", matchable: false)
    raise ArgumentError, "invalid context column" unless column.match?(/\A[a-z_]+\z/)
    parts = PATHS.fetch(key).map do |path|
      value = "JSONExtractString(#{column}, #{path.map { |p| "'#{p}'" }.join(', ')})"
      "if(JSONType(#{column}, #{path.map { |p| "'#{p}'" }.join(', ')}) = 'String' AND match(#{value}, '^[A-Za-z0-9._:-]{1,#{key == 'request_id' ? 200 : 128}}$'), #{value}, '')"
    end
    values = "arrayFilter(v -> v != '', [#{parts.join(', ')}])"
    canonical = "arrayElement(#{values}, 1)"
    matchable ? "if(length(arrayDistinct(#{values})) = 1, #{canonical}, '')" : canonical
  end

  private

  def values(key)
    PATHS.fetch(key).filter_map do |path|
      value = path.reduce(@context) { |node, part| node.is_a?(Hash) ? node[part] : nil }
      value if value.is_a?(String) && value.match?(/\A[A-Za-z0-9._:-]{1,#{key == 'request_id' ? 200 : 128}}\z/)
    end
  end
end
