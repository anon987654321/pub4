# frozen_string_literal: true

require "vips"

# Removes a mark from skin while keeping the skin.
#
# A bruise is a colour and tone change spread over a patch, so it lives in the
# low frequencies; a scratch is a thin line, so it lives in the high ones. Each
# spot is rebuilt from both halves: the tone is filled in from the skin around
# the mark (a blur that ignores the pixels inside it), and the texture is copied
# from a nearby clean patch so the result keeps pores and grain. Blurring or
# cloning alone gives the smooth plastic skin MASTER/tools/README.md warns about.
#
# Only skin feeds a repair. A mark near the silhouette sits beside a wall, and a
# fill that averages the wall in leaves a pale halo, so every weight is scaled by
# how skin-like each pixel is in LCh: skin has chroma and a warm hue, a wall is
# near-neutral. postpro's skin_protect is no help here — its HSV band selects
# blonde hair, not skin.
#
# Heal the ungraded original and grade afterwards. The grade's grain and curve
# belong over the repair, not under it.
#
#   ruby _toolkit/heal.rb IN OUT X,Y,RX,RY,DX,DY [...]
#
# Every number is a fraction of the image width (X, RX, DX) or height (Y, RY,
# DY). X,Y is the mark's centre, RX,RY its radii, DX,DY where the donor texture
# sits relative to it.
module Lora
  module Heal
    Spot = Struct.new(:x, :y, :rx, :ry, :dx, :dy)

    def self.parse(spec)
      values = spec.split(",").map { Float(_1) }
      abort "warn: spot needs X,Y,RX,RY,DX,DY, got #{spec}" unless values.size == 6
      Spot.new(*values)
    end

    # ruby-vips has no coerce, so a Ruby number cannot sit left of an image.
    def self.unit(image) = image.clamp(min: 0, max: 1)

    # The default integer kernel rounds and cuts off early; a repair needs neither.
    def self.blur(image, sigma) = image.gaussblur(sigma, precision: :float, min_ampl: 0.05)

    def self.lch(rgb) = rgb.copy(interpretation: :srgb).colourspace(:lch)

    # 1 for skin-like colour, 0 for a near-neutral wall or an off-hue pixel.
    def self.skin_weight(rgb, chroma_low: 6.0, chroma_high: 14.0, hue: 50.0, hue_half: 40.0, hue_soft: 20.0)
      lch = lch(rgb)
      chroma = unit((lch[1] - chroma_low) / (chroma_high - chroma_low))
      hue_distance = ((lch[2] - hue + 540.0) % 360.0 - 180.0).abs
      chroma * unit((hue_distance * -1 + hue_half + hue_soft) / hue_soft)
    end

    # A soft-edged ellipse, 1 inside and 0 past 1.6 radii.
    def self.ellipse(width, height, cx, cy, rx, ry)
      xy = Vips::Image.xyz(width, height).cast(:float)
      distance = ((xy[0] - cx) / rx)**2 + ((xy[1] - cy) / ry)**2
      unit((distance * -1 + 1.6) / 0.6)
    end

    def self.heal(image, spot)
      w, h = image.width, image.height
      cx, cy = spot.x * w, spot.y * h
      rx, ry = spot.rx * w, spot.ry * h
      pad = [rx, ry].max * 2.5
      left = (cx - pad).floor.clamp(0, w - 1)
      top = (cy - pad).floor.clamp(0, h - 1)
      box_w = (cx + pad).ceil.clamp(0, w) - left
      box_h = (cy + pad).ceil.clamp(0, h) - top
      donor_left = (left + spot.dx * w).round.clamp(0, w - box_w)
      donor_top = (top + spot.dy * h).round.clamp(0, h - box_h)

      patch = image.crop(left, top, box_w, box_h).cast(:float)
      donor = image.crop(donor_left, donor_top, box_w, box_h).cast(:float)
      mask = ellipse(box_w, box_h, cx - left, cy - top, rx, ry)

      texture_sigma = [[rx, ry].min * 0.12, 2.0].max
      texture = (donor - blur(donor, texture_sigma)) * skin_weight(donor)

      weight = (mask < 0.01).ifthenelse(1.0, 0.0) * skin_weight(patch)
      fill_sigma = [rx, ry].max * 0.6
      coverage = blur(weight, fill_sigma)
      tone = (coverage > 1e-3).ifthenelse(blur(patch * weight, fill_sigma) / coverage.maxpair(1e-3), patch)

      alpha = mask * unit((lch(patch)[1] - 4) / 6.0)
      repaired = patch * (alpha * -1 + 1) + (tone + texture) * alpha
      image.insert(repaired.round(:rint).cast(image.format), left, top)
    end

    def self.main(argv)
      input, output, *specs = argv
      abort "warn: usage: heal.rb IN OUT X,Y,RX,RY,DX,DY [...]" unless input && output && specs.any?
      image = Vips::Image.new_from_file(input).autorot
      image = image[0..2] if image.bands > 3
      specs.map { parse(_1) }.each { |spot| image = heal(image, spot) }
      image.write_to_file(output, Q: 97)
      puts "ok: #{specs.size} spot(s) healed -> #{output}"
    end
  end
end

Lora::Heal.main(ARGV) if $PROGRAM_NAME == __FILE__
