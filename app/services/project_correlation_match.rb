# frozen_string_literal: true

class ProjectCorrelationMatch
  def self.evidence(anchor, candidate)
    trace, other_trace = anchor.matchable("trace_id"), candidate.matchable("trace_id")
    if trace.present? && trace == other_trace
      parent = (anchor.matchable("span_id").present? && anchor.matchable("span_id") == candidate.matchable("parent_span_id")) ||
        (anchor.matchable("parent_span_id").present? && anchor.matchable("parent_span_id") == candidate.matchable("span_id"))
      return parent ? "parent_span" : "shared_trace"
    end
    return if trace.present? && other_trace.present? && trace != other_trace

    request = anchor.matchable("request_id")
    "shared_request_id" if request.present? && request == candidate.matchable("request_id")
  end
end
