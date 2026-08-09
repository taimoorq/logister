# frozen_string_literal: true

module ClientSubmissions
  module RequestLimits
    # Keep the legacy JSON endpoint and the gzip/NDJSON endpoint behind the same
    # bounded wire-size policy. Batch decompression and per-envelope limits are
    # enforced separately by TelemetryBatchDecoder and TelemetryPayloadLimits.
    MAX_WIRE_BYTES = 2 * 1024 * 1024
  end
end
