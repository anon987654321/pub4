# frozen_string_literal: true

class PwaController < Rails::PwaController
  def manifest
    http_cache_forever(public: true) { super }
  end

  def service_worker
    http_cache_forever(public: true) { super }
  end
end