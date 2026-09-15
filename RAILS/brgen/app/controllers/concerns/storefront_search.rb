# frozen_string_literal: true

# The one search on markedsplass and takeaway: the field in the storefront
# header, the results in the page under it. Amazon, the functional model, has a
# single field in its bar, and these pages carried a second copy in the body
# with the same placeholder — the header's did a full page load and the body's
# streamed results, below the fold.
#
# The ids are declared here because three sides meet on them: the header form
# that the page's filter controls join through their form attribute, the region
# the stream updates, and the controller that streams. brgen's search palette
# already owns #live_search_results and #search_suggestions ahead of <main> on
# every page, and a Turbo Stream lands on the first id in the document.
module StorefrontSearch
  extend ActiveSupport::Concern

  FORM = "storefront-search"
  RESULTS = "storefront-results"
  SUGGESTIONS = "storefront-suggestions"

  included do
    include Shared::LiveSearchable
  end

  private

  def finish_storefront_search(partial:)
    finish_live_search(partial:, target: RESULTS, suggestions: SUGGESTIONS)
  end
end
