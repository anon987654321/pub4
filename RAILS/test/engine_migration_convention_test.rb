# frozen_string_literal: true

require "minitest/autorun"

# A migration in the engine runs nowhere, and nothing said so.
#
# shared/lib/shared/engine.rb declared config.paths["db/migrate"] and no app read
# it: db:migrate:status in all three lists only that app's own migrations. The
# three files under shared/db/migrate have per-app equivalents doing the real work.
# On 2026-08-11 a migration for outbound_clicks was written there, created no
# table in any app, and the beacon that writes to it would have failed silently
# behind a rescue — the declaration read as wiring and was decoration.
#
# The convention is one migration per app. This test is what makes the convention
# enforceable rather than remembered.
class EngineMigrationConventionTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  APPS = %w[amber brgen bsdports].freeze

  # The three that predate the convention. They are history, not a pattern to copy.
  HISTORICAL = %w[
    20260524000200_create_shared_social_tables.rb
    20260615120000_add_guest_to_users.rb
    20260625140000_create_anonymous_post_quotas.rb
  ].freeze

  def test_no_new_migration_is_added_to_the_engine
    present = Dir.glob(File.join(ROOT, "shared/db/migrate/*.rb")).map { |path| File.basename(path) }.sort

    assert_equal HISTORICAL.sort, present,
                 "a migration here runs in no app — db:migrate:status lists only each app's own. " \
                 "Put one file per app in <app>/db/migrate instead, and if this list is genuinely " \
                 "meant to grow, wire the engine path first and prove it with db:migrate:status."
  end

  # The inverse: the declaration must stay gone, or the next reader trusts it.
  def test_the_engine_declares_no_migration_path
    engine = File.read(File.join(ROOT, "shared/lib/shared/engine.rb"))
    code = engine.lines.reject { |line| line.strip.start_with?("#") }.join

    refute_match(/config\.paths\["db\/migrate"\]/, code,
                 "this path is not read by any app; a declaration nothing reads is worse than " \
                 "no declaration, because it looks like wiring")
  end

  # What replaced it: every app carries the outbound_clicks migration itself, and
  # its schema knows the table. A missing one is a beacon writing to nothing.
  def test_every_app_carries_the_shared_tables_it_needs
    APPS.each do |app|
      migration = Dir.glob(File.join(ROOT, app, "db/migrate/*_create_outbound_clicks.rb"))
      refute_empty migration, "#{app} has no outbound_clicks migration"

      schema = File.read(File.join(ROOT, app, "db/schema.rb"))
      assert_includes schema, "outbound_clicks",
                      "#{app}/db/schema.rb has no outbound_clicks table — the migration was " \
                      "written but never run, so the beacon writes to nothing"
    end
  end
end
