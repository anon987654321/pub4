# frozen_string_literal: true

require "test_helper"

# Ports carry both a `maintainer` string and a `maintainer_id`. The string is
# what the ports tree ships; the record is what this app resolves it to, and the
# label is how it renders back. A maintainer that loses their ports on destroy
# would delete packages because a person left, which is why the association is
# nullify.
class MaintainerTest < ActiveSupport::TestCase
  test "a maintainer needs a name" do
    refute Maintainer.new(email: "a@example.com").valid?
    assert Maintainer.new(name: "Ingo").valid?
  end

  test "a name is unique" do
    Maintainer.create!(name: "Ingo")

    refute Maintainer.new(name: "Ingo").valid?
  end

  # Plenty of ports name a maintainer with no usable address. Refusing them
  # would drop the attribution entirely.
  test "an address is optional and checked when present" do
    assert Maintainer.new(name: "Ingo").valid?
    assert Maintainer.new(name: "Theo", email: "").valid?
    assert Maintainer.new(name: "Marc", email: "marc@example.org").valid?
    refute Maintainer.new(name: "Bob", email: "not-an-address").valid?
  end

  test "the label carries the address when there is one" do
    assert_equal "Ingo <ingo@example.org>", Maintainer.new(name: "Ingo", email: "ingo@example.org").label
    assert_equal "Ingo", Maintainer.new(name: "Ingo").label
    assert_equal "Ingo", Maintainer.new(name: "Ingo", email: "").label
  end

  test "active selects only the maintainers still taking ports" do
    current = Maintainer.create!(name: "Ingo")
    retired = Maintainer.create!(name: "Theo", active: false)

    assert_includes Maintainer.active, current
    refute_includes Maintainer.active, retired
  end

  test "a maintainer is active unless someone says otherwise" do
    assert Maintainer.create!(name: "Ingo").active?
  end

  # nullify: a person leaving does not delete their packages.
  test "destroying a maintainer releases their ports rather than deleting them" do
    platform = platforms(:openbsd)
    category = Category.create!(platform:, name: "net", slug: "net")
    maintainer = Maintainer.create!(name: "Ingo")
    port = Port.create!(platform:, category:, maintainer:, name: "curl",
                        pkgpath: "net/curl", version: "1")

    assert_no_difference "Port.count" do
      maintainer.destroy!
    end
    assert_nil port.reload.maintainer_id
  end
end
