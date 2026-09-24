# frozen_string_literal: true

# Regenerates the generated block of gates/data/geometry_surfaces.yml: every
# HTML GET route of amber, bsdports and brgen that renders for a guest.
#
#   RAILS/bin/triangle up
#   ruby RAILS/tools/view_surfaces/generate.rb
#
# Per app it lists the GET routes (list_get_routes.rb, under rails runner),
# fills each parameter from the first local record of the model it names
# (resolve_route_params.rb), requests every URL as a guest against the local
# fleet (probe_routes.rb), then rewrites the block from the pages that
# answered 200 HTML (write_surfaces.rb). Work files go to a temporary
# directory; the YAML is the only thing written in the tree.
require "open3"
require "tmpdir"

HERE = __dir__
RAILS = File.expand_path("../..", HERE)
APPS = %w[amber bsdports brgen].freeze

def run!(*cmd, chdir:, out: nil)
  stdout, stderr, status = Open3.capture3(*cmd, chdir:)
  abort "#{cmd.join(" ")} failed in #{chdir}:\n#{stderr.lines.last(5).join}" unless status.success?
  File.write(out, stdout) if out
  stdout
end

Dir.mktmpdir("view_surfaces") do |work|
  APPS.each do |app|
    app_dir = File.join(RAILS, app)
    routes = File.join(work, "routes_#{app}.jsonl")
    resolved = File.join(work, "resolved_#{app}.jsonl")
    run!("bin/rails", "runner", File.join(HERE, "list_get_routes.rb"), chdir: app_dir, out: routes)
    run!("bin/rails", "runner", File.join(HERE, "resolve_route_params.rb"), routes, chdir: app_dir, out: resolved)
    print run!("ruby", File.join(HERE, "probe_routes.rb"), app, resolved, chdir: RAILS)
  end
  print run!("ruby", File.join(HERE, "write_surfaces.rb"), work, File.join(RAILS, "gates/data/geometry_surfaces.yml"), chdir: RAILS)
end
