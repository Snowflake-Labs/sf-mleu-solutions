import { useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { ComposedChart, Line, Area, Scatter, ScatterChart, XAxis, YAxis, ZAxis, CartesianGrid, ReferenceLine, Tooltip, ResponsiveContainer, Cell } from 'recharts'
import PageHeader from '../components/PageHeader'
import { CHART, tooltipStyle } from '../components/charts/theme'
import { fetchEmergingSummary, fetchEmergingSignals, fetchEmergingSeries } from '../services/api'

const arr = (d: any) => (Array.isArray(d) ? d : [])
const one = (d: any) => (Array.isArray(d) && d.length ? d[0] : {})
const fmtMonth = (s: string) => (s ? String(s).slice(0, 7) : '')

function zTone(z: number) {
  if (z >= 5) return 'bg-pillar-safety/20 text-pillar-safety'
  if (z >= 4) return 'bg-brand-accent/20 text-brand-primary'
  return 'bg-brand-subtle text-brand-text'
}

function TrendChart({ series }: { series: any[] }) {
  const data = series.map((r) => ({
    month: fmtMonth(r.EVENT_MONTH),
    rate: Number(r.RATE_PER_1K) || 0,
    baseline: Number(r.BASELINE_RATE) || 0,
    ewma: Number(r.EWMA) || 0,
    cp: r.IS_CHANGEPOINT ? (Number(r.RATE_PER_1K) || 0) : null,
    alarm: r.ALARM ? (Number(r.RATE_PER_1K) || 0) : null,
  }))
  return (
    <ResponsiveContainer width="100%" height={220}>
      <ComposedChart data={data} margin={{ top: 8, right: 12, bottom: 0, left: 0 }}>
        <defs>
          <linearGradient id="rateFill" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor={CHART.primary} stopOpacity={0.25} />
            <stop offset="100%" stopColor={CHART.primary} stopOpacity={0} />
          </linearGradient>
        </defs>
        <CartesianGrid stroke={CHART.grid} strokeDasharray="3 3" vertical={false} />
        <XAxis dataKey="month" tick={{ fill: CHART.textDim, fontSize: 10 }} stroke={CHART.grid} minTickGap={24} />
        <YAxis tick={{ fill: CHART.textDim, fontSize: 10 }} stroke={CHART.grid} width={36} />
        <Tooltip {...tooltipStyle} />
        <Area type="monotone" dataKey="rate" stroke="none" fill="url(#rateFill)" isAnimationActive={false} />
        <Line type="monotone" dataKey="baseline" stroke="#8A999E" strokeWidth={1.5} strokeDasharray="4 3" dot={false} isAnimationActive={false} name="baseline" />
        <Line type="monotone" dataKey="ewma" stroke="#0F766E" strokeWidth={1.5} dot={false} isAnimationActive={false} opacity={0.7} name="EWMA" />
        <Line type="monotone" dataKey="rate" stroke={CHART.primary} strokeWidth={2} dot={false} isAnimationActive={false} name="rate/1k" />
        <Scatter dataKey="cp" fill="#C62828" isAnimationActive={false} name="change-point" />
        <Scatter dataKey="alarm" fill={CHART.primary} isAnimationActive={false} name="CUSUM alarm" />
      </ComposedChart>
    </ResponsiveContainer>
  )
}

function ZQuadrant({ rows, active, onPick }: { rows: any[]; active: any; onPick: (m: string, sg: string) => void }) {
  const data = rows.map((r) => ({
    x: Number(r.ACTIVE_FLEET) || 0, y: Number(r.Z) || 0,
    model: r.MODEL, sg: r.SYSTEM_GROUP_CD,
    color: r.IS_CHANGEPOINT ? '#C62828' : r.ALARM ? CHART.primary : r.ANOMALY_FLAG ? '#0F766E' : '#8A999E',
    isActive: active && r.MODEL === active.model && r.SYSTEM_GROUP_CD === active.sg,
  }))
  return (
    <ResponsiveContainer width="100%" height={220}>
      <ScatterChart margin={{ top: 8, right: 16, bottom: 4, left: 0 }}>
        <CartesianGrid stroke={CHART.grid} strokeDasharray="3 3" />
        <XAxis type="number" dataKey="x" name="Active fleet" tick={{ fill: CHART.textDim, fontSize: 10 }} stroke={CHART.grid} width={36} />
        <YAxis type="number" dataKey="y" name="Z-score" tick={{ fill: CHART.textDim, fontSize: 10 }} stroke={CHART.grid} width={30} />
        <ZAxis range={[40, 200]} />
        <ReferenceLine y={4} stroke="#B45309" strokeDasharray="4 3" />
        <Tooltip {...tooltipStyle} cursor={{ stroke: CHART.grid }}
          formatter={(v: any, n: any) => [Number(v).toLocaleString(), n]}
          labelFormatter={() => ''} />
        <Scatter data={data} onClick={(p: any) => onPick(p.model, p.sg)} cursor="pointer">
          {data.map((d, i) => <Cell key={i} fill={d.color} stroke={d.isActive ? CHART.text : 'none'} strokeWidth={d.isActive ? 2 : 0} />)}
        </Scatter>
      </ScatterChart>
    </ResponsiveContainer>
  )
}

export default function EmergingIssues() {
  const summary = useQuery({ queryKey: ['emg-summary'], queryFn: fetchEmergingSummary })
  const signals = useQuery({ queryKey: ['emg-signals'], queryFn: fetchEmergingSignals })
  const rows = arr(signals.data)
  const [params] = useSearchParams()
  const pModel = params.get('model'); const pSg = params.get('sg')
  const [sel, setSel] = useState<{ model: string; sg: string } | null>(pModel && pSg ? { model: pModel, sg: pSg } : null)
  const active = sel || (rows.length ? { model: rows[0].MODEL, sg: rows[0].SYSTEM_GROUP_CD } : null)
  const series = useQuery({
    queryKey: ['emg-series', active?.model, active?.sg],
    queryFn: () => fetchEmergingSeries(active!.model, active!.sg),
    enabled: !!active,
  })
  const s = one(summary.data)
  const seriesRows = arr(series.data)

  const cards = [
    { label: 'CUSUM alarms', val: s.ALARMS, tone: 'text-pillar-safety' },
    { label: 'Change-points', val: s.CHANGEPOINTS, tone: 'text-brand-primary' },
    { label: 'IsoForest anomalies', val: s.ANOMALIES, tone: 'text-pillar-experience' },
    { label: 'Watched series', val: s.WATCHED_SERIES, tone: 'text-brand-text' },
  ]

  return (
    <div className="flex-1">
      <PageHeader title="Emerging Issues" subtitle="EWMA + iterative CUSUM + change-point + Isolation Forest detections" />
      <div className="p-8 space-y-6">
        <div className="grid grid-cols-4 gap-3">
          {cards.map((c) => (
            <div key={c.label} className="rounded-lg border border-brand-border bg-brand-surface p-4">
              <div className="text-[10px] uppercase tracking-widest text-brand-muted">{c.label}</div>
              <div className={`text-2xl font-bold mt-1 ${c.tone}`}>{c.val != null ? Number(c.val).toLocaleString() : '—'}</div>
            </div>
          ))}
        </div>

        <div className="grid grid-cols-3 gap-4">
          {active && (
            <section className="col-span-2 rounded-lg border border-brand-border bg-brand-surface p-4" data-spotlight="emerging-trend">
              <div className="flex items-baseline justify-between mb-2">
                <h3 className="text-sm font-semibold tracking-widest text-brand-text">{active.model} · {active.sg}</h3>
                <div className="text-xs text-brand-muted">
                  <span className="text-brand-primary">— rate/1k</span> &nbsp; <span className="text-pillar-experience">— EWMA</span> &nbsp;
                  <span className="text-brand-muted">-- baseline</span> &nbsp; <span className="text-pillar-safety">● CP</span>
                </div>
              </div>
              <TrendChart series={seriesRows} />
            </section>
          )}
          <section className="rounded-lg border border-brand-border bg-brand-surface p-4">
            <div className="flex items-baseline justify-between mb-2">
              <h3 className="text-sm font-semibold tracking-widest text-brand-text">TRIAGE · Z vs FLEET</h3>
            </div>
            <ZQuadrant rows={rows} active={active} onPick={(model, sg) => setSel({ model, sg })} />
          </section>
        </div>

        <section>
          <h3 className="text-sm font-semibold tracking-widest text-brand-muted mb-2">ACTIVE DETECTIONS</h3>
          <div className="rounded-lg border border-brand-border overflow-hidden">
            <table className="w-full text-sm">
              <thead className="bg-brand-surface text-brand-muted text-xs uppercase tracking-wider">
                <tr>
                  <th className="text-left px-3 py-2">Model</th>
                  <th className="text-left px-3 py-2">System group</th>
                  <th className="text-left px-3 py-2">Month</th>
                  <th className="text-right px-3 py-2">Events</th>
                  <th className="text-right px-3 py-2">Rate/1k</th>
                  <th className="text-right px-3 py-2">Baseline</th>
                  <th className="text-right px-3 py-2">Z</th>
                  <th className="text-center px-3 py-2">Signals</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((r: any, i: number) => {
                  const isActive = active && r.MODEL === active.model && r.SYSTEM_GROUP_CD === active.sg
                  return (
                    <tr
                      key={i}
                      onClick={() => setSel({ model: r.MODEL, sg: r.SYSTEM_GROUP_CD })}
                      className={`border-t border-brand-border cursor-pointer hover:bg-brand-subtle ${isActive ? 'bg-brand-subtle' : ''}`}
                    >
                      <td className="px-3 py-2 font-semibold text-brand-text">{r.MODEL}</td>
                      <td className="px-3 py-2 text-brand-text">{r.SYSTEM_GROUP_CD}</td>
                      <td className="px-3 py-2 text-brand-muted">{fmtMonth(r.EVENT_MONTH)}</td>
                      <td className="px-3 py-2 text-right text-brand-muted">{r.N}<span className="text-slate-500">/{Number(r.ACTIVE_FLEET).toLocaleString()}</span></td>
                      <td className="px-3 py-2 text-right text-brand-primary">{Number(r.RATE_PER_1K).toFixed(1)}</td>
                      <td className="px-3 py-2 text-right text-brand-muted">{Number(r.BASELINE_RATE).toFixed(1)}</td>
                      <td className="px-3 py-2 text-right">
                        <span className={`text-xs px-2 py-0.5 rounded ${zTone(Number(r.Z))}`}>{Number(r.Z).toFixed(1)}</span>
                      </td>
                      <td className="px-3 py-2 text-center space-x-1">
                        {r.ALARM ? <span className="text-[10px] px-1.5 py-0.5 rounded bg-brand-accent/20 text-brand-primary">CUSUM</span> : null}
                        {r.IS_CHANGEPOINT ? <span className="text-[10px] px-1.5 py-0.5 rounded bg-pillar-safety/20 text-pillar-safety">CP</span> : null}
                        {r.ANOMALY_FLAG ? <span className="text-[10px] px-1.5 py-0.5 rounded bg-pillar-experience/20 text-pillar-experience">ANOM</span> : null}
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        </section>
      </div>
    </div>
  )
}
