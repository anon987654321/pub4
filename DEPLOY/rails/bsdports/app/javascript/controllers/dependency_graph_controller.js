import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { nodes: Array, links: Array }

  connect() {
    this.render()
  }

  render() {
    const width = this.element.clientWidth || 640
    const height = 360
    const nodes = this.nodesValue.map((n, i) => ({ ...n, x: width / 2, y: 40 + i * 20 }))
    const links = this.linksValue

    this.element.innerHTML = ""
    const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg")
    svg.setAttribute("width", width)
    svg.setAttribute("height", height)
    svg.setAttribute("viewBox", `0 0 ${width} ${height}`)

    const center = nodes.find((n) => n.root) || nodes[0]
    if (center) {
      const cx = width / 2
      const cy = height / 2
      const radius = Math.min(width, height) / 2 - 40
      nodes.forEach((node, i) => {
        if (node.root) {
          node.x = cx
          node.y = cy
        } else {
          const angle = (i / Math.max(nodes.length - 1, 1)) * Math.PI * 2
          node.x = cx + Math.cos(angle) * radius
          node.y = cy + Math.sin(angle) * radius
        }
      })
    }

    links.forEach((link) => {
      const source = nodes.find((n) => n.id === link.source)
      const target = nodes.find((n) => n.id === link.target)
      if (!source || !target) return
      const line = document.createElementNS("http://www.w3.org/2000/svg", "line")
      line.setAttribute("x1", source.x)
      line.setAttribute("y1", source.y)
      line.setAttribute("x2", target.x)
      line.setAttribute("y2", target.y)
      line.setAttribute("stroke", "#666")
      svg.appendChild(line)
    })

    nodes.forEach((node) => {
      const g = document.createElementNS("http://www.w3.org/2000/svg", "g")
      const circle = document.createElementNS("http://www.w3.org/2000/svg", "circle")
      circle.setAttribute("cx", node.x)
      circle.setAttribute("cy", node.y)
      circle.setAttribute("r", node.root ? 22 : 14)
      circle.setAttribute("fill", node.root ? "#111" : "#eee")
      circle.setAttribute("stroke", "#333")
      const text = document.createElementNS("http://www.w3.org/2000/svg", "text")
      text.setAttribute("x", node.x)
      text.setAttribute("y", node.y + 4)
      text.setAttribute("text-anchor", "middle")
      text.setAttribute("font-size", "8")
      text.textContent = node.label
      g.appendChild(circle)
      g.appendChild(text)
      svg.appendChild(g)
    })

    this.element.appendChild(svg)
  }
}