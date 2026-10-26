# frozen_string_literal: true

require "minitest/autorun"
require "yaml"

class TreeContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  BOOT_FILES = %w[
    bin/ruby
    bin/cli
    lib/boot/entrypoint.rb
    lib/boot/dependency_manager.rb
    lib/master.rb
    data/soul.yml
    data/laws.yml
  ].freeze

  ZEITWERK_DIRECTORIES = %w[
    lib/ai
    lib/cli/command_registry
    lib/cli/session
    lib/fix/scan
    lib/fix/fix_loop
    lib/ground/memory
    lib/music
    lib/voice/renderer
  ].freeze

  PROTECTED_PATHS = %w[
    MASTER/bin
    MASTER/lib
    MASTER/data
    MASTER/law
    MASTER/tools/test
    OPENBSD/var/nsd
    RAILS/brgen_marketplace/engines
    RAILS/brgen_radio
    STUDIO
    STUDIO/dilla
    STUDIO/replicate/lora
    STUDIO/postpro
    STUDIO/replicate
  ].freeze

  # Each vertical's engine root, relative to RAILS/.
  BRGEN_ENGINES = {
    "marketplace" => "brgen_marketplace",
    "playlist" => "brgen_radio/playlist",
    "tv" => "brgen_radio/tv",
    "takeaway" => "brgen_marketplace/engines/takeaway",
    "dating" => "brgen_dating",
    "maps" => "brgen_maps",
  }.freeze

  def test_ruby_sources_never_contain_transport_markup
    Dir.glob(File.join(ROOT, "**", "*.rb")).each do |path|
      next if path.include?("/vendor/")

      source = File.read(path, encoding: "UTF-8")
      refute_match(/(?:^|\n)<\/?sub>(?:$|\n)/, source, "transport wrapper leaked into #{path}")
    end
  end

  def test_boot_spine_exists_in_its_canonical_locations
    BOOT_FILES.each do |relative|
      assert File.file?(File.join(ROOT, relative)), "missing boot-critical path: #{relative}"
    end
  end

  def test_boot_spine_uses_relative_lib_loader
    cli = File.read(File.join(ROOT, "bin/cli"), encoding: "UTF-8")
    entrypoint = File.read(File.join(ROOT, "lib/boot/entrypoint.rb"), encoding: "UTF-8")

    assert_includes cli, 'require_relative "../lib/boot/entrypoint"'
    assert_includes cli, '$LOAD_PATH.unshift File.expand_path("../lib", __dir__)'
    assert_includes entrypoint, 'require_relative "dependency_manager"'
  end

  def test_protected_master_boundaries_remain_directories
    PROTECTED_PATHS.each do |relative|
      path = File.join(File.expand_path("..", ROOT), relative)
      assert Dir.exist?(path), "protected runtime/deploy boundary moved: #{relative}"
    end

    ZEITWERK_DIRECTORIES.each do |relative|
      assert Dir.exist?(File.join(ROOT, relative)), "Zeitwerk namespace moved or flattened: #{relative}"
    end
  end

  def test_brgen_engine_boundaries_remain_mountable
    BRGEN_ENGINES.each do |engine, root|
      path = File.join(File.expand_path("..", ROOT), "RAILS", root)
      assert Dir.exist?(path), "brgen engine boundary moved: #{engine}"
      assert File.file?(File.join(path, "config/routes.rb")), "#{engine} engine lost config/routes.rb"
      assert File.file?(File.join(path, "lib", engine, "engine.rb")), "#{engine} engine lost its Rails::Engine class"
    end
  end

  def test_studio_owns_media_tools_and_master_keeps_compatibility_links
    links = {
      "dilla" => "../../STUDIO/dilla",
      "lora" => "../../STUDIO/replicate/lora",
      "postpro" => "../../STUDIO/postpro",
      "replicate" => "../../STUDIO/replicate",
    }

    links.each do |name, target|
      path = File.join(ROOT, "tools", name)
      assert File.symlink?(path), "MASTER/tools/#{name} must remain a compatibility symlink"
      assert_equal target, File.readlink(path), "MASTER/tools/#{name} points somewhere other than STUDIO/#{name}"
      assert File.file?(File.join(path, "#{name}.rb")), "STUDIO/#{name}/#{name}.rb is not reachable through the compatibility path"
    end
  end

  def test_autoload_ignores_point_at_real_files
    manifest = YAML.safe_load_file(File.join(ROOT, "data/autoload.yml")).fetch("autoload")
    manifest.values.flatten.each do |relative|
      assert File.exist?(File.join(ROOT, "lib", relative)) || File.exist?(File.join(ROOT, "lib", "#{relative}.rb")),
             "autoload ignore points at missing path: #{relative}"
    end
  end
end
