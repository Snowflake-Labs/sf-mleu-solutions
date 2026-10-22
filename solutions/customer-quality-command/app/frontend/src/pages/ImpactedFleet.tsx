import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { BarChart, Bar, XAxis, YAxis, ResponsiveContainer, Tooltip, Cell, LabelList } from 'recharts'
import PageHeader from '../components/PageHeader'
import USRegionMap from '../components/charts/USRegionMap'
import { CHART, SEQ, tooltipStyle, fmtUsd, fmtNum } from '../components/charts/theme'
import { fetchCuratedIssues, fetchImpacted } from '../services/api'

const arr = (d: any) => (Array.isArray(d) ? d : [])

function BarPanel({ title, dim, issueId }: { title: string; dim: any; issueId: string }) {
  const q = useQuery({ queryKey: ['imp', dim, issueId], queryFn: () => fetchImpacted(dim, issueId), enabled: !!issueId })
  const rows = arr(q.data).slice(0, 8)
  const data = rows.map((r: any) => ({
    name: r.ENTITY_NAME, value: Number(r.EXPOSURE_COUNT) || 0, impact: Number(r.IMPACT_VALUE) || 0,
  }))
  return (
    <section className="rounded-lg border border-brand-border bg-brand-surface p-4">
      <div className="flex items-baseline justify-between mb-3">
        <h3 className="text-sm font-semibold tracking-widest text-brand-text">{title}</h3>
        <span className="text-[10px] uppercase tracking-widest text-brand-muted">{rows.length} shown</span>
      </div>
      {data.length ? (
        <ResponsiveContainer width="100%" height={Math.max(140, data.length * 30)}>
          <BarChart data={data} layout="vertical" margin={{ top: 0, right: 52, bottom: 0, left: 8 }}>
            <XAxis type="number" tick={{ fill: CHART.textDim, fontSize: 10 }} stroke={CHART.grid} />
            <YAxis type="category" dataKey="name" width={140} tick={{ fill: CHART.text, fontSize: 11 }} stroke={CHART.grid} />
            <Tooltip {...tooltipStyle}
              formatter={(v: any, n: any) => n === 'value' ? [fmtNum(v), 'Exposed'] : [fmtUsd(v), 'Impact']}
              cursor={{ fill: '#E3EAF0' }} />
            <Bar dataKey="value" radius={[0, 3, 3, 0]}>
              {data.map((_, i) => <Cell key={i} fill={SEQ[i % SEQ.length]} />)}
              <LabelList dataKey="value" position="right" formatter={fmtNum} fill={CHART.text} fontSize={10} />
            </Bar>
          </BarChart>
        </ResponsiveContainer>
      ) : <div className="text-xs text-slate-500">No impacted {String(dim)} for this issue.</div>}
    </section>
  )
}

function AreaMapPanel({ issueId }: { issueId: string }) {
  const q = useQuery({ queryKey: ['imp', 'areas', issueId], queryFn: () => fetchImpacted('areas', issueId), enabled: !!issueId })
  const data = arr(q.data).map((r: any) => ({ name: r.ENTITY_NAME, value: Number(r.EXPOSURE_COUNT) || 0 }))
  return (
    <section className="rounded-lg border border-brand-border bg-brand-surface p-4">
      <div className="flex items-baseline justify-between mb-3">
        <h3 className="text-sm font-semibold tracking-widest text-brand-text">GEOGRAPHIC AREAS</h3>
        <span className="text-[10px] uppercase tracking-widest text-brand-muted">exposure by region</span>
      </div>
      {data.length ? <USRegionMap data={data} height={240} /> : <div className="text-xs text-slate-500">No regional data.</div>}
    </section>
  )
}

export default function ImpactedFleet() {
  const issues = useQuery({ queryKey: ['curated'], queryFn: () => fetchCuratedIssues(15) })
  const list = arr(issues.data)
  const [sel, setSel] = useState<string | null>(null)
  const id = sel || list[0]?.ISSUE_ID

  return (
    <div className="flex-1">
      <PageHeader title="Impacted Fleet" subtitle="Who and where an issue reaches — customers, dealers, facilities, regions" />
      <div className="p-8 space-y-5">
        <select value={id || ''} onChange={ev => setSel(ev.target.value)}
          className="bg-brand-surface border border-brand-border rounded px-3 py-2 text-sm w-full max-w-xl">
          {list.map((i: any) => <option key={i.ISSUE_ID} value={i.ISSUE_ID}>#{i.PRIORITY_RANK} · {i.TITLE} ({i.QUALITY_DIMENSION})</option>)}
        </select>

        {id && (
          <div className="grid grid-cols-2 gap-4">
            <BarPanel title="IMPACTED CUSTOMERS" dim="customers" issueId={id} />
            <BarPanel title="IMPACTED DEALERS" dim="dealers" issueId={id} />
            <BarPanel title="BUILD FACILITIES" dim="facilities" issueId={id} />
            <AreaMapPanel issueId={id} />
          </div>
        )}
      </div>
    </div>
  )
}
