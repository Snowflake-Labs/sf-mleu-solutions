import { useEffect, useRef } from 'react'
import embed from 'vega-embed'

interface Props {
  spec: any
  className?: string
}

export function VegaChart({ spec, className }: Props) {
  const ref = useRef<HTMLDivElement>(null)
  useEffect(() => {
    if (!ref.current || !spec) return
    let cancelled = false
    const finalSpec = { width: 'container', height: 240, background: 'transparent', ...spec }
    if (finalSpec.config) {
      finalSpec.config = {
        ...finalSpec.config,
        axis: { labelFont: 'Inter', titleFont: 'Inter', ...(finalSpec.config?.axis || {}) },
      }
    } else {
      finalSpec.config = {
        axis: { labelFont: 'Inter', titleFont: 'Inter' },
        title: { font: 'Inter', fontWeight: 700 },
      }
    }
    embed(ref.current, finalSpec, { actions: false, renderer: 'svg' })
      .then(r => { if (cancelled) r.finalize() })
      .catch(e => { if (ref.current) ref.current.textContent = `Chart error: ${e.message || e}` })
    return () => { cancelled = true }
  }, [spec])
  return <div ref={ref} className={`w-full overflow-hidden ${className || ''}`} />
}
