  # "A method whose whole body is the conditional" is what the paragraph above
  # claims and what a guard clause can actually replace, but the pattern only
  # anchored the `if` to the first line and never checked the method ended
  # there. display_ok opens with `if streamed` and then prints five footers
  # after the block; returning early from either arm would skip them, so there
  # is no guard clause to flatten it to. The def's own `end` has to follow the
  # conditional's.
  detect do |text|
    match = text.match(/^([ \t]*)def \w+[^\n]*\n\1[ \t]+if [^\n]+\n(?:(?!\1(?:def|end)\b)[^\n]*\n)*?\1[ \t]+else\n(?:(?!\1(?:def|end)\b)[^\n]*\n)*?\1[ \t]+end\n\1end\b/)
    next false unless match

    branches = match[0].split(/^\s+else\s*$/)
    branches.size == 2 &&
      branches.all? { |branch| branch.match?(/\b(?:return|redirect_to|render|head|raise)\b/) }
  end
  fix "Flatten to: return ... unless condition"
  bad <<~X
    def go(x)
      if x
        return run
      else
        return nil
      end
    end
  X
  good <<~X
    def go(x)
      return unless x
      run
    end

    def pick(x)
      if x
        foo
      else
        bar