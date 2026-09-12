# Recipes

The recipes are `OPENBSD/data/operator.yml`, and that file is the command list
rather than a copy of one. Print it with `MASTER/bin/operator status` for the
posture and next command, or with `/orient deploy` inside `MASTER/bin/cli` for
the whole thing — `MASTER/lib/operator/operator_docs.rb` renders it either way.

This file is a door, not a table. It was thirteen lines of pointer plus one
recipe the yaml did not carry, which is how a pointer becomes a fifth copy; that
recipe is in the yaml now. Add a recipe there and every door shows it.
