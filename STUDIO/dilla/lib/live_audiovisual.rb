# frozen_string_literal: true

require "json"
require "socket"

module LiveAudiovisual
  ROOT = File.expand_path("../../..", __dir__)
  THREE_MODULE = File.join(ROOT, "MASTER", "web", "public", "three.face.module.js")
  WIDTH = 1280
  HEIGHT = 720

  class Server
    attr_reader :port

    def initialize
      @server = TCPServer.new("127.0.0.1", 0)
      @port = @server.addr[1]
      @mutex = Mutex.new
      @state = { scene: "boot", seed: 0, started_at: monotonic, hue: 0.58, energy: 0.2, fracture: 0.2 }
      @thread = Thread.new { accept_loop }
    end

    def publish(row)
      @mutex.synchronize { @state.merge!(row.transform_keys(&:to_sym)) }
    end

    def close
      @server.close
      @thread&.kill
      @thread&.join
    rescue IOError, Errno::EBADF
      nil
    end

    private

    def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    def state
      @mutex.synchronize { @state.merge(now: monotonic) }
    end

    def accept_loop
      loop do
        socket = @server.accept
        Thread.new(socket) do |client|
          handle(client)
        rescue StandardError
          nil
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
      _method, target, = request.split
      while (line = client.gets)
        break if line.chomp.empty?
      end
      case target.to_s.split("?", 2).first
      when "/"
        respond(client, 200, "text/html; charset=utf-8", LiveAudiovisual.page)
      when "/three.face.module.js"
        respond_file(client, THREE_MODULE, "text/javascript; charset=utf-8")
      when "/state"
        respond(client, 200, "application/json; charset=utf-8", JSON.generate(state))
      else
        respond(client, 404, "text/plain; charset=utf-8", "not found")
      end
    end

    def respond_file(client, path, type)
      size = File.size(path)
      client.write("HTTP/1.1 200 OK\r\nContent-Type: #{type}\r\nContent-Length: #{size}\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n")
      File.open(path, "rb") { |io| while (chunk = io.read(65_536)); client.write(chunk); end }
    end

    def respond(client, status, type, body)
      reason = status == 200 ? "OK" : "Not Found"
      body = body.to_s.b
      client.write("HTTP/1.1 #{status} #{reason}\r\nContent-Type: #{type}\r\nContent-Length: #{body.bytesize}\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n")
      client.write(body)
    end
  end

  @server = nil
  @browser = nil

  module_function

  def start!
    return @server if @server
    unless File.file?(THREE_MODULE)
      warn "visual0: local Three.js bundle missing; sound stays live without visuals"
      return nil
    end
    browser = browser_path
    unless browser
      warn "visual0: no Chrome/Chromium; sound stays live without visuals"
      return nil
    end
    @server = Server.new
    @browser = Process.spawn(
      browser, "--headless=new", "--disable-dev-shm-usage", "--no-first-run",
      "--no-default-browser-check", "--window-size=#{WIDTH},#{HEIGHT}",
      "http://127.0.0.1:#{@server.port}/", out: File::NULL, err: File::NULL
    )
    warn "visual0: DMT architecture http://127.0.0.1:#{@server.port}"
    @server
  rescue StandardError => e
    warn "visual0: disabled #{e.class}: #{e.message}"
    stop!
    nil
  end

  def publish(row = {})
    @server&.publish(row)
  end

  def stop!
    Process.kill("TERM", @browser) rescue nil if @browser
    Process.wait(@browser) rescue nil if @browser
    @browser = nil
    @server&.close
    @server = nil
  rescue StandardError
    @browser = nil
    @server = nil
  end

  def browser_path
    [
      "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
      "/Applications/Chromium.app/Contents/MacOS/Chromium",
      "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
      "/opt/homebrew/bin/google-chrome",
      "/opt/homebrew/bin/chromium",
      "/usr/local/bin/google-chrome"
    ].find { |path| File.executable?(path) }
  end

  def page
    abort "visual0: missing #{THREE_MODULE}" unless File.file?(THREE_MODULE)
    <<~HTML
      <!doctype html>
      <html lang="en"><head><meta charset="utf-8">
      <meta name="viewport" content="width=#{WIDTH},height=#{HEIGHT},initial-scale=1">
      <style>
        html,body{margin:0;width:100%;height:100%;overflow:hidden;background:#040509}
        canvas{display:block;width:100%;height:100%}
        .hud{position:fixed;inset:0;pointer-events:none;color:rgba(235,235,232,.72);font:500 12px/1.4 ui-monospace,Menlo,monospace;letter-spacing:.12em;text-transform:uppercase}
        .title{position:absolute;left:24px;top:20px}.state{position:absolute;right:24px;bottom:20px;text-align:right}.name{color:rgba(243,232,204,.92);font-weight:700}
      </style></head><body>
      <canvas id="dmt"></canvas>
      <div class="hud"><div class="title"><span class="name">DILLA TIME</span><br>LIVE / DEFRAGMENTING ARCHITECTURE</div><div id="state" class="state">BOOT / POCKET / SPACE</div></div>
      <script type="module">
        import * as THREE from "/three.face.module.js"

        const canvas=document.getElementById("dmt"), label=document.getElementById("state")
        const renderer=new THREE.WebGLRenderer({canvas,antialias:true,powerPreference:"high-performance"})
        renderer.setPixelRatio(Math.min(devicePixelRatio||1,1.5))
        renderer.setSize(innerWidth,innerHeight,false)
        if ("outputColorSpace" in renderer && THREE.SRGBColorSpace) renderer.outputColorSpace=THREE.SRGBColorSpace
        const scene=new THREE.Scene()
        scene.fog=new THREE.FogExp2(0x040509,0.018)
        const camera=new THREE.PerspectiveCamera(48,innerWidth/innerHeight,0.1,180)
        camera.position.set(0,3.2,18)

        const hemi=new THREE.HemisphereLight(0x9fb0c8,0x08090e,1.0); scene.add(hemi)
        const key=new THREE.DirectionalLight(0xffebcf,2.0); key.position.set(4,10,8); scene.add(key)
        const point=new THREE.PointLight(0x496caa,4.0,50); point.position.set(-4,5,-10); scene.add(point)

        const floor=new THREE.Mesh(new THREE.PlaneGeometry(42,140),new THREE.MeshStandardMaterial({color:0x090c12,roughness:.9,metalness:.1}))
        floor.rotation.x=-Math.PI/2; floor.position.y=-1; floor.position.z=-28; scene.add(floor)
        const world=new THREE.Group(); scene.add(world)

        const architecture=[]
        for(let i=0;i<16;i++){
          const z=8-i*3.6
          const beam=new THREE.Mesh(new THREE.BoxGeometry(16,.22,.32),new THREE.MeshStandardMaterial({color:0x343944,roughness:.72,metalness:.28}))
          beam.position.set(0,7,z); world.add(beam)
          for(const side of [-1,1]){
            const col=new THREE.Mesh(new THREE.BoxGeometry(.42,8,.42),new THREE.MeshStandardMaterial({color:0x61656d,roughness:.82,metalness:.16}))
            col.position.set(side*6.3,3,z); world.add(col); architecture.push({mesh:col,index:i,side})
          }
        }

        const slabs=new THREE.Group(); scene.add(slabs)
        for(let i=0;i<12;i++){
          const slab=new THREE.Mesh(new THREE.BoxGeometry(.16,.16,8.5),new THREE.MeshStandardMaterial({color:0x8e7954,roughness:.48,metalness:.58,emissive:0x261e10,emissiveIntensity:.4}))
          const a=i/12*Math.PI*2; slab.position.set(Math.cos(a)*9.2,1.6+(i%3)*1.2,-15+Math.sin(a)*8); slab.rotation.y=a+Math.PI/2; slabs.add(slab)
        }

        const core=new THREE.Group(); scene.add(core)
        const coreMesh=new THREE.Mesh(new THREE.IcosahedronGeometry(2.2,1),new THREE.MeshStandardMaterial({color:0x35547e,metalness:.5,roughness:.4,emissive:0x102645,emissiveIntensity:1.2,wireframe:true}))
        core.add(coreMesh)
        const rings=[]
        for(let i=0;i<7;i++){
          const ring=new THREE.Mesh(new THREE.TorusGeometry(2.9+i*.7,.025+i*.008,8,80),new THREE.MeshBasicMaterial({color:0xc6a86f,transparent:true,opacity:.25}))
          ring.rotation.x=Math.PI/2; core.add(ring); rings.push(ring)
        }

        const shards=[], shardGroup=new THREE.Group(); scene.add(shardGroup)
        for(let i=0;i<96;i++){
          const geo=i%3===0?new THREE.TetrahedronGeometry(.35+(i%7)*.035,0):new THREE.BoxGeometry(.22,.22,.22)
          const mesh=new THREE.Mesh(geo,new THREE.MeshStandardMaterial({color:0x667c9c,roughness:.46,metalness:.44,emissive:0x0b1d39,emissiveIntensity:.85}))
          const a=i*2.399963, radius=3.5+(i%11)*.62
          mesh.position.set(Math.cos(a)*radius,-.2+(i%17)*.32,-4-(i%23)*2.4)
          mesh.rotation.set(a*.37,a*.71,a*.19); shardGroup.add(mesh); shards.push({mesh,index:i,seed:(i*2654435761)>>>0})
        }

        const fractures=[]
        for(let i=0;i<18;i++){
          const pts=[]
          for(let j=0;j<9;j++) pts.push(new THREE.Vector3(Math.sin(i*1.7+j*.91)*(2.5+j*.5),.5+Math.cos(i+j)*1.7,7-j*3.2))
          const line=new THREE.Line(new THREE.BufferGeometry().setFromPoints(pts),new THREE.LineBasicMaterial({color:0xa78f68,transparent:true,opacity:.3}))
          scene.add(line); fractures.push(line)
        }

        let state={scene:"boot",seed:0,started_at:performance.now()/1000,energy:.2,fracture:.2,hue:.58}, target={...state}
        async function poll(){try{target={...target,...await fetch("/state",{cache:"no-store"}).then(r=>r.json())}catch(_){}}
        setInterval(poll,140); poll()
        addEventListener("resize",()=>{camera.aspect=innerWidth/innerHeight;camera.updateProjectionMatrix();renderer.setSize(innerWidth,innerHeight,false)})
        const clock=new THREE.Clock()

        function animate(){
          const dt=clock.getDelta(), t=performance.now()/1000
          state.energy+=(Number(target.energy||.2)-state.energy)*Math.min(1,dt*4)
          state.fracture+=(Number(target.fracture||.2)-state.fracture)*Math.min(1,dt*3)
          const age=Math.max(0,t-Number(target.started_at||t))
          const pulse=Math.min(1,.15+state.energy*.95+Math.sin(age*6.1)*.08)

          camera.position.x=Math.sin(t*.17+Number(target.seed||0)*.001)*3.4+Math.sin(t*.043)*1.3
          camera.position.y=3.4+Math.sin(t*.13)*.85+pulse*.9
          camera.position.z=16-Math.min(10,age*.035)+Math.sin(t*.071)*2.2
          camera.lookAt(0,2.4,-13)
          point.intensity=2.4+pulse*7; key.intensity=1.45+pulse*1.8
          core.rotation.x+=dt*(.17+state.fracture*.22); core.rotation.y+=dt*(.23+pulse*.28); core.scale.setScalar(.92+pulse*.34)

          rings.forEach((ring,i)=>{ring.rotation.z=t*(.05+i*.009)*(i%2?-1:1);ring.scale.setScalar(1+pulse*.13+Math.sin(t*.8+i)*.035);ring.material.opacity=.12+pulse*.32})
          architecture.forEach(({mesh,index,side})=>{const wobble=Math.sin(t*.43+index*.72+side*.5);mesh.position.y=3+wobble*.14+pulse*.5;mesh.scale.y=1+pulse*.08+state.fracture*.12*Math.abs(wobble)})
          slabs.rotation.y=t*.018; shardGroup.rotation.y=t*.027

          shards.forEach(({mesh,index,seed})=>{
            const p=.16+(seed%1000)/2000
            mesh.rotation.x+=dt*(.2+p*1.6); mesh.rotation.y-=dt*(.15+p*1.1)
            const local=Math.sin(t*(.37+p)+index*.53)
            mesh.position.x+=local*dt*state.fracture*.16
            mesh.position.y+=Math.cos(t*.71+index)*dt*(.3+pulse*.8)
            mesh.scale.setScalar(.55+pulse*.65+Math.max(0,local)*.45)
            mesh.material.emissiveIntensity=.35+pulse*1.5
          })
          fractures.forEach((line,index)=>{line.rotation.y=Math.sin(t*.08+index)*.08+state.fracture*.16*Math.sin(t*.27+index);line.material.opacity=.08+state.fracture*.32+pulse*.22})
          label.textContent=String(target.scene||"LIVE").replaceAll("_"," ")+" / "+Math.round(state.energy*100)+" ENERGY / "+Math.round(state.fracture*100)+" FRACTURE"
          renderer.render(scene,camera); requestAnimationFrame(animate)
        }
        animate()
      </script></body></html>
    HTML
  end
end
