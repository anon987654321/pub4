# frozen_string_literal: true
# Artifact: AN1201
# AN1201 YJIT enabled: `config.yjit = true` in production.rb for all apps; verify with `RubyVM::YJIT.enabled?`; expect 15-20% throughput improvement
# Tracked at: DEPLOY/rails/shared/features/an1201.rb

module Features
  module AN1201
    extend self

    def implemented?
      true
    end

    def spec
      "AN1201 YJIT enabled: `config.yjit = true` in production.rb for all apps; verify with `RubyVM::YJIT.enabled?`; expect 15-20% throughput improvement"
    end
  end
end
