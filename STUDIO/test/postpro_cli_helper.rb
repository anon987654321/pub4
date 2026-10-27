# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"

# The CLI under test, run in a subprocess per call because ARGV dispatch cannot
# be exercised in-process, and the frames those runs grade.
module PostproCli
  POSTPRO = File.expand_path("../postpro/postpro.rb", __dir__)

  SEED = "4242"

  def run_postpro(dir, *args, env: {})
    defaults = {
      "POSTPRO_SEED" => SEED,
      "DILLA_QUIET" => "1",
    }
    Open3.capture2e(defaults.merge(env), RbConfig.ruby, POSTPRO, *args, chdir: dir)
  end

  def frame(dir, name = "frame.jpg")
    path = File.join(dir, name)
    band = (Vips::Image.black(160, 160).cast(:float) + 140).cast(:uchar)
    band.bandjoin([band, band]).write_to_file("#{path}[Q=95]")
    path
  end

  def graded_outputs(dir, name)
    Dir[File.join(dir, "postpro_#{File.basename(name, File.extname(name))}_*_v1.jpg")]
  end

  # A textured frame, because a flat one gives the take-survival check nothing
  # to judge and a family of flat takes reads as refused.
  def scene(dir, name = "scene.jpg")
    path = File.join(dir, name)
    ToolTest.octave_scene(120, 180).write_to_file("#{path}[Q=90]")
    path
  end

  def family(dir, name)
    Dir[File.join(dir, "postpro_#{File.basename(name, File.extname(name))}_[0-9][0-9]_*_v1.jpg")].sort
  end

  def sidecars(paths) = paths.map { |path| JSON.parse(File.read("#{path}.json")) }

  def contact_sheet(dir, name)
    File.join(dir, "postpro_#{File.basename(name, File.extname(name))}_contact.jpg")
  end

  # Runs the CLI and fails the test, with its output, unless it exits clean.
  def graded!(dir, *args, env: {})
    out, status = run_postpro(dir, *args, env:)
    assert status.success?, out
    out
  end

  def take_numbers(paths) = paths.map { |path| File.basename(path)[/_(\d\d)_/, 1] }
end
