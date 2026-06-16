require 'parser/current'
require 'unparser'

# Helper to build AST nodes succinctly
def s(type, *children)
  Parser::AST::Node.new(type, children)
end

# Build an AST for:
#   def foo(x)
#     x + 3
#   end
node = s(
  :def,
  :foo,
  s(:args, s(:arg, :x)),
  s(:send, s(:lvar, :x), :+, s(:int, 3))
)

# Render the Ruby source from the AST
puts Unparser.unparse(node)
# => "def foo(x)\n  x + 3\nend"
