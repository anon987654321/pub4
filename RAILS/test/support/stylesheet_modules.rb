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
  ROOT = File.expand_path("../..", __dir__)

  MODULE_OPEN = /\A\/\/ ={5,} module: ([a-z0-9_]+)\s*\z/.freeze
  MODULE_CLOSE = /\A\/\/ ={5,} \/module: /.freeze

  # brgen was re-cut into `@use` partials on 2026-11-01; amber and bsdports keep
  # the banner layout. Both are read here so the law tests name modules, not files.
  LOCAL_USE = /\A@use "([a-z0-9_]+)";\s*\z/.freeze
  WRAPPER_LINE = %r{\A\s*(?:@use\b.*|//.*)?\z}.freeze

  def application_scss(app)
    File.read(File.join(ROOT, app, "app", "assets", "stylesheets", "application.scss"))
  end

  def partial_path(app, name)
    path = File.join(ROOT, app, "app", "assets", "stylesheets", "_#{name}.scss")
    path if File.file?(path)
  end

  # Local partials the root sheet loads with a bare `@use`, in cascade order.
  def used_partials(app)
    application_scss(app).lines.filter_map { |line| line[LOCAL_USE, 1] }.select { |name| partial_path(app, name) }
  end

  # The whole stylesheet as the compiler sees it: root sheet plus its partials.
  def stylesheet_source(app)
    [application_scss(app), *used_partials(app).map { |name| File.read(partial_path(app, name)) }].join("\n")
  end

  # The text of one former partial, exactly as it was before the merge —
  # banner lines excluded, content byte-identical. A split app answers with
  # the partial file of that name.
  def stylesheet_module(app, name)
    return File.read(partial_path(app, name)) if used_partials(app).include?(name)

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
  # sequence via load-css call positions. The banner regex anchors at the start
  # of its line, so the scan runs per line rather than over the whole sheet.
  def stylesheet_module_names(app)
    banners = application_scss(app).lines.filter_map { |line| line[MODULE_OPEN, 1] }
    return banners unless banners.empty?

    # A partial that only re-exports (`@use` lines and comments) is a wrapper,
    # not a feature module.
    used_partials(app).reject do |name|
      File.readlines(partial_path(app, name)).all? { |line| line.match?(WRAPPER_LINE) }
    end
  end
end
