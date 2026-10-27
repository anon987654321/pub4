# frozen_string_literal: true

# Where renders land, what they are called, and which paths a command line
# names. Only the contact-sheet tests open pictures, and those are tiny
# synthetic frames.
module PostproFixtures
  REPO_ROOT = File.expand_path("..", ToolTest::ROOT)
  CHAIN = [["film_curve", { "intensity" => 0.8 }], ["halation", 0.4], ["grain", { "intensity" => 0.6 }]].freeze

  private

  def with_env(name, value)
    previous = ENV[name]
    value.nil? ? ENV.delete(name) : ENV[name] = value
    yield
  ensure
    previous.nil? ? ENV.delete(name) : ENV[name] = previous
  end

  def with_argv(*args)
    saved = ARGV.dup
    ARGV.replace(args)
    yield
  ensure
    ARGV.replace(saved)
  end

  def quietly
    result = nil
    capture_io { result = yield }
    result
  end

  def source_in(dir, name = "frame.jpg")
    path = File.join(dir, name)
    File.write(path, "source")
    path
  end

  def render(dir, name, input:)
    path = File.join(dir, name)
    File.write(path, "render")
    File.write("#{path}.json", JSON.generate("input" => File.expand_path(input)))
    path
  end

  # A take on disk the way a random run leaves it: picture plus chain sidecar.
  def take(input, number:, look:, picture: false)
    stem = File.basename(input, ".jpg")
    path = File.join(File.dirname(input), format("postpro_%s_%02d_%s_subtle_analog_v1.jpg", stem, number, look))
    picture ? tiny_frame(path) : File.write(path, "render")
    sidecar = { "schema" => "postpro.chain.v1", "input" => File.expand_path(input), "take" => number, "look" => look }
    File.write("#{path}.json", JSON.generate(sidecar))
    path
  end

  def tiny_frame(path)
    band = (Vips::Image.black(40, 60).cast(:float) + 120).cast(:uchar)
    band.bandjoin([band, band]).write_to_file(path)
    path
  end

  def label(take = nil) = send(:random_take_label, CHAIN, take)

  # A smooth colour ramp with no texture: what the effect tests grade.
  def process_frame
    x = Vips::Image.xyz(200, 150).extract_band(0).cast(:float)
    y = Vips::Image.xyz(200, 150).extract_band(1).cast(:float)
    (x * 1.1 + 10).bandjoin([y * 1.3 + 20, (x + y) * 0.5 + 15]).cast(:uchar).copy(interpretation: :srgb)
  end

  def verify_render(source, output) = Postpro::Constitution.verify_output!(input_path: source, output_path: output)

  def random_take(number, look: :noir, lane: :subtle_analog) = RandomTake.new(number:, look:, lane:)
end
