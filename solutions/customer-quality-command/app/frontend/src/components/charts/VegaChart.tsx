import { useEffect, useRef } from 'react'
import embed from 'vega-embed'
import { CHART, SEQ } from './theme'

const CHART_CONFIG = {
  background: 'transparent',
  title: { color: CHART.text, fontSize: 13 },
  axis: {
    labelColor: CHART.textDim, titleColor: CHART.text, gridColor: CHART.grid,
    domainColor: CHART.grid, tickColor: CHART.grid, labelFontSize: 10, titleFontSize: 11,
  },
  legend: { labelColor: CHART.textDim, titleColor: CHART.text, labelFontSize: 10 },
  view: { stroke: 'transparent' },
  range: { category: SEQ },
  mark: { color: CHART.primary },
  bar: { fill: CHART.primary },
  line: { stroke: CHART.primary },
  point: { fill: CHART.primary },
}

export default function VegaChart({ spec }: { spec: Record<string, unknown> }) {
  const ref = useRef<HTMLDivElement>(null)
  useEffect(() => {
    if (!ref.current || !spec) return
    let view: any
    const merged = { ...spec, config: { ...(spec as any).config, ...CHART_CONFIG }, width: 'container' as any }
    embed(ref.current, merged as any, { actions: false, renderer: 'svg' })
      .then(r => { view = r.view })
      .catch(() => {})
    return () => { try { view?.finalize() } catch { /* noop */ } }
  }, [spec])
  return <div ref={ref} className="w-full mt-3 [&_svg]:!w-full" />
}
