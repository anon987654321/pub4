# frozen_string_literal: true

require "test_helper"

# Advisories arrive from a nightly NVD cross-reference and render inside
# ports/show. The model's own header records that two Turbo broadcasts were
# removed from it because neither had a partial, a target, or a subscriber --
# so what is left is a plain record whose whole behaviour is its enum, its two
# scopes, and a uniqueness rule that has to tolerate blanks.
class SecurityAdvisoryTest < ActiveSupport::TestCase
  setup do
    @platform = platforms(:openbsd)
    @category = Category.create!(platform: @platform, name: "net", slug: "net")
    @port = Port.create!(platform: @platform, category: @category, name: "curl",
                         pkgpath: "net/curl", version: "1")
  end

  def advisory(**overrides)
    SecurityAdvisory.new({ title: "buffer overflow in curl" }.merge(overrides))
  end

  test "an advisory needs a title" do
    refute advisory(title: nil).valid?
  end

  # An advisory is a fact about a CVE; port relationships live in the join,
  # so an advisory is valid before any package is linked.
  test "an advisory can exist without a linked port" do
    record = advisory
    assert record.valid?
    assert_empty record.ports
  end

  test "one CVE can be linked to multiple affected ports" do
    other = Port.create!(platform: @platform, category: @category, name: "curl-compat",
                         pkgpath: "net/curl-compat", version: "1")
    record = advisory(identifier: "CVE-2026-44001").tap(&:save!)

    record.ports << @port
    record.ports << other

    # Read back through queries: strict loading refuses a lazy association read in every environment.
    assert_equal [ @port.id, other.id ].sort, SecurityAdvisoryPort.where(security_advisory: record).pluck(:port_id).sort
    [ @port, other ].each do |port|
      assert_includes SecurityAdvisory.joins(:security_advisory_ports).where(security_advisory_ports: { port: }), record
    end
  end

  test "the four severities are ordered from low to critical" do
    assert_equal %w[low medium high critical], SecurityAdvisory.severities.keys
    assert_equal (0..3).to_a, SecurityAdvisory.severities.values
  end

  test "an advisory with no stated severity defaults to medium" do
    record = advisory
    assert_equal "medium", record.severity
    assert record.valid?
  end

  test "a nil severity is invalid" do
    refute advisory(severity: nil).valid?
  end

  test "negative severity scope does not hide valid records" do
    medium = advisory(severity: :medium).tap(&:save!)
    critical = advisory(identifier: "CVE-2026-0005", severity: :critical).tap(&:save!)

    assert_equal [ medium ], SecurityAdvisory.not_critical.to_a
    refute SecurityAdvisory.not_critical.include?(critical)
  end

  test "each severity round-trips through its predicate" do
    SecurityAdvisory.severities.each_key do |name|
      record = advisory(severity: name)
      assert record.public_send("#{name}?"), "#{name}? is false for a #{name} advisory"
    end
  end

  # CVE ids are unique. Blank is not an id, and refusing a second blank would
  # drop every advisory that has not been assigned one yet.
  test "an identifier is unique but a missing one is not a collision" do
    advisory(identifier: "CVE-2026-0001").save!

    refute advisory(identifier: "CVE-2026-0001").valid?
    assert advisory(identifier: nil).tap { |a| a.save! }.persisted?
    assert advisory(identifier: "").valid?, "two advisories awaiting an id are not duplicates"
  end

  test "active holds the advisories nobody has resolved" do
    open_one = advisory(identifier: "CVE-2026-0002").tap(&:save!)
    advisory(identifier: "CVE-2026-0003", resolved_at: Time.current).save!

    assert_equal [ open_one ], SecurityAdvisory.active.to_a
  end

  test "recent leads with the newest publication" do
    old = advisory(identifier: "a", published_at: 10.days.ago).tap(&:save!)
    fresh = advisory(identifier: "b", published_at: 1.hour.ago).tap(&:save!)

    assert_equal [ fresh, old ], SecurityAdvisory.recent.to_a
  end

  test "destroying a port removes only its relationship to an advisory" do
    record = advisory(identifier: "CVE-2026-0004").tap(&:save!)
    record.ports << @port

    assert_difference "SecurityAdvisoryPort.count", -1 do
      @port.destroy!
    end
    assert SecurityAdvisory.exists?(record.id), "an advisory must survive loss of one affected port"
  end
end
