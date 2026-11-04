# frozen_string_literal: true

require "test_helper"

# Version-history and advisory dates were strftime("%Y-%m-%d") in a bare
# <small>, unlocalised and with no machine date, and a port row's
# "updated 12d ago" had neither a datetime nor the date itself.
class PortDatesTest < ActionDispatch::IntegrationTest
  setup do
    platform = platforms(:openbsd)
    category = Category.create!(platform:, name: "devel", slug: "devel")
    @port = Port.create!(platform:, category:, name: "git", version: "2.45", pkgpath: "devel/git",
                         last_updated: Date.new(2026, 10, 1))
    @committed = Time.zone.local(2026, 9, 14, 12)
    @port.port_updates.create!(old_version: "2.44", new_version: "2.45", committed_at: @committed)
    advisory = SecurityAdvisory.create!(title: "CVE-2026-1", identifier: "CVE-2026-1", published_at: @committed)
    SecurityAdvisoryPort.create!(security_advisory: advisory, port: @port)
  end

  test "port page dates are localised time elements" do
    get port_path(@port, locale: "nb")
    assert_response :success
    assert_select "small time[datetime=?]", @committed.iso8601, text: I18n.l(@committed.to_date, locale: :nb), count: 2
    assert_not_includes response.body, "2026-09-14<"
  end

  test "a port row carries the update date" do
    get ports_path
    assert_select "li.port-row time[datetime='2026-10-01'][title=?]", I18n.l(Date.new(2026, 10, 1))
  end
end
