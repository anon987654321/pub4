# frozen_string_literal: true

require "test_helper"

# Category is the only bsdports model with a before_validation callback, and the
# callback is `self.slug ||= name.parameterize` on create only. Two things follow
# that nothing checked: an update never regenerates the slug (deliberate -- the
# slug is the URL), and a name that parameterizes to nothing leaves the record
# invalid rather than saving a blank slug.
class CategoryTest < ActiveSupport::TestCase
  setup { @platform = platforms(:openbsd) }

  def category(**overrides)
    Category.new({ platform: @platform, name: "Networking" }.merge(overrides))
  end

  test "a slug is derived from the name when none is given" do
    record = category
    record.validate

    assert_equal "networking", record.slug
  end

  test "an explicit slug is not overwritten" do
    assert_equal "net", category(slug: "net").tap(&:validate).slug
  end

  # The slug is the URL. Renaming a category must not move its page.
  test "renaming a category leaves its slug where it was" do
    record = category(name: "Networking")
    record.save!
    record.update!(name: "Internet")

    assert_equal "networking", record.reload.slug
  end

  test "a name that parameterizes to nothing is refused rather than saved blank" do
    record = category(name: "///")

    refute record.valid?
    assert_includes record.errors.attribute_names, :slug
  end

  test "a slug must be lowercase alphanumeric and hyphens" do
    %w[Net net_work net.work "net work"].each do |slug|
      refute category(slug:).valid?, "#{slug.inspect} was accepted as a slug"
    end
    %w[net net-work net2].each do |slug|
      assert category(slug:).valid?, "#{slug.inspect} was refused"
    end
  end

  test "a slug is unique per platform and free across platforms" do
    category(slug: "net").save!

    refute category(slug: "net").valid?

    other = Platform.create!(name: "NetBSD", slug: "netbsd")
    assert Category.new(platform: other, name: "Networking", slug: "net").valid?,
           "every BSD tree has a net category; that is not a collision"
  end

  test "a category belongs to a platform" do
    refute Category.new(name: "Networking", slug: "net").valid?
  end

  test "to_param puts the slug in the URL rather than the id" do
    record = category(slug: "net")
    record.save!

    assert_equal "net", record.to_param
  end

  # nullify, not destroy: losing a category must not delete the ports in it.
  test "destroying a category releases its ports rather than deleting them" do
    record = category(slug: "net")
    record.save!
    port = Port.create!(platform: @platform, category: record, name: "curl",
                        pkgpath: "net/curl", version: "1")

    assert_no_difference "Port.count" do
      record.destroy!
    end
    assert_nil port.reload.category_id
  end
end
