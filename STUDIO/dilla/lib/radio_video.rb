# frozen_string_literal: true

require "fileutils"
require "socket"
require "yaml"

module RadioVideo
  ROOT = File.expand_path("../../..", __dir__)
  DILLA_ROOT = File.expand_path("..", __dir__)
  THREE_MODULE = File.join(ROOT, "MASTER", "web", "public", "three.face.module.js")
  POSTPRO_VIDEO_RECIPE = File.join(ROOT, "STUDIO", "postpro", "video.yml")
  DEFAULT_AUDIO = File.join(DILLA_ROOT, "dilla.wav")
  DEFAULT_OUTPUT = File.join(DILLA_ROOT, "dilla.mp4")
  WIDTH = 720
  HEIGHT = 1280
  FPS = 30

  module_function

  def run(argv)
    input = File.expand_path(argv.shift || ENV.fetch("DILLA_VIDEO_AUDIO", DEFAULT_AUDIO))
    format = ENV.fetch("DILLA_SHOWCASE_VIDEO_FORMAT", "mp4").to_s.downcase
    abort "video: DILLA_SHOWCASE_VIDEO_FORMAT must be mp4 or mov" unless %w[mp4 mov].include?(format)
    default_output = File.join(DILLA_ROOT, "dilla.#{format}")
    output = File.expand_path(argv.shift || ENV.fetch("DILLA_VIDEO_OUT", default_output))
    seconds = video_seconds

    abort "video: missing #{input} — run dilla showcase first" unless File.file?(input) && File.size?(input)
    abort "video: Three.js bundle is missing at #{THREE_MODULE}; run web assets:build first" unless File.file?(THREE_MODULE)
    validate_postpro_recipe!

    browser = browser_path or abort "video: no Chrome/Chromium browser found"
    ffmpeg = executable("ffmpeg") or abort "video: ffmpeg is required"
    tmp = Dir.mktmpdir("dilla-video-")
    capture = File.join(tmp, "radio.webm")

    server = Server.new(
      audio: input,
      three_module: THREE_MODULE,
      html: page_html(seconds),
      output: capture
    )
    url = "http://127.0.0.1:#{server.port}/"

    warn "video0: architectural score + #{File.basename(input)} -> #{output}"
    warn "video0: #{WIDTH}x#{HEIGHT} #{FPS}fps H.264/AAC, #{format_seconds(seconds)} cap"

    pid = Process.spawn(
      browser,
      "--headless=new",
      "--autoplay-policy=no-user-gesture-required",
      "--disable-dev-shm-usage",
      "--no-first-run",
      "--no-default-browser-check",
      "--window-size=#{WIDTH},#{HEIGHT}",
      url,
      out: File::NULL,
      err: File::NULL
    )

    begin
      abort "video: browser did not produce a capture" unless server.wait(timeout: [seconds + 45.0, 90.0].max)
      terminate(pid)
      raw = File.join(tmp, "raw.mp4")
      transcode!(ffmpeg, capture, raw, seconds)
      postpro_video!(ffmpeg, raw, output)
    ensure
      terminate(pid)
      server.close
      FileUtils.remove_entry(tmp) if File.exist?(tmp)
    end

    size_mb = (File.size(output) / 1_048_576.0).round(1)
    warn "video0: wrote #{output} (#{size_mb} MB)"
    output
  end

  def validate_postpro_recipe!
    return true if ENV["DILLA_VIDEO_POSTPRO"].to_s == "0"
    data = YAML.safe_load_file(POSTPRO_VIDEO_RECIPE, aliases: false)
    presets = data.fetch("presets")
    name = ENV.fetch("DILLA_VIDEO_POSTPRO", "dmt_bled").to_s
    preset = presets.fetch(name) { abort "video: no postpro video preset #{name.inspect}" }
    filters = Array(preset.fetch("filters")).map(&:to_s)
    abort "video: postpro preset #{name.inspect} is empty" if filters.empty?
    filters.each { |filter| abort "video: blank postpro filter" if filter.strip.empty? }
    true
  rescue Errno::ENOENT
    abort "video: missing shared Postpro recipe #{POSTPRO_VIDEO_RECIPE}"
  end

  def postpro_video!(ffmpeg, input, output)
    return FileUtils.mv(input, output) if ENV["DILLA_VIDEO_POSTPRO"].to_s == "0"
    data = YAML.safe_load_file(POSTPRO_VIDEO_RECIPE, aliases: false)
    name = ENV.fetch("DILLA_VIDEO_POSTPRO", "dmt_bled").to_s
    filters = Array(data.fetch("presets").fetch(name).fetch("filters")).map(&:to_s)
    partial = "#{output}.partial"
    args = [
      ffmpeg, "-y", "-hide_banner", "-loglevel", "error", "-i", input,
      "-vf", filters.join(","), "-c:v", "libx264", "-preset", "medium",
      "-profile:v", "high", "-pix_fmt", "yuv420p", "-crf", "22",
      "-c:a", "copy", "-movflags", "+faststart", partial
    ]
    system(*args) or abort "video: Postpro video grade #{name.inspect} failed"
    FileUtils.mv(partial, output)
    warn "video0: postpro=#{name} filters=#{filters.length}"
    output
  ensure
    FileUtils.rm_f(partial) if defined?(partial) && partial && File.file?(partial)
  end
  def video_seconds
    raw = ENV.fetch("DILLA_VIDEO_SECONDS", "0")
    value = Float(raw, exception: false)
    abort "video: DILLA_VIDEO_SECONDS must be 0 or a positive number" unless value && value >= 0
    value
  end

  def executable(name)
    candidates = [
      "/opt/homebrew/bin/#{name}",
      "/usr/local/bin/#{name}",
      *ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).map { |dir| File.join(dir, name) }
    ]
    candidates.uniq.find { |path| File.executable?(path) && !File.directory?(path) }
  end

  def browser_path
    candidates = [
      "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
      "/Applications/Chromium.app/Contents/MacOS/Chromium",
      "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
      "/opt/homebrew/bin/google-chrome",
      "/opt/homebrew/bin/chromium",
      "/usr/local/bin/google-chrome",
      "/usr/local/bin/chromium"
    ]
    candidates.find { |path| File.executable?(path) } || executable("google-chrome") || executable("chromium") || executable("chrome")
  end

  def terminate(pid)
    return unless pid
    Process.kill("TERM", pid)
    Process.wait(pid)
  rescue Errno::ESRCH, Errno::ECHILD
    nil
  ensure
    begin
      Process.kill("KILL", pid)
    rescue Errno::ESRCH, Errno::ECHILD
      nil
    end
  end

  def transcode!(ffmpeg, capture, output, seconds)
    FileUtils.mkdir_p(File.dirname(output))
    args = [
      ffmpeg, "-y", "-hide_banner", "-loglevel", "error",
      "-i", capture
    ]
    args += ["-t", seconds.to_s] if seconds.positive?
    args.concat([
      "-vf", "scale=#{WIDTH}:#{HEIGHT}:force_original_aspect_ratio=decrease,pad=#{WIDTH}:#{HEIGHT}:(ow-iw)/2:(oh-ih)/2:black,format=yuv420p",
      "-r", FPS.to_s,
      "-c:v", "libx264",
      "-preset", "medium",
      "-profile:v", "high",
      "-level:v", "3.1",
      "-crf", "24",
      "-c:a", "aac",
      "-b:a", "128k",
      "-ar", "48000",
      "-ac", "2",
      "-movflags", "+faststart",
      output
    ])
    system(*args) or abort "video: ffmpeg could not write #{output}"
  end

  def format_seconds(value)
    return "full source" if value.zero?
    format("%.1fs", value)
  end

  def page_html(seconds)
    <<~HTML
      <!doctype html>
      <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=#{WIDTH},height=#{HEIGHT},initial-scale=1">
        <style>
          :root { color-scheme: dark; }
          html, body { margin: 0; padding: 0; width: #{WIDTH}px; height: #{HEIGHT}px; background: #07080b; overflow: hidden; }
          canvas { display: block; width: #{WIDTH}px; height: #{HEIGHT}px; }
          .hud {
            position: fixed; inset: 0; pointer-events: none; user-select: none;
            color: rgba(230,234,236,.78); font: 500 13px/1.35 ui-monospace, SFMono-Regular, Menlo, monospace;
            letter-spacing: .16em; text-transform: uppercase;
          }
          .title { position:absolute; top:28px; left:32px; }
          .state { position:absolute; right:30px; bottom:28px; text-align:right; }
          .rule { position:absolute; left:32px; right:32px; bottom:22px; height:1px; background:rgba(210,214,218,.16); }
          .title strong { font-weight:700; color:rgba(244,238,223,.92); }
        </style>
      </head>
      <body>
        <canvas id="architectural-score" width="#{WIDTH}" height="#{HEIGHT}"></canvas>
        <div class="hud">
          <div class="title"><strong>DILLA TIME</strong><br>LIVE ARCHITECTURE / THREE.JS</div>
          <div class="state" id="state">HARMONY / POCKET / SPACE</div>
          <div class="rule"></div>
        </div>
        <audio id="audio" preload="auto"></audio>
        <script type="module">
          import * as THREE from "/three.face.module.js"

          const audio = document.getElementById("audio")
          const canvas = document.getElementById("architectural-score")
          const state = document.getElementById("state")
          const width = #{WIDTH}
          const height = #{HEIGHT}
          const limit = #{seconds}

          const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, powerPreference: "high-performance" })
          renderer.setSize(width, height, false)
          renderer.setPixelRatio(1)
          renderer.setClearColor(0x07080b, 1)
          if ("outputColorSpace" in renderer && THREE.SRGBColorSpace) renderer.outputColorSpace = THREE.SRGBColorSpace
          if ("toneMapping" in renderer && THREE.ACESFilmicToneMapping) {
            renderer.toneMapping = THREE.ACESFilmicToneMapping
            renderer.toneMappingExposure = 1.0
          }

          const scene = new THREE.Scene()
          scene.fog = new THREE.FogExp2(0x07080b, 0.031)
          const camera = new THREE.PerspectiveCamera(39, width / height, 0.1, 90)
          camera.position.set(0, 4.6, 18.5)

          const hemi = new THREE.HemisphereLight(0xc8d0d4, 0x080a0d, 0.85)
          scene.add(hemi)
          const key = new THREE.DirectionalLight(0xf0e8d5, 1.65)
          key.position.set(4, 10, 7)
          scene.add(key)
          const rim = new THREE.PointLight(0x46658a, 2.1, 42)
          rim.position.set(-7, 5, -8)
          scene.add(rim)

          const concrete = new THREE.MeshStandardMaterial({ color: 0x8d9194, roughness: 0.78, metalness: 0.12 })
          const graphite = new THREE.MeshStandardMaterial({ color: 0x1a1e24, roughness: 0.62, metalness: 0.34 })
          const brass = new THREE.MeshStandardMaterial({ color: 0xb79b61, roughness: 0.42, metalness: 0.62, emissive: 0x2b210f, emissiveIntensity: 0.55 })
          const blue = new THREE.MeshStandardMaterial({ color: 0x29466a, roughness: 0.5, metalness: 0.4, emissive: 0x0b1830, emissiveIntensity: 0.8 })
          const lineMat = new THREE.LineBasicMaterial({ color: 0xc8b890, transparent: true, opacity: 0.32 })
          const glowMat = new THREE.MeshBasicMaterial({ color: 0xc8b890, transparent: true, opacity: 0.45 })
          const darkLine = new THREE.LineBasicMaterial({ color: 0x52616f, transparent: true, opacity: 0.28 })

          const floor = new THREE.Mesh(new THREE.PlaneGeometry(34, 74), new THREE.MeshStandardMaterial({
            color: 0x0b0e12, roughness: 0.92, metalness: 0.08
          }))
          floor.rotation.x = -Math.PI / 2
          floor.position.set(0, -0.08, -13)
          scene.add(floor)

          const grid = new THREE.GridHelper(34, 34, 0x343a42, 0x171b21)
          grid.position.set(0, 0, -13)
          grid.material.transparent = true
          grid.material.opacity = 0.48
          scene.add(grid)

          const plinth = new THREE.Mesh(new THREE.BoxGeometry(11.8, 0.55, 34), graphite)
          plinth.position.set(0, 0.18, -11)
          scene.add(plinth)

          const nave = new THREE.Group()
          scene.add(nave)

          const bays = 12
          const columns = []
          for (let i = 0; i < bays; i++) {
            const z = 8 - i * 2.55
            const x = 5.15
            for (const side of [-1, 1]) {
              const column = new THREE.Mesh(new THREE.BoxGeometry(0.58, 6.0, 0.58), concrete)
              column.position.set(side * x, 3.0, z)
              nave.add(column)
              columns.push({ mesh: column, side, index: i })
            }
            const beam = new THREE.Mesh(new THREE.BoxGeometry(11.15, 0.28, 0.42), concrete)
            beam.position.set(0, 6.1, z)
            nave.add(beam)
          }

          const roof = new THREE.Mesh(new THREE.BoxGeometry(12.2, 0.22, 31.0), graphite)
          roof.position.set(0, 6.35, -6.2)
          nave.add(roof)

          const aisle = new THREE.Mesh(new THREE.BoxGeometry(1.1, 0.18, 30), brass)
          aisle.position.set(0, 0.55, -6.8)
          nave.add(aisle)

          const vaults = []
          for (let row = 0; row < 9; row++) {
            const z = 6.2 - row * 3.1
            const points = []
            for (let i = 0; i <= 36; i++) {
              const t = i / 36
              const x = -5.0 + t * 10.0
              const arch = Math.sin(t * Math.PI)
              points.push(new THREE.Vector3(x, 6.1 + arch * 2.2, z))
            }
            const geo = new THREE.BufferGeometry().setFromPoints(points)
            const line = new THREE.Line(geo, lineMat.clone())
            vaults.push(line)
            scene.add(line)
          }

          const atrium = new THREE.Group()
          atrium.position.set(0, 3.1, -5.0)
          scene.add(atrium)

          const core = new THREE.Mesh(new THREE.CylinderGeometry(1.55, 2.0, 0.48, 64), brass)
          core.rotation.x = Math.PI / 2
          atrium.add(core)

          const ring = new THREE.Mesh(new THREE.TorusGeometry(2.15, 0.06, 10, 96), glowMat)
          ring.rotation.x = Math.PI / 2
          atrium.add(ring)

          const ring2 = new THREE.Mesh(new THREE.TorusGeometry(3.05, 0.035, 8, 96), new THREE.MeshBasicMaterial({
            color: 0x617a96, transparent: true, opacity: 0.22
          }))
          ring2.rotation.x = Math.PI / 2
          atrium.add(ring2)

          const scoreBars = []
          for (let i = 0; i < 16; i++) {
            const bar = new THREE.Mesh(new THREE.BoxGeometry(0.11, 2.1, 0.11), blue)
            const angle = (i / 16) * Math.PI * 2
            bar.position.set(Math.cos(angle) * 3.75, 0.9, Math.sin(angle) * 3.75)
            atrium.add(bar)
            scoreBars.push(bar)
          }

          const orbit = new THREE.Group()
          scene.add(orbit)
          for (let i = 0; i < 8; i++) {
            const angle = (i / 8) * Math.PI * 2
            const slab = new THREE.Mesh(new THREE.BoxGeometry(0.18, 0.18, 7.8), concrete)
            slab.position.set(Math.cos(angle) * 8.5, 0.2, Math.sin(angle) * 8.5 - 8)
            slab.rotation.y = angle
            orbit.add(slab)
          }

          // DMT fracture field: architectural debris that deconstructs and
          // reassembles with the score instead of becoming a generic particle
          // cloud. The seed is fixed, but its motion is not periodic.
          const shardGroup = new THREE.Group()
          scene.add(shardGroup)
          const shards = []
          for (let i = 0; i < 84; i++) {
            const geo = i % 3 === 0
              ? new THREE.TetrahedronGeometry(0.18 + (i % 7) * 0.025, 0)
              : new THREE.BoxGeometry(0.12, 0.12, 0.12)
            const mat = new THREE.MeshStandardMaterial({
              color: i % 2 ? 0x5e7494 : 0x9b835c,
              roughness: 0.42,
              metalness: 0.48,
              emissive: 0x0b1830,
              emissiveIntensity: 0.7
            })
            const mesh = new THREE.Mesh(geo, mat)
            const angle = i * 2.399963
            const radius = 3.0 + (i % 13) * 0.58
            mesh.position.set(
              Math.cos(angle) * radius,
              0.25 + (i % 17) * 0.29,
              -4.5 - (i % 25) * 1.8
            )
            mesh.rotation.set(angle * 0.37, angle * 0.71, angle * 0.19)
            shardGroup.add(mesh)
            shards.push({ mesh, index: i, phase: (i * 1.61803398875) % (Math.PI * 2) })
          }

          const fractures = []
          for (let i = 0; i < 16; i++) {
            const points = []
            for (let j = 0; j < 10; j++) {
              const z = 7.5 - j * 3.0
              const x = Math.sin(i * 1.37 + j * 0.83) * (2.2 + j * 0.45)
              const y = 0.7 + Math.cos(i * 0.7 + j * 1.1) * 1.8
              points.push(new THREE.Vector3(x, y, z))
            }
            const geo = new THREE.BufferGeometry().setFromPoints(points)
            const line = new THREE.Line(
              geo,
              new THREE.LineBasicMaterial({
                color: 0x9b8c72,
                transparent: true,
                opacity: 0.18
              })
            )
            scene.add(line)
            fractures.push(line)
          }

          const context = new (window.AudioContext || window.webkitAudioContext)()
          const analyser = context.createAnalyser()
          analyser.fftSize = 2048
          analyser.smoothingTimeConstant = 0.72
          const source = context.createMediaElementSource(audio)
          const destination = context.createMediaStreamDestination()
          source.connect(analyser)
          analyser.connect(destination)
          const bins = new Uint8Array(analyser.frequencyBinCount)
          const previous = new Uint8Array(analyser.frequencyBinCount)

          const videoStream = canvas.captureStream(#{FPS})
          const stream = new MediaStream([
            ...videoStream.getVideoTracks(),
            ...destination.stream.getAudioTracks()
          ])

          const mimeTypes = [
            "video/webm;codecs=vp9,opus",
            "video/webm;codecs=vp8,opus",
            "video/webm"
          ]
          const mimeType = mimeTypes.find((type) => MediaRecorder.isTypeSupported(type))
          if (!mimeType) throw new Error("MediaRecorder WebM unavailable")

          const recorder = new MediaRecorder(stream, {
            mimeType,
            videoBitsPerSecond: 8_000_000,
            audioBitsPerSecond: 192_000
          })
          const chunks = []
          recorder.ondataavailable = (event) => {
            if (event.data.size) chunks.push(event.data)
          }

          function bands() {
            analyser.getByteFrequencyData(bins)
            let bass = 0, mid = 0, high = 0, flux = 0
            const bassEnd = Math.max(2, Math.floor(bins.length * 0.018))
            const midEnd = Math.max(bassEnd + 1, Math.floor(bins.length * 0.15))
            for (let i = 0; i < bins.length; i++) {
              const v = bins[i]
              flux += Math.max(0, v - previous[i])
              previous[i] = v
              if (i < bassEnd) bass += v
              else if (i < midEnd) mid += v
              else high += v
            }
            bass = Math.min(1, bass / bassEnd / 255 * 1.55)
            mid = Math.min(1, mid / (midEnd - bassEnd) / 255 * 1.15)
            high = Math.min(1, high / (bins.length - midEnd) / 255 * 3.0)
            flux = Math.min(1, flux / bins.length / 255 * 7.0)
            return { bass, mid, high, flux }
          }

          const draw = () => {
            const a = bands()
            const t = performance.now() * 0.001
            const pulse = Math.min(1, a.flux * 1.4 + a.bass * 0.35)
            const clamp01 = (value) => Math.max(0, Math.min(1, value))
            const tension = clamp01(a.mid * 0.52 + a.high * 0.28 + a.flux * 0.42)
            const release = 1 - tension
            const parametricField = (x, z, phase) => {
              const spine = Math.exp(-Math.abs(x) * 0.28)
              const depth = Math.exp(-Math.abs(z + 7) * 0.035)
              const wave = Math.sin(performance.now() * 0.00031 + z * 0.17 + x * 0.23 + phase)
              return {
                mass: clamp01(a.bass * 0.72 + spine * 0.18 + depth * 0.08),
                span: clamp01(a.mid * 0.78 + (1 - spine) * 0.12),
                porosity: clamp01(a.high * 0.72 + Math.max(0, wave) * 0.18),
                fracture: clamp01(a.flux * 0.72 + Math.abs(wave) * 0.18)
              }
            }

            camera.position.x = Math.sin(t * 0.075) * (2.8 + tension * 2.4) + Math.sin(t * 0.019) * 1.1
            camera.position.y = 4.2 + Math.sin(t * 0.11) * 0.7 + a.mid * 0.9 + release * 0.45
            camera.position.z = 18.0 - Math.min(5.5, audio.currentTime * 0.07) + Math.sin(t * 0.041) * 1.8
            camera.lookAt(0, 3.0 + a.bass * 0.45 - release * 0.25, -6.0)

            rim.intensity = 1.6 + a.high * 4.5
            key.intensity = 1.35 + a.mid * 1.2
            ring.scale.setScalar(1.0 + pulse * 0.24)
            ring.material.opacity = 0.32 + pulse * 0.45
            core.rotation.z = t * 0.13
            core.scale.set(0.94 + release * 0.10, 1.0 + a.bass * 0.28 + tension * 0.26, 0.94 + a.high * 0.18)
            atrium.rotation.y = t * 0.045 + a.high * 0.08
            orbit.rotation.y = t * 0.012
            shardGroup.rotation.y = t * 0.018 + a.high * 0.12
            shardGroup.rotation.x = Math.sin(t * 0.07) * 0.08

            shards.forEach(({ mesh, index, phase }) => {
              const local = Math.sin(t * (0.28 + (index % 9) * 0.021) + phase)
              mesh.rotation.x += 0.002 + a.flux * 0.012
              mesh.rotation.y -= 0.001 + a.mid * 0.009
              mesh.position.y += local * 0.004 + a.bass * 0.012
              const scale = 0.48 + a.high * 0.52 + Math.max(0, local) * 0.24
              mesh.scale.setScalar(scale)
              mesh.material.emissiveIntensity = 0.25 + a.high * 1.05
              mesh.material.opacity = 0.5 + a.high * 0.45
              mesh.material.transparent = true
            })

            fractures.forEach((line, index) => {
              line.rotation.y = Math.sin(t * 0.07 + index) * 0.07 + a.flux * 0.12
              line.rotation.x = Math.sin(t * 0.05 + index * 0.31) * 0.035
              line.material.opacity = 0.07 + a.mid * 0.24 + a.flux * 0.2
            })

            columns.forEach(({ mesh, side, index }) => {
              const local = Math.sin(t * 0.43 + index * 0.62 + side * 0.35)
              const f = parametricField(mesh.position.x, mesh.position.z, index * 0.13)
              const height = 0.82 + f.mass * 0.52 + f.span * 0.24 + Math.max(0, local) * 0.12
              const taper = 0.84 + f.porosity * 0.2
              mesh.scale.set(taper, height, taper)
              mesh.position.y = 3.0 + (height - 1) * 2.65
              mesh.rotation.z = side * local * f.fracture * 0.025
              mesh.rotation.x = Math.sin(t * 0.11 + index) * f.fracture * 0.018
              mesh.material.emissiveIntensity = 0.12 + a.high * 0.7 + f.fracture * 0.35
            })

            vaults.forEach((line, index) => {
              const s = 0.7 + 0.15 * Math.sin(t * 0.35 + index) + a.high * 0.28
              const compression = 0.82 + a.bass * 0.22 + tension * 0.30
              line.scale.set(1.0 + a.mid * 0.03, s * compression, 1.0 + tension * 0.015)
              line.position.y = release * 0.18 * Math.sin(t * 0.23 + index)
              line.rotation.z = Math.sin(t * 0.13 + index) * tension * 0.012
              line.material.opacity = 0.18 + a.mid * 0.28 + a.high * 0.08
            })

            scoreBars.forEach((bar, index) => {
              const r = 0.74 + a.bass * 0.8 + a.high * 0.25
              const local = 0.5 + 0.5 * Math.sin(t * 0.8 + index * 0.9)
              bar.scale.y = 0.25 + r * (0.45 + local * 0.35)
              bar.position.y = 0.9 + bar.scale.y * 0.55
            })

            state.textContent = `BASS ${Math.round(a.bass * 100)} / MID ${Math.round(a.mid * 100)} / AIR ${Math.round(a.high * 100)} / TENSION ${Math.round(tension * 100)} — PARAMETRIC SCORE`
            renderer.render(scene, camera)
            requestAnimationFrame(draw)
          }

          let stopped = false
          const finish = () => {
            if (stopped) return
            stopped = true
            audio.pause()
            if (recorder.state !== "inactive") recorder.stop()
          }

          recorder.onstop = async () => {
            const blob = new Blob(chunks, { type: mimeType })
            const response = await fetch("/capture", { method: "POST", body: blob })
            if (!response.ok) throw new Error(await response.text())
          }

          audio.addEventListener("ended", finish, { once: true })
          audio.addEventListener("loadedmetadata", async () => {
            await context.resume()
            recorder.start(1000)
            draw()
            await audio.play()
            const duration = limit > 0 ? Math.min(limit, audio.duration) : audio.duration
            window.setTimeout(finish, Math.max(0.1, duration) * 1000)
          }, { once: true })

          audio.src = "/audio.wav"
          audio.load()
        </script>
      </body>
      </html>
    HTML
  end

  class Server
    attr_reader :port

    def initialize(audio:, three_module:, html:, output:)
      @audio = audio
      @three_module = three_module
      @html = html
      @output = output
      @server = TCPServer.new("127.0.0.1", 0)
      @port = @server.addr[1]
      @mutex = Mutex.new
      @condition = ConditionVariable.new
      @captured = false
      @error = nil
      @thread = Thread.new { accept_loop }
    end

    def wait(timeout:)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      @mutex.synchronize do
        until @captured || @error
          remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
          break if remaining <= 0
          @condition.wait(@mutex, remaining)
        end
        raise @error if @error
        @captured
      end
    end

    def close
      @server.close
      @thread&.kill
      @thread&.join
    rescue IOError, Errno::EBADF
      nil
    end

    private

    def accept_loop
      loop do
        socket = @server.accept
        Thread.new(socket) do |client|
          handle(client)
        rescue StandardError => e
          @mutex.synchronize do
            @error ||= e
            @condition.broadcast
          end
        ensure
          client.close rescue nil
        end
      end
    rescue IOError, Errno::EBADF
      nil
    end

    def handle(client)
      request = client.gets
      return unless request

      method, target, = request.split
      headers = {}
      while (line = client.gets)
        line = line.chomp
        break if line.empty? || line == "\r"
        key, value = line.split(":", 2)
        headers[key.downcase] = value.to_s.strip if key
      end

      path = target.to_s.split("?", 2).first
      case [method, path]
      when ["GET", "/"]
        respond(client, 200, "text/html; charset=utf-8", @html)
      when ["GET", "/three.face.module.js"]
        respond_file(client, @three_module, "text/javascript; charset=utf-8")
      when ["GET", "/visual_field.js"]
        respond(client, 200, "text/javascript; charset=utf-8", "export function publishVisual() {}")
      when ["GET", "/audio.wav"]
        respond_file(client, @audio, "audio/wav")
      when ["POST", "/capture"]
        receive_body(client, headers.fetch("content-length").to_i, @output)
        respond(client, 200, "text/plain; charset=utf-8", "ok")
        @mutex.synchronize do
          @captured = true
          @condition.broadcast
        end
      when ["POST", "/fail"]
        length = headers.fetch("content-length", "0").to_i
        message = read_body(client, length)
        @mutex.synchronize do
          @error = RuntimeError.new("browser export failed: #{message}")
          @condition.broadcast
        end
        respond(client, 500, "text/plain; charset=utf-8", "failed")
      else
        respond(client, 404, "text/plain; charset=utf-8", "not found")
      end
    end

    def respond_file(client, path, type)
      size = File.size(path)
      client.write("HTTP/1.1 200 OK\r\nContent-Type: #{type}\r\nContent-Length: #{size}\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n")
      File.open(path, "rb") do |file|
        while (chunk = file.read(65_536))
          client.write(chunk)
        end
      end
    end

    def respond(client, status, type, body)
      body = body.to_s.b
      client.write("HTTP/1.1 #{status} OK\r\nContent-Type: #{type}\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n")
      client.write(body)
    end

    def receive_body(client, length, path)
      raise "video: browser sent an empty capture" if length <= 0
      File.open(path, "wb") do |file|
        remaining = length
        while remaining.positive?
          chunk = client.read([remaining, 65_536].min)
          raise EOFError, "capture ended early" unless chunk
          file.write(chunk)
          remaining -= chunk.bytesize
        end
      end
    end

    def read_body(client, length)
      return "" if length <= 0
      client.read(length).to_s
    end
  end
end
