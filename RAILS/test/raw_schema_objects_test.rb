# frozen_string_literal: true

require "minitest/autorun"

# Schema objects that `schema_format = :ruby` cannot express.
#
# Rails' Ruby schema dumper writes tables, columns and indexes. It cannot write
# a virtual table, a trigger, or a view -- those exist only as raw `execute` in
# a migration. All three apps are on the default :ruby format, and two of them
# create exactly that kind of object:
#
#   brgen     posts_fts (fts5) + posts_ai/au/ad triggers
#   bsdports  ports_fts (fts5) + ports_ai/au/ad triggers
#
# Production runs db:migrate, so the boxes have them. Everything built by
# db:schema:load does not -- which is `bin/rails test` on every developer
# machine and in CI. So the search index and its three sync triggers are absent
# from precisely the environment that would have tested them, and the code that
# uses them fails in the quietest possible way:
#
#   Post.search / Port.search             raise "no such table"
#   NightlySearchIndexRebuildJob          `return unless data_source_exists?`
#   Ports::Importer#rebuild_fts           rescue StandardError, log a warning
#
# Two of those three are guards that were added because the thing they guard
# was already absent. A nightly job whose entire body sits behind a check for a
# table the test schema cannot contain has never once been observed doing its
# work.
#
# This test does not fix that -- moving an app to structure.sql changes what
# deploy loads and is not a decision a test makes. It makes the inventory
# explicit and holds it at its current size, so the next raw object is a
# decision someone takes rather than one that arrives.
class RawSchemaObjectsTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  APPS = %w[amber brgen bsdports].freeze

  # CREATE <kind> <name>, in raw SQL inside a migration.
  RAW = /CREATE\s+(VIRTUAL\s+TABLE|TRIGGER|VIEW)\s+(?:IF\s+NOT\s+EXISTS\s+)?["`]?(\w+)/i

  # What each app is known to create outside its schema dump, and why it is
  # tolerated. An entry here is a statement that someone looked; an object
  # missing from here is one that arrived unnoticed.
  KNOWN = {
    "brgen" => {
      "posts_fts" => "fts5 index over posts.title/body — 20260528000100_create_posts_fts.rb",
      "posts_ai" => "keeps posts_fts in step on insert",
      "posts_au" => "keeps posts_fts in step on update",
      "posts_ad" => "keeps posts_fts in step on delete",
    },
    "bsdports" => {
      "ports_fts" => "fts5 index over ports.name/comment — 20260528000100_create_ports_fts.rb",
      "ports_ai" => "keeps ports_fts in step on insert",
      "ports_au" => "keeps ports_fts in step on update",
      "ports_ad" => "keeps ports_fts in step on delete",
    },
    "amber" => {},
  }.freeze

  def migrations(app) = Dir.glob(File.join(ROOT, app, "db", "migrate", "*.rb")).sort

  def schema(app)
    path = File.join(ROOT, app, "db", "schema.rb")
    File.file?(path) ? File.read(path) : nil
  end

  def raw_objects(app)
    migrations(app).flat_map do |path|
      File.read(path).scan(RAW).map { |kind, name| [name, kind.downcase.squeeze(" "), File.basename(path)] }
    end
  end

  def schema_format(app)
    config = File.read(File.join(ROOT, app, "config", "application.rb"))
    config[/schema_format\s*=\s*:(\w+)/, 1] || "ruby"
  end

  # --- the inventory ------------------------------------------------------

  def test_every_raw_object_is_declared_here
    undeclared = APPS.flat_map do |app|
      known = KNOWN.fetch(app).keys
      raw_objects(app).reject { |name, _, _| known.include?(name) }
                      .map { |name, kind, file| "#{app}: #{kind} #{name} (#{file})" }
    end

    assert_empty undeclared,
                 "a schema object the Ruby dumper cannot write arrived without anyone saying so — " \
                 "add it to KNOWN with a reason, or move the app to structure.sql:\n  #{undeclared.join("\n  ")}"
  end

  def test_nothing_is_declared_that_no_migration_creates
    stale = APPS.flat_map do |app|
      created = raw_objects(app).map(&:first)
      (KNOWN.fetch(app).keys - created).map { |name| "#{app}: #{name}" }
    end

    assert_empty stale, "declared here and created by no migration: #{stale.inspect}"
  end

  def test_every_declaration_gives_a_reason
    KNOWN.each do |app, objects|
      objects.each do |name, reason|
        refute_empty reason.to_s.strip, "#{app}/#{name} is declared with no reason"
        assert_operator reason.length, :>, 20, "#{app}/#{name}'s reason says nothing a reader could act on"
      end
    end
  end

  # --- the consequence ----------------------------------------------------

  # The claim this whole file rests on. If an app ever moves to structure.sql,
  # this fails and the exception for it can go.
  def test_the_apps_are_on_the_format_that_cannot_dump_these
    APPS.each do |app|
      next if KNOWN.fetch(app).empty?

      assert_equal "ruby", schema_format(app),
                   "#{app} is on structure.sql now — its objects survive db:schema:load, so drop them from KNOWN"
    end
  end

  def test_the_schema_dump_really_does_not_contain_them
    APPS.each do |app|
      dump = schema(app) or next

      KNOWN.fetch(app).each_key do |name|
        refute_includes dump, name,
                        "#{app}/db/schema.rb mentions #{name} after all — the premise here is wrong"
      end
    end
  end

  # Every use of one of these objects must either guard or be reachable only
  # where migrations have run. An unguarded use in a request path is the one
  # shape that turns this from "untested" into "a 500".
  GUARDS = /data_source_exists\?|table_exists\?|rescue\b|skip\b/

  def test_no_request_path_touches_a_raw_object_without_a_guard
    unguarded = APPS.flat_map do |app|
      names = KNOWN.fetch(app).keys
      next [] if names.empty?

      Dir.glob(File.join(ROOT, app, "app", "controllers", "**", "*.rb")).filter_map do |path|
        body = File.read(path)
        hit = names.find { |name| body.include?(name) }
        next unless hit && !body.match?(GUARDS)

        "#{app}: #{path.sub("#{ROOT}/", '')} uses #{hit} with no existence check"
      end
    end

    assert_empty unguarded, unguarded.join("\n  ")
  end

  # The finding worth acting on, stated rather than asserted away: two of the
  # three consumers are guards, and a guard against an object the test schema
  # cannot contain is a body that has never run under test.
  def test_the_consumers_are_known_and_each_one_degrades_quietly
    consumers = {
      "brgen/app/models/post.rb" => :raises,
      "brgen/app/jobs/nightly_search_index_rebuild_job.rb" => :returns,
      "bsdports/app/models/port.rb" => :raises,
      "bsdports/app/services/ports/importer.rb" => :rescues,
    }

    consumers.each do |relative, behaviour|
      path = File.join(ROOT, relative)
      assert File.file?(path), "#{relative} is gone; update this inventory"
      body = File.read(path)

      case behaviour
      when :returns
        assert_match(/return unless.*(?:data_source_exists\?|table_exists\?)/, body,
                     "#{relative} no longer guards; it now raises in every schema-loaded environment")
      when :rescues
        assert_match(/rescue StandardError/, body, "#{relative} no longer rescues")
      when :raises
        refute_match(GUARDS, body[/scope :search.*?\}/m].to_s,
                     "#{relative} grew a guard — say so here, because a silent empty result " \
                     "is worse than a raise for a search box")
      end
    end
  end
end
