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
  # A reflex that needs more than the pattern has two seams rather than a copy of
  # the spine: `after_paginate` for work between pagination and rendering, and
  # `row_locals` for a partial that takes more than the record.
  class InfiniteScrollReflex < Shared::ApplicationReflex
    if defined?(Pagy::Method)
      include Pagy::Method
    elsif defined?(Pagy::Backend)
      include Pagy::Backend
    end

    class << self
      attr_reader :row_partial, :row_local

      # renders "posts/post", as: :post
      def renders(partial, as:)
        @row_partial = partial
        @row_local = as
      end

      # Subclasses of subclasses would otherwise lose the declaration.
      def inherited(child)
        super
        child.instance_variable_set(:@row_partial, @row_partial)
        child.instance_variable_set(:@row_local, @row_local)
      end
    end

    def load_more
      @pagy, @records = pagy(scope, page: page, request:)
      after_paginate

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

    def page_html
      partial = self.class.row_partial
      raise NotImplementedError, "#{self.class} must declare `renders`" if partial.nil?

      @records.map { |record| render(partial: partial, locals: row_locals(record)) }.join
    end
  end
end
