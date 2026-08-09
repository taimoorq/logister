# frozen_string_literal: true

require "json"

module Logister
  class BoundedJsonPayload
    DEFAULT_MAX_STRING_BYTES = 16.kilobytes
    DEFAULT_MAX_ARRAY_ITEMS = 100
    OMIT = Object.new.freeze

    Result = Data.define(:value, :truncated, :bytes)

    def self.call(value, max_bytes:, max_string_bytes: DEFAULT_MAX_STRING_BYTES, max_array_items: DEFAULT_MAX_ARRAY_ITEMS)
      new(value:, max_bytes:, max_string_bytes:, max_array_items:).call
    end

    def initialize(value:, max_bytes:, max_string_bytes:, max_array_items:)
      @value = value.as_json
      @max_bytes = [ max_bytes.to_i, 2 ].max
      @max_string_bytes = [ max_string_bytes.to_i, 1 ].max
      @max_array_items = [ max_array_items.to_i, 1 ].max
    end

    def call
      bounded, truncated = bound(value, max_bytes)
      bounded = {} if bounded.equal?(OMIT)
      encoded_bytes = JSON.generate(bounded).bytesize

      if encoded_bytes > max_bytes
        bounded = {}
        encoded_bytes = JSON.generate(bounded).bytesize
        truncated = true
      end

      Result.new(bounded, truncated, encoded_bytes)
    end

    private

    attr_reader :value, :max_bytes, :max_string_bytes, :max_array_items

    def bound(candidate, budget)
      case candidate
      when Hash then bound_hash(candidate, budget)
      when Array then bound_array(candidate, budget)
      when String then bound_string(candidate, budget)
      else bound_scalar(candidate, budget)
      end
    end

    def bound_hash(candidate, budget)
      return [ OMIT, true ] if budget < 2

      result = {}
      used = 2
      truncated = false
      candidate.each do |key, nested|
        key = key.to_s
        entry_overhead = (result.empty? ? 0 : 1) + JSON.generate(key).bytesize + 1
        available = budget - used - entry_overhead
        if available <= 0
          truncated = true
          next
        end

        bounded, child_truncated = bound(nested, available)
        if bounded.equal?(OMIT)
          truncated = true
          next
        end

        result[key] = bounded
        used += entry_overhead + JSON.generate(bounded).bytesize
        truncated ||= child_truncated
      end
      truncated ||= result.length < candidate.length
      [ result, truncated ]
    end

    def bound_array(candidate, budget)
      return [ OMIT, true ] if budget < 2

      result = []
      used = 2
      truncated = candidate.length > max_array_items
      candidate.first(max_array_items).each do |nested|
        entry_overhead = result.empty? ? 0 : 1
        available = budget - used - entry_overhead
        if available <= 0
          truncated = true
          break
        end

        bounded, child_truncated = bound(nested, available)
        if bounded.equal?(OMIT)
          truncated = true
          break
        end

        result << bounded
        used += entry_overhead + JSON.generate(bounded).bytesize
        truncated ||= child_truncated
      end
      truncated ||= result.length < candidate.length
      [ result, truncated ]
    end

    def bound_string(candidate, budget)
      encoded = JSON.generate(candidate)
      return [ candidate, false ] if encoded.bytesize <= budget && candidate.bytesize <= max_string_bytes
      return [ OMIT, true ] if budget < 2

      upper_bound = [ candidate.bytesize, max_string_bytes, budget ].min
      while upper_bound >= 0
        prefix = candidate.byteslice(0, upper_bound).to_s.scrub
        bounded = upper_bound < candidate.bytesize ? "#{prefix}…" : prefix
        return [ bounded, true ] if JSON.generate(bounded).bytesize <= budget

        upper_bound -= [ upper_bound / 8, 1 ].max
      end

      [ "", true ]
    end

    def bound_scalar(candidate, budget)
      JSON.generate(candidate).bytesize <= budget ? [ candidate, false ] : [ OMIT, true ]
    end
  end
end
