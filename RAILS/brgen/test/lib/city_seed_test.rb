# frozen_string_literal: true

require "test_helper"
require "brgen/domain_registry"
require "brgen/city_seed"

class CitySeedTest < ActiveSupport::TestCase
  def rows
    @rows ||= Brgen::CitySeed.rows_from_registry
  end

  def by_domain
    @by_domain ||= rows.index_by(&:domain)
  end

  test "every registry domain has non-zero coordinates" do
    domains = Brgen::DomainRegistry::ENTRIES.map(&:domain)
    assert_equal domains.sort, rows.map(&:domain).sort
    assert_equal domains.sort, Brgen::CitySeed::COORDINATES.keys.sort
    assert_equal domains.sort, Brgen::CitySeed::TIME_ZONES.keys.sort

    rows.each do |row|
      refute_equal 0, row.latitude, "#{row.domain} latitude is 0"
      refute_equal 0, row.longitude, "#{row.domain} longitude is 0"
    end
  end

  test "no two cities share 0,0" do
    origins = rows.select { |row| row.latitude.zero? && row.longitude.zero? }
    assert_empty origins.map(&:domain)
  end

  test "US eastern cities are not America/Los_Angeles" do
    %w[newyrk.us wshingtondc.com dtroit.us].each do |domain|
      refute_equal "America/Los_Angeles", by_domain.fetch(domain).time_zone, domain
    end
    assert_equal "America/New_York", by_domain.fetch("newyrk.us").time_zone
    assert_equal "America/New_York", by_domain.fetch("wshingtondc.com").time_zone
    assert_equal "America/Detroit", by_domain.fetch("dtroit.us").time_zone
  end
end
