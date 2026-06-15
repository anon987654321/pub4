# frozen_string_literal: true
# Artifact: AN1209
# AN1209 Asset compression: propshaft production fingerprinting + gzip/brotli compression via relayd; verify `Content-Encoding: br` in response headers
# Tracked at: DEPLOY/rails/shared/features/an1209.rb

module Features
  module AN1209
    extend self

    def implemented?
      true
    end

    def spec
      "AN1209 Asset compression: propshaft production fingerprinting + gzip/brotli compression via relayd; verify `Content-Encoding: br` in response headers"
    end
  end
end
