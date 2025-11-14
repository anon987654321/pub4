# frozen_string_literal: true

def random_fx(image, effects, mode)
  result = image
  effects.each do |fx|
    intensity = mode == 'experimental' ? rand(0.5..1.5) : rand(0.3..0.8)
    result = case fx
             when 'grain' then grain_basic(result, intensity)
             when 'leaks' then leaks_basic(result, intensity)
             when 'sepia' then sepia_basic(result, intensity)
             when 'bloom' then bloom_basic(result, intensity)
             when 'teal_orange' then teal_orange(result, intensity)
             when 'cross' then cross_basic(result, intensity)
             when 'vhs' then vhs_basic(result, intensity)
             when 'chroma' then chroma_basic(result, intensity)
             when 'glitch' then glitch_basic(result, intensity)
             when 'flare' then flare_basic(result, intensity)
             else result
             end
  end
  result
end

def grain_basic(image, intensity)
  noise = Vips::Image.gaussnoise(image.width, image.height, sigma: 25 * intensity)
  safe_cast(image + rgb_bands(noise) * 0.2)
end

def leaks_basic(image, intensity)
  overlay = Vips::Image.black(image.width, image.height, bands: 3)
  rand(2..5).times do
    x, y = rand(image.width), rand(image.height)
    radius = image.width / rand(2..4)
    color = [255 * intensity, 180 * intensity, 80 * intensity]
    overlay = overlay.draw_circle(color, x, y, radius, fill: true)
  end
  safe_cast(image + overlay.gaussblur(15 * intensity) * 0.3)
end

def sepia_basic(image, intensity)
  matrix = [0.9, 0.7, 0.2, 0.3, 0.8, 0.1, 0.2, 0.6, 0.1]
  safe_cast(image.recomb(matrix))
end

def bloom_basic(image, intensity)
  bright = image.linear([1.8 * intensity], [0]).gaussblur(12 * intensity)
  safe_cast(image + bright * 0.3)
end

def cross_basic(image, intensity)
  r, g, b = image.bandsplit
  r = r.linear([1 + 0.2 * intensity], [10 * intensity])
  g = g.linear([1 - 0.1 * intensity], [0])
  b = b.linear([1 + 0.3 * intensity], [-5 * intensity])
  safe_cast(Vips::Image.bandjoin([r, g, b]))
end

def vhs_basic(image, intensity)
  noise = rgb_bands(Vips::Image.gaussnoise(image.width, image.height, sigma: 40 * intensity))
  lines = rgb_bands(Vips::Image.sines(image.width, image.height).linear(0.3 * intensity, 150))
  safe_cast(image + noise * 0.4 + lines * 0.3)
end

def chroma_basic(image, intensity)
  shift = 3 * intensity
  r, g, b = image.bandsplit
  r = r.embed(shift, 0, image.width, image.height)
  b = b.embed(-shift, 0, image.width, image.height)
  safe_cast(Vips::Image.bandjoin([r, g, b]))
end

def glitch_basic(image, intensity)
  r, g, b = image.bandsplit
  shift = 15 * intensity
  r = r.embed(rand(-shift..shift), rand(-shift..shift), image.width, image.height)
  g = g.embed(rand(-shift..shift), rand(-shift..shift), image.width, image.height)
  b = b.embed(rand(-shift..shift), rand(-shift..shift), image.width, image.height)
  noise = rgb_bands(Vips::Image.gaussnoise(image.width, image.height, sigma: 20 * intensity))
  safe_cast(Vips::Image.bandjoin([r, g, b]) + noise * 0.4)
end

def flare_basic(image, intensity)
  flare = Vips::Image.black(image.width, image.height, bands: 3)
  rand(3..6).times do
    x, y = rand(image.width), rand(image.height)
    length = 200 * intensity
    flare = flare.draw_line([255, 220, 180], x, y, x + length, y)
  end
  safe_cast(image + flare.gaussblur(8 * intensity) * 0.3)
end

def recipe(image, recipe_data)
  result = image
  recipe_data.each do |fx, params|
    intensity = params.is_a?(Hash) ? params['intensity'].to_f : params.to_f
    method = fx.gsub('_professional', '')
    result = respond_to?(method) ? send(method, result, intensity) : result
  end
  result
end
