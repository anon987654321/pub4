# frozen_string_literal: true

require "minitest/autorun"
require "erb"
require "yaml"

# Two promises each app's config makes to production, read as data rather than
# as spelling.
#
# A recurring task naming a job class that does not exist stops Solid Queue's
# scheduler when it validates the file, so every other task on that app stops
# with it. And every SQLite database runs in WAL mode, because the web and job
# processes write the same files and a rollback journal makes each writer
# block every reader.
class AppConfigContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  APPS = %w[amber brgen bsdports].freeze

  def job_roots(app)
    [File.join(ROOT, app, "app", "jobs"), File.join(ROOT, "shared", "app", "jobs"),
     *Dir.glob(File.join(ROOT, app, "engines", "*", "app", "jobs"))]
  end

  def job_file(class_name)
    "#{class_name.gsub("::", "/").gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase}.rb"
  end

  def load_yaml(path)
    YAML.safe_load(ERB.new(File.read(path)).result, aliases: true) || {}
  end

  def test_every_recurring_task_names_a_job_that_exists
    checked = 0
    missing = APPS.flat_map do |app|
      path = File.join(ROOT, app, "config", "recurring.yml")
      next [] unless File.file?(path)

      load_yaml(path).flat_map do |env, tasks|
        (tasks || {}).filter_map do |name, task|
          next unless task.is_a?(Hash) && task["class"]

          checked += 1
          file = job_file(task["class"])
          next if job_roots(app).any? { |root| File.file?(File.join(root, file)) }

          "#{app} #{env}.#{name}: #{task["class"]} (no #{file})"
        end
      end
    end

    assert_operator checked, :>, 10, "parsed #{checked} recurring tasks — the scan broke, not the tree"
    assert_empty missing, "recurring tasks naming a job class no app defines"
  end

  def test_every_sqlite_database_runs_in_wal_mode
    rollback = APPS.flat_map do |app|
      load_yaml(File.join(ROOT, app, "config", "database.yml")).flat_map do |env, dbs|
        next [] unless dbs.is_a?(Hash)

        dbs.filter_map do |role, db|
          next unless db.is_a?(Hash) && db["adapter"] == "sqlite3"
          next if db["journal_mode"].to_s.casecmp?("wal")

          "#{app} #{env}.#{role}"
        end
      end
    end

    assert_empty rollback, "SQLite databases without journal_mode: WAL"
  end
end
