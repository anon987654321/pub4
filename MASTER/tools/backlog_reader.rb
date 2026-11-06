# frozen_string_literal: true

module Backlog
  # Reads a source into rows: prose lines belong to the checkbox above them,
  # fenced code keeps its lines for command extraction, checked rows are
  # landed evidence, and a planned phase (pub5) folds into one gated entry
  # rather than many rows whose gate is the operator's freeze decision.
  class Reader
    CHECKBOX = %r{\A- \[( |x|X)\] ?(.*)\z}
    CHECKED = %r{\A- \[(?:x|X)\]}

    def initialize
      @items = []
      @item = nil
      @fence = false
      @h1 = @h2 = @h3 = nil
      @plan = { active: false, seen: false, heading: nil, prose: [], prose_done: false }
    end

    def read(line)
      return toggle_fence(line) if line.lstrip.start_with?("```")
      return collect_code(line) if @fence
      return read_heading(line) if line.start_with?("#")
      return read_plan(line) if plan_active?
      return read_checkbox(line) if line.match?(CHECKBOX)

      read_continuation(line)
    end

    def finish
      raise "the source carries no pub5 section" unless plan_seen?

      @items << plan_item if plan_active?
      @items
    end

    private

    def plan_active? = @plan[:active]

    def plan_seen? = @plan[:seen]

    def toggle_fence(_line)
      @fence = !@fence
    end

    def collect_code(line)
      @item[:code] << line.strip if @item
    end

    def read_heading(line)
      case line
      when %r{\A## (.+)\z}
        enter_section(Regexp.last_match(1))

      when %r{\A### (.+)\z}
        @h3 = Regexp.last_match(1)
        @item = nil
      else
        @h1 = line.sub(/\A#\s+/, "")
        @h2 = @h3 = @item = nil
      end
    end

    def enter_section(title)
      @h2 = title
      @h3 = @item = nil
      active = title.start_with?("pub5")
      @plan[:active] = active
      open_plan(title) if active
    end

    # The plan folds its whole section into one entry: prose accumulates once
    # the pub5 heading opens it, and its checkbox lines stay unread rows.
    def open_plan(title)
      @plan[:seen] = true
      @plan[:heading] = title
      @plan[:prose] = []
      @plan[:prose_done] = false
    end

    def read_plan(line)
      checkbox = line.match?(CHECKBOX)
      @item = nil if checkbox
      @plan[:prose_done] = true if line.match?(%r{\A### })
      prose = line.strip
      @plan[:prose] << prose if !checkbox && !@plan[:prose_done] && !prose.empty?
    end

    def read_checkbox(line)
      @item = line.match?(CHECKED) ? nil : open_row(line)
    end

    def read_continuation(line)
      prose = line.strip
      @item = nil unless line.start_with?(" ") || prose.empty?
      @item[:prose] << prose if @item && !prose.empty?
    end

    def open_row(line)
      match = line.match(CHECKBOX)
      @item = { prose: [match[2]], code: [], h1: @h1, h2: @h2, h3: @h3 }
      @items << @item
      @item
    end

    def plan_item
      {
        plan: true,
        prose: @plan[:prose],
        code: [],
        h1: @h1,
        h2: @plan[:heading],
        h3: nil,
      }
    end
  end
end
