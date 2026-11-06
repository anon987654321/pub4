import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { createRequire } from "node:module";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

// The web face draws the terminal's ASCII face. MASTER/test/fixtures/face_ascii_frames.json
// holds what the Ruby renderer drew for ten fixed inputs; the port must draw the same
// characters from the same contract (MASTER/data/tokens.yml, face_interface), which the
// page receives as MASTER_FACE_CONTRACT. The contract is read here the way the view gives
// it to the browser: the face_interface block of tokens.yml, as JSON.

const here = dirname(fileURLToPath(import.meta.url));
const repo = join(here, "..", "..", "..");
const sourcePath = join(here, "..", "public", "face_ascii.js");
const require = createRequire(import.meta.url);
const ascii = require(sourcePath);

const fixtures = JSON.parse(readFileSync(join(repo, "MASTER", "test", "fixtures", "face_ascii_frames.json"), "utf8"));
const contract = JSON.parse(execFileSync("ruby", [
  "-ryaml", "-rjson", "-e",
  'puts JSON.generate(YAML.load_file(ARGV[0], aliases: true).fetch("tokens").fetch("face_interface"))',
  join(repo, "MASTER", "data", "tokens.yml"),
], { encoding: "utf8" }));
const engine = ascii.build(contract);

const PRINTABLE = /^[\x20-\x7e\n]*$/;
const BRAILLE = /[⠀-⣿]/;

// The fixtures fingerprint the fitted points with Ruby's own format("%.4f"), which rounds a
// near-tie by its own rule (0.50374999999999992 prints 0.5038), so the digest is taken by Ruby
// from the points this port made rather than imitated here.
function rubyDigest(points) {
  return execFileSync("ruby", [
    "-rjson", "-rdigest", "-e",
    'pts = JSON.parse($stdin.read); print Digest::SHA256.hexdigest(pts.map { |p| p.map { |v| format("%.4f", v) }.join(",") }.join(";"))[0, 16]',
  ], { input: JSON.stringify(points), encoding: "utf8" });
}

function sourceFor(c) {
  return c.source.kind === "head" ? engine.head(c.rows, c.cols) : engine.mesh(fixtures.meshes[c.source.ref]);
}

function render(c, look = engine.pose(c.state, c.t, c.seed)) {
  const renderer = new engine.Renderer(sourceFor(c), c.rows, c.cols, { chars: fixtures.chars, mode: "dark" });
  return { renderer, frame: renderer.render(look, c.state) };
}

test("every fixture frame is reproduced character for character", () => {
  assert.equal(fixtures.cases.length, 13);
  for (const c of fixtures.cases) {
    const { renderer, frame } = render(c);
    assert.equal(rubyDigest(renderer.fitted()), c.digest, `${c.name}: the vertices differ from the Ruby head`);
    const expected = c.lines.map((l) => l.replace(/ +$/, ""));
    assert.deepEqual(frame.lines, expected, c.name);
  }
});

test("the pose is the fixture's Look, within the fixtures' tolerance", () => {
  for (const c of fixtures.cases) {
    const look = engine.pose(c.state, c.t, c.seed);
    for (const [key, want] of Object.entries(c.look)) {
      const got = look[key];
      if (Array.isArray(want)) {
        want.forEach((w, i) => assert.ok(Math.abs(got[i] - w) <= fixtures.tolerance, `${c.name}: ${key}[${i}]`));
      } else {
        assert.ok(Math.abs(got - want) <= fixtures.tolerance, `${c.name}: ${key} ${got} vs ${want}`);
      }
    }
  }
});

test("the renderer source and every frame are printable ASCII, never Braille", () => {
  const source = readFileSync(sourcePath, "utf8");
  assert.ok(!BRAILLE.test(source));
  assert.ok(/^[\x09\x0a\x20-\x7e]*$/.test(source), "face_ascii.js holds only printable ASCII");
  for (const c of fixtures.cases) {
    const { frame } = render(c);
    assert.match(frame.toString(), PRINTABLE, c.name);
    assert.ok(!BRAILLE.test(frame.toString()), c.name);
  }
  assert.ok(!BRAILLE.test(JSON.stringify(contract.ascii)));
});

test("turning does not shimmer", () => {
  const c = { source: { kind: "head" }, rows: 28, cols: 64, state: "idle", t: 0, seed: 1 };
  const still = { yaw: 0, pitch: 0, roll: 0, scale: 1, dolly: 1, bob: 0, eye_open: 1, gaze: [0, 0], mouth: 0, mouth_open: 1, mouth_wide: 0 };
  const a = render(c, { ...still, turn: 1.0 }).frame.lines;
  const b = render(c, { ...still, turn: 1.002 }).frame.lines;
  const cells = a.reduce((sum, line) => sum + line.length, 0);
  let changed = 0;
  a.forEach((line, r) => {
    const x = line.padEnd(64);
    const y = b[r].padEnd(64);
    for (let i = 0; i < 64; i += 1) if (x[i] !== y[i]) changed += 1;
  });
  assert.ok(changed / cells < 0.06, `${changed} of ${cells} cells moved`);
});

test("the dither is fixed in screen space and the line glyphs follow the cell aspect", () => {
  const g = engine.Glyphs;
  assert.equal(g.index(0.5, 10, 3, 2), g.index(0.5, 10, 7, 6));
  assert.equal(g.line(1, 0), "-");
  assert.equal(g.line(0, 1), "|");
  assert.equal(g.line(1, 1), "/");
  assert.equal(g.line(1, -1), "\\");
  assert.equal(g.level(true, true, true), "_");
  assert.equal(g.level(true, true, false), "'");
  assert.deepEqual(g.ramp(" .:-=+*#%@", "light"), "@%#*+=-:. ".split(""));
});

test("configured ink ramps are ordered subsets of the calibrated glyph ramp", () => {
  const calibrated = Array.from(contract.ascii.chars);
  const ramps = contract.ascii.ramps;
  assert.ok(ramps && ramps.sculpt && ramps.high_contrast && ramps.fine_detail);
  for (const [name, ramp] of Object.entries(ramps)) {
    const positions = Array.from(ramp, (glyph) => calibrated.indexOf(glyph));
    assert.ok(positions.every((index) => index >= 0), `${name}: every ramp glyph has calibrated ink`);
    assert.deepEqual(positions, positions.slice().sort((a, b) => a - b), `${name}: glyph density stays ordered`);
  }
});

test("renderer cache separates ramp and dark/light relief choices", () => {
  const state = "idle";
  const look = engine.pose(state, 1.1, 1);
  const base = engine.frame({ rows: 28, cols: 64, state, look, chars: contract.ascii.ramps.sculpt, mode: "dark" });
  const contrast = engine.frame({ rows: 28, cols: 64, state, look, chars: contract.ascii.ramps.high_contrast, mode: "dark" });
  const light = engine.frame({ rows: 28, cols: 64, state, look, chars: contract.ascii.ramps.sculpt, mode: "light" });
  assert.notDeepEqual(contrast.lines, base.lines, "the high-contrast ramp changes surface ink");
  assert.notDeepEqual(light.lines, base.lines, "light mode reverses the tone ramp");
  for (const lines of [base.lines, contrast.lines, light.lines]) assert.match(lines.join("\n"), PRINTABLE);
});

test("Ruby's compensated sum is used where the anchors are means", () => {
  assert.equal(ascii.kbSum([0.1, 0.2, 0.3]), 0.6);
  assert.notEqual(0.1 + 0.2 + 0.3, 0.6);
});

test("a manual turn offset rotates the ASCII mesh independently of the auto-spin state", () => {
  const { canvas } = stubCanvas(900, 900);
  const view = ascii.createView(canvas, { contract, env: pageWindow() });
  view.draw(1000, { state: "listening" });
  const front = view.lastText;
  view.turnOffset = Math.PI / 2;
  view.lastText = "";
  view.lastAt = -Infinity;
  view.draw(1000, { state: "listening" });
  assert.notEqual(view.lastText, front);
});

test("the page's state is mapped onto the pose the way the terminal maps it", () => {
  const shapes = { A: { open: 1.0, wide: 0.2 }, O: { open: 0.9, wide: -0.7 } };
  const speaking = engine.lookFor({ state: "speaking", t: 1.35, level: 0.8, viseme: "O", shapes });
  assert.equal(speaking.mouth, 0.8);
  assert.equal(speaking.mouth_open, 0.9);
  assert.equal(speaking.mouth_wide, -0.7);
  const timed = engine.lookFor({ state: "speaking", t: 1.35 });
  assert.ok(timed.mouth > 0, "no envelope: the timed level stands in");
  assert.equal(engine.lookFor({ state: "idle", t: 1.35, level: 0.9 }).mouth, 0, "only speaking opens the mouth");
  assert.equal(engine.lookFor({ state: "nonsense", t: 0 }).dolly, 1.0);
  const idle = engine.lookFor({ state: "idle", t: 2 });
  assert.deepEqual([idle.turn, idle.pitch, idle.roll, idle.scale, idle.dolly, idle.bob, idle.light, idle.eye_open],
    [0, 0, 0, 1, 1, 0, contract.ascii.light.start, 1]);
  assert.ok(engine.lookFor({ state: "thinking", t: 2 }).turn > 0, "thinking retains its canonical rotation");
  assert.equal(engine.lookFor({ state: "listening", t: 2 }).turn, 0, "an attending head faces the user");
  const calm = engine.lookFor({ state: "idle", t: 2, reduced: true });
  assert.deepEqual([calm.turn, calm.pitch, calm.roll, calm.bob, calm.scale], [0, 0, 0, 0, 1]);
  const open = engine.lookFor({ state: "speaking", t: 2, reduced: true, level: 1 });
  assert.equal(open.mouth, 1, "reduced motion holds the head still, not the mouth");
});

test("a window too small for a face names the state, as the terminal does", () => {
  const small = engine.frame({ rows: engine.MIN_ROWS - 1, cols: 60, state: "thinking", look: engine.pose("thinking", 0, 1) });
  assert.ok(small.word);
  assert.equal(small.lines.map((l) => l.trim()).filter(Boolean)[0], "thinking");
  const narrow = engine.frame({ rows: 20, cols: engine.MIN_COLS - 1, state: "idle", look: engine.pose("idle", 0, 1) });
  assert.equal(narrow.lines.map((l) => l.trim()).filter(Boolean)[0], "idle");
});

test("constitutional law glyphs form a deterministic perimeter without overwriting occupied cells", () => {
  const blank = Array.from({ length: 16 }, () => " ".repeat(40));
  const before = blank.slice();
  const laws = ["@", "#", "%", "&", "*", "+", "=", ":"].map((glyph) => ({ glyph }));
  const first = ascii.paintLawField(blank, null, laws);
  const second = ascii.paintLawField(blank, null, laws);

  assert.deepEqual(first, second, "the law field must not shimmer between equivalent frames");
  for (const law of laws) {
    assert.ok(first.lines.some((line) => line.includes(law.glyph)), `missing constitutional glyph ${law.glyph}`);
  }
  assert.deepEqual(blank, before, "painting the law field does not mutate the face frame");
  assert.match(first.lines.join("\n"), PRINTABLE);

  const occupied = blank.slice();
  occupied[0] = `${occupied[0].slice(0, 20)}X${occupied[0].slice(21)}`;
  const protectedCell = ascii.paintLawField(occupied, null, [{ glyph: "@" }]);
  assert.equal(protectedCell.lines[0][20], "X", "a facial contour already occupying a cell keeps ownership");
});

// A canvas that records what it is asked to draw.
function stubCanvas(width, height) {
  const calls = [];
  const ctx = {
    font: "", fillStyle: "", globalAlpha: 1, textBaseline: "",
    setTransform() {}, clearRect() {},
    measureText: () => ({ width: 8 }),
    fillText(text, x, y) { calls.push({ text, x, y, font: this.font, alpha: this.globalAlpha, fill: this.fillStyle }); },
  };
  return { calls, canvas: { clientWidth: width, clientHeight: height, width: 0, height: 0, getContext: () => ctx } };
}

function pageWindow(overrides = {}) {
  return {
    devicePixelRatio: 1, innerWidth: 900, innerHeight: 900,
    getComputedStyle: () => ({ getPropertyValue: () => "ui-monospace, monospace", color: "rgb(240, 240, 240)" }),
    matchMedia: () => ({ matches: false }),
    document: { createElement: () => ({ setAttribute() {}, style: {} }), body: { appendChild() {} }, documentElement: {} },
    addEventListener() {},
    ...overrides,
  };
}

test("the canvas view draws printable characters, near bold and far dim, in the face colour", () => {
  const { calls, canvas } = stubCanvas(900, 900);
  const view = ascii.createView(canvas, { contract, env: pageWindow() });
  assert.ok(view.draw(1000, { state: "speaking", level: 0.7, viseme: "A", shapes: { A: { open: 1, wide: 0.2 } } }));
  assert.ok(calls.length > 0);
  for (const call of calls) assert.match(call.text, /^[\x20-\x7e]*$/);
  assert.ok(calls.some((c) => c.font.startsWith("700 ")), "near cells are bold");
  assert.ok(calls.some((c) => c.alpha < 0.5), "far cells are dim");
  assert.ok(calls.every((c) => c.fill === "rgb(240, 240, 240)"), "the face colour, resolved from --face-fg");
  assert.ok(calls.every((c) => c.font.endsWith("ui-monospace, monospace")), "the --font-mono stack");
});

test("forced colors draw in the system text colour at full strength", () => {
  const { calls, canvas } = stubCanvas(900, 900);
  const env = pageWindow({ matchMedia: () => ({ matches: true }) });
  ascii.createView(canvas, { contract, env }).draw(1000, { state: "idle" });
  assert.ok(calls.length > 0);
  assert.ok(calls.every((c) => c.fill === "CanvasText" && c.alpha === 1));
});

test("a small viewport shows the state word", () => {
  const { calls, canvas } = stubCanvas(120, 60);
  ascii.createView(canvas, { contract, env: pageWindow({ innerWidth: 120, innerHeight: 60 }) }).draw(1000, { state: "thinking" });
  assert.equal(calls.length > 0, true);
  assert.ok(calls.some((c) => c.text.trim() === "thinking"));
});

test("reduced motion holds the head still: the same text a second later is not repainted", () => {
  const { calls, canvas } = stubCanvas(900, 900);
  const view = ascii.createView(canvas, { contract, env: pageWindow() });
  assert.ok(view.draw(1000, { state: "listening", reduced: true }));
  const painted = calls.length;
  assert.equal(view.draw(2500, { state: "listening", reduced: true }), false);
  assert.equal(calls.length, painted);
});


test("ranked constitutional glyphs orbit the head without replacing face cells", () => {
  const laws = [
    { id: "CAPABILITY_STATUS_MUST_BE_TRUTHFUL", glyph: "@" },
    { id: "ROBUSTNESS", glyph: "#" },
    { id: "SINGULARITY", glyph: "%" },
    { id: "LINEARITY", glyph: "&" },
    { id: "PROXIMITY", glyph: "*" },
    { id: "ABSTRACTION", glyph: "+" },
    { id: "DENSITY", glyph: "=" },
    { id: "RENDERED_VALUES", glyph: ":" },
  ];
  const lines = Array.from({ length: 24 }, () => " ".repeat(64));
  const depth = lines.map((line) => Array(line.length).fill(1));
  const field = ascii.paintLawField(lines, depth, laws);
  const painted = field.lines.join("");

  assert.ok(laws.every((law) => painted.includes(law.glyph)));
  assert.equal(painted.split("").filter((char) => laws.some((law) => law.glyph === char)).length, laws.length);
  assert.ok(lines.every((line) => line.trim() === ""), "the input frame must remain untouched");

  const obstructed = lines.map((line) => line.split(""));
  obstructed[1][32] = "o";
  const blocked = ascii.paintLawField(obstructed, depth, laws);
  assert.equal(blocked.lines[1][32], "o", "the first law marker must yield to the portrait");
  assert.ok(!blocked.lines.join("").includes("@"), "an occupied landmark stays visible");
});

test("the browser overlay uses the existing face frame clock, with no second animation loop", () => {
  const source = readFileSync(sourcePath, "utf8");
  const frame = readFileSync(join(here, "..", "public", "face.part3.txt"), "utf8");
  const fallback = readFileSync(join(here, "..", "public", "face_2d_fallback.js"), "utf8");
  assert.equal(typeof ascii.update, "function");
  assert.equal(typeof ascii.createView, "function");
  assert.match(frame, /MASTER_FACE_ASCII\?\.update/);
  assert.match(fallback, /window\.MASTER_FACE_ASCII/);
  assert.match(fallback, /ascii\.createView/);
  assert.doesNotMatch(source, /requestAnimationFrame/);
});

// ---- Mask morph targets ------------------------------------------------------------
// MASTER/lib/cli/face/masks.rb holds the same morph, trigger and choice; the fixtures
// carry what Ruby drew for each mask at mix 0, 0.5 and 1.0, and what it computed.

function maskFrame(c) {
  const head = engine.head(c.rows, c.cols);
  const renderer = new engine.Renderer(engine.Masks.source(head, c.mask, c.mix), c.rows, c.cols, { chars: fixtures.chars, mode: "dark" });
  return { renderer, frame: renderer.render(engine.pose(c.state, c.t, c.seed), c.state) };
}

test("every mask fixture frame is reproduced character for character", () => {
  assert.equal(fixtures.masks.length, engine.Masks.ORDER.length * 4);
  for (const c of fixtures.masks) {
    const { renderer, frame } = maskFrame(c);
    assert.equal(rubyDigest(renderer.fitted()), c.digest, `${c.name}: the points differ from the Ruby mask`);
    assert.deepEqual(frame.lines, c.lines.map((l) => l.replace(/ +$/, "")), c.name);
    assert.match(frame.toString(), PRINTABLE, c.name);
    assert.ok(!BRAILLE.test(frame.toString()), c.name);
  }
});

test("the trigger section is reproduced: the session's mask, the mix, and the parameters at the middle", () => {
  for (const [session, mask] of Object.entries(fixtures.trigger.picks)) assert.equal(engine.Masks.pick(session), mask, JSON.stringify(session));
  for (const m of fixtures.trigger.mixes) assert.ok(Math.abs(engine.Masks.mix(m.state, m.t, m.since, m.from) - m.mix) < 1e-15, JSON.stringify(m));
  for (const [mask, middle] of Object.entries(fixtures.trigger.morphs)) {
    const got = engine.Masks.morph(engine.Masks.params(null), engine.Masks.params(mask), 0.5);
    assert.deepEqual(Object.keys(got).sort(), Object.keys(middle).sort(), mask);
    for (const [key, want] of Object.entries(middle)) assert.equal(got[key], want, `${mask} ${key}`);
  }
});

test("morph ends are exact, and every target is the head's own mesh under other numbers", () => {
  const human = engine.Masks.params(null);
  for (const mask of engine.Masks.ORDER) {
    const target = engine.Masks.params(mask);
    assert.equal(engine.Masks.morph(human, target, 0), human);
    assert.equal(engine.Masks.morph(human, target, 1), target);
    assert.deepEqual(engine.Masks.morph(human, target, 0.37), engine.Masks.morph(human, target, 0.37));
    for (const [rows, cols] of [[20, 40], [28, 64]]) {
      const head = engine.head(rows, cols);
      for (const mix of [0.3, 1.0]) {
        const shaped = engine.Masks.source(head, mask, mix);
        assert.equal(shaped.vertexCount, head.mesh().vertexCount, `${mask} ${rows}x${cols} ${mix}`);
        assert.equal(shaped.tris, head.mesh().tris, "the same triangles");
      }
    }
  }
  const head = engine.head(20, 40);
  assert.equal(engine.Masks.source(head, "baining", 0), head.mesh());
  assert.equal(engine.Masks.source(head, "baining", 1), head.mesh("baining"));
  assert.equal(engine.Masks.smoothstep(0.25), 0.15625);
});

test("the human parameters are the head's own mesh, and the ends of a morph are exact", () => {
  const head = engine.head(20, 40);
  const plain = head.mesh();
  const target = head.mesh("maprik_yam");
  const near = engine.Masks.source(head, "maprik_yam", 1e-300);
  assert.deepEqual(near.pos, plain.pos);
  assert.notDeepEqual(target.pos, plain.pos);
});

// Every undirected edge with the number of triangles that use it.
function edgeCounts(m) {
  const counts = new Map();
  for (let i = 0; i < m.tris.length; i += 3) {
    for (let k = 0; k < 3; k += 1) {
      const a = m.tris[i + k];
      const b = m.tris[i + ((k + 1) % 3)];
      const key = a < b ? `${a},${b}` : `${b},${a}`;
      counts.set(key, (counts.get(key) || 0) + 1);
    }
  }
  return counts;
}

test("the head is a closed mesh: every edge is shared by two triangles, wound outward", () => {
  for (const [rows, cols] of [[20, 40], [28, 64], [44, 140]]) {
    for (const mask of [null, ...engine.Masks.ORDER]) {
      const m = engine.head(rows, cols).mesh(mask);
      for (const [edge, n] of edgeCounts(m)) assert.equal(n, 2, `${mask} ${rows}x${cols} edge ${edge}`);
      assert.ok(m.volume() > 0, `${mask} ${rows}x${cols}: outward`);
    }
    assert.ok(engine.head(rows, cols).triangleCount >= 3000);
  }
});

test("the rasteriser covers a unit cube by the square the camera gives it, and culls a back face", () => {
  const cube = engine.mesh(fixtures.meshes.cube);
  assert.equal(cube.triangleCount, 12);
  assert.ok(cube.volume() > 0, "an inward-wound file is turned outward");
  const r = new engine.Renderer(cube, 30, 40, { chars: fixtures.chars, mode: "dark" });
  r.render(engine.pose("idle", 0, 0), "idle");
  const hit = r.tri.filter((t) => t >= 0).length;
  const k = r.scale * contract.ascii.camera / (contract.ascii.camera - 1.0);
  const side = 2 * k * contract.ascii.samples;
  assert.ok(Math.abs(hit - (side * side)) <= side * side * 0.03, `cube covers ${hit} samples, wanted ${side * side}`);

  const tri = engine.mesh("v -1 -1 0\nv 1 -1 0\nv 0 1 0\nf 1 2 3\n");
  const area = (m) => {
    const q = new engine.Renderer(m, 20, 40, {});
    q.render(engine.pose("idle", 0, 0), "idle");
    return [q, q.tri.filter((t) => t >= 0).length];
  };
  const [q, n] = area(tri);
  const expected = 0.5 * 2 * 2 * ((q.scale * contract.ascii.samples) ** 2);
  assert.ok(Math.abs(n - expected) <= expected * 0.06, `${n} vs ${expected}`);
  const back = new engine.Mesh(tri.pos, [0, 2, 1], tri.bright);
  assert.equal(area(back)[1], 0, "seen from behind it is culled");
});

test("the ramp is ordered by measured ink", () => {
  const ink = contract.ascii.ink;
  const glyphs = Array.from(contract.ascii.chars);
  glyphs.forEach((g, i) => { if (i > 0) assert.ok(ink[g] > ink[glyphs[i - 1]], `${g} is inkier than ${glyphs[i - 1]}`); });
  assert.ok(glyphs.every((g) => g in ink));
});

test("the key light orbits with the pose, and the light is part of the look", () => {
  const a = engine.pose("idle", 0, 1);
  const b = engine.pose("idle", 4, 1);
  assert.ok(b.light > a.light);
  assert.equal(a.light, contract.ascii.light.start);
  assert.equal(engine.lookFor({ state: "idle", t: 4, reduced: true }).light, contract.ascii.light.start);
  const lit = (look) => new engine.Renderer(engine.head(28, 64), 28, 64, {}).render(look, "idle").lines;
  assert.notDeepEqual(lit({ ...a, turn: 0.5 }), lit({ ...b, turn: 0.5, light: a.light + 2.5 }));
});

test("the mask follows thinking only, and reduced motion or a small window shows none", () => {
  for (const state of engine.STATES.filter((s) => s !== "thinking")) assert.equal(engine.Masks.mix(state, 5, 0, 0), 0, state);
  assert.equal(engine.Masks.mix("thinking", 0, 0, 0), 0);
  assert.ok(Math.abs(engine.Masks.mix("thinking", 0.6, 0, 0) - 0.5) < 1e-12);
  assert.equal(engine.Masks.mix("thinking", 1.2, 0, 0), 1);
  assert.ok(Math.abs(engine.Masks.mix("idle", 0.4, 0, 1) - 0.5) < 1e-12);
  assert.equal(engine.pose("thinking", 2, 1).mask, null, "no schedule, no mask");
  const look = engine.lookFor({ state: "thinking", t: 2, session: "abc", since: 0, from: 0 });
  assert.equal(look.mask, "iatmul_mei");
  assert.equal(look.mix, 1);
  assert.equal(engine.lookFor({ state: "thinking", t: 2, session: "abc", since: 0, from: 0, reduced: true }).mix, 0);
  assert.equal(engine.lookFor({ state: "idle", t: 2, session: "abc", since: 0, from: 0 }).mix, 0);
  const plain = engine.frame({ rows: 24, cols: 60, state: "thinking", look: { ...look, mix: 0 } });
  const morphed = engine.frame({ rows: 24, cols: 60, state: "thinking", look });
  assert.notDeepEqual(morphed.lines, plain.lines);
  const small = engine.frame({ rows: engine.MIN_ROWS - 1, cols: 60, state: "thinking", look });
  assert.ok(small.word);
});

test("the view eases into the mask while thinking and back out when it stops", () => {
  const { canvas } = stubCanvas(900, 900);
  const view = ascii.createView(canvas, { contract, env: pageWindow() });
  view.draw(0, { state: "idle", session: "abc" });
  assert.equal(view.maskMix, 0);
  view.draw(1000, { state: "thinking", session: "abc" });
  assert.equal(view.maskMix, 0);
  view.draw(1600, { state: "thinking", session: "abc" });
  assert.ok(Math.abs(view.maskMix - 0.5) < 1e-9);
  view.draw(3000, { state: "thinking", session: "abc" });
  assert.equal(view.maskMix, 1);
  view.draw(3400, { state: "idle", session: "abc" });
  view.draw(3800, { state: "idle", session: "abc" });
  assert.ok(Math.abs(view.maskMix - 0.5) < 1e-9);
  view.draw(5000, { state: "idle", session: "abc", reduced: true });
  assert.equal(view.maskMix, 0);
});
