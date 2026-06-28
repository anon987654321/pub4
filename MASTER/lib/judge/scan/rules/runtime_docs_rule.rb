# frozen_string_literal: true

module Master
  module Judge
    module Scan
      module Rules
        # Runtime authority lives in YAML + Ground::BootstrapDocs — not markdown under data/.
        RuleDSL.rule :RUNTIME_DOCS_YAML,
          severity: :error,
          tags: %i[CONSTITUTION DOCS],
          applies_to: %i[markdown],
          autofix: false,
          description: "runtime-read docs must be YAML — forbid stray .md under data/" do |_src, path:|
          rel = RuntimeDocsPaths.data_relative(path)
          next [] unless rel&.start_with?("data/") && rel.end_with?(".md")

          allowed = %w[
            data/SOUL.md
            data/CANON.md
            data/IDENTITY.md
            data/skills/README.md
          ].freeze
          next [] if allowed.include?(rel)

          target = case rel
                   when %r{\Adata/principles/} then "data/operator_principles.yml"
                   when %r{\Adata/claude/} then "data/project_context.yml"
                   when %r{\Adata/skills/} then "data/skills_registry.yml"
                   else "YAML runtime (operator_principles.yml, skills_registry.yml, project_context.yml, or /orient bootstrap)"
                   end

          [finding(
            line: 1,
            message: "runtime docs belong in #{target} — delete #{rel} (see Ground::BootstrapDocs, /orient)"
          )]
        end

        module RuntimeDocsPaths
          module_function

          def data_relative(path)
            expanded = File.expand_path(path.to_s)
            root = File.expand_path(Master::ROOT)
            return nil unless expanded.start_with?("#{root}/")

            expanded.delete_prefix("#{root}/")
          end
        end
      end
    end
  end
end