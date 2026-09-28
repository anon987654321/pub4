# frozen_string_literal: true

require "minitest/autorun"

class PwaRuntimeContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_shared_runtime_exposes_capability_matrix_and_idempotent_queue
    source = File.read(File.join(ROOT, "shared/frontend/pwa_runtime.js"))
    assert_includes source, 'indexedDB.open(DB_NAME,DB_VERSION)'
    assert_includes source, '"X-Idempotency-Key":record.id'
    application = File.read(File.join(ROOT, "brgen/app/javascript/application.js"))
    assert_includes application, 'register("feed-prewarm"'
    assert_includes source, "navigator.mediaSession"
    assert_includes source, "BarcodeDetector"
  end

  def test_hotwire_activates_the_queue_once
    source = File.read(File.join(ROOT, "shared/frontend/hotwire.js"))
    assert_includes source, 'import { installOfflineQueue } from "pub4/pwa_runtime"'
    assert_includes source, "installOfflineQueue()"
  end
end
