# frozen_string_literal: true

module Shared
  # The spine every infinite-scroll reflex shares: paginate a scope, render one
  # partial per row, append, and tell the sentinel where it got to.
  #
  # Twenty-one subclasses across the three apps each carried their own copy of
  # the first two steps -- an identical `load_more` that paginated and called
  # super, and a `page_html` that differed only in a partial path and a local
  # name. The scope is the only thing that was ever really different, so that is
  # the only thing a subclass writes now, alongside one `renders` line.
  #
  # A reflex that needs more than the pattern has three seams rather than a copy
  # of the spine: `after_paginate` for work between pagination and rendering,
  # `row_locals` for a partial that takes more than the record, and `after_row`
  # for markup interleaved between rows.
  #
  # `after_row` exists because the home feed had no seam that fit and overrode
  # `page_html` instead — the one method the contract test names as re-implementing
  # the spine. It needed to interleave an affiliate unit every Nth row, which
  # neither of the other two seams can express, so the copy was the only way to
  # say it. A seam here says it once for all twenty-one subclasses.
  class InfiniteScrollReflex < Shared::ApplicationReflex
    if defined?(Pagy::Method)
      include Pagy::Method
    elsif defined?(Pagy::Backend)
      include Pagy::Backend
    end

    class << self
      attr_reader :row_partial, :row_local, :row_wrapper

      # renders "posts/post", as: :post
      # wrap_in: :li when the container this appends into is a list. The
      # feeds became ul/li so screen readers announce them; page_html joins
      # raw partials, so without this the first page was list items and every
      # appended page was bare articles inside a ul.
      def renders(partial, as:, wrap_in: nil)
        @row_partial = partial
        @row_local = as
        @row_wrapper = wrap_in
      end

      # Subclasses of subclasses would otherwise lose the declaration.
      def inherited(child)
        super
        child.instance_variable_set(:@row_wrapper, @row_wrapper)
        child.instance_variable_set(:@row_partial, @row_partial)
        child.instance_variable_set(:@row_local, @row_local)
      end
    end

    def load_more
      @pagy, @records = pagy(scope, page:, request:)
      after_paginate

      morph :nothing
      cable_ready.insert_adjacent_html(
        selector:,
        position:,
        html: page_html,
      ).broadcast

      if @pagy&.next
        cable_ready
          .set_attribute(selector:, name: "data-next-page", value: @pagy.next)
          .broadcast
      else
        cable_ready.remove(selector:).broadcast
      end

      # Always clear loading state for Hotwire/Stimulus integration
      cable_ready
        .set_attribute(selector:, name: "data-loading", value: "false")
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

    # The `q` filter these scopes reach for, spelled once. It was retyped in
    # sixteen files, each rebuilding the same escaped LIKE term by hand.
    def like_term(key = "q")
      value = element.dataset[key]
      return nil if value.blank?

      "%#{ActiveRecord::Base.sanitize_sql_like(value)}%"
    end

    private

    # The one thing that genuinely differs between reflexes.
    def scope
      raise NotImplementedError, "#{self.class} must implement #scope"
    end

    # Work between pagination and rendering. Default: none.
    def after_paginate; end

    # What the row partial is handed. Override to pass more than the record.
    def row_locals(record)
      { self.class.row_local => record }
    end

    # Markup to append after a row, or nil for none. `slot` is the row's position
    # in the feed as a whole, not within this page — see #slot_for.
    def wrap_row(html, wrapper)
      return html if wrapper.nil?

      "<#{wrapper}>#{html}</#{wrapper}>".html_safe
    end

    def after_row(record, slot) = nil

    # The row's position in the feed as a whole. This is the whole subtlety of
    # interleaving: counting within the page restarts at every page boundary,
    # which bunches interleaved units near the top of each batch and drifts out
    # of step with whatever the first screen rendered server-side. So page and
    # per_page carry into it.
    def slot_for(index)
      per_page = @pagy&.limit.to_i
      offset = per_page.positive? ? (page - 1) * per_page : 0
      offset + index + 1
    end

    def page_html
      partial = self.class.row_partial
      raise NotImplementedError, "#{self.class} must declare `renders`" if partial.nil?

      wrapper = self.class.row_wrapper
      @records.each_with_index.map { |record, index|
        row = wrap_row(render(partial:, locals: row_locals(record)), wrapper)
        extra = after_row(record, slot_for(index))
        extra ? row + wrap_row(extra, wrapper) : row
      }.join
    end
  end
end
