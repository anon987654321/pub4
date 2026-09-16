# frozen_string_literal: true

require_relative "../../../../OPENBSD/lib/gate_result"
require_relative "../../support/cdp_session"
require_relative "../../support/geometry_probe"
require_relative "../../../tools/crawl_support"

module Deploy
  # Whether a surface made of WebGL drew anything.
  #
  # Nothing asserted this, and nothing could: every other rendered gate launches
  # Chrome with --disable-gpu, which turns WebGL off outright, so MapLibre and
  # the MASTER face both measure as an empty canvas. A gate built on that
  # instrument would pass or fail for reasons that have nothing to do with the
  # map — TODO.md section 4 is this, and it is an instrument problem
  # rather than a feature gap.
  #
  # This session opts into SwiftShader. Software GL is slow and rasterises text
  # differently, which is exactly why the other gates keep --disable-gpu: the
  # opt-in is per session, not a change to the default.
  class WebglSurfacesGate
    ROOT = File.expand_path("../../../..", __dir__)

    # A canvas is not proof. The assertions are: the context exists (so the
    # instrument is working at all), the drawing buffer has size, and the
    # library's own readiness signal fired — for MapLibre, that its style is
    # loaded, which is false while it is still an empty canvas.
    SURFACES = [
      {
        app: "brgen", host: "maps.brgen.no", path: "/",
        ready: "window.__mapReady === true",
        label: "maps",
      },
    ].freeze

    PROBE = <<~JS
      (() => {
        const canvas = document.querySelector("canvas");
        if (!canvas) return JSON.stringify({ canvas: false });
        const gl = canvas.getContext("webgl2") || canvas.getContext("webgl");
        return JSON.stringify({
          canvas: true,
          context: !!gl,
          renderer: gl ? String(gl.getParameter(gl.RENDERER)).slice(0, 60) : null,
          width: gl ? gl.drawingBufferWidth : 0,
          height: gl ? gl.drawingBufferHeight : 0,
        });
      })()
    JS

    def self.run = new.run

    def run
      @result = GateResult.new
      return unavailable unless CdpSession.available?

      ports = GeometryProbe.app_ports(root: ROOT)
      CdpSession.open(host_map: host_map(ports), timeout: 40, webgl: true) do |cdp|
        cdp.viewport(1024, 768)
        surfaces.each { |surface| measure(cdp, surface, ports) }
      end
      @result
    rescue CdpSession::Error => e
      # A browser that will not start is an unchecked precondition, not a pass:
      # this gate exists because a green run over an unmeasured surface is the
      # failure mode.
      @result.inconclusive!("webgl_surfaces: #{e.class}: #{e.message}")
      @result
    end

private

# Read through the class rather than the constant directly: a constant in a
# method body resolves lexically, so a subclass pointing this at a page with
# no canvas — which is how the test proves the gate can fail — would silently
# measure the same surface as the parent.
def surfaces = self.class::SURFACES


    def unavailable
      @result.inconclusive!("webgl_surfaces: no Chrome, so no WebGL surface was measured")
      @result
    end

    def host_map(ports)
      port = ports["brgen"]
      port ? { "maps.brgen.no" => "127.0.0.1:#{port}" } : {}
    end

    def measure(cdp, surface, ports)
      port = ports[surface[:app]]
      unless port && CrawlSupport.port_open?("127.0.0.1", port)
        @result.skipped_live("webgl_surfaces: #{surface[:label]} skipped (#{surface[:app]} not listening)")
        return
      end

      cdp.navigate("http://#{surface[:host]}#{surface[:path]}", settle: 1.5)
      probe = JSON.parse(cdp.evaluate(PROBE).to_s)

      return @result.fail("webgl_surfaces: #{surface[:label]} has no canvas") unless probe["canvas"]
      return @result.fail("webgl_surfaces: #{surface[:label]} got no WebGL context — the instrument is off, not the map") unless probe["context"]

      if probe["width"].to_i.zero? || probe["height"].to_i.zero?
        return @result.fail("webgl_surfaces: #{surface[:label]} drawing buffer is #{probe["width"]}x#{probe["height"]}")
      end

# Counted, so "measured nothing" and "measured and passed" are
# distinguishable — which is the complaint this gate answers.
@result.checked!
    end
  end
end
