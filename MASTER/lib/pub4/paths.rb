# frozen_string_literal: true

module Pub4
  # Canonical repo layout paths. OPENBSD holds the VPS config backup (etc/usr/var)
  # and production operator tooling (bin, lib, sh, gates).
  module Paths
    module_function

    def repo_root(from = __dir__)
      Environment.repo_root(from:)
    end

    def operator_root
      openbsd_root
    end

    def rails_root
      File.join(repo_root, "RAILS")
    end

    def openbsd_root
      File.join(repo_root, "OPENBSD")
    end

    def openbsd_operator_root
      openbsd_root
    end

    def master_root
      File.join(repo_root, "MASTER")
    end

    # Legacy aliases — we folded DEPLOY/OPERATOR into OPENBSD (2026-07).
    def deploy_root = openbsd_root

    def resolve(path)
      expanded = File.expand_path(path, repo_root)
      return expanded if File.exist?(expanded)

      legacy = path.to_s
        .sub(%r{\ADEPLOY/rails/}, "RAILS/")
        .sub(%r{\ADEPLOY/openbsd/}, "OPENBSD/")
        .sub(%r{\ADEPLOY/}, "OPENBSD/")
        .sub(%r{\AOPERATOR/openbsd/}, "OPENBSD/")
        .sub(%r{\AOPERATOR/}, "OPENBSD/")
        .sub(%r{\AOPENBSD/rails/}, "RAILS/")
      File.expand_path(legacy, repo_root)
    end
  end
end
