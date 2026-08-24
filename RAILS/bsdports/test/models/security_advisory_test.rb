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

  # A port is optional: an advisory can name a library this tree does not
  # package yet, and dropping it because of that loses the warning.
  test "an advisory without a port is still an advisory" do
    assert advisory.valid?
    assert advisory(port: @port).valid?
  end

  test "the four severities are ordered from low to critical" do
    assert_equal %w[low medium high critical], SecurityAdvisory.severities.keys
    assert_equal (0..3).to_a, SecurityAdvisory.severities.values
  end

  test "an advisory with no stated severity is medium" do
    assert_equal "medium", advisory.tap(&:validate).severity
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

  test "destroying a port takes its advisories with it" do
    advisory(port: @port, identifier: "CVE-2026-0004").save!

    assert_difference "SecurityAdvisory.count", -1 do
      @port.destroy!
    end
  end
end
