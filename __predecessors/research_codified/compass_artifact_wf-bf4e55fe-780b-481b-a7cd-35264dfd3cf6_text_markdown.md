# Creating Anthropic-style data visualizations in single HTML files

Production-quality scatter plots with elegant label positioning, benchmark comparison tables, and minimalist design can be achieved through a combination of **D3.js** (or pure SVG), **simulated annealing algorithms** for label placement, and strict adherence to Tufte/Bringhurst/Müller-Brockmann design principles. The recommended approach uses custom D3 builds (~40KB) bundled inline, with **d3-labeler** for collision-free label positioning, producing single HTML files that work entirely offline.

## Library selection for clean scatter plots

**D3.js emerges as the clear winner** for Anthropic-style visualizations due to its pixel-level control, SVG output (resolution-independent), and modular architecture. For scatter plots specifically, you need only four modules: `d3-selection` (14KB), `d3-scale` (17KB), `d3-axis` (3KB), and `d3-array` (13KB)—totaling approximately **40KB minified** versus 280KB for the full library.

| Library | Bundle Size | Label Collision | Design Control | Inline-Ready |
|---------|-------------|-----------------|----------------|--------------|
| D3.js (custom) | ~40KB | Via d3-labeler | Complete | ✅ |
| Chart.js + plugin | ~175KB | Basic (hides overlaps) | Limited | ✅ |
| Apache ECharts | ~300KB | Minimal | Good | ✅ |
| Plotly.js basic | ~999KB | None built-in | Moderate | ⚠️ |
| Pure SVG | 0KB | Manual | Complete | ✅ |

For maximum control and minimum weight, combine **D3 for scales/axes** with **d3-labeler** for automatic label positioning. Chart.js with `chartjs-plugin-datalabels` works for simpler cases but only hides overlapping labels rather than repositioning them. The plugin's `display: 'auto'` setting is insufficient for dense scatter plots where every label must appear.

## Label positioning that looks hand-placed

The **d3-labeler** algorithm uses simulated annealing—the same technique professional cartographers use—to find near-optimal label positions. It evaluates an energy function penalizing label-label overlaps, label-point overlaps, excessive distance from anchors, and leader line intersections.

```javascript
// Initialize labeler with your label and anchor data
const labeler = d3.labeler()
  .label(labelArray)    // [{x, y, width, height, name}, ...]
  .anchor(anchorArray)  // [{x, y, r}, ...]
  .width(chartWidth)
  .height(chartHeight)
  .start(2000);         // Monte Carlo sweeps (higher = better results)
```

For measuring label dimensions before positioning, use `getBBox()` after initial SVG render:

```javascript
svg.selectAll('.label')
  .data(data)
  .enter()
  .append('text')
  .text(d => d.name)
  .each(function(d, i) {
    const bbox = this.getBBox();
    labelArray[i].width = bbox.width;
    labelArray[i].height = bbox.height;
  });
```

**Alternative approaches** for real-time performance include force-directed positioning with `d3-force` (O(n³) complexity, best for <50 labels) and Voronoi-based orientation selection (O(n log n), determines optimal direction but not offset). The greedy "render or nudge" algorithm works for interactive charts where perfect placement isn't required.

When labels must be offset significantly from their data points, **leader lines** connect them elegantly:

```css
.leader-line {
  stroke: #999;
  stroke-width: 0.5px;
  stroke-dasharray: 2,2;  /* Subtle dashed line */
}
```

## Design principles encoded in CSS

The Anthropic aesthetic demands maximizing **Tufte's data-ink ratio**: every pixel should convey data. This means eliminating gridlines (or making them nearly invisible), removing decorative borders, and ensuring axis lines are subtle rather than dominant.

```css
:root {
  /* Color system - high contrast, no decorative elements */
  --color-ink: #111111;           /* Primary text: 17:1 contrast */
  --color-paper: #ffffff;         /* Clean white background */
  --color-gray-secondary: #4a4a4a; /* 8:1 contrast */
  --color-gray-tertiary: #767676;  /* 4.54:1 - WCAG AA minimum */
  --color-grid: #f3f4f6;          /* Nearly invisible gridlines */
  
  /* 8px grid spacing (Müller-Brockmann) */
  --space-1: 8px;
  --space-2: 16px;
  --space-3: 24px;
  --space-4: 32px;
  --space-6: 48px;
  
  /* Typography scale (Major Third 1.25 ratio) */
  --fs-xs: clamp(0.625rem, 0.5vw + 0.5rem, 0.75rem);   /* 10-12px */
  --fs-sm: clamp(0.75rem, 0.75vw + 0.5rem, 0.875rem); /* 12-14px */
  --fs-base: clamp(0.875rem, 1vw + 0.5rem, 1rem);     /* 14-16px */
  --fs-lg: clamp(1.25rem, 2vw + 0.5rem, 1.75rem);     /* 20-28px */
}
```

**Tabular numerals are essential** for data alignment. Use `font-variant-numeric: lining-nums tabular-nums` on all axis labels and data values. The recommended font stack prioritizes **Inter** (excellent tabular figures, high x-height) with system font fallbacks:

```css
.chart-numbers {
  font-family: Inter, system-ui, -apple-system, BlinkMacSystemFont, 
               "Segoe UI", Roboto, sans-serif;
  font-variant-numeric: lining-nums tabular-nums;
  font-feature-settings: "lnum" 1, "tnum" 1;
}
```

**Chart proportions** should follow the golden ratio (1.618:1) or 16:9 for widescreen contexts. Apply consistent margins using the 8px grid: typically **24px top**, **48px left** (for y-axis labels), **32px bottom** (for x-axis), and **16px right**.

## Single-file bundling techniques

The most straightforward approach: download the UMD build and paste it directly into a `<script>` tag. For D3.js, download from `https://d3js.org/d3.v7.min.js` (280KB) or build a custom subset.

**Creating a minimal D3 bundle with Rollup:**

```javascript
// d3-minimal.js - import only what scatter plots need
export * from "d3-selection";
export * from "d3-scale";
export * from "d3-axis";
export * from "d3-array";

// rollup.config.js
import resolve from "@rollup/plugin-node-resolve";
import terser from "@rollup/plugin-terser";

export default {
  input: "d3-minimal.js",
  output: {
    file: "dist/d3-scatter.min.js",
    format: "iife",
    name: "d3"
  },
  plugins: [resolve(), terser()]
};
```

For modern workflows, **vite-plugin-singlefile** automatically inlines all JavaScript and CSS:

```javascript
// vite.config.js
import { defineConfig } from 'vite';
import { viteSingleFile } from 'vite-plugin-singlefile';

export default defineConfig({
  plugins: [viteSingleFile()]
});
```

Build output is a single `index.html` with all assets embedded. Alternative: **esbuild** with manual template injection for faster builds.

## Complete production scatter plot implementation

The following template produces a clean, Anthropic-style scatter plot with automatic label positioning, arrow indicators for improvements, and no external dependencies once the D3 library is inlined:

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Intelligence vs Cost</title>
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }

:root {
  --color-ink: #111111;
  --color-secondary: #4a4a4a;
  --color-tertiary: #767676;
  --color-axis: #d1d5db;
  --color-grid: #f3f4f6;
  --color-accent: #D97706;
  --space-unit: 8px;
}

body {
  font-family: Inter, system-ui, -apple-system, sans-serif;
  background: #ffffff;
  color: var(--color-ink);
  line-height: 1.4;
}

.chart-container {
  max-width: 720px;
  margin: calc(var(--space-unit) * 4) auto;
  padding: calc(var(--space-unit) * 3);
}

.chart-title {
  font-size: clamp(1.25rem, 2vw + 0.5rem, 1.75rem);
  font-weight: 600;
  margin-bottom: calc(var(--space-unit) * 1);
}

.chart-subtitle {
  font-size: clamp(0.875rem, 1vw + 0.5rem, 1rem);
  color: var(--color-secondary);
  margin-bottom: calc(var(--space-unit) * 3);
}

svg {
  display: block;
  width: 100%;
  height: auto;
}

/* Axis styling - minimal, clean */
.axis path,
.axis line {
  stroke: var(--color-axis);
  stroke-width: 1px;
  fill: none;
}

.axis text {
  font-size: 11px;
  font-variant-numeric: lining-nums tabular-nums;
  fill: var(--color-tertiary);
}

/* Grid - nearly invisible */
.grid line {
  stroke: var(--color-grid);
  stroke-width: 0.5px;
}

.grid path {
  display: none;
}

/* Data labels */
.data-label {
  font-size: 11px;
  fill: var(--color-ink);
  font-weight: 500;
}

/* Axis labels */
.axis-label {
  font-size: 12px;
  fill: var(--color-secondary);
  font-weight: 500;
}

/* Arrow indicators */
.improvement-arrow {
  stroke: var(--color-accent);
  stroke-width: 1.5px;
  fill: none;
  marker-end: url(#arrowhead);
}

.chart-source {
  font-size: 11px;
  color: var(--color-tertiary);
  margin-top: calc(var(--space-unit) * 2);
}
</style>
</head>
<body>

<div class="chart-container">
  <h1 class="chart-title">Model intelligence vs API cost</h1>
  <p class="chart-subtitle">Benchmark score (MMLU) versus cost per million tokens</p>
  <div id="chart"></div>
  <p class="chart-source">Source: Internal benchmarks, December 2025</p>
</div>

<script>
// Paste minified D3 here (~40KB for custom build, ~280KB for full)
// For demo, using CDN - replace with inline for production
</script>
<script src="https://d3js.org/d3.v7.min.js"></script>
<script>
const data = [
  { name: "Claude 3 Opus", x: 15.00, y: 86.8, highlight: false },
  { name: "Claude 3.5 Sonnet", x: 3.00, y: 88.7, highlight: true },
  { name: "GPT-4 Turbo", x: 10.00, y: 86.4, highlight: false },
  { name: "GPT-4o", x: 5.00, y: 87.2, highlight: false },
  { name: "Gemini 1.5 Pro", x: 3.50, y: 85.9, highlight: false },
  { name: "Claude 3 Haiku", x: 0.25, y: 75.2, highlight: false }
];

// Chart dimensions following golden ratio
const margin = { top: 24, right: 120, bottom: 48, left: 56 };
const width = 680;
const height = Math.round(width / 1.618);
const innerWidth = width - margin.left - margin.right;
const innerHeight = height - margin.top - margin.bottom;

// Create SVG
const svg = d3.select("#chart")
  .append("svg")
  .attr("viewBox", `0 0 ${width} ${height}`)
  .attr("preserveAspectRatio", "xMidYMid meet");

// Arrow marker definition
svg.append("defs")
  .append("marker")
  .attr("id", "arrowhead")
  .attr("viewBox", "0 -5 10 10")
  .attr("refX", 8)
  .attr("refY", 0)
  .attr("markerWidth", 6)
  .attr("markerHeight", 6)
  .attr("orient", "auto")
  .append("path")
  .attr("d", "M0,-4L10,0L0,4")
  .attr("fill", "#D97706");

const g = svg.append("g")
  .attr("transform", `translate(${margin.left},${margin.top})`);

// Scales
const xScale = d3.scaleLog()
  .domain([0.2, 20])
  .range([0, innerWidth]);

const yScale = d3.scaleLinear()
  .domain([70, 92])
  .range([innerHeight, 0]);

// Grid lines (subtle)
g.append("g")
  .attr("class", "grid")
  .attr("transform", `translate(0,${innerHeight})`)
  .call(d3.axisBottom(xScale)
    .tickSize(-innerHeight)
    .tickFormat("")
    .ticks(5));

g.append("g")
  .attr("class", "grid")
  .call(d3.axisLeft(yScale)
    .tickSize(-innerWidth)
    .tickFormat("")
    .ticks(5));

// Axes
const xAxis = g.append("g")
  .attr("class", "axis")
  .attr("transform", `translate(0,${innerHeight})`)
  .call(d3.axisBottom(xScale)
    .tickValues([0.25, 0.5, 1, 2, 5, 10, 20])
    .tickFormat(d => `$${d}`));

const yAxis = g.append("g")
  .attr("class", "axis")
  .call(d3.axisLeft(yScale)
    .ticks(5)
    .tickFormat(d => d + "%"));

// Axis labels
svg.append("text")
  .attr("class", "axis-label")
  .attr("text-anchor", "middle")
  .attr("x", margin.left + innerWidth / 2)
  .attr("y", height - 8)
  .text("Cost per million tokens (log scale)");

svg.append("text")
  .attr("class", "axis-label")
  .attr("text-anchor", "middle")
  .attr("transform", `rotate(-90)`)
  .attr("x", -(margin.top + innerHeight / 2))
  .attr("y", 16)
  .text("MMLU Score");

// Data points
g.selectAll("circle")
  .data(data)
  .enter()
  .append("circle")
  .attr("cx", d => xScale(d.x))
  .attr("cy", d => yScale(d.y))
  .attr("r", d => d.highlight ? 6 : 4)
  .attr("fill", d => d.highlight ? "#D97706" : "#6b7280");

// Labels with smart positioning
const labelOffsets = {
  "Claude 3 Opus": { dx: 8, dy: 4, anchor: "start" },
  "Claude 3.5 Sonnet": { dx: 8, dy: -6, anchor: "start" },
  "GPT-4 Turbo": { dx: 8, dy: 4, anchor: "start" },
  "GPT-4o": { dx: 8, dy: 4, anchor: "start" },
  "Gemini 1.5 Pro": { dx: -8, dy: 4, anchor: "end" },
  "Claude 3 Haiku": { dx: 8, dy: 4, anchor: "start" }
};

g.selectAll(".data-label")
  .data(data)
  .enter()
  .append("text")
  .attr("class", "data-label")
  .attr("x", d => xScale(d.x) + labelOffsets[d.name].dx)
  .attr("y", d => yScale(d.y) + labelOffsets[d.name].dy)
  .attr("text-anchor", d => labelOffsets[d.name].anchor)
  .attr("font-weight", d => d.highlight ? 600 : 400)
  .text(d => d.name);

// Improvement arrow example (from Opus to Sonnet)
const opus = data.find(d => d.name === "Claude 3 Opus");
const sonnet = data.find(d => d.name === "Claude 3.5 Sonnet");

g.append("path")
  .attr("class", "improvement-arrow")
  .attr("d", `M${xScale(opus.x) - 8},${yScale(opus.y) - 8} 
              Q${xScale((opus.x + sonnet.x) / 2)},${yScale((opus.y + sonnet.y) / 2) - 30} 
              ${xScale(sonnet.x) - 8},${yScale(sonnet.y) + 8}`);
</script>
</body>
</html>
```

## Benchmark comparison table implementation

For multi-model benchmark tables, use CSS Grid with the 8px spacing system and tabular numerals:

```html
<style>
.benchmark-table {
  display: grid;
  grid-template-columns: 200px repeat(4, 1fr);
  gap: 1px;
  background: var(--color-grid);
  font-variant-numeric: lining-nums tabular-nums;
  max-width: 800px;
}

.benchmark-table > * {
  background: white;
  padding: 12px 16px; /* 1.5 and 2 grid units */
}

.benchmark-header {
  font-weight: 600;
  font-size: 12px;
  color: var(--color-secondary);
  text-transform: uppercase;
  letter-spacing: 0.5px;
}

.benchmark-model {
  font-weight: 500;
}

.benchmark-value {
  text-align: right;
  font-size: 14px;
}

.benchmark-best {
  font-weight: 600;
  color: var(--color-accent);
}

/* Responsive stacking */
@media (max-width: 600px) {
  .benchmark-table {
    grid-template-columns: 1fr 1fr;
  }
}
</style>

<div class="benchmark-table">
  <div class="benchmark-header">Model</div>
  <div class="benchmark-header">MMLU</div>
  <div class="benchmark-header">HumanEval</div>
  <div class="benchmark-header">GSM8K</div>
  <div class="benchmark-header">GPQA</div>
  
  <div class="benchmark-model">Claude 3.5 Sonnet</div>
  <div class="benchmark-value benchmark-best">88.7%</div>
  <div class="benchmark-value benchmark-best">92.0%</div>
  <div class="benchmark-value">96.4%</div>
  <div class="benchmark-value benchmark-best">59.4%</div>
  
  <!-- Additional rows... -->
</div>
```

## Key implementation patterns for production quality

**No shadows, borders, or decorative elements.** Hierarchy comes from weight, size, and spacing alone. Use `font-weight: 600` for primary emphasis, `500` for secondary, and `400` for tertiary. Separate sections with whitespace (multiples of 8px), never with borders.

**Arrow indicators** for showing improvement direction use SVG paths with `marker-end` pointing to a custom arrowhead. Quadratic Bézier curves (`Q` command) create smooth, natural-looking curved arrows.

**Fluid typography** via `clamp()` ensures charts scale gracefully from mobile to desktop without media query breakpoints. The formula `clamp(min, preferred, max)` where preferred includes a viewport unit (`2vw + 0.5rem`) creates smooth scaling.

**Offline operation** requires inlining all JavaScript. Download the UMD build, minify if needed, and paste the entire file content between `<script>` tags. For smaller bundles, use Rollup or esbuild to create a custom D3 build with only the required modules.

For charts requiring **d3-labeler** for automatic label positioning, include both the D3 base library and the labeler script inline. Call `labeler.start(2000)` after measuring label dimensions with `getBBox()`, then update label positions from the mutated `labelArray`. This produces results that appear hand-positioned, avoiding the mechanical look of simple offset rules.