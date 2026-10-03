# frozen_string_literal: true

require "vips"
require "numo/narray"
require "digest"
require "fileutils"

# A real depth map, where the old ones were cues standing in for one.
#
# postpro.rb's aerial_depth derives far-from-near from local sharpness and
# relight's key falls off in a geometric ramp across the frame — both are
# proxies named as proxies in their own comments, and a sharp cloud reads as
# near to both. Depth Anything V2 (the small model, 25M parameters) is the
# monocular estimator the research settled on, and its small fp16 ONNX export
# runs in about twelve seconds of CPU, which is inside the budget of a chain that
# already spends minutes in heavy glows. So the proxies gain a real instrument
# and lose nothing when it is missing.
#
# Degradation is the design: without the gem or the weights, every caller gets
# nil and behaves as it always did, one log line quiet. The model file is
# never committed — fetch it out of band, paths and sizes in the README.
module Postpro
  module Depth
    # The fp16 export of onnx-community/depth-anything-v2-small-ONNX, one file
    # plus its external data. Fifty megabytes against 127 for the graph.
    ONNX_DIR = File.expand_path("models/depth", __dir__)
    ONNX_GRAPH = File.join(ONNX_DIR, "model_fp16.onnx")
    # Depth Anything processes at multiples of 14; 518 is the published size.
    MODEL_EDGE = 518
    # ImageNet statistics, which the DPT processor this export came from uses.
    MEAN = [0.485, 0.456, 0.406].freeze
    STD = [0.229, 0.224, 0.225].freeze

    # Depth Anything predicts inverse depth: a high reading means CLOSE. Every
    # consumer here is named for what it receives — `near` is a map where 1.0
    # is the viewer's side of the plane — so no caller has to remember which
    # way a raw inverse-depth tensor points.
    def self.near(image)
      key = fingerprint(image)
      plane = read_cache(key)
      unless plane
        model = self.model
        return nil unless model

        feed = Numo::SFloat.cast(tensor(image)).reshape(1, 3, MODEL_EDGE, MODEL_EDGE)
        outputs = model.predict({ "pixel_values" => feed }, output_names: ["predicted_depth"])
        raw = outputs.fetch("predicted_depth").first
        plane = normalise(raw)
        write_cache(key, plane)
      end
      resize_up(plane, image)
    rescue StandardError => e
      warn "depth: #{e.message}"
      nil
    end

    # Loaded once, and quietly absent when either the binding or the weights
    # are — `nil` is the contract every caller is written against.
    def self.model
      require "onnxruntime"
      @model ||= OnnxRuntime::Model.new(ONNX_GRAPH)
    rescue LoadError, StandardError => e
      @model = nil
      warn "depth: estimator unavailable (#{e.message}) — postpro.rb's cues stand in"
      nil
    end

    # The processor: square up on srgb 0-1, take ImageNet normalisation away
    # off the channels, and return the CHW plane of floats — the batch axis
    # and the dense packing are the caller's, since Numo does both at once.
    def self.tensor(image)
      rgb = image.colourspace("srgb").resize(MODEL_EDGE.to_f / [image.width, image.height].max)
      rgb = rgb.embed(0, 0, MODEL_EDGE, MODEL_EDGE, background: 0).crop(0, 0, MODEL_EDGE, MODEL_EDGE)
      rgb.bandsplit.each_with_index.flat_map do |band, ch|
        band.cast("float").write_to_memory.unpack("e*").map do |v|
          (v / 255.0 - MEAN[ch]) / STD[ch]
        end
      end
    end

    # min-max on the raw reading: the map is used low-frequency by every
    # consumer, so absolute calibration buys nothing over the spread. The
    # runtime's nesting around the depth plane is whatever its dims made it;
    # descend to the first 2D plane.
    def self.normalise(raw)
      rows = raw
      rows = rows.first while rows.first.is_a?(Array) && rows.first.first.is_a?(Array)
      raise("depth: unexpected output rank") unless rows.first.is_a?(Array)

      flat = rows.flatten
      lo = flat.min.to_f
      span = [flat.max.to_f - lo, 1e-6].max
      Vips::Image.new_from_array(rows.map { |row| row.map { |v| (v - lo) / span } }).cast("float")
    end

    def self.resize_up(near, image)
      scaled = near.resize(image.width.to_f / near.width,
                           vscale: image.height.to_f / near.height)
      scaled.embed(0, 0, image.width, image.height, extend: :copy)
    end

    # A tiny greyscale fingerprint stands in for the photograph it came from:
    # two images that agree at 64x64 differ by nothing worth a second pass of
    # a one-second model.
    def self.fingerprint(image)
      thumb = image.colourspace("b-w").resize(64.0 / image.width).cast("uchar")
      Digest::MD5.hexdigest(thumb.write_to_memory)
    end

    def self.cache_path(key)
      File.join(ONNX_DIR, "cache", "#{key}.bin")
    end

    # The cached shape is invariant (the model's own square), so a hit can be
    # trusted to the byte; resizing to the caller's frame happens after, since
    # that is where the cache and a fresh read meet.
    def self.read_cache(key)
      bytes = File.binread(cache_path(key))
      return nil unless bytes && bytes.bytesize == MODEL_EDGE * MODEL_EDGE * 4

      Vips::Image.new_from_memory(bytes, MODEL_EDGE, MODEL_EDGE, 1, :float)
    rescue StandardError
      nil
    end

    def self.write_cache(key, plane)
      FileUtils.mkdir_p(File.join(ONNX_DIR, "cache"))
      File.binwrite(cache_path(key), plane.write_to_memory)
      true
    rescue StandardError
      nil
    end
  end
end