# frozen_string_literal: true

require "test_helper"

# The categories and maintainers indexes used includes(:ports) and
# ports.size, loading every port row of every listed category or
# maintainer to print how many there were.
class PortCountsTest < ActionDispatch::IntegrationTest
  setup do
    platform = platforms(:openbsd)
    @category = Category.create!(platform:, name: "devel", slug: "devel")
    @maintainer = Maintainer.create!(name: "Jane Porter")
    %w[git gettext].each do |name|
      Port.create!(platform:, category: @category, name:, version: "1", pkgpath: "devel/#{name}",
                   maintainer_id: @maintainer.id)
    end
  end

  test "both indexes print the count without loading the ports" do
    [ categories_path, maintainers_path ].each do |path|
      loads = port_row_loads { get path }
      assert_response :success
      assert_includes response.body, I18n.t("ports.port_count", count: 2), path
      assert_equal 0, loads, "#{path} loaded port rows"
    end
  end

  private

  def port_row_loads(&)
    loads = 0
    counter = ->(*, payload) { loads += 1 if payload[:sql].start_with?('SELECT "ports".*') }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &)
    loads
  end
end
