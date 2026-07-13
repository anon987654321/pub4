# frozen_string_literal: true

module Pub4
  # Canonical repo layout paths. OPENBSD is the config backup; operator tooling
  # lives under OPERATOR/openbsd.
  module Paths
    module_function

    def repo_root(from = __dir__)
      Environment.repo_root(from:)
    end

    def operator_root
      File.join(repo_root, "OPERATOR")
    end

    def rails_root
      File.join(repo_root, "RAILS")
    end

    def openbsd_root
      File.join(repo_root, "OPENBSD")
    end

    def openbsd_operator_root
      File.join(operator_root, "openbsd")
    end

    def master_root
      File.join(repo_root, "MASTER")
    end

    # Legacy alias — DEPLOY was renamed to OPERATOR (2026-07).
    def deploy_root = operator_root

    def resolve(path)
      expanded = File.expand_path(path, repo_root)
      return expanded if File.exist?(expanded)

      legacy = path.to_s
        .sub(%r{\ADEPLOY/rails/}, "RAILS/")
        .sub(%r{\ADEPLOY/openbsd/}, "OPERATOR/openbsd/")
        .sub(%r{\ADEPLOY/}, "OPERATOR/")
        .sub(%r{\AOPERATOR/rails/}, "RAILS/")
      File.expand_path(legacy, repo_root)
    end
  end
end
