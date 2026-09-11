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
      return result.inconclusive!("schema_migration: the inventory lists no apps — nothing was read") if inventory.apps.empty?

      inventory.apps.each do |app|
        app_dir = File.join(RAILS_ROOT, app.name)
        next unless File.directory?(app_dir)

        result.checked!
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

    # A table name is a symbol or a quoted string, and either delimiter closes it.
    #
    # This read /create_table\s+["':](\w+)["']/ — a colon allowed to open the name
    # and a quote demanded to close it — so `create_table :posts`, the form every
    # migration in this fleet uses, matched nothing. The scan saw 3 of 200 calls
    # and the duplicate check below had never once seen a table.
    CREATE_TABLE = /create_table\s+(?::(\w+)|"(\w+)"|'(\w+)')/
    def create_table_names(body)
      body.scan(CREATE_TABLE).map { |symbol, double, single| symbol || double || single }
    end

    # A second create_table is ordinary when the migration says what it expects
    # to find. Three forms say it, and all three are in use here: `if_not_exists:
    # true` on the call, a `table_exists?` guard anywhere in the file — whether it
    # wraps the call, returns early, or drops the table before recreating it — and
    # a drop of that table first. Sixteen second calls exist across the fleet and
    # every one of them is guarded, which is why this check must read the guard
    # rather than count the calls.
    def guarded_for?(body, table)
      return true if body.match?(/create_table\s+(?::#{table}|["']#{table}["'])[^\n]*if_not_exists/)
      return true if body.match?(/table_exists\?\(\s*[:"']#{table}\b/)

      # GUARD_EXPENSIVE_OPS sees drop_table inside the pattern and cannot tell a
      # match from an execution; this reads the word in somebody else's migration.
      body.match?(/drop_table\s+[:"']#{table}\b/) # scan: intentional
    end

    def duplicate_create_tables(app_dir, result, app_name)
      seen = {}
      Dir.glob(File.join(app_dir, "db", "migrate", "*.rb")).sort.each do |path|
        body = read_utf8(path) # scan: intentional — two plain lines beat a .then
        create_table_names(body).each do |table|
          first = seen[table]
          if first.nil?
            seen[table] = File.basename(path)
            next
          end
          next if guarded_for?(body, table)

          result.fail("#{app_name}: unguarded second create_table #{table} in " \
                      "#{File.basename(path)}, already created in #{first} — " \
                      "add if_not_exists: true or a table_exists? guard")
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
