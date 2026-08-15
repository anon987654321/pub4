# frozen_string_literal: true

require "test_helper"

# Platform is the tenant boundary of this app: every category, port and import
# run hangs off one, and the three named finders are how the rest of the code
# gets hold of one. They use find_by!, so an absent tree raises rather than
# returning nil into a chain -- worth pinning, because the nil version of that
# mistake surfaces three frames later as an unrelated NoMethodError.
class PlatformTest < ActiveSupport::TestCase
  test "a platform needs a name and a slug" do
    blank = Platform.new

    refute blank.valid?
    assert_includes blank.errors.attribute_names, :name
    assert_includes blank.errors.attribute_names, :slug
  end

  # No hyphens, unlike Category: these are openbsd/freebsd/netbsd and the finders
  # below hard-code exactly those spellings. Slugs here avoid the fixture's
  # `openbsd`, so a uniqueness failure cannot be read as a format one.
  test "a slug is lowercase alphanumeric with no separators" do
    %w[freebsd netbsd2].each { |slug| assert Platform.new(name: "x", slug:).valid?, "#{slug} refused" }
    ["free-bsd", "free_bsd", "FreeBSD", "free bsd"].each do |slug|
      refute Platform.new(name: "x", slug:).valid?, "#{slug.inspect} accepted"
    end
  end

  test "a slug is unique across the whole table" do
    refute Platform.new(name: "Another OpenBSD", slug: "openbsd").valid?
  end

  test "active selects only the platforms marked active" do
    dormant = Platform.create!(name: "NetBSD", slug: "netbsd", active: false)

    assert_includes Platform.active, platforms(:openbsd)
    refute_includes Platform.active, dormant
  end

  # find_by!, not find_by: an absent tree must raise here rather than return nil
  # into a chain and surface three frames later as a NoMethodError.
  test "each named finder returns its tree or raises" do
    assert_equal platforms(:openbsd), Platform.openbsd

    assert_raises(ActiveRecord::RecordNotFound) { Platform.freebsd }
    assert_raises(ActiveRecord::RecordNotFound) { Platform.netbsd }
  end

  # A finder whose slug this model would refuse can never find anything.
  test "every named finder looks for a slug the format allows" do
    %i[openbsd freebsd netbsd].each do |tree|
      assert_respond_to Platform, tree
      assert_match(/\A[a-z0-9]+\z/, tree.to_s,
                   "Platform.#{tree} looks for a slug this model's format rejects")
    end
  end

  # destroy, not nullify: a tree that is gone takes its ports with it, because a
  # port with no platform is not a port.
  test "destroying a platform takes its categories, ports and import runs" do
    platform = Platform.create!(name: "NetBSD", slug: "netbsd")
    category = Category.create!(platform:, name: "net", slug: "net")
    Port.create!(platform:, category:, name: "curl", pkgpath: "net/curl", version: "1")
    ImportRun.create!(platform:, status: "succeeded", started_at: Time.current)

    assert_difference ["Port.count", "Category.count", "ImportRun.count"], -1 do
      platform.destroy!
    end
  end
end
