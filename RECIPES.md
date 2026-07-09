# Recipes

Runtime authority: `DEPLOY/data/operator.yml` — list with `cd MASTER && bundle exec ruby bin/cli` then `/orient deploy`, or `bin/pub4 status`.

## Repo shape (visual overview)

```bash
ruby DEPLOY/openbsd/tools/tree.rb . --pub4-overview
# or: zsh DEPLOY/openbsd/sh/tree.sh . --pub4-overview
```

Prunes vendor/tmp/log/storage/node_modules/builds. Shows Rails apps collapsed, MASTER/lib subsystems, alignment notes.