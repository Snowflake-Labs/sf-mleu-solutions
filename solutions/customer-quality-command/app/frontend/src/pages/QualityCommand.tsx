import { useQuery } from '@tanstack/react-query'
import { useNavigate } from 'react-router-dom'
import { PieChart, Pie, Cell, ResponsiveContainer, Tooltip, BarChart, Bar, XAxis, YAxis } from 'recharts'
import PageHeader from '../components/PageHeader'
import MiniSparkline from '../components/charts/MiniSparkline'
import USRegionMap from '../components/charts/USRegionMap'
import { PILLAR, SEQ, CHART, tooltipStyle, fmtUsd } from '../components/charts/theme'
import { fetchRibbon, fetchCuratedIssues, fetchImpacted, fetchTrend } from '../services/api'
import ArchetypeBand from '../components/ArchetypeBand'
import { ANCHOR_MACHINE, BRAND } from '../config/brand'

const arr = (d: any) => (Array.isArray(d) ? d : [])

const PILLAR_BORDER: Record<string, string> = {
  SAFETY: 'border-pillar-safety/60', PRODUCTIVITY: 'border-pillar-productivity/60',
  EXPERIENCE: 'border-pillar-experience/60', ENTERPRISE: 'border-brand-accent/60',
}
const PILLAR_TEXT: Record<string, string> = {
  SAFETY: 'text-pillar-safety', PRODUCTIVITY: 'text-pillar-productivity',
  EXPERIENCE: 'text-pillar-experience', ENTERPRISE: 'text-brand-primary',
}

function RibbonCard({ r, spark }: { r: any; spark: number[] }) {
  const headline =
    r.PILLAR === 'PRODUCTIVITY' || r.PILLAR === 'ENTERPRISE'
      ? fmtUsd(r.HEADLINE || 0)
      : r.HEADLINE != null ? String(r.HEADLINE) : '—'
  const label = r.PILLAR === 'ENTERPRISE' ? 'Enterprise Exposure · plan for'
    : r.PILLAR === 'SAFETY' ? 'Safety · max SIP'
    : r.PILLAR === 'PRODUCTIVITY' ? 'Productivity · max VTC'
    : 'Experience · CEI'
  return (
    <div className={`rounded-lg border p-4 bg-brand-surface ${PILLAR_BORDER[r.PILLAR] || ''}`}>
      <div className="text-[11px] uppercase tracking-widest text-brand-muted">{label}</div>
      <div className={`text-2xl font-bold mt-1 ${PILLAR_TEXT[r.PILLAR] || ''}`}>{headline}</div>
      <div className="text-xs text-brand-muted mb-1">{r.ISSUE_COUNT} issues</div>
      <MiniSparkline data={spark} color={PILLAR[r.PILLAR] || CHART.primary} />
    </div>
  )
}

export default function QualityCommand() {
  const nav = useNavigate()
  const ribbon = useQuery({ queryKey: ['ribbon'], queryFn: fetchRibbon })
  const issues = useQuery({ queryKey: ['curated'], queryFn: () => fetchCuratedIssues(10) })
  const custs = useQuery({ queryKey: ['imp-cust'], queryFn: () => fetchImpacted('customers') })
  const areas = useQuery({ queryKey: ['imp-area'], queryFn: () => fetchImpacted('areas') })
  const trend = useQuery({ queryKey: ['trend'], queryFn: fetchTrend })

  const trendByDim = (dim: string): number[] =>
    arr(trend.data).filter((t: any) => t.DIMENSION === dim).map((t: any) => Number(t.VALUE))
  const sparkFor = (pillar: string) => {
    if (pillar === 'ENTERPRISE') {
      const all: Record<string, number> = {}
      arr(trend.data).forEach((t: any) => { all[t.MONTH] = (all[t.MONTH] || 0) + Number(t.VALUE) })
      return Object.keys(all).sort().map(k => all[k])
    }
    return trendByDim(pillar)
  }

  const custData = arr(custs.data).slice(0, 6).map((c: any) => ({ name: c.ENTITY_NAME, value: Number(c.EXPOSURE_COUNT) }))
  const areaData = arr(areas.data).map((a: any) => ({ name: a.ENTITY_NAME, value: Number(a.EXPOSURE_COUNT) }))
  const issueBars = arr(issues.data).slice(0, 8).map((i: any) => ({
    name: `#${i.PRIORITY_RANK}`, value: Number(i.WARRANTY_EXPOSURE_P90 || 0), pillar: i.QUALITY_DIMENSION, id: i.ISSUE_ID,
  }))

  return (
    <div className="flex-1">
      <PageHeader title="Quality Command" subtitle={`${ANCHOR_MACHINE} · ${BRAND.businessUnit}`} />
      <div className="p-8 space-y-6">
        <div className="grid grid-cols-4 gap-4">
          {arr(ribbon.data).map((r: any) => <RibbonCard key={r.PILLAR} r={r} spark={sparkFor(r.PILLAR)} />)}
        </div>

        <ArchetypeBand />

        <div className="grid grid-cols-3 gap-6">
          <section className="col-span-2 space-y-6">
            <div>
              <h2 className="text-sm font-semibold tracking-widest text-brand-muted mb-2">CURATED — TOP QUALITY ISSUES</h2>
              <div className="rounded-lg border border-brand-border overflow-hidden">
                <table className="w-full text-sm">
                  <thead className="bg-brand-subtle text-brand-muted text-xs uppercase">
                    <tr>
                      <th className="text-left px-3 py-2">#</th><th className="text-left px-3 py-2">Issue</th>
                      <th className="text-left px-3 py-2">Pillar</th><th className="text-right px-3 py-2">Exposed</th>
                      <th className="text-right px-3 py-2" title="Budget this — 9-in-10 chance it won't be exceeded">Plan-for exposure</th><th className="text-left px-3 py-2">Root cause</th>
                    </tr>
                  </thead>
                  <tbody>
                    {arr(issues.data).map((i: any) => (
                      <tr key={i.ISSUE_ID} onClick={() => nav('/issues')}
                          className="border-t border-brand-border hover:bg-brand-subtle cursor-pointer">
                        <td className="px-3 py-2 text-brand-muted">{i.PRIORITY_RANK}</td>
                        <td className="px-3 py-2">{i.TITLE}</td>
                        <td className={`px-3 py-2 font-semibold ${PILLAR_TEXT[i.QUALITY_DIMENSION] || ''}`}>{i.QUALITY_DIMENSION}</td>
                        <td className="px-3 py-2 text-right">{i.EXPOSED_FLEET_COUNT}</td>
                        <td className="px-3 py-2 text-right">{fmtUsd(i.WARRANTY_EXPOSURE_P90 || 0)}</td>
                        <td className="px-3 py-2 text-xs text-brand-muted">{i.ROOT_CAUSE_TYPE}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>

            <div>
              <h2 className="text-sm font-semibold tracking-widest text-brand-muted mb-2">PLAN-FOR EXPOSURE BY ISSUE</h2>
              <div className="rounded-lg border border-brand-border bg-brand-surface p-3">
                <ResponsiveContainer width="100%" height={200}>
                  <BarChart data={issueBars} margin={{ top: 4, right: 12, bottom: 0, left: 8 }}>
                    <XAxis dataKey="name" tick={{ fill: CHART.textDim, fontSize: 11 }} stroke={CHART.grid} />
                    <YAxis tickFormatter={fmtUsd} tick={{ fill: CHART.textDim, fontSize: 11 }} stroke={CHART.grid} width={48} />
                    <Tooltip {...tooltipStyle} formatter={(v: any) => fmtUsd(v)} cursor={{ fill: '#E3EAF0' }} />
                    <Bar dataKey="value" radius={[3, 3, 0, 0]} onClick={() => nav('/issues')} cursor="pointer">
                      {issueBars.map((b, i) => <Cell key={i} fill={PILLAR[b.pillar] || CHART.primary} />)}
                    </Bar>
                  </BarChart>
                </ResponsiveContainer>
              </div>
            </div>
          </section>

          <section className="space-y-6">
            <div>
              <h2 className="text-sm font-semibold tracking-widest text-brand-muted mb-2">IMPACTED CUSTOMERS</h2>
              <div className="rounded-lg border border-brand-border bg-brand-surface p-3">
                <ResponsiveContainer width="100%" height={180}>
                  <PieChart>
                    <Pie data={custData} dataKey="value" nameKey="name" cx="50%" cy="50%" innerRadius={40} outerRadius={70} paddingAngle={2}>
                      {custData.map((_, i) => <Cell key={i} fill={SEQ[i % SEQ.length]} stroke={CHART.panel} />)}
                    </Pie>
                    <Tooltip {...tooltipStyle} />
                  </PieChart>
                </ResponsiveContainer>
              </div>
            </div>
            <div>
              <h2 className="text-sm font-semibold tracking-widest text-brand-muted mb-2">IMPACTED AREAS</h2>
              <div className="rounded-lg border border-brand-border bg-brand-surface p-3">
                <USRegionMap data={areaData} height={230} />
              </div>
            </div>
          </section>
        </div>
      </div>
    </div>
  )
}
