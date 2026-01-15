<script setup>
import { ref, watch, onMounted, onUnmounted } from 'vue'
import * as d3 from 'd3'

const props = defineProps({
  worlds: Array
})

const svgRef = ref(null)
const containerRef = ref(null)

const VIRTUAL_WIDTH = 8000
const VIRTUAL_HEIGHT = 5000

let simulation = null
let resizeObserver = null
let zoomBehavior = null
let savedTransform = null

const collapsed = ref(new Set())
const hoveredNode = ref(null)

const colorForDepth = d => (d === 0 ? '#5a67d8' : d === 1 ? '#4299e1' : '#48bb78')

function textColorFor(fill) {
  const c = d3.color(fill)
  if (!c) return '#000'
  const lum = (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) / 255
  return lum > 0.5 ? '#000' : '#fff'
}

function breakIntoLines(str, max = 18) {
  const words = String(str).split(/\s+/)
  const lines = []
  let cur = ''
  for (const w of words) {
    if ((cur + ' ' + w).trim().length <= max) cur = (cur + ' ' + w).trim()
    else { if (cur) lines.push(cur); cur = w }
  }
  if (cur) lines.push(cur)
  return lines
}

function toggleCollapse(id) {
  const s = new Set(collapsed.value)
  if (s.has(id)) s.delete(id); else s.add(id)
  collapsed.value = s
}

function render() {
  if (!props.worlds || !svgRef.value) return
  const oldPos = new Map()
  if (simulation) {
    simulation.nodes().forEach(d => {
      oldPos.set(d.data.id, { x: d.x, y: d.y, fx: d.fx, fy: d.fy })
    })
  }

  if (svgRef.value && zoomBehavior) savedTransform = d3.zoomTransform(svgRef.value)

  d3.select(svgRef.value).selectAll('*').remove()
  if (simulation) simulation.stop()

  const svg = d3.select(svgRef.value)
    .attr('viewBox', [0, 0, VIRTUAL_WIDTH, VIRTUAL_HEIGHT])
    .style('cursor', 'grab')

  const zoomLayer = svg.append('g').attr('class', 'zoom-layer')

  zoomBehavior = d3.zoom()
    .scaleExtent([0.8, 6])
    .on('zoom', (e) => zoomLayer.attr('transform', e.transform))

  svg.call(zoomBehavior)

  const spacing = VIRTUAL_WIDTH / (props.worlds.length + 1) * 1.4

  const allVisibleNodes = []
  const allLinks = []
  const nodeGroups = []

  props.worlds.forEach((world, i) => {
    const root = d3.hierarchy(world)
    const all = root.descendants()

    const visible = all.filter(node => {
      let p = node.parent
      while (p) { if (collapsed.value.has(p.data.id)) return false; p = p.parent }
      return true
    })

    const links = root.links().filter(l => visible.includes(l.source) && visible.includes(l.target))

    visible.forEach(n => {
      n._worldIndex = i
      const existing = oldPos.get(n.data.id)
      if (existing) {
        n.x = existing.x
        n.y = existing.y
        n.fx = existing.fx
        n.fy = existing.fy
      } else {
        const baseX = spacing * (i + 1)
        if (n.depth === 0) { 
          n.x = baseX
          n.y = VIRTUAL_HEIGHT / 2 
        } else if (n.depth === 1) {
          const siblings = n.parent.children.filter(ch => {
            let p = ch.parent
            while (p) { if (collapsed.value.has(p.data.id)) return false; p = p.parent }
            return true
          })
          const idx = siblings.indexOf(n)
          const total = siblings.length
          const angle = (idx / Math.max(total, 1)) * Math.PI * 2 - Math.PI / 2
          const r = 350
          n.x = (oldPos.get(n.parent.data.id)?.x || baseX) + Math.cos(angle) * r
          n.y = (oldPos.get(n.parent.data.id)?.y || VIRTUAL_HEIGHT / 2) + Math.sin(angle) * r
        } else {
          const siblings = n.parent.children.filter(ch => {
            let p = ch.parent
            while (p) { if (collapsed.value.has(p.data.id)) return false; p = p.parent }
            return true
          })
          const idx = siblings.indexOf(n)
          const total = siblings.length
          const angle = (idx / Math.max(total, 1)) * Math.PI * 2
          const r = 180
          const px = n.parent.x || oldPos.get(n.parent.data.id)?.x || spacing * (i + 1)
          const py = n.parent.y || oldPos.get(n.parent.data.id)?.y || VIRTUAL_HEIGHT / 2
          n.x = px + Math.cos(angle) * r
          n.y = py + Math.sin(angle) * r
        }
      }
      
      n._baseR = n.depth === 0 ? 50 : n.depth === 1 ? 35 : 20
      n._r = n._baseR
    })

    allVisibleNodes.push(...visible)
    allLinks.push(...links)
    nodeGroups.push({ visible, links, worldIndex: i, baseX: spacing * (i + 1) })
  })

  simulation = d3.forceSimulation(allVisibleNodes)
    .force('link', d3.forceLink(allLinks).id(d => d.data.id)
      .distance(d => d.target.depth === 1 ? 200 : d.target.depth === 2 ? 300 : 250)
      .strength(0.6))
    .force('charge', d3.forceManyBody().strength(d => d.depth === 0 ? -1200 : d.depth === 1 ? -800 : -500))
    .force('x', d3.forceX(d => {
      if (d.depth === 0) return spacing * (d._worldIndex + 1)
      return d.x
    }).strength(d => d.depth === 0 ? 0.5 : 0.03))
    .force('y', d3.forceY(d => d.depth === 0 ? VIRTUAL_HEIGHT / 2 : d.y).strength(d => d.depth === 0 ? 0.5 : 0.03))
    .force('collide', d3.forceCollide(d => d._r + 60).strength(1))
    .alpha(1).alphaDecay(0.01)

  nodeGroups.forEach(({ visible, links }) => {
    const g = zoomLayer.append('g')

    const link = g.selectAll('line').data(links).enter().append('line')
      .attr('stroke', d => {
        if (d.target.depth === 1) return '#90a4ae'
        if (d.target.depth === 2) return '#b0bec5'
        return '#cfd8dc'
      })
      .attr('stroke-width', d => d.target.depth === 1 ? 2.5 : d.target.depth === 2 ? 1.8 : 1.2)
      .attr('opacity', 0.4)
      .attr('class', d => `link-${d.source.data.id} link-${d.target.data.id}`)

    const node = g.selectAll('g.node').data(visible).enter().append('g')
      .attr('class', d => `node node-${d.data.id}`)
      .style('cursor', 'pointer')
      .on('mouseenter', (e, d) => {
        hoveredNode.value = d.data.id
        d3.select(e.currentTarget).select('circle').transition().duration(200).attr('r', d._r * 1.15).attr('stroke-width', 4)
        zoomLayer.selectAll('line').transition().duration(200).attr('opacity', 0.1)
        const relatedIds = new Set([d.data.id])
        if (d.children) d.children.forEach(ch => relatedIds.add(ch.data.id))
        if (d.parent) relatedIds.add(d.parent.data.id)
        relatedIds.forEach(id => {
          zoomLayer.selectAll(`.link-${id}`).transition().duration(200).attr('opacity', 0.9).attr('stroke-width', d => d.target.depth === 1 ? 4 : d.target.depth === 2 ? 3 : 2)
          zoomLayer.selectAll(`.node-${id}`).select('circle').transition().duration(200).attr('stroke-width', 3)
        })
      })
      .on('mouseleave', (e, d) => {
        hoveredNode.value = null
        d3.select(e.currentTarget).select('circle').transition().duration(200).attr('r', d._r).attr('stroke-width', (collapsed.value.has(d.data.id) && d.children) ? 4 : 2)
        zoomLayer.selectAll('line').transition().duration(200).attr('opacity', 0.4).attr('stroke-width', d => d.target.depth === 1 ? 2.5 : d.target.depth === 2 ? 1.8 : 1.2)
        zoomLayer.selectAll('circle').transition().duration(200).attr('stroke-width', d => (collapsed.value.has(d.data.id) && d.children) ? 4 : 2)
      })
      .on('click', (e, d) => { 
        e.stopPropagation()
        if (d.children && d.children.length) toggleCollapse(d.data.id)
      })
      .call(d3.drag()
        .on('start', (e, d) => { 
          if (!e.active) simulation.alphaTarget(0.3).restart()
          d.fx = d.x
          d.fy = d.y
        })
        .on('drag', (e, d) => { 
          d.fx = e.x
          d.fy = e.y
        })
        .on('end', (e, d) => { 
          if (!e.active) simulation.alphaTarget(0)
        })
      )

    const circle = node.append('circle')
      .attr('r', d => d._baseR)
      .attr('fill', d => colorForDepth(d.depth))
      .attr('stroke', d => (collapsed.value.has(d.data.id) && d.children) ? '#e53e3e' : '#2d3748')
      .attr('stroke-width', d => (collapsed.value.has(d.data.id) && d.children) ? 4 : 2)
      .attr('opacity', 0.95)
      .style('filter', 'drop-shadow(0 2px 4px rgba(0,0,0,0.2))')

    const text = node.append('text')
      .attr('text-anchor', 'middle')
      .attr('dominant-baseline', 'middle')
      .style('pointer-events', 'none')
      .style('font-size', d => d.depth === 0 ? '15px' : d.depth === 1 ? '13px' : '11px')
      .style('font-weight', d => d.depth === 0 ? '700' : d.depth === 1 ? '600' : '400')

    text.each(function (d) {
      const lines = breakIntoLines(d.data.name, d.depth === 0 ? 16 : d.depth === 1 ? 20 : 24)
      const el = d3.select(this)
      el.text(null)
      const lineHeight = 1.1
      const totalHeight = lines.length * lineHeight
      const startY = -(totalHeight - 1) / 2
      lines.forEach((l, idx) => {
        el.append('tspan').attr('x', 0).attr('dy', idx === 0 ? `${startY}em` : `${lineHeight}em`).text(l)
      })
      const box = this.getBBox()
      d._r = Math.max(d._baseR, box.width / 2 + 12, box.height / 2 + 10)
    })

    circle.attr('r', d => d._r)
    text.attr('fill', d => textColorFor(colorForDepth(d.depth)))
  })

  simulation.on('tick', () => {
    zoomLayer.selectAll('line')
      .attr('x1', d => d.source.x)
      .attr('y1', d => d.source.y)
      .attr('x2', d => d.target.x)
      .attr('y2', d => d.target.y)
    
    zoomLayer.selectAll('g.node')
      .attr('transform', d => `translate(${d.x},${d.y})`)
  })

  if (savedTransform) svg.call(zoomBehavior.transform, savedTransform)
  else {
    const container = containerRef.value
    const w = container.clientWidth
    const h = container.clientHeight
    const scale = 1.6
    const cx = VIRTUAL_WIDTH / 2
    const cy = VIRTUAL_HEIGHT / 2
    const tx = w / 2 - cx * scale
    const ty = h / 2 - cy * scale
    svg.call(zoomBehavior.transform, d3.zoomIdentity.translate(tx, ty).scale(scale))
  }
}

watch(() => props.worlds, render)
watch(() => collapsed.value, render)

onMounted(() => {
  render()
  resizeObserver = new ResizeObserver(render)
  if (containerRef.value) resizeObserver.observe(containerRef.value)
})

onUnmounted(() => {
  if (simulation) simulation.stop()
  resizeObserver?.disconnect()
})
</script>

<template>
  <div ref="containerRef" style="flex:1; width:100%; height:100%; overflow:hidden;">
    <svg ref="svgRef" style="width:100%; height:100%;" />
  </div>
</template>

<style scoped>
.node { cursor: grab; }
.node:active { cursor: grabbing; }
</style>