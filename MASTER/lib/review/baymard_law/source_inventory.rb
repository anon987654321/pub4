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
          errors = apps.flat_map do |app|
            app.records.filter_map do |record|
              "#{record.relative}: #{record.error}" if record.error
            end
          end
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
          routes_path = File.join(path, "config", "routes.rb")
          routes = ""
          if File.file?(routes_path)
            app_real = File.realpath(path)
            routes_real = File.realpath(routes_path)
            raise BaymardLaw::InvalidProfile, "route source escapes #{name}" unless inside?(routes_real, app_real)

            routes = File.read(routes_real)
          end
          app_prefix = "#{path.sub(%r{/$}, "")}/"
          relative_paths = records.map(&:path).map do |source_path|
            source_path.delete_prefix(app_prefix).downcase
          end

          # Feature applicability follows actual route and view/controller
          # structure, not incidental words in copy, CSS or Ruby comments.
          features = {
            search: path_or_route?(relative_paths, routes, %w[search searches search_results catalog catalogues]),
            product: path_or_route?(relative_paths, routes, %w[product products listing listings deal deals marketplace takeaway menu menus menu_items restaurant restaurants storefront]),
            cart: path_or_route?(relative_paths, routes, %w[cart carts basket baskets shopping_cart]),
            checkout: path_or_route?(relative_paths, routes, %w[checkout checkouts payment payments order orders]),
          }.freeze

          BaymardLaw::App.new(name:, root: path, records: records.freeze, features:)
        rescue SystemCallError => e
          raise BaymardLaw::InvalidProfile, "cannot inventory #{name}: #{e.class}: #{e.message}"
        end

        def path_or_route?(paths, routes, names)
          path_match = paths.any? do |relative|
            segments = relative.split("/")
            (segments & names).any? ||
              names.any? { |name| File.basename(relative, File.extname(relative)).casecmp?(name) }
          end
          route_pattern = names.map { |name| Regexp.escape(name).sub(/s\z/, "s?") }.join("|")
          route_match = routes.match?(%r{(?:resources?|get|post|patch|put|delete)\s*(?:\(|\s)*[:"]?(?:#{route_pattern})\b}i) ||
            routes.match?(%r{/(?:#{route_pattern})(?:/|["'\s]|\z)}i)
          path_match || route_match
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
