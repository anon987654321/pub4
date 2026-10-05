# frozen_string_literal: true

module Master
  module CLI
    class Pipeline
      module TargetResolver
        ALL_TREE_NAMES = %w[MASTER RAILS OPENBSD STUDIO].freeze

        def resolve_target(raw)
          text = raw.to_s.strip
          # Shell-style recursive targets are scope notation, not literal
          # directories. /fix RAILS/** therefore governs the RAILS tree itself.
          text = text.sub(%r{/\*\*(?:/\*)?\z}, "")
          # An omitted target means the checkout MASTER is actually running from.
          # "everything"/"all" remains the explicit repository-wide spelling.
          return Master::REPO_ROOT if all_tree_target?(text)
          return @root if text.empty?
          return Master::REPO_ROOT if text.match?(%r{\A(?:all|everything|the|code|codebase|it|this|that)\z}i)
          aliases = target_aliases
          return aliases[text] if aliases.key?(text)
          if text.match?(%r{\Arails[:/]}i)
            return File.join(Master::RAILS_ROOT, text.sub(%r{\Arails[:/]}i, ""))
          end
          if text.match?(%r{\A(?:\.\./)?RAILS(?:/|\z)})
            return File.expand_path(text.delete_prefix("../"), Master::REPO_ROOT)
          end
          if text.match?(%r{\A(?:\.\./)?MASTER(?:/|\z)}i)
            return File.expand_path(text.delete_prefix("../"), Master::REPO_ROOT)
          end
          if text.match?(%r{\A(?:\.\./)?OPENBSD(?:/|\z)}i)
            return File.expand_path(text.delete_prefix("../"), Master::REPO_ROOT)
          end
          if text.match?(%r{\A(?:\.\./)?STUDIO(?:/|\z)}i)
            return File.expand_path(text.delete_prefix("../"), Master::REPO_ROOT)
          end
          path = File.expand_path(text, @root)
          return path if governed_path?(path)

          raise ArgumentError, "target outside pub4 trees: #{raw.inspect}"
        end

        def governed_path?(path)
          repo = File.expand_path(Master::REPO_ROOT)
          return true if path == repo
          ALL_TREE_NAMES.any? do |tree|
            root = File.join(repo, tree)
            path == root || path.start_with?("#{root}/")
          end
        end

        def all_tree_target?(text)
          names = text.split(/[,\s]+/).reject(&:empty?).map(&:upcase).uniq.sort
          names == ALL_TREE_NAMES.sort
        end

        def shell_target(abs)
          return "self" if abs == File.join(@root, "lib")
          return "all four trees" if abs == Master::REPO_ROOT
          return "master" if abs == @root
          return "rails" if abs == Master::RAILS_ROOT
          return "face" if abs == File.join(@root, "web", "public")
          return "web" if abs == File.join(@root, "web")
          if abs.start_with?("#{Master::RAILS_ROOT}/")
            return "rails/#{abs.delete_prefix("#{Master::RAILS_ROOT}/")}"
          end
          if abs.start_with?("#{@root}/")
            return abs.delete_prefix("#{@root}/")
          end

          abs
        end

        def target_aliases
          {
            "self" => File.join(@root, "lib"),
            "master" => @root,
            "itself" => @root,
            "." => @root,
            "rails" => Master::RAILS_ROOT,
            "RAILS" => Master::RAILS_ROOT,
            "face" => File.join(@root, "web", "public"),
            "web" => File.join(@root, "web"),
          }
        end
      end
    end
  end
end