# frozen_string_literal: true

require_relative "../../../../OPENBSD/lib/gate_result"
require_relative "../../../../OPENBSD/lib/deploy_inventory"

module Deploy
  class SchemaMigrationGate
    ROOT = File.expand_path("../../../..", __dir__)
    RAILS_ROOT = File.join(ROOT, "RAILS")

    def self.run
      new.run
    end

    def run
      result = GateResult.new
      inventory = Inventory.new(root: ROOT)
      inventory.apps.each do |app|
        app_dir = File.join(RAILS_ROOT, app.name)
        next unless File.directory?(app_dir)

        versions = migration_versions(app_dir)
        schema_v = schema_version(app_dir)
        if versions.any? && schema_v && schema_v != versions.last
          result.fail("#{app.name}: schema version #{schema_v} != latest migration #{versions.last}")
        end

        duplicate_create_tables(app_dir, result, app.name)
        route_controllers(app_dir, result, app.name)

        schema = File.join(app_dir, "db", "schema.rb")
        duplicate_columns_per_table(read_utf8(schema), result, app.name) if File.file?(schema)
      end
      result
    end

    private

    def migration_versions(app_dir)
      Dir.glob(File.join(app_dir, "db", "migrate", "*.rb")).map do |path|
        File.basename(path).split("_", 2).first.to_i
      end.sort
    end

    def schema_version(app_dir)
      schema = File.join(app_dir, "db", "schema.rb")
      return nil unless File.file?(schema)

      read_utf8(schema)[/define\(version:\s*(\d+)\)/, 1]&.to_i
    end

    def read_utf8(path)
      File.read(path, encoding: "UTF-8")
    rescue Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
      File.read(path).force_encoding("UTF-8").scrub
    end

    def duplicate_create_tables(app_dir, result, app_name)
      seen = {}
      Dir.glob(File.join(app_dir, "db", "migrate", "*.rb")).sort.each do |path|
        tables = read_utf8(path).scan(/create_table\s+["':](\w+)["']/)
        tables.each do |table|
          key = table.first
          if seen[key]
            result.fail("#{app_name}: duplicate create_table #{key} in #{File.basename(path)} and #{seen[key]}")
          else
            seen[key] = File.basename(path)
          end
        end
      end
    end

    def controller_exists?(app_dir, controller)
      parts = controller.split("/")
      candidates = [
        File.join(app_dir, "app", "controllers", *parts.map { |part| "#{part}_controller.rb" }),
        File.join(app_dir, "app", "controllers", "#{controller}_controller.rb")
      ]
      return true if candidates.any? { |path| File.file?(path) }

      leaf = parts.last
      Dir.glob(File.join(app_dir, "app", "controllers", "**", "#{leaf}_controller.rb")).any?
    end

    def route_controllers(app_dir, result, app_name)
      routes = File.join(app_dir, "config", "routes.rb")
      return unless File.file?(routes)

      read_utf8(routes).scan(/to:\s*["']([\w#\/]+)["']/).flatten.each do |target|
        next if target.start_with?("rails/")

        controller = target.split("#").first
        next if controller.to_s.strip.empty?
        next if controller_exists?(app_dir, controller)

        result.fail("#{app_name}: route target #{target} missing controller")
      end
    end

    def duplicate_columns_per_table(schema_body, result, app_name)
      schema_body.scan(/create_table\s+"(\w+)".*?do\s*\|t\|(.*?)end/m).each do |table, block|
        counts = Hash.new(0)
        block.scan(/t\.(\w+)\s+"(\w+)"/).each do |_type, column|
          counts[column] += 1
        end
        counts.each do |column, count|
          next if count == 1

          result.fail("#{app_name}: duplicate column #{column} on #{table} in schema.rb")
        end
      end
    end
  end
end
