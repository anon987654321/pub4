# frozen_string_literal: true

require "test_helper"

class NvdCveTest < ActiveSupport::TestCase
  setup do
    @platform = platforms(:openbsd)
    @category = Category.create!(platform: @platform, name: "nvd-test", slug: "nvd-test")
    @first = Port.create!(platform: @platform, category: @category, name: "alpha",
                          pkgpath: "security/alpha", version: "1")
    @second = Port.create!(platform: @platform, category: @category, name: "beta",
                           pkgpath: "security/beta", version: "1")
  end

  test "one CVE discovered for two ports remains one advisory linked to both" do
    payload = {
      "id" => "CVE-2026-44002",
      "descriptions" => [{ "value" => "A sample vulnerability affecting multiple packages" }],
      "published" => "2026-09-01T12:00:00.000",
      "metrics" => { "cvssMetricV31" => [{ "cvssData" => { "baseScore" => 8.1 } }] }
    }

    first_record = NvdCve.new(@first).send(:record, payload)
    second_record = NvdCve.new(@second).send(:record, payload)

    assert_equal first_record.id, second_record.id
    assert_equal 1, SecurityAdvisory.where(identifier: "CVE-2026-44002").count
    assert_equal [ @first.id, @second.id ].sort, first_record.ports.pluck(:id).sort
  end
end
