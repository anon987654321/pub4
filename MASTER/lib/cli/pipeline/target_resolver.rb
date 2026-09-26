# frozen_string_literal: true

module Master
  module CLI
    class Pipeline
      module TargetResolver
        def resolve_target(raw)
          text = raw.to_s.strip
          return Master::REPO_ROOT if text.empty? || text.match?(%r{\A(?:all|everything|the|code|codebase|it|this|that)\z}i)
          aliases = target_aliases
          return aliases[text] if aliases.key?(text)
          if text.match?(%r{\Arails[:/]}i)
            return File.join(Master::RAILS_ROOT, text.sub(%r{\Arails[:/]}i, ""))
          end
          if text.match?(%r{\A(?:\.\./)?RAILS(?:/|\z)})
            return File.expand_path(text.delete_prefix("../"), Master::REPO_ROOT)
          end
          path = File.expand_path(text, @root)
          return path if File.exist?(path)
          File.expand_path(text, Master::REPO_ROOT)
        end

        def shell_target(abs)
          return "self" if abs == File.join(@root, "lib")
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