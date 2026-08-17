# frozen_string_literal: true

# Prints every file config/face_assets.yml claims the chat shell loads, one
# absolute path per line, for /etc/rc.d/master's precompile-skip digest.
#
# That digest used to be a hand-maintained list of ~15 paths plus a face_*.js
# glob. It covered 23 of the 38 manifest files; the 15 it missed included
# particle_kernel.js (the one synchronous prerequisite), face.runtime.js (the
# generated blob itself) and three.face.module.js. Editing any of those and
# restarting silently skipped precompile and kept a stale fingerprint — the
# exact failure web/CLAUDE.md warns about.
#
# Plain Ruby, no Rails: this runs from rc_pre() before the app boots.

require "yaml"

root = File.expand_path("..", __dir__)
manifest = YAML.safe_load_file(File.join(root, "config", "face_assets.yml"))

names = %w[face_eager face_runtime_deferred face_vision_deferred
           shell_blocking shell_boot shell_early shell_late]
        .flat_map { |group| Array(manifest[group]) }
names += manifest.fetch("singletons", {}).values
names += Array(manifest["shell_manifest"]).map { |name| "#{name}.js" }

names.uniq.sort.each do |name|
  path = File.join(root, "public", name)
  puts path if File.file?(path)
end
