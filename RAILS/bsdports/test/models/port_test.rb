# frozen_string_literal: true

require "test_helper"

# The tree's central record, and it had no test naming it.
#
# Everything bsdports does hangs off Port: the FTS search the index page runs,
# the uniqueness scope that lets one pkgpath exist once per platform, and the
# dependency edges in both directions. The reverse edge is the one worth
# pinning -- `dependents` and `reverse_deps` are declared with an explicit
# foreign key, which is the shape that silently resolves to the wrong column
# when an association is renamed.
class PortTest < ActiveSupport::TestCase
  setup do
    @platform = platforms(:openbsd)
    @category = Category.create!(platform: @platform, name: "net", slug: "net")
  end

  def port(name, **overrides)
    Port.create!({ platform: @platform, category: @category, name:,
                   pkgpath: "net/#{name}", version: "1.0" }.merge(overrides))
  end

  # --- validations --------------------------------------------------------

  test "a port needs a name, a version and a pkgpath" do
    blank = Port.new(platform: @platform, category: @category)

    refute blank.valid?
    assert_includes blank.errors.attribute_names, :name
    assert_includes blank.errors.attribute_names, :version
    assert_includes blank.errors.attribute_names, :pkgpath
  end

  # The unique index is on [platform_id, pkgpath], not on pkgpath alone: the
  # same port exists in every BSD tree and that is the point of the app.
  test "one pkgpath exists once per platform and once per other platform" do
    port("curl")
    duplicate = Port.new(platform: @platform, category: @category, name: "curl",
                         pkgpath: "net/curl", version: "2.0")

    refute duplicate.valid?
    assert_includes duplicate.errors.attribute_names, :pkgpath

    other = Platform.create!(name: "FreeBSD", slug: "freebsd")
    other_category = Category.create!(platform: other, name: "net", slug: "net")

    assert Port.new(platform: other, category: other_category, name: "curl",
                    pkgpath: "net/curl", version: "1.0").valid?,
           "the same pkgpath in another tree is a different port"
  end

  test "a maintainer is optional and a platform and category are not" do
    assert port("wget").valid?
    refute Port.new(category: @category, name: "x", pkgpath: "net/x", version: "1").valid?
    refute Port.new(platform: @platform, name: "x", pkgpath: "net/x", version: "1").valid?
  end

  # --- dependency edges ---------------------------------------------------

  test "dependencies run forwards and backwards from one edge" do
    git = port("git")
    gettext = port("gettext")
    Dependency.create!(port: git, depends_on: gettext, dep_type: "build")

    # Loaded explicitly rather than off the instance: Port is strict_loading,
    # which is deliberate -- brgen lost its chat rooms for weeks to a lazy load
    # in a strict_loading scope -- so a test that reads through the association
    # is testing the wrong thing anyway.
    assert_equal [ gettext ], Port.where(id: git.id).includes(:depends_on).first.depends_on.to_a
    assert_equal [ git ], Port.where(id: gettext.id).includes(:reverse_deps).first.reverse_deps.to_a,
                 "the reverse edge resolves through an explicit foreign key; a rename breaks it silently"
    assert_empty Port.where(id: git.id).includes(:reverse_deps).first.reverse_deps.to_a
    assert_empty Port.where(id: gettext.id).includes(:depends_on).first.depends_on.to_a
  end

  test "destroying a port takes both directions of its edges with it" do
    git = port("git")
    gettext = port("gettext")
    Dependency.create!(port: git, depends_on: gettext, dep_type: "build")

    assert_difference "Dependency.count", -1 do
      gettext.destroy!
    end
    assert_empty Dependency.where(port: git).to_a, "a dependency survived the port it pointed at"
  end

  # --- scopes -------------------------------------------------------------

  test "by_category and by_maintainer narrow to what they name" do
    other = Category.create!(platform: @platform, name: "devel", slug: "devel")
    keeper = Maintainer.create!(name: "Ingo")
    mine = port("curl", maintainer: keeper)
    theirs = port("make", category: other)

    assert_equal [ mine ], Port.by_category(@category).to_a
    assert_equal [ theirs ], Port.by_category(other).to_a
    assert_equal [ mine ], Port.by_maintainer(keeper).to_a
  end

  test "recent_updates orders by the commit date and lists a port once" do
    old = port("curl")
    fresh = port("wget")
    PortUpdate.create!(port: old, new_version: "2", committed_at: 3.days.ago)
    PortUpdate.create!(port: fresh, new_version: "2", committed_at: 1.hour.ago)
    PortUpdate.create!(port: fresh, new_version: "3", committed_at: 2.hours.ago)

    result = Port.recent_updates.to_a
    assert_equal [ fresh, old ], result, "the newest commit does not lead"
    assert_equal result.uniq, result, "a port with two updates appeared twice"
  end

  # --- full-text search ---------------------------------------------------
  #
  # ports_fts is an fts5 virtual table created by raw `execute` in
  # 20260528000100_create_ports_fts.rb, along with three triggers that keep it in
  # step with `ports`. schema_format is :ruby, and the Ruby schema dumper cannot
  # express a virtual table or a trigger, so db/schema.rb contains neither: every
  # database built by db:schema:load -- this test environment, and any freshly
  # provisioned box -- has no search index at all.
  #
  # Nothing shouts about it. Ports::Importer#rebuild_fts rescues StandardError
  # and logs a warning, and the ports index page searches with LIKE through
  # apply_live_search rather than through this scope, so the only visible symptom
  # is a search index that is never built.
  #
  # Skipped rather than deleted: the skip is the finding, stated where the method
  # is used. RAILS/test/raw_schema_objects_test.rb states it for the tree.
  FTS_ABSENT = "ports_fts is not in schema.rb — see RAILS/test/raw_schema_objects_test.rb"

  def fts_table? = Port.connection.table_exists?("ports_fts")

  # A MATCH against an empty index must return nothing, not everything.
  # `ids.any? ? where(id: ids) : none` is what makes that true; a bare
  # `where(id: ids)` would have looked identical and returned the whole table.
  test "a search that matches nothing returns nothing" do
    skip FTS_ABSENT unless fts_table?
    port("curl")

    assert_empty Port.search("a_term_that_matches_no_port").to_a
  end

  test "semantic_search is still the lexical search and says so" do
    skip FTS_ABSENT unless fts_table?

    assert_equal Port.search("curl").to_sql, Port.semantic_search("curl").to_sql
  end

  # --- instance methods ---------------------------------------------------

  test "latest_update is the newest by commit date rather than by insertion" do
    curl = port("curl")
    PortUpdate.create!(port: curl, new_version: "3", committed_at: 1.day.ago)
    newest = PortUpdate.create!(port: curl, new_version: "2", committed_at: 1.hour.ago)

    assert_equal newest, curl.latest_update
  end

  test "latest_update is nil for a port nobody has committed to" do
    assert_nil port("curl").latest_update
  end

  test "watched_by? answers for the user who watches and the one who does not" do
    curl = port("curl")
    watcher = User.strict_loading(false).create!(email_address: "a@example.com", password: "password123")
    bystander = User.strict_loading(false).create!(email_address: "b@example.com", password: "password123")
    Watch.create!(user: watcher, port: curl)

    assert curl.watched_by?(watcher)
    refute curl.watched_by?(bystander)
  end
end
