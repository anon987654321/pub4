# frozen_string_literal: true

# Back-compat alias: callers/tests may still enqueue EmbedGarmentJob.
# Implementation is local fingerprint only (see FingerprintGarmentJob).
class EmbedGarmentJob < FingerprintGarmentJob
end
