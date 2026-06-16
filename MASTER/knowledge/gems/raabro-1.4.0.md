# frozen_string_literal: true
require "raabro"

# Simple arithmetic‑like parser built on Raabro.
#
# The parser recognizes function calls with integer arguments and
# plain integer literals. Whitespace is permitted after delimiters but
# not before, keeping the grammar concise and deterministic.
module Fun
  include Raabro

  # '(' followed by optional whitespace
  def pstart(i) ; rex(nil, i, /\(\s*/) ; end

  # ')' preceded by optional whitespace
  def pend(i)   ; rex(nil, i, /\)\s*/) ; end

  # ',' followed by optional whitespace
  def comma(i)  ; rex(nil, i, /,\s*/) ; end

  # Integer literal, optional leading minus, trailing whitespace ignored
  def num(i)    ; rex(:num, i, /-?\d+\s*/) ; end

  # Argument list: '(' expr (',' expr)* ')'
  def args(i)   ; eseq(:args, i, :pstart, :exp, :comma, :pend) ; end

  # Function name: lower‑case letter followed by alphanumerics
  def funname(i) ; rex(nil, i, /[a-z][a-z0-9]*/) ; end

  # Function call: name '(' arguments ')'
  def fun(i)    ; seq(:fun, i, :funname, :args) ; end

  # Expression: either a function call or a number
  def exp(i)    ; alt(:exp, i, :fun, :num) ; end

  # -----------------------------------------------------------------
  # Rewrite rules – convert the parse tree into native Ruby objects.
  # -----------------------------------------------------------------

  # Dispatch based on the node label.
  def rewrite_exp(t)      ; rewrite(t.children.first) ; end
  def rewrite_num(t)      ; t.string.to_i ; end

  # Transform a function node into an Array:
  #   [function_name, arg1, arg2, …]
  def rewrite_fun(t)
    name_node, *arg_nodes = t.children
    [name_node.string] + arg_nodes.map { |n| rewrite(n) }
  end
end