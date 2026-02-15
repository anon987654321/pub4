# frozen_string_literal: true

require "yaml"

# Load all code review sub-modules from review/ directory
require_relative "review/violations"
require_relative "review/smells"
require_relative "review/bug_hunting"
require_relative "review/engine"
require_relative "review/llm_friendly"
require_relative "review/audit"
require_relative "review/cross_ref"

# Load enforcement modules
require_relative "review/layers"
require_relative "review/scopes"

module MASTER
  module Review
    # Scanner - Automated checks learned from deep analysis sessions
  end
end

require_relative "review/scanner"
require_relative "review/fixer"
require_relative "review/enforcer"
require_relative "review/axiom_stats"
require_relative "review/constitution"

# Backward-compatible aliases
CodeReview = MASTER::Review::Scanner
AutoFixer = MASTER::Review::Fixer
Enforcement = MASTER::Review::Enforcer
QualityStandards = MASTER::Review::Enforcer
FileHygiene = MASTER::Review::Scanner::FileHygiene
