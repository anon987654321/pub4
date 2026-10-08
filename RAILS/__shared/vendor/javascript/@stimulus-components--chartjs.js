import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["canvas"]
  static values = {
    type: { type: String, default: "line" },
    data: Object,
    options: Object,
  }

  connect() {
    const canvas = this.hasCanvasTarget ? this.canvasTarget : this.element
    this.chart = {
      canvas,
      type: this.typeValue,
      data: this.dataValue || {},
      options: { ...this.defaultOptions, ...(this.optionsValue || {}) },
      update: () => this.render(),
      destroy: () => this.destroyChart(),
    }
    this.render()
  }

  render() {
    const canvas = this.chart?.canvas || this.element
    const context = canvas?.getContext?.("2d")
    if (!context) return
    const datasets = Array.isArray(this.chart?.data?.datasets) ? this.chart.data.datasets : []
    const values = datasets
      .flatMap((dataset) => Array.isArray(dataset.data) ? dataset.data : [])
      .map(Number)
      .filter(Number.isFinite)
    const width = canvas.clientWidth || canvas.width || 320
    const height = canvas.clientHeight || canvas.height || 180
    const scale = window.devicePixelRatio || 1
    canvas.width = Math.max(1, Math.round(width * scale))
    canvas.height = Math.max(1, Math.round(height * scale))
    context.setTransform(scale, 0, 0, scale, 0, 0)
    context.clearRect(0, 0, width, height)
    if (!values.length) return
    const padding = Number(this.chart.options.padding || 12)
    const max = Math.max(...values)
    const min = Math.min(...values)
    const range = max - min || 1
    context.beginPath()
    values.forEach((value, index) => {
      const x = padding + (index / Math.max(1, values.length - 1)) * (width - padding * 2)
      const y = height - padding - ((value - min) / range) * (height - padding * 2)
      index === 0 ? context.moveTo(x, y) : context.lineTo(x, y)
    })
    context.stroke()
  }

  destroyChart() {
    const canvas = this.chart?.canvas
    const context = canvas?.getContext?.("2d")
    if (canvas && context) {
      context.setTransform(1, 0, 0, 1, 0, 0)
      context.clearRect(0, 0, canvas.width, canvas.height)
    }
    this.chart = null
  }

  disconnect() {
    this.destroyChart()
  }

  get defaultOptions() {
    return {}
  }
}
