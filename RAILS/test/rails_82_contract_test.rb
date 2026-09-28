# frozen_string_literal: true

require "minitest/autorun"

class Rails82ContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  APPS = %w[brgen amber bsdports eritel].freeze
  RAILS_ROOTS = APPS + ["MASTER/web"]
  RAILS_REF = "c9e85dbe297e248dd2f217d04f84a94881ac046a"

  def read(path)
    File.read(File.join(ROOT, path))
  end

  test "all Rails apps stay on the same 8.2 framework-default baseline" do
    APPS.each do |app|
      source = read("#{app}/config/application.rb")

      assert_includes source, "config.load_defaults 8.2",
                      "#{app} drifted from the Rails 8.2 baseline"
      refute_includes source, "config.load_defaults 8.1",
                      "#{app} still carries the Rails 8.1 baseline"
    end
  end

  test "no app overrides HTML+ERB back to Erubi after the 8.2 cutover" do
    APPS.each do |app|
      source = Dir.glob(File.join(ROOT, app, "config/**/*.rb")).map { |path| File.read(path) }.join("\n")

      refute_match(/erb_implementation\s*=\s*:erubi/, source,
                   "#{app} has an explicit Erubi override that would hide the 8.2 Herb migration")
    end
  end

  test "Brgen covers both modern header and legacy form CSRF writes" do
    source = read("brgen/test/controllers/session_boundaries_test.rb")

    assert_includes source, '"X-CSRF-Token"'
    assert_includes source, "authenticity_token:"
    assert_includes source, "a write without an authenticity token is refused"
  end

  test "audited enum fields are non-null at the persistence boundary" do
    advisory_schema = read("bsdports/db/schema.rb")
    advisory_model = read("bsdports/app/models/security_advisory.rb")

    assert_includes advisory_schema, 't.integer "severity", default: 1, null: false'
    assert_includes advisory_model, "validates :title, :severity, presence: true"

    declarations = [
      ["eritel/db/migrate/20260925000100_create_domains.rb", 't.string :state, null: false, default: "pending"'],
      ["eritel/db/migrate/20260925000300_create_participants_registrants_orders.rb", "t.string :kind, null: false"],
      ["eritel/db/migrate/20260925000300_create_participants_registrants_orders.rb", 't.string :status, null: false, default: "pending"'],
      ["eritel/db/migrate/20260925000300_create_participants_registrants_orders.rb", 't.string :verification_status, null: false, default: "pending"'],
      ["eritel/db/migrate/20260925000300_create_participants_registrants_orders.rb", "t.string :operation, null: false"],
      ["eritel/db/migrate/20260925000300_create_participants_registrants_orders.rb", 't.string :state, null: false, default: "pending"']
    ].uniq.each do |path, declaration|
      assert_includes read(path), declaration
    end

    {
      "eritel/app/models/domain.rb" => %w[state],
      "eritel/app/models/participant.rb" => %w[kind status],
      "eritel/app/models/registrant.rb" => %w[verification_status],
      "eritel/app/models/order.rb" => %w[operation state],
      "eritel/app/models/registry_operation.rb" => %w[state]
    }.each do |path, fields|
      source = read(path)
      fields.each do |field|
        assert_match(/validates .*#{field}.*presence/, source, "#{path} allows nil enum #{field}")
      end
    end
  end

  test "Active Storage limits and processing are record-side and post-commit" do
    application_record = read("shared/app/models/application_record.rb")
    limits = read("shared/app/models/concerns/shared/attachment_limits.rb")
    processing = read("shared/app/models/concerns/shared/media_processable.rb")

    assert_includes application_record, "include Shared::AttachmentLimits"
    assert_includes limits, "validate :new_attachments_within_limits"
    assert_includes processing, "after_commit :enqueue_media_variant_processing"
  end

  test "transaction-sensitive job producers enqueue from commit callbacks" do
    {
      "brgen/app/models/post.rb" => "after_commit :federate_creation",
      "shared/app/models/concerns/shared/link_embeddable.rb" => "after_commit :resolve_link_embed_later",
      "amber/app/models/message.rb" => "after_create_commit :enqueue_master_reply",
      "brgen/app/models/notification.rb" => "after_create_commit",
      "brgen/app/models/repost.rb" => "after_create_commit :federate",
      "brgen/app/models/message.rb" => "after_create_commit :maybe_summon_bot",
      "brgen/engines/marketplace/app/models/marketplace/listing.rb" => "after_create_commit :queue_ranking_recalculation"
    }.each do |path, callback|
      source = read(path)

      assert_includes source, callback
      assert_match(/perform_later/, source, "#{path} declares a commit callback but no delayed producer")
    end
  end

  test "SQLite foreign-key rebuild migrations restore enforcement" do
    migrations = %w[
      brgen/db/migrate/20260623221000_fix_dating_foreign_keys.rb
      brgen/db/migrate/20260623220000_fix_marketplace_order_foreign_keys.rb
      brgen/db/migrate/20260623222000_fix_takeaway_order_item_foreign_keys.rb
      amber/db/migrate/20260625000100_fix_follows_foreign_keys.rb
    ]

    migrations.each do |path|
      source = read(path)

      assert_match(/PRAGMA\s+foreign_keys\s*=\s*OFF/i, source, "#{path} never disables SQLite FK enforcement for its rebuild")
      assert_match(/PRAGMA\s+foreign_keys\s*=\s*ON/i, source, "#{path} never restores SQLite FK enforcement")
    end
  end

test "every Rails Gemfile is pinned to the audited 8.2 source commit" do
    RAILS_ROOTS.each do |root|
      source = File.read(File.join(File.expand_path("..", ROOT), root, "Gemfile"))
      assert_includes source, 'gem "rails", github: "rails/rails", ref: "' + RAILS_REF + '"',
                      "#{root}/Gemfile drifted from the exact Rails edge pin"
    end
  end

  test "every locked Rails app names the audited git revision" do
    %w[RAILS/brgen RAILS/amber RAILS/bsdports MASTER/web].each do |root|
      source = File.read(File.join(File.expand_path("..", ROOT), root, "Gemfile.lock"))
      assert_match(/^  revision: #{Regexp.escape(RAILS_REF)}$/m, source)
      assert_match(/^    rails \(8\.2\.0\.alpha\)$/m, source)
    end
  end


  test "locked dependency graph carries the Rails 8.2 runtime floors" do
    %w[RAILS/brgen RAILS/amber RAILS/bsdports MASTER/web].each do |root|
      source = File.read(File.join(File.expand_path("..", ROOT), root, "Gemfile.lock"))
      assert_includes source, "    herb (0.10.2)"
      assert_includes source, "    ractor-dispatch (0.3.0)"
      assert_includes source, "    marcel (2.1.0)"
      assert_includes source, "    globalid (1.4.0)"
      assert_includes source, "actionpack (= 8.2.0.alpha)"
      assert_includes source, "activejob (= 8.2.0.alpha)"
    end
  end

  test "repository contains no stale Rails 8.1 Gemfile or default pin" do
    RAILS_ROOTS.each do |root|
      root_path = File.join(File.expand_path("..", ROOT), root)
      gemfile = File.read(File.join(root_path, "Gemfile"))
      application = File.read(File.join(root_path, "config", "application.rb"))

      refute_includes gemfile, "8.1.4"
      refute_includes application, "config.load_defaults 8.1"
    end
  end

end