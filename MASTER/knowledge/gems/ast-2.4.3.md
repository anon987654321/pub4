# frozen_string_literal: true

require "ast"

# ------------------------------------------------------------
# Example: building an AST for `puts "hello"`
# ------------------------------------------------------------
#
# Ruby source:
#
#   puts "hello"
#
# translates to the S‑expression:
#
#   (send nil :puts (str "hello"))
#
# Using the **ast** gem we construct the same tree manually:

node =
  AST::Node.new(
    :send,
    [
      AST::Node.new(:nil),                # receiver (nil → Kernel method)
      :puts,                              # method name
      AST::Node.new(:str, ["hello"])      # argument node
    ]
  )

# ------------------------------------------------------------
# Processor: upper‑case every string literal
# ------------------------------------------------------------
#
# `AST::Processor::Mixin` supplies a depth‑first traversal that
# returns a *new* immutable tree.  Implement only the callbacks you
# need.  Here we override `on_str` to replace the string payload
# with its uppercase representation.

class UppercaseStrings
  include AST::Processor::Mixin

  # called for each `:str` node
  def on_str(node)
    original = node.children.first
    node.updated(:str, [original.upcase])
  end
end

# ------------------------------------------------------------
# Transform the tree
# ------------------------------------------------------------
transformed = UppercaseStrings.new.process(node)

# Resulting S‑expression:
#   (send nil :puts (str "HELLO"))
p transformed