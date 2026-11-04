# frozen_string_literal: true

require "test_helper"

# The empty catalogue stated its last import as a clock time and the raw
# status ("failed, 14:02") while the header said "3 hours ago" for the
# same fact.
class EmptyCatalogueImportLineTest < ActionDispatch::IntegrationTest
  test "the empty list words the last import as the header does" do
    Port.delete_all
    started = 3.hours.ago
    ImportRun.create!(platform: platforms(:openbsd), status: "failed", started_at: started, ports_count: 0)

    get root_url(locale: "nb")
    assert_response :success
    status = I18n.t("ports.import_status.failed", locale: :nb)
    ago = ApplicationController.helpers.time_ago_in_words(started, locale: :nb)
    line = I18n.t("ports.last_import", status:, count: 0, when: ago, locale: :nb)
    assert_includes response.body, line
    assert_not_includes response.body, I18n.l(started, format: :short, locale: :nb)
  end
end
