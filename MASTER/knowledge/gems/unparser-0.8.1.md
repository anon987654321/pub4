require 'parser/current'
require 'unparser'

def s(type, *children)
  Parser::AST::Node.new(type, children)
end

node = s(:def,
         :foo,
         s(:args, s(:arg, :x)),
         s(:send, s(:lvar, :x), :+, s(:int, 3))
Unparser.unparse(node) # => "def foo(x)\n  x + 3\nend"
