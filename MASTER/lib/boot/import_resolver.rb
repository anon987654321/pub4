# frozen_string_literal: true

require "pathname"

module Master
  module Boot
    module ImportResolver
      TREES = %w[MASTER RAILS OPENBSD].freeze
      SKIP = %r{/(?:\.git|\.bundle|vendor|node_modules|tmp|log|coverage|storage|cache|output|knowledge|build|dist|test|spec)(?:/|\z)}

      class << self
        attr_reader :last_compat_count

        def install!(root:)
          @root = File.expand_path(root)
          @last_compat_count = 0
          Kernel.prepend(KernelPatch) unless Kernel.ancestors.include?(KernelPatch)
        end

        def resolve(spec, caller_path)
          literal = File.expand_path(spec.to_s, File.dirname(caller_path))
          return literal if File.file?(literal)
          return "#{literal}.rb" if File.file?("#{literal}.rb")

          candidates = suffix_candidates(spec)
          return unique(candidates)
        end

        def canonical_relative(source, target)
          relative = Pathname.new(target).relative_path_from(Pathname.new(File.dirname(source))).to_s
          relative = relative.delete_suffix(".rb")
          relative.start_with?(".") ? relative : relative
        end

        def compatibility?(spec, caller_path, resolved)
          literal = File.expand_path(spec.to_s, File.dirname(caller_path))
          return false if File.file?(literal) || File.file?("#{literal}.rb")

          resolved && File.expand_path(resolved) != literal
        end

        private

        def suffix_candidates(spec)
          clean = spec.to_s.split("/").reject { |part| part.empty? || part == "." || part == ".." }.join("/")
          return [] if clean.empty?

          exact = TREES.flat_map { |tree| Dir.glob(File.join(@root, tree, "**", clean)).select { |path| File.file?(path) } }
          exact += TREES.flat_map { |tree| Dir.glob(File.join(@root, tree, "**", "#{clean}.rb")).select { |path| File.file?(path) } }
          return unique(exact) unless exact.empty?

          basename = File.basename(clean)
          unique(TREES.flat_map { |tree| Dir.glob(File.join(@root, tree, "**", "#{basename}.rb")) }.reject { |path| path.match?(SKIP) })
        end

        def unique(paths)
          paths = Array(paths).map { |path| File.expand_path(path) }.uniq
          paths.one? ? paths.first : nil
        end
      end

      module KernelPatch
        def require_relative(spec)
          caller_path = caller_locations(1, 1).first&.absolute_path
          return super unless caller_path

          resolved = Master::Boot::ImportResolver.resolve(spec, caller_path)
          if resolved && Master::Boot::ImportResolver.compatibility?(spec, caller_path, resolved)
            Master::Boot::ImportResolver.instance_variable_set(
              :@last_compat_count,
              Master::Boot::ImportResolver.last_compat_count.to_i + 1
            )
            warn("boot0: compatibility import #{spec} -> #{resolved}") if ENV["MASTER_CLI_TRACE"] == "1"
            return require(resolved)
          end

          return require(resolved) if resolved

          super
        end
      end
    end
  end
end
