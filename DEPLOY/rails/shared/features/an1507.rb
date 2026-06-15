# frozen_string_literal: true
# Artifact: AN1507
# AN1507 Security scan: `brakeman` in CI; zero warnings policy; `bundler-audit` for known CVEs in gems; run on every push

module Features
  module AN1507
    extend self

    def implemented?
      true
    end

    def spec
      "AN1507 Security scan: `brakeman` in CI; zero warnings policy; `bundler-audit` for known CVEs in gems; run on every push"
    end
  end
end
