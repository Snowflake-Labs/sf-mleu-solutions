import { CHART } from './theme'

interface Region {
  key: string
  label: string
  path: string
  cx: number
  cy: number
}

// Schematic North America regions (approximate geographic placement).
const REGIONS: Region[] = [
  { key: 'Canada West', label: 'Canada W', path: 'M30,20 L250,20 L250,80 L200,95 L30,95 Z', cx: 135, cy: 55 },
  { key: 'Canada East', label: 'Canada E', path: 'M250,20 L440,20 L440,85 L300,95 L250,80 Z', cx: 350, cy: 55 },
  { key: 'West', label: 'West', path: 'M30,95 L150,95 L150,210 L45,235 L30,150 Z', cx: 92, cy: 160 },
  { key: 'Midwest', label: 'Midwest', path: 'M150,95 L300,95 L300,190 L150,210 Z', cx: 225, cy: 150 },
  { key: 'Northeast', label: 'Northeast', path: 'M300,95 L440,85 L430,170 L300,190 Z', cx: 370, cy: 135 },
  { key: 'South Central', label: 'S. Central', path: 'M45,235 L150,210 L245,210 L235,290 L110,290 Z', cx: 150, cy: 250 },
  { key: 'Southeast', label: 'Southeast', path: 'M245,210 L430,170 L420,270 L300,285 L235,290 Z', cx: 335, cy: 235 },
]

interface Props {
  data: { name: string; value: number }[]
  height?: number
}

function shade(t: number): string {
  // interpolate subtle surface (#EEF3F7) -> brand Mid Blue (#11567F)
  const a = [238, 243, 247]
  const b = [17, 86, 127]
  const c = a.map((v, i) => Math.round(v + (b[i] - v) * t))
  return `rgb(${c[0]},${c[1]},${c[2]})`
}

export default function USRegionMap({ data, height = 320 }: Props) {
  const map = new Map(data.map(d => [d.name, d.value]))
  const max = Math.max(...data.map(d => d.value), 1)
  return (
    <svg viewBox="0 0 470 310" style={{ width: '100%', height }}>
      {REGIONS.map(r => {
        const v = map.get(r.key) || 0
        const t = v / max
        return (
          <g key={r.key}>
            <title>{`${r.key}: ${v.toLocaleString()}`}</title>
            <path d={r.path} fill={shade(t)} stroke="#FFFFFF" strokeWidth={1.5}
              style={{ transition: 'fill 0.4s' }} />
            <text x={r.cx} y={r.cy} textAnchor="middle" fontSize={10}
              fill={t > 0.55 ? '#FFFFFF' : CHART.textDim} fontWeight={600}>{r.label}</text>
            <text x={r.cx} y={r.cy + 13} textAnchor="middle" fontSize={11}
              fill={t > 0.55 ? '#FFFFFF' : CHART.text} fontWeight={700}>{v.toLocaleString()}</text>
          </g>
        )
      })}
    </svg>
  )
}
