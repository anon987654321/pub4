# frozen_string_literal: true

module Master
  module CLI
    module Face
      # web/public/face.part1.txt's generateFaceDepthMap, layer for layer: the
      # painting the web face samples its particles from. Each layer is the
      # gradient the canvas fills with, in the same order, on a unit square
      # (the canvas's 512 pixels as 1.0), composited source-over in grey, so a
      # point of the terminal face sits where the web face puts one. A change
      # to the web painting belongs here too.
      module DepthMap
        CX = 0.493
        CY = 0.46

        module_function

        # Brightness at u, v in 0..1, from 0.0 (black) to 1.0.
        def lum(u, v)
          LAYERS.reduce(0.0) { |under, layer| paint(layer, u, v, under) } / 255.0
        end

        def paint(layer, u, v, under)
          x, y = local(layer, u, v)
          return under unless clipped?(layer, x, y)

          t = layer[:linear] ? along(layer[:linear], x, y) : radius(layer[:radial], x, y)
          return under unless t

          grey, alpha = stop(layer[:stops], t.clamp(0.0, 1.0))
          (grey * alpha) + (under * (1 - alpha))
        end

        # ctx.translate then ctx.scale, undone for the point.
        def local(layer, u, v)
          tx, ty, sx, sy = layer[:transform] || [0.0, 0.0, 1.0, 1.0]
          [(u - tx) / sx, (v - ty) / sy]
        end

        def clipped?(layer, x, y)
          if (ellipse = layer[:ellipse])
            ex, ey, rx, ry = ellipse
            return (((x - ex) / rx)**2) + (((y - ey) / ry)**2) <= 1.0
          end
          return true unless (rect = layer[:rect])

          rx, ry, w, h = rect
          x.between?(rx, rx + w) && y.between?(ry, ry + h)
        end

        def along((x0, y0, x1, y1), x, y)
          dx = x1 - x0
          dy = y1 - y0
          (((x - x0) * dx) + ((y - y0) * dy)) / ((dx * dx) + (dy * dy))
        end

        # The canvas's two-circle radial gradient with a start radius of zero:
        # the largest t for which the point lies on the circle interpolated
        # between the focus and the end circle. Nil where no circle reaches.
        def radius((fx, fy, ex, ey, r), x, y)
          dx = ex - fx
          dy = ey - fy
          qx = x - fx
          qy = y - fy
          a = (dx * dx) + (dy * dy) - (r * r)
          b = -2 * ((qx * dx) + (qy * dy))
          c = (qx * qx) + (qy * qy)
          quadratic(a, b, c)
        end

        def quadratic(a, b, c)
          if a.abs < 1e-12
            return if b.zero? || (-c / b).negative?

            return -c / b
          end

          disc = (b * b) - (4 * a * c)
          return if disc.negative?

          roots = [(-b + Math.sqrt(disc)) / (2 * a), (-b - Math.sqrt(disc)) / (2 * a)].select { |t| t >= 0 }
          roots.max
        end

        def stop(stops, t)
          upper = stops.index { |at, _, _| at >= t } || (stops.size - 1)
          return stops[upper][1..] if upper.zero?

          t0, g0, a0 = stops[upper - 1]
          t1, g1, a1 = stops[upper]
          f = t1 == t0 ? 0.0 : (t - t0) / (t1 - t0)
          [g0 + ((g1 - g0) * f), a0 + ((a1 - a0) * f)]
        end

        def radial(x, y, r, stops, **rest) = { radial: [x, y, x, y, r], stops: }.merge(rest)

        FADE = [1.0, 0, 0.0].freeze

        LAYERS = [
          { radial: [CX, CY - 0.10, CX, CY, 0.36], ellipse: [CX, CY, 0.255, 0.48],
            stops: [[0, 228, 1.0], [0.34, 182, 1.0], [0.70, 72, 1.0], [1.0, 0, 1.0]] },
          *[-0.215, 0.215].map { |ex| radial(CX + ex, CY + 0.28, 0.16, [[0, 0, 0.98], [0.5, 0, 0.72], FADE]) },
          radial(CX, CY - 0.36, 0.30, [[0, 210, 0.78], [0.55, 150, 0.36], FADE]),
          radial(CX, CY - 0.44, 0.18, [[0, 198, 0.55], [0.62, 118, 0.18], FADE]),
          *[-0.20, 0.20].map { |ex| radial(CX + ex, CY - 0.28, 0.09, [[0, 0, 0.28], FADE]) },
          *[-0.112, 0.112].map do |ex|
            { linear: [CX + ex - 0.08, CY - 0.198, CX + ex + 0.08, CY - 0.186],
              rect: [CX + ex - 0.08, CY - 0.206, 0.16, 0.014], stops: [[0, 0, 0.0], [0.5, 0, 0.08], FADE] }
          end,
          *[-0.112, 0.112].map { |ex| radial(CX + ex, CY - 0.168, 0.078, [[0, 205, 0.38], [0.5, 150, 0.16], FADE]) },
          radial(CX, CY - 0.160, 0.022, [[0, 0, 0.22], FADE]),
          *[[-0.118, 0.66], [0.118, 0.62]].map do |ex, alpha|
            radial(0.0, 0.0, 0.106, [[0, 0, alpha], [0.45, 0, 0.70], [0.80, 0, 0.24], FADE],
                   transform: [CX + ex, CY - 0.088, 1.42, 1.08], ellipse: [0.0, 0.0, 0.106, 0.106])
          end,
          *[-0.118, 0.118].flat_map do |ex|
            [radial(CX + ex, CY - 0.088, 0.044, [[0, 185, 0.42], [0.55, 95, 0.18], FADE]),
             radial(CX + ex + 0.012, CY - 0.102, 0.028, [[0, 240, 0.78], [0.45, 190, 0.30], FADE])]
          end,
          { linear: [CX - 0.012, 0, CX + 0.012, 0], rect: [CX - 0.012, CY - 0.02, 0.024, 0.12],
            stops: [[0, 0, 0.0], [0.5, 205, 0.52], FADE] },
          radial(CX, CY + 0.082, 0.058, [[0, 245, 0.92], [0.30, 220, 0.68], [0.62, 150, 0.30], FADE]),
          *[-0.048, 0.048].map { |ex| radial(CX + ex, CY + 0.100, 0.022, [[0, 0, 0.32], FADE]) },
          *[-0.188, 0.188].map { |ex| radial(CX + ex, CY + 0.012, 0.098, [[0, 190, 0.38], [0.6, 100, 0.14], FADE]) },
          *[-0.068, 0.068].map { |ex| radial(CX + ex, CY + 0.142, 0.042, [[0, 0, 0.22], [0.6, 0, 0.08], FADE]) },
          radial(CX, CY + 0.158, 0.018, [[0, 0, 0.26], FADE]),
          radial(0.0, 0.0, 0.050, [[0, 215, 0.78], [0.38, 168, 0.42], FADE],
                 transform: [CX, CY + 0.198, 1.85, 1.0], ellipse: [0.0, 0.0, 0.050, 0.050]),
          radial(0.0, 0.0, 0.056, [[0, 205, 0.72], [0.38, 158, 0.38], FADE],
                 transform: [CX, CY + 0.212, 1.95, 1.0], ellipse: [0.0, 0.0, 0.056, 0.056]),
          { linear: [CX - 0.062, 0, CX + 0.062, 0], rect: [CX - 0.062, CY + 0.206, 0.124, 0.007],
            stops: [[0, 0, 0.0], [0.10, 0, 0.34], [0.5, 0, 0.42], [0.90, 0, 0.34], FADE] },
          radial(CX, CY + 0.238, 0.022, [[0, 0, 0.30], FADE]),
          radial(CX, CY + 0.318, 0.068, [[0, 155, 0.52], [0.58, 82, 0.20], FADE]),
          *[-0.36, 0.36].map { |ex| { radial: [CX + ex, CY - 0.04, CX + ex, CY + 0.04, 0.048], stops: [[0, 90, 0.10], FADE] } },
          { linear: [0, CY + 0.44, 0, 1.0], rect: [CX - 0.032, CY + 0.44, 0.064, 1.0 - (CY + 0.44)],
            stops: [[0, 58, 0.30], FADE] },
        ].freeze
      end
    end
  end
end
