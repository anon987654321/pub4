# frozen_string_literal: true

# Split one class per file (2026-07-20): this file used to nest all 6 agent
# classes directly inside one `class ReviewCrew ... end` body, which made
# this single file's ClassNode span 421 lines -- NO_GOD_CLASS's line-count
# ceiling doesn't distinguish "genuinely one big class" from "a namespace
# holding six small ones." Each agent file still reopens `class ReviewCrew`
# and nests its one class the same way, so the resulting constant path
# (ReviewCrew::SecurityAgent etc.) is unchanged and build_workers'
# unqualified SecurityAgent.new in review_crew.rb still resolves exactly as
# before -- purely a file-layout split, no behavior change.
require_relative "finding"
require_relative "base_agent"
require_relative "security_agent"
require_relative "performance_agent"
require_relative "style_agent"
require_relative "architecture_agent"
require_relative "minimalist_agent"
require_relative "chaos_agent"
