# frozen_string_literal: true

class RequestSpanSegments
  LIMIT = 5_000

  # Attribute each child to its nearest local server/browser span. Trace IDs alone
  # cannot distinguish concurrent or retried requests within a distributed trace.
  def self.call(roots, children)
    root_keys = roots.to_h { |row| [ [ row.fetch("trace_id"), row.fetch("external_span_id") ], true ] }
    index = children.index_by { |row| [ row.fetch("trace_id"), row.fetch("external_span_id") ] }
    result = Hash.new { |hash, key| hash[key] = [] }
    children.each do |child|
      next if TraceSpan::ROOT_KINDS.include?(child["kind"])
      parent = child["parent_span_id"]
      seen = Set.new
      while parent.present? && seen.add?(parent)
        key = [ child["trace_id"], parent ]
        if root_keys[key]
          result[key] << child.merge("child_count" => 1)
          break
        end
        ancestor = index[key]
        break unless ancestor
        break if TraceSpan::ROOT_KINDS.include?(ancestor["kind"])
        parent = ancestor["parent_span_id"]
      end
    end
    result
  end
end
