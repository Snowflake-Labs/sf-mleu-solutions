import { useState, useEffect, useRef } from 'react'
import { useSearchParams } from 'react-router-dom'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { BarChart, Bar, XAxis, YAxis, ResponsiveContainer, Tooltip, Cell, PieChart, Pie, LabelList } from 'recharts'
import PageHeader from '../components/PageHeader'
import { CHART, SEQ, tooltipStyle } from '../components/charts/theme'
import {
  fetchOpenWorkflow, fetchOwners, fetchWorkflowTimeline,
  transitionWorkflow, assignWorkflow,
} from '../services/api'

const arr = (d: any) => (Array.isArray(d) ? d : [])
const fmtUsd = (n: number) =>
  n == null ? '—' : n >= 1e6 ? `$${(n / 1e6).toFixed(1)}M` : n >= 1e3 ? `$${(n / 1e3).toFixed(0)}K` : `$${Number(n).toFixed(0)}`

const STATES = ['NEW', 'ACKNOWLEDGED', 'FORWARDED', 'ASSIGNED', 'IN_PROGRESS', 'RESOLVED', 'VERIFIED']
const STATE_TONE: Record<string, string> = {
  NEW: 'bg-pillar-safety/20 text-pillar-safety',
  ACKNOWLEDGED: 'bg-brand-accent/20 text-brand-primary',
  FORWARDED: 'bg-pillar-experience/20 text-pillar-experience',
  ASSIGNED: 'bg-blue-500/20 text-blue-700',
  IN_PROGRESS: 'bg-blue-500/20 text-blue-700',
  RESOLVED: 'bg-pillar-productivity/20 text-pillar-productivity',
  VERIFIED: 'bg-pillar-productivity/20 text-pillar-productivity',
}
const PILLAR_TONE: Record<string, string> = {
  SAFETY: 'text-pillar-safety', PRODUCTIVITY: 'text-pillar-productivity', EXPERIENCE: 'text-pillar-experience',
}

// legal next-states per the WS8 state machine
const NEXT: Record<string, string[]> = {
  NEW: ['ACKNOWLEDGED', 'DISMISSED'],
  ACKNOWLEDGED: ['ASSIGNED', 'FORWARDED', 'DISMISSED'],
  FORWARDED: ['ASSIGNED'],
  ASSIGNED: ['IN_PROGRESS', 'FORWARDED'],
  IN_PROGRESS: ['RESOLVED'],
  RESOLVED: ['VERIFIED', 'IN_PROGRESS'],
  VERIFIED: ['IN_PROGRESS'],
}

function Timeline({ id }: { id: string }) {
  const tl = useQuery({ queryKey: ['tl', id], queryFn: () => fetchWorkflowTimeline(id) })
  const rows = arr(tl.data)
  return (
    <div className="mt-3 border-t border-brand-border pt-3 space-y-1.5">
      {rows.map((e: any, i: number) => (
        <div key={i} className="flex items-center gap-2 text-xs">
          <span className="text-slate-500 w-36 shrink-0">{String(e.EVENT_TS).slice(0, 16).replace('T', ' ')}</span>
          <span className="text-brand-muted w-28 shrink-0">{e.EVENT_TYPE}</span>
          <span className="text-brand-text">{e.FROM_STATE ? `${e.FROM_STATE} → ` : ''}{e.TO_STATE}</span>
          <span className="text-brand-muted truncate">{e.NOTE}</span>
          <span className="ml-auto text-slate-500">{e.ACTOR}</span>
        </div>
      ))}
      {!rows.length && <div className="text-xs text-slate-500">No events.</div>}
    </div>
  )
}

export default function ResolutionTracker() {
  const qc = useQueryClient()
  const items = useQuery({ queryKey: ['wf-open'], queryFn: fetchOpenWorkflow })
  const owners = useQuery({ queryKey: ['owners'], queryFn: fetchOwners })
  const [open, setOpen] = useState<string | null>(null)
  const inval = () => {
    qc.invalidateQueries({ queryKey: ['wf-open'] })
    qc.invalidateQueries({ queryKey: ['owners'] })
    if (open) qc.invalidateQueries({ queryKey: ['tl', open] })
  }
  const trans = useMutation({
    mutationFn: (v: { id: string; to: string }) =>
      transitionWorkflow(v.id, v.to, 'app_user', v.to === 'RESOLVED' ? 'Containment complete' : ''),
    onSuccess: inval,
  })
  const assign = useMutation({
    mutationFn: (v: { id: string; owner: string }) => assignWorkflow(v.id, v.owner),
    onSuccess: inval,
  })

  const rows = arr(items.data)
  const ownerList = arr(owners.data)

  // Story Mode: focus + auto-open the timeline of the item for ?focus=<issue_id>
  const [params] = useSearchParams()
  const focusIssue = params.get('focus')
  const focusItem = focusIssue ? rows.find((r: any) => r.INSIGHT_ISSUE_ID === focusIssue) : null
  const focusId = focusItem?.WORKFLOW_ITEM_ID
  const focusedRef = useRef<string | null>(null)
  useEffect(() => {
    if (focusId && focusedRef.current !== focusId) {
      focusedRef.current = focusId
      setOpen(focusId)
    }
  }, [focusId])
  const counts = STATES.map(s => ({ s, n: rows.filter((r: any) => r.STATE === s).length }))
  const breached = rows.filter((r: any) => r.SLA_BREACHED).length
  const onTrack = rows.length - breached
  const slaData = [{ name: 'On track', value: onTrack, color: '#059669' }, { name: 'Breached', value: breached, color: '#C62828' }]
  const ownerAgg = Object.entries(
    rows.reduce((acc: Record<string, number>, r: any) => {
      const k = r.OWNER_NAME || 'Unassigned'; acc[k] = (acc[k] || 0) + 1; return acc
    }, {})
  ).map(([name, n]) => ({ name, n: n as number })).sort((a, b) => b.n - a.n).slice(0, 6)

  return (
    <div className="flex-1">
      <PageHeader title="Resolution Tracker" subtitle="Closed-loop work items — owned, state-managed, SLA-tracked" />
      <div className="p-8 space-y-5">
        <div className="grid grid-cols-3 gap-4">
          <section className="rounded-lg border border-brand-border bg-brand-surface p-4">
            <h3 className="text-xs font-semibold tracking-widest text-brand-muted mb-2">RESOLUTION PIPELINE</h3>
            <ResponsiveContainer width="100%" height={150}>
              <BarChart data={counts} margin={{ top: 12, right: 8, bottom: 6, left: 22 }}>
                <XAxis dataKey="s" tick={{ fill: CHART.textDim, fontSize: 8 }} stroke={CHART.grid} interval={0} angle={-30} textAnchor="end" height={52} />
                <YAxis allowDecimals={false} tick={{ fill: CHART.textDim, fontSize: 10 }} stroke={CHART.grid} />
                <Tooltip {...tooltipStyle} cursor={{ fill: '#E3EAF0' }} />
                <Bar dataKey="n" radius={[3, 3, 0, 0]} fill={CHART.primary}>
                  <LabelList dataKey="n" position="top" fill={CHART.text} fontSize={10} />
                </Bar>
              </BarChart>
            </ResponsiveContainer>
          </section>
          <section className="rounded-lg border border-brand-border bg-brand-surface p-4">
            <h3 className="text-xs font-semibold tracking-widest text-brand-muted mb-2">SLA STATUS</h3>
            <div className="relative">
              <ResponsiveContainer width="100%" height={150}>
                <PieChart>
                  <Pie data={slaData} dataKey="value" nameKey="name" cx="50%" cy="50%" innerRadius={42} outerRadius={64} paddingAngle={2}>
                    {slaData.map((d, i) => <Cell key={i} fill={d.color} stroke={CHART.panel} />)}
                  </Pie>
                  <Tooltip {...tooltipStyle} />
                </PieChart>
              </ResponsiveContainer>
              <div className="absolute inset-0 flex flex-col items-center justify-center pointer-events-none">
                <div className="text-2xl font-bold text-brand-text">{rows.length}</div>
                <div className="text-[10px] uppercase tracking-widest text-brand-muted">open items</div>
              </div>
            </div>
          </section>
          <section className="rounded-lg border border-brand-border bg-brand-surface p-4">
            <h3 className="text-xs font-semibold tracking-widest text-brand-muted mb-2">OWNER WORKLOAD</h3>
            {ownerAgg.length ? (
              <ResponsiveContainer width="100%" height={150}>
                <BarChart data={ownerAgg} layout="vertical" margin={{ top: 0, right: 24, bottom: 0, left: 8 }}>
                  <XAxis type="number" allowDecimals={false} hide />
                  <YAxis type="category" dataKey="name" width={92} tick={{ fill: CHART.text, fontSize: 10 }} stroke={CHART.grid} />
                  <Tooltip {...tooltipStyle} cursor={{ fill: '#E3EAF0' }} />
                  <Bar dataKey="n" radius={[0, 3, 3, 0]}>
                    {ownerAgg.map((_, i) => <Cell key={i} fill={SEQ[i % SEQ.length]} />)}
                    <LabelList dataKey="n" position="right" fill={CHART.text} fontSize={10} />
                  </Bar>
                </BarChart>
              </ResponsiveContainer>
            ) : <div className="h-[150px] flex items-center justify-center text-xs text-slate-500">No items.</div>}
          </section>
        </div>

        <div className="space-y-3">
          {rows.map((r: any) => (
            <div key={r.WORKFLOW_ITEM_ID}
              data-spotlight={r.WORKFLOW_ITEM_ID === focusId ? 'tracker-focus' : undefined}
              className={`rounded-lg border bg-brand-surface p-4 ${r.WORKFLOW_ITEM_ID === focusId ? 'border-brand-accent/60' : r.SLA_BREACHED ? 'border-pillar-safety/50' : 'border-brand-border'}`}>
              <div className="flex items-center gap-2">
                <span className={`text-[10px] px-2 py-0.5 rounded ${STATE_TONE[r.STATE] || 'bg-brand-subtle'}`}>{r.STATE}</span>
                <span className={`text-xs font-semibold ${PILLAR_TONE[r.PILLAR] || ''}`}>{r.PILLAR}</span>
                <span className="text-sm font-semibold">{r.TITLE}</span>
                <span className="ml-auto text-xs text-brand-muted">
                  {r.OWNER_NAME || 'unassigned'} · VTC {fmtUsd(Number(r.VTC_USD))}
                </span>
              </div>
              <div className="flex items-center gap-3 mt-2 text-xs text-brand-muted">
                <span>{r.MODEL} · {r.SYSTEM_GROUP} · {r.FAILURE_MODE}</span>
                <span className={r.SLA_BREACHED ? 'text-pillar-safety font-semibold' : ''}>
                  SLA {r.SLA_HOURS_REMAINING != null ? `${r.SLA_HOURS_REMAINING}h ${Number(r.SLA_HOURS_REMAINING) < 0 ? 'overdue' : 'left'}` : '—'}
                </span>
                <span className="font-mono text-slate-400">{r.WORKFLOW_ITEM_ID}</span>
              </div>

              <div className="flex flex-wrap items-center gap-2 mt-3">
                {(NEXT[r.STATE] || []).map(to => (
                  <button key={to} onClick={() => trans.mutate({ id: r.WORKFLOW_ITEM_ID, to })} disabled={trans.isPending}
                    className="text-xs px-2.5 py-1 rounded border border-brand-border text-brand-text hover:border-brand-accent hover:text-brand-primary disabled:opacity-50">
                    → {to}
                  </button>
                ))}
                <select defaultValue="" onChange={e => e.target.value && assign.mutate({ id: r.WORKFLOW_ITEM_ID, owner: e.target.value })}
                  className="text-xs bg-brand-subtle border border-brand-border rounded px-2 py-1 text-brand-text">
                  <option value="">Assign owner…</option>
                  {ownerList.map((o: any) => <option key={o.OWNER_ID} value={o.OWNER_ID}>{o.OWNER_NAME}</option>)}
                </select>
                <button onClick={() => setOpen(open === r.WORKFLOW_ITEM_ID ? null : r.WORKFLOW_ITEM_ID)}
                  className="text-xs px-2.5 py-1 rounded text-brand-muted hover:text-brand-text">
                  {open === r.WORKFLOW_ITEM_ID ? 'Hide' : 'Timeline'}
                </button>
              </div>

              {open === r.WORKFLOW_ITEM_ID && <Timeline id={r.WORKFLOW_ITEM_ID} />}
            </div>
          ))}
          {!rows.length && <p className="text-brand-muted text-sm">No open work items. Forward an alert from Quality Alerts to open one.</p>}
        </div>
      </div>
    </div>
  )
}
