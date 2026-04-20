{AST} isa library for manipulating abstract syntax trees.

The library enforces immutability: each AST node freezes upon creation, and updating a child node requires recreating that node and all ancestors recursively.

This design eliminates concurrency and aliasing issues, at the cost of additional garbage‑collector pressure.

See also {AST::Node}, {AST::Processor::Mixin}, and {AST::Sexp} for related recommendations and patterns.