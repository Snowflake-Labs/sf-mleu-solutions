import { AreaChart, Area, ResponsiveContainer, YAxis } from 'recharts'
import { CHART } from './theme'

interface Props {
  data: number[]
  color?: string
  height?: number
}

export default function MiniSparkline({ data, color = CHART.primary, height = 36 }: Props) {
  if (!data || !data.length) return null
  const chartData = data.map((v, i) => ({ i, v }))
  const gid = `spark-${color.replace('#', '')}`
  return (
    <ResponsiveContainer width="100%" height={height}>
      <AreaChart data={chartData} margin={{ top: 2, right: 0, bottom: 0, left: 0 }}>
        <defs>
          <linearGradient id={gid} x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor={color} stopOpacity={0.5} />
            <stop offset="100%" stopColor={color} stopOpacity={0} />
          </linearGradient>
        </defs>
        <YAxis hide domain={['dataMin', 'dataMax']} />
        <Area type="monotone" dataKey="v" stroke={color} strokeWidth={1.5} fill={`url(#${gid})`} isAnimationActive={false} />
      </AreaChart>
    </ResponsiveContainer>
  )
}
