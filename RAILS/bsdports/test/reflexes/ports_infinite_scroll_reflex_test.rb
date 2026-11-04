# frozen_string_literal: true

require "test_helper"

# The index searched with Port.search (pkgpaths, maintainers, categories,
# dependencies, advisories); the reflex that appends page 2 searched only
# name, comment and description with LIKE. A search for a maintainer showed
# their ports on page 1 and then appended an unrelated or empty page 2.
class PortsInfiniteScrollReflexTest < ActiveSupport::TestCase
  setup do
    platform = platforms(:openbsd)
    category = Category.create!(platform:, name: "net", slug: "net")
    maintainer = Maintainer.create!(name: "Ola Nordmann")
    @ports = Array.new(3) do |index|
      Port.create!(platform:, category:, name: "tool#{index}", version: "1",
                   pkgpath: "net/tool#{index}", maintainer:)
    end
    Port.create!(platform:, category:, name: "other", version: "1", pkgpath: "net/other")
  end

  def reflex_scope(dataset)
    reflex = PortsInfiniteScrollReflex.allocate
    reflex.define_singleton_method(:element) { Struct.new(:dataset).new(dataset) }
    reflex.send(:scope)
  end

  test "later pages match the same ports as the first page's search" do
    paged = reflex_scope("q" => "Ola Nordmann").to_a

    assert_equal Port.search("Ola Nordmann").order(:name).to_a, paged
    assert_equal @ports, paged
  end
end
