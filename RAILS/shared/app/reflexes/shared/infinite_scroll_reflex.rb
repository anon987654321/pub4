# frozen_string_literal: true

module Shared
  class InfiniteScrollReflex < Shared::ApplicationReflex
    if defined?(Pagy::Method)
      include Pagy::Method
    elsif defined?(Pagy::Backend)
      include Pagy::Backend
    end

    def load_more
      morph :nothing
      cable_ready.insert_adjacent_html(
        selector: selector,
        position: position,
        html: page_html
      ).broadcast

      if @pagy&.next
        cable_ready
          .set_attribute(selector: selector, name: "data-next-page", value: @pagy.next)
          .broadcast
      else
        cable_ready.remove(selector: selector).broadcast
      end

      # Always clear loading state for Hotwire/Stimulus integration
      cable_ready
        .set_attribute(selector: selector, name: "data-loading", value: "false")
        .broadcast

      # Dispatch for additional Stimulus/Hotwire listeners (e.g. re-init controllers)
      cable_ready
        .dispatch_event(name: "infinite-scroll:updated", detail: { id: element.id })
        .broadcast
    end

    def page
      element.dataset["next_page"].to_i
    end

    def position
      "beforebegin"
    end

    def selector
      "##{element.id}"
    end

    private

    def page_html
      raise NotImplementedError, "#{self.class} must implement #page_html"
    end
  end
end