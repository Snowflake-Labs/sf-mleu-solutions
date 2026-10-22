import { RadialBarChart, RadialBar, PolarAngleAxis } from 'recharts'
import { CHART } from './theme'

interface GaugeProps {
  value: number
  max?: number
  label?: string
  sublabel?: string
  color?: string
  size?: number
  suffix?: string
}

export default function Gauge({ value, max = 100, label, sublabel, color = CHART.primaryDark, size = 130, suffix = '' }: GaugeProps) {
  const pct = max > 0 ? Math.max(0, Math.min(100, (value / max) * 100)) : 0
  const data = [{ name: label || '', value: pct, fill: color }]
  const disp = value == null ? '—'
    : Math.abs(value) >= 1e6 ? `${(value / 1e6).toFixed(1)}M`
    : Math.abs(value) >= 1e4 ? `${(value / 1e3).toFixed(0)}K`
    : Number(value).toLocaleString()
  return (
    <div className="flex flex-col items-center" style={{ width: size }}>
      <div style={{ position: 'relative', width: size, height: size * 0.72 }}>
        <RadialBarChart
          width={size}
          height={size}
          cx="50%"
          cy="75%"
          innerRadius="78%"
          outerRadius="115%"
          barSize={10}
          data={data}
          startAngle={180}
          endAngle={0}
        >
          <PolarAngleAxis type="number" domain={[0, 100]} angleAxisId={0} tick={false} />
          <RadialBar background={{ fill: CHART.gray }} dataKey="value" cornerRadius={6} angleAxisId={0} />
        </RadialBarChart>
        <div style={{ position: 'absolute', top: '52%', left: 0, right: 0, textAlign: 'center' }}>
          <div style={{ fontSize: 20, fontWeight: 700, color }}>
            {disp}{value != null ? suffix : ''}
          </div>
        </div>
      </div>
      {label && <div className="text-[10px] uppercase tracking-widest text-brand-muted text-center leading-tight">{label}</div>}
      {sublabel && <div className="text-[10px] text-brand-muted text-center">{sublabel}</div>}
    </div>
  )
}
