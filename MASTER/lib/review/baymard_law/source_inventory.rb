# frozen_string_literal: true

module Master
  module Review
    class BaymardLaw
      # Owns the bounded source inventory for one RAILS checkout. App identity
      # comes from apps.yml, while existing brgen vertical engines and the
      # shared engine are added from their actual source roots.
      class SourceInventory
        Result = Data.define(:apps, :read_errors)

        def initialize(repo_root:, rails_root:, requested_apps: nil)
          @repo_root = repo_root
          @rails_root = rails_root
          @requested_apps = requested_apps
        end

        def call
          manifest_path = File.join(@rails_root, "apps.yml")
          manifest = read_app_manifest(manifest_path)
          declared = manifest.fetch("apps", {})
          raise BaymardLaw::InvalidProfile, "RAILS/apps.yml apps must be a mapping" unless declared.is_a?(Hash)

          names = @requested_apps || declared.keys.map(&:to_s)
          paths = names.filter_map do |name|
            path = File.join(@rails_root, name)
            path if valid_app_root?(path)
          end

          unless @requested_apps
            paths.concat(Dir.glob(File.join(@rails_root, "brgen_*")).select { |path| valid_app_root?(path) })
            shared = File.join(@rails_root, "__shared")
            paths << shared if valid_app_root?(shared)
          end

          apps = paths.uniq.sort.map { |path| build_app(File.basename(path), path) }
          errors = apps.flat_map { |app| app.records.filter_map(&:error) }
          Result.new(apps:, read_errors: errors.freeze)
        end

        private

        def read_app_manifest(path)
          return {} unless File.file?(path)

          real = File.realpath(path)
          repo_root = File.realpath(@repo_root)
          raise BaymardLaw::InvalidProfile, "RAILS/apps.yml resolves outside the repository" unless inside?(real, repo_root)

          Master.load_yaml(real)
        rescue SystemCallError => e
          raise BaymardLaw::InvalidProfile, "RAILS/apps.yml cannot be safely read: #{e.class}: #{e.message}"
        end

        def valid_app_root?(path)
          expanded = File.expand_path(path)
          rails_root = File.expand_path(@rails_root)
          return false unless inside?(expanded, rails_root)
          return false unless File.directory?(expanded)

          real = File.realpath(expanded)
          rails_real = File.realpath(rails_root)
          return false unless inside?(real, rails_real)

          File.file?(File.join(real, "config", "routes.rb")) ||
            File.directory?(File.join(real, "app", "views"))
        rescue SystemCallError
          false
        end

        def inside?(path, root)
          path == root || path.start_with?("#{root}#{File::SEPARATOR}")
        end

        def build_app(name, path)
          records = collect_source_files(path)
          content = records.map(&:content).join("\n")
          routes = File.join(path, "config", "routes.rb")
          content << "\n#{File.read(routes)}" if File.file?(routes)

          features = {
            search: content.match?(/(?:search_path|searches_path|type\s*=\s*["']search|resources\s+:search|\/search\b)/i),
            product: content.match?(/(?:products?|listings?|marketplace|takeaway)/i),
            cart: content.match?(/(?:shopping[_ -]?cart|cart_path|carts_path|\/cart\b|basket)/i),
            checkout: content.match?(/(?:checkout|payment_step|\/orders?\b)/i),
          }.freeze

          BaymardLaw::App.new(name:, root: path, records: records.freeze, features:)
        end

        def collect_source_files(root)
          root_real = File.realpath(root)
          Dir.glob(File.join(root, "**", "*"), File::FNM_DOTMATCH).sort.filter_map do |path|
            next unless File.file?(path)
            next if BaymardLaw::SKIP_PATH.match?(path.delete_prefix("#{root}/"))
            next unless BaymardLaw::SOURCE_EXTENSIONS.include?(File.extname(path).downcase)
            next unless File.realpath(path).start_with?("#{root_real}#{File::SEPARATOR}")

            bytes = File.binread(path, BaymardLaw::MAX_SOURCE_BYTES + 1)
            error = if bytes.bytesize > BaymardLaw::MAX_SOURCE_BYTES
                      "source exceeds #{BaymardLaw::MAX_SOURCE_BYTES} byte audit limit"
                    elsif bytes.include?("\x00")
                      "binary content is not a markup or stylesheet measurement"
                    end
            content = error ? "" : bytes.force_encoding(Encoding::UTF_8)
            error ||= "source is not valid UTF-8" unless error || content.valid_encoding?

            BaymardLaw::FileRecord.new(
              path:,
              relative: path.delete_prefix("#{@repo_root}/"),
              content: error ? "" : content.freeze,
              error:,
            )
          rescue SystemCallError, EncodingError => e
            BaymardLaw::FileRecord.new(
              path:,
              relative: path.delete_prefix("#{@repo_root}/"),
              content: "",
              error: "#{path}: #{e.class}: #{e.message}",
            )
          end
        end
      end
    end
  end
end
