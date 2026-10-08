# frozen_string_literal: true

# Prints every file config/face_assets.yml claims the chat shell loads, one
# absolute path per line, for /etc/rc.d/master's precompile-skip digest.
#
# The digest reads the manifest rather than maintaining a second asset list.
# Every declared face asset therefore contributes to the same precompile
# fingerprint, including synchronous prerequisites and generated bundles.
#
# Plain Ruby, no Rails: this runs from rc_pre() before the app boots.

require "yaml"

root = File.expand_path("..", __dir__)
manifest = YAML.safe_load_file(File.join(root, "config", "face_assets.yml"))

names = %w[face_eager face_runtime_deferred face_vision_deferred
           shell_blocking shell_boot shell_early shell_late shell_css]
        .flat_map { |group| Array(manifest[group]) }
names += manifest.fetch("singletons", {}).values
names += Array(manifest["shell_manifest"]).map { |name| "#{name}.js" }

names.uniq.sort.each do |name|
  path = File.join(root, "public", name)
  puts path if File.file?(path)
end
