# frozen_string_literal: true
#
# One stylesheet per app, operator 2026-10-28: every Rails app's
# app/assets/stylesheets holds a single application.scss. The former feature
# partials live inside it between `// ==== module: <name>` and
# `// ==== /module: <name>` banner comments, in the exact cascade order the
# old @include meta.load-css calls had — the merge is compiled-byte-identical
# apart from comment placement (scripts/merge-scss.mjs proved it with
# dart-sass).
#
# The law tests still reason about per-module text. StylesheetModules slices
# the merged sheet back into those modules, so every assertion that matched a
# partial's text matches the same text in its new home.

module StylesheetModules
  MODULE_OPEN = /\A\/\/ ={5,} module: ([a-z0-9_]+)\s*\z/.freeze
  MODULE_CLOSE = /\A\/\/ ={5,} \/module: /.freeze

  def application_scss(app)
    File.read(File.join(ROOT, app, "app", "assets", "stylesheets", "application.scss"))
  end

  # The text of one former partial, exactly as it was before the merge —
  # banner lines excluded, content byte-identical.
  def stylesheet_module(app, name)
    found = []
    inside = false
    application_scss(app).each_line do |line|
      if (open_m = line.match(MODULE_OPEN))
        raise "#{app}: module #{name} reopened inside another module" if inside
        inside = open_m[1] == name
      elsif line.match?(MODULE_CLOSE)
        return found.join if inside
        inside = false
      elsif inside
        found << line
      end
    end
    raise "#{app}: no module banner `#{name}` in application.scss — the consolidation moved it"
  end

  # Former partial names, in cascade order, for tests that asserted module
  # sequence via load-css call positions.
  def stylesheet_module_names(app)
    application_scss(app).scan(MODULE_OPEN).flatten
  end
end
