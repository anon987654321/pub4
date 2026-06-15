import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { nodes: Array, links: Array }

  connect() {
    this.render()
  }

  render() {
    const width = 640
    const height = 320
    const cx = width / 2
    const cy = height / 2
    const radius = 120
    const nodes = this.nodesValue.map((n) => ({ ...n }))
    const root = nodes.find((n) => n.root) || nodes[0]

    nodes.forEach((node, i) => {
      if (node.id === root.id) {
        node.x = cx
        node.y = cy
      } else {
        const angle = ((i - 1) / Math.max(nodes.length - 1, 1)) * Math.PI * 2
        node.x = cx + Math.cos(angle) * radius
        node.y = cy + Math.sin(angle) * radius
      }
    })

    const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg")
    svg.setAttribute("width", width)
    svg.setAttribute("height", height)

    this.linksValue.forEach((link) => {
      const source = nodes.find((n) => n.id === link.source)
      const target = nodes.find((n) => n.id === link.target)
      if (!source || !target) return
      const line = document.createElementNS("http://www.w3.org/2000/svg", "line")
      line.setAttribute("x1", source.x)
      line.setAttribute("y1", source.y)
      line.setAttribute("x2", target.x)
      line.setAttribute("y2", target.y)
      line.setAttribute("stroke", "#888")
      svg.appendChild(line)
    })

    nodes.forEach((node) => {
      const circle = document.createElementNS("http://www.w3.org/2000/svg", "circle")
      circle.setAttribute("cx", node.x)
      circle.setAttribute("cy", node.y)
      circle.setAttribute("r", node.root ? 18 : 12)
      circle.setAttribute("fill", node.root ? "#222" : "#f2f2f2")
      svg.appendChild(circle)
      const text = document.createElementNS("http://www.w3.org/2000/svg", "text")
      text.setAttribute("x", node.x)
      text.setAttribute("y", node.y + 28)
      text.setAttribute("text-anchor", "middle")
      text.setAttribute("font-size", "9")
      text.textContent = node.label
      svg.appendChild(text)
    })

    this.element.innerHTML = ""
    this.element.appendChild(svg)
  }
}