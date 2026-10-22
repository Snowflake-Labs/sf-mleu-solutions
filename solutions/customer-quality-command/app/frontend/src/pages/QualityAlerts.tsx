import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { BarChart, Bar, XAxis, YAxis, ResponsiveContainer, Tooltip, Cell, PieChart, Pie, LabelList } from 'recharts'
import PageHeader from '../components/PageHeader'
import { CHART, tooltipStyle } from '../components/charts/theme'
import { fetchAlerts, forwardAlert, ackAlert } from '../services/api'

const SEV_TONE: Record<string, string> = {
  CRITICAL: 'border-l-pillar-safety', HIGH: 'border-l-pillar-productivity', MED: 'border-l-pillar-experience',
}
const STATE_TONE: Record<string, string> = {
  NEW: 'bg-pillar-safety/20 text-pillar-safety',
  ACKNOWLEDGED: 'bg-brand-accent/20 text-brand-primary',
  FORWARDED: 'bg-pillar-experience/20 text-pillar-experience',
  ASSIGNED: 'bg-blue-500/20 text-blue-700',
  IN_PROGRESS: 'bg-blue-500/20 text-blue-700',
  RESOLVED: 'bg-pillar-productivity/20 text-pillar-productivity',
  VERIFIED: 'bg-pillar-productivity/20 text-pillar-productivity',
}
const arr = (d: any) => (Array.isArray(d) ? d : [])

export default function QualityAlerts() {
  const qc = useQueryClient()
  const [filter, setFilter] = useState<string | undefined>(undefined)
  const alerts = useQuery({ queryKey: ['alerts', filter], queryFn: () => fetchAlerts(filter) })
  const inval = () => qc.invalidateQueries({ queryKey: ['alerts'] })
  const fwd = useMutation({ mutationFn: (id: string) => forwardAlert(id, 'OWN-MFG', 'app_user'), onSuccess: inval })
  const ack = useMutation({ mutationFn: (id: string) => ackAlert(id, 'app_user'), onSuccess: inval })

  const rows = arr(alerts.data)
  const SEV_COLOR: Record<string, string> = { CRITICAL: '#C62828', HIGH: '#B45309', MED: '#0F766E' }
  const sevData = ['CRITICAL', 'HIGH', 'MED'].map(s => ({ name: s, n: rows.filter((a: any) => a.SEVERITY === s).length, color: SEV_COLOR[s] }))
  const pillarData = ['SAFETY', 'PRODUCTIVITY', 'EXPERIENCE'].map(p => ({
    name: p, n: rows.filter((a: any) => a.PILLAR === p).length,
    color: p === 'SAFETY' ? '#C62828' : p === 'PRODUCTIVITY' ? '#B45309' : '#0F766E',
  })).filter(d => d.n > 0)
  const breached = rows.filter((a: any) => a.SLA_BREACHED).length

  return (
    <div className="flex-1">
      <PageHeader title="Quality Alerts" subtitle="Live alert feed — forward or acknowledge to open a tracked work item" />
      <div className="p-8">
        <div className="flex gap-2 mb-4">
          {[undefined, 'SAFETY', 'PRODUCTIVITY', 'EXPERIENCE'].map((f, k) => (
            <button key={k} onClick={() => setFilter(f)}
              className={`px-3 py-1 rounded text-sm border ${filter === f ? 'border-brand-accent text-brand-primary' : 'border-brand-border text-brand-muted'}`}>
              {f || 'All'}
            </button>
          ))}
          <span className="ml-auto flex items-center gap-2 text-xs text-brand-muted"><span className="h-2 w-2 rounded-full bg-green-500 animate-pulse-live" /> Live</span>
        </div>
        {rows.length > 0 && (
          <div className="grid grid-cols-3 gap-4 mb-5">
            <section className="rounded-lg border border-brand-border bg-brand-surface p-4">
              <h3 className="text-xs font-semibold tracking-widest text-brand-muted mb-2">SEVERITY</h3>
              <ResponsiveContainer width="100%" height={130}>
                <BarChart data={sevData} margin={{ top: 12, right: 8, bottom: 0, left: -18 }}>
                  <XAxis dataKey="name" tick={{ fill: CHART.textDim, fontSize: 10 }} stroke={CHART.grid} />
                  <YAxis allowDecimals={false} tick={{ fill: CHART.textDim, fontSize: 10 }} stroke={CHART.grid} />
                  <Tooltip {...tooltipStyle} cursor={{ fill: '#E3EAF0' }} />
                  <Bar dataKey="n" radius={[3, 3, 0, 0]}>
                    {sevData.map((d, i) => <Cell key={i} fill={d.color} />)}
                    <LabelList dataKey="n" position="top" fill={CHART.text} fontSize={10} />
                  </Bar>
                </BarChart>
              </ResponsiveContainer>
            </section>
            <section className="rounded-lg border border-brand-border bg-brand-surface p-4">
              <h3 className="text-xs font-semibold tracking-widest text-brand-muted mb-2">BY PILLAR</h3>
              <ResponsiveContainer width="100%" height={130}>
                <PieChart>
                  <Pie data={pillarData} dataKey="n" nameKey="name" cx="50%" cy="50%" innerRadius={34} outerRadius={56} paddingAngle={2}>
                    {pillarData.map((d, i) => <Cell key={i} fill={d.color} stroke={CHART.panel} />)}
                  </Pie>
                  <Tooltip {...tooltipStyle} />
                </PieChart>
              </ResponsiveContainer>
            </section>
            <section className="rounded-lg border border-brand-border bg-brand-surface p-4 flex flex-col justify-center">
              <h3 className="text-xs font-semibold tracking-widest text-brand-muted mb-2">SLA</h3>
              <div className="flex items-baseline gap-6">
                <div><div className="text-3xl font-bold text-brand-text">{rows.length}</div><div className="text-[10px] uppercase tracking-widest text-brand-muted">open alerts</div></div>
                <div><div className={`text-3xl font-bold ${breached > 0 ? 'text-pillar-safety' : 'text-pillar-productivity'}`}>{breached}</div><div className="text-[10px] uppercase tracking-widest text-brand-muted">breached</div></div>
              </div>
            </section>
          </div>
        )}
        <div className="space-y-3">
          {arr(alerts.data).map((a: any) => (
            <div key={a.ALERT_ID} className={`rounded-lg border border-brand-border border-l-4 ${SEV_TONE[a.SEVERITY] || ''} bg-brand-surface p-4`}>
              <div className="flex items-center gap-2 mb-1">
                <span className={`text-[10px] px-2 py-0.5 rounded ${STATE_TONE[a.WORKFLOW_STATE] || 'bg-brand-subtle text-brand-text'}`}>{a.WORKFLOW_STATE}</span>
                <span className="text-[10px] px-2 py-0.5 rounded bg-brand-subtle text-brand-text">{a.SEVERITY}</span>
                <span className="text-[10px] px-2 py-0.5 rounded bg-brand-subtle text-brand-muted">{a.PILLAR}</span>
                <span className="text-sm font-semibold">{a.HEADLINE}</span>
                <span className="ml-auto text-xs text-brand-muted">
                  {a.OWNER_NAME ? `→ ${a.OWNER_NAME}` : `#${a.PRIORITY_RANK}`}
                  {a.SLA_BREACHED ? <span className="ml-2 text-pillar-safety font-semibold">SLA BREACHED</span> : null}
                </span>
              </div>
              <p className="text-sm text-brand-muted mb-2">{a.BODY}</p>
              <div className="flex gap-2">
                <button onClick={() => fwd.mutate(a.ALERT_ID)} disabled={fwd.isPending}
                  className="text-xs px-3 py-1 rounded bg-brand-primary text-white font-semibold disabled:opacity-50">Forward to Plant QC</button>
                <button onClick={() => ack.mutate(a.ALERT_ID)} disabled={ack.isPending}
                  className="text-xs px-3 py-1 rounded border border-brand-border text-brand-text disabled:opacity-50">Acknowledge</button>
                {a.WORKFLOW_ITEM_ID ? <span className="text-[10px] px-2 py-1 text-slate-500 font-mono">{a.WORKFLOW_ITEM_ID}</span> : null}
              </div>
            </div>
          ))}
          {arr(alerts.data).length === 0 && <p className="text-brand-muted text-sm">No alerts.</p>}
        </div>
      </div>
    </div>
  )
}
