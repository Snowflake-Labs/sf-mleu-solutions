import { THEME } from '../../config/brand'

// Chart tokens for recharts / vega on a light surface. Sourced from config/brand.ts.
export const CHART = {
  primary: THEME.accent,
  primaryDark: THEME.primary,
  panel: THEME.surface,
  gray: THEME.border,
  grid: '#E3EAF0',
  text: THEME.text,
  textDim: THEME.muted,
}

export const PILLAR: Record<string, string> = {
  SAFETY: THEME.pillar.safety,
  PRODUCTIVITY: THEME.pillar.productivity,
  EXPERIENCE: THEME.pillar.experience,
  ENTERPRISE: THEME.primary,
}

export const SEQ: string[] = [...THEME.series]

export const axisProps = {
  tick: { fill: CHART.textDim, fontSize: 11 },
  stroke: CHART.grid,
}

export const tooltipStyle = {
  contentStyle: {
    background: THEME.surface,
    border: `1px solid ${CHART.gray}`,
    borderRadius: 8,
    fontSize: 12,
    boxShadow: '0 4px 12px rgba(16, 42, 67, 0.08)',
  },
  labelStyle: { color: CHART.text, fontWeight: 600 },
  itemStyle: { color: CHART.text },
} as const

export const fmtUsd = (n: number) =>
  n == null ? '—' : n >= 1e6 ? `$${(n / 1e6).toFixed(1)}M` : n >= 1e3 ? `$${(n / 1e3).toFixed(0)}K` : `$${Number(n).toFixed(0)}`

export const fmtNum = (n: number) => (n == null ? '—' : Number(n).toLocaleString())
