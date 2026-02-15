# frozen_string_literal: true

require "yaml"

require_relative "code_review/violations"
require_relative "code_review/smells"
require_relative "code_review/bug_hunting"
require_relative "code_review/engine"
require_relative "code_review/llm_friendly"
require_relative "code_review/audit"
require_relative "code_review/cross_ref"

require_relative "enforcement/layers"
require_relative "enforcement/scopes"

module MASTER
  module Review
    # Scanner - Automated checks learned from deep analysis sessions
    # These patterns were discovered through cross-referencing and execution tracing
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
QualityStandards = MASTER::Review::QualityStandards
FileHygiene = MASTER::Review::Scanner::FileHygiene

module MASTER
  Constitution = Review::Constitution
  AxiomStats = Review::AxiomStats
  LanguageAxioms = Review::LanguageAxioms
  QualityStandards = Review::QualityStandards
  CodeReview = Review::Scanner
end
