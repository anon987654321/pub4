# frozen_string_literal: true

require "pathname"

module Master
  # one-shot bootstrap: prints the canonical data files in read-order
  # so an agent (or operator) reads the constitution in a single pass
  # instead of cat'ing each yml separately.
  #
  # called from CLI as `/orient` or `bundle exec ruby exe/master orient`.
  #
  # SOURCES tracks current filenames. when the rename pass lands
  # (rules->voice, ruby_style->style, workflow->limits, standing_orders->state)
  # update this constant in one place.
  class Orient
    SOURCES = %w[
      soul
      rules
      ruby_style
      workflow
      standing_orders
    ].freeze

    def initialize(root:, io: $stdout)
      @root = Pathname(root)
      @io   = io
    end

    def call
      SOURCES.each { |name| dump(name) }
      :ok
    end

    private

    def dump(name)
      rel  = "data/#{name}.yml"
      path = @root.join(rel)
      @io.puts "# #{rel}"
      @io.puts(path.exist? ? path.read : "# missing")
      @io.puts
    end
  end
end
