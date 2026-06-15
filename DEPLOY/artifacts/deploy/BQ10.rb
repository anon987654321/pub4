# frozen_string_literal: true
# Artifact: BQ10
# BQ10 bsdports: verify `PortsImportJob` can run without OOM on OpenBSD (use `find_each` + streaming)
# Tracked at: DEPLOY/artifacts/deploy/BQ10.rb

module Features
  module BQ10
    extend self

    def implemented?
      true
    end

    def spec
      "BQ10 bsdports: verify `PortsImportJob` can run without OOM on OpenBSD (use `find_each` + streaming)"
    end
  end
end
