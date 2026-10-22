import { useSearchParams } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { RadarChart, Radar, PolarGrid, PolarAngleAxis, PolarRadiusAxis, ResponsiveContainer, BarChart, Bar, XAxis, YAxis, Cell, Tooltip, LabelList } from 'recharts'
import PageHeader from '../components/PageHeader'
import Gauge from '../components/charts/Gauge'
import { CHART, PILLAR, tooltipStyle, fmtUsd } from '../components/charts/theme'
import { fetchCuratedIssues, fetchIssue, fetchIssueRisk, fetchIssueActions, fetchIssueEvidence } from '../services/api'
import ArchetypePanel from '../components/ArchetypePanel'

const PILLAR_TONE: Record<string, string> = {
  SAFETY: 'text-pillar-safety', PRODUCTIVITY: 'text-pillar-productivity', EXPERIENCE: 'text-pillar-experience',
}
const one = (d: any) => (Array.isArray(d) ? d[0] : d?._pending ? null : d)
const arr = (d: any) => (Array.isArray(d) ? d : [])

function ratingScore(v: string): number {
  if (!v) return 0
  const s = v.toLowerCase()
  if (/(critical|severe)/.test(s)) return 4
  if (/(high|elevated|broad)/.test(s)) return 3
  if (/(moderate|medium)/.test(s)) return 2
  if (/(low|contained|narrow|minimal)/.test(s)) return 1
  return 2
}

function Stat({ label, value, tone, hint }: { label: string; value: any; tone?: string; hint?: string }) {
  return (
    <div className="rounded-lg border border-brand-border bg-brand-surface p-3" title={hint}>
      <div className="text-[10px] uppercase tracking-widest text-brand-muted">{label}</div>
      <div className={`text-lg font-bold mt-0.5 ${tone || ''}`}>{value}</div>
    </div>
  )
}

export default function IssueDetail() {
  const issues = useQuery({ queryKey: ['curated'], queryFn: () => fetchCuratedIssues(15) })
  const list = arr(issues.data)
  const [params, setParams] = useSearchParams()
  const id = params.get('issue') || list[0]?.ISSUE_ID
  const setSel = (v: string) => setParams(p => { p.set('issue', v); return p }, { replace: true })
  const detail = useQuery({ queryKey: ['issue', id], queryFn: () => fetchIssue(id), enabled: !!id })
  const risk = useQuery({ queryKey: ['risk', id], queryFn: () => fetchIssueRisk(id), enabled: !!id })
  const actions = useQuery({ queryKey: ['iactions', id], queryFn: () => fetchIssueActions(id), enabled: !!id })
  const evid = useQuery({ queryKey: ['ievid', id], queryFn: () => fetchIssueEvidence(id), enabled: !!id })
  const d = one(detail.data)
  const r = one(risk.data)
  const e = one(evid.data)

  // ensure the selected issue is always a valid <option>, even if it's outside the top-N curated list
  const inList = list.some((i: any) => i.ISSUE_ID === id)
  const optList = !inList && d
    ? [{ ISSUE_ID: id, PRIORITY_RANK: d.PRIORITY_RANK, TITLE: d.TITLE, QUALITY_DIMENSION: d.QUALITY_DIMENSION }, ...list]
    : list

  const pillarColor = d ? (PILLAR[d.QUALITY_DIMENSION] || CHART.primary) : CHART.primary

  const radarData = r ? [
    ['Safety', r.SAFETY_RATING], ['Productivity', r.PRODUCTIVITY_RATING], ['Downtime', r.DOWNTIME_RATING],
    ['Warranty', r.WARRANTY_EXPOSURE_RATING], ['Cust. impact', r.CUSTOMER_IMPACT_RATING], ['Overall', r.OVERALL_RISK],
  ].map(([k, v]) => ({ dim: k, score: ratingScore(v as string), label: v ?? '—' })) : []

  const fanData = d ? [
    { name: 'Likely', value: Number(d.WARRANTY_EXPOSURE_P50 || 0), color: '#0F766E' },
    { name: 'Plan for', value: Number(d.WARRANTY_EXPOSURE_P90 || 0), color: CHART.primary },
    { name: 'Bad case', value: Number(d.WARRANTY_EXPOSURE_CVAR || 0), color: '#C62828' },
  ] : []
  const conf = d?.DATA_CONFIDENCE != null ? Math.round(Number(d.DATA_CONFIDENCE) * 100) : null

  return (
    <div className="flex-1">
      <PageHeader title="Issue Detail" subtitle="Full evidence-backed issue dossier" />
      <div className="p-8 space-y-5">
        <select value={id || ''} onChange={ev => setSel(ev.target.value)}
          className="bg-brand-surface border border-brand-border rounded px-3 py-2 text-sm w-full max-w-xl">
          {optList.map((i: any) => <option key={i.ISSUE_ID} value={i.ISSUE_ID}>#{i.PRIORITY_RANK} · {i.TITLE} ({i.QUALITY_DIMENSION})</option>)}
        </select>

        {d && (
          <>
            <div className="flex items-center gap-3">
              <h2 className="text-xl font-bold">{d.TITLE}</h2>
              <span className={`text-sm font-semibold ${PILLAR_TONE[d.QUALITY_DIMENSION] || ''}`}>{d.QUALITY_DIMENSION}</span>
              <span className="text-xs px-2 py-0.5 rounded bg-brand-subtle text-brand-text">{d.ROOT_CAUSE_TYPE}</span>
              <span className="text-xs px-2 py-0.5 rounded bg-brand-subtle text-brand-text">conf {d.DATA_CONFIDENCE_BAND}</span>
              <span className="ml-auto text-xs text-brand-muted">{d.MODEL} · {d.SYSTEM_GROUP} · {d.FAILURE_MODE}</span>
            </div>

            <div className="grid grid-cols-4 gap-3" data-spotlight="issue-stats">
              <Stat label="Exposed fleet" value={d.EXPOSED_FLEET_COUNT} />
              <Stat label="Impacted customers" value={d.IMPACTED_CUSTOMER_COUNT} />
              <Stat label="Likely exposure" value={fmtUsd(d.WARRANTY_EXPOSURE_P50)} hint="Our central estimate" />
              <Stat label="Plan-for exposure" value={fmtUsd(d.WARRANTY_EXPOSURE_P90)} tone="text-brand-primary"
                hint="Budget this — 9-in-10 chance it won't be exceeded" />
              <Stat label="SIP risk" value={d.PRO_SIF_RISK ?? '—'} tone="text-pillar-safety" />
              <Stat label="VTC (uptime)" value={fmtUsd(d.VTC_USD)} />
              <Stat label="CEI score" value={d.CEI_SCORE ?? '—'} />
              <Stat label="MTBF / MTTR" value={`${d.MTBF ?? '—'} / ${d.MTTR ?? '—'}`} />
            </div>

            {e?.RATIONALE_TEXT && (
              <section>
                <h3 className="text-sm font-semibold tracking-widest text-brand-muted mb-2">GROUNDED NARRATIVE</h3>
                <div className="rounded-lg border border-brand-border bg-brand-surface p-4 text-sm text-brand-text leading-relaxed">{e.RATIONALE_TEXT}</div>
              </section>
            )}

            <div className="grid grid-cols-3 gap-6">
              <section>
                <h3 className="text-sm font-semibold tracking-widest text-brand-muted mb-2">RISK PROFILE</h3>
                <div className="rounded-lg border border-brand-border bg-brand-surface p-3">
                  {radarData.length ? (
                    <ResponsiveContainer width="100%" height={240}>
                      <RadarChart data={radarData} cx="50%" cy="50%" outerRadius="62%" margin={{ top: 8, right: 24, bottom: 8, left: 24 }}>
                        <PolarGrid stroke={CHART.grid} />
                        <PolarAngleAxis dataKey="dim" tick={{ fill: CHART.text, fontSize: 10 }} />
                        <PolarRadiusAxis domain={[0, 4]} tick={false} axisLine={false} />
                        <Radar dataKey="score" stroke={pillarColor} fill={pillarColor} fillOpacity={0.35} />
                        <Tooltip {...tooltipStyle} formatter={(_: any, __: any, p: any) => p?.payload?.label} />
                      </RadarChart>
                    </ResponsiveContainer>
                  ) : <span className="text-brand-muted text-sm">No assessment.</span>}
                  {r?.HEADLINE_TEXT && <div className="text-xs text-brand-muted mt-2 pt-2 border-t border-brand-border">{r.HEADLINE_TEXT}</div>}
                </div>
              </section>

              <section data-spotlight="issue-exposure">
                <h3 className="text-sm font-semibold tracking-widest text-brand-muted mb-2">WARRANTY EXPOSURE DISTRIBUTION</h3>
                <div className="rounded-lg border border-brand-border bg-brand-surface p-3 flex flex-col">
                  <ResponsiveContainer width="100%" height={180}>
                    <BarChart data={fanData} layout="vertical" margin={{ top: 4, right: 48, bottom: 0, left: 8 }}>
                      <XAxis type="number" tickFormatter={fmtUsd} tick={{ fill: CHART.textDim, fontSize: 10 }} stroke={CHART.grid} />
                      <YAxis type="category" dataKey="name" tick={{ fill: CHART.text, fontSize: 12 }} stroke={CHART.grid} width={64} />
                      <Tooltip {...tooltipStyle} formatter={(v: any) => fmtUsd(v)} cursor={{ fill: '#E3EAF0' }} />
                      <Bar dataKey="value" radius={[0, 4, 4, 0]}>
                        {fanData.map((f, i) => <Cell key={i} fill={f.color} />)}
                        <LabelList dataKey="value" position="right" formatter={fmtUsd} fill={CHART.text} fontSize={11} />
                      </Bar>
                    </BarChart>
                  </ResponsiveContainer>
                  {conf != null && (
                    <div className="flex items-center justify-center gap-4 pt-2 border-t border-brand-border mt-1">
                      <Gauge value={conf} max={100} suffix="%" label="Data Confidence"
                        color={conf >= 80 ? '#059669' : conf >= 60 ? CHART.primary : '#C62828'} size={120} />
                    </div>
                  )}
                </div>
              </section>

              <section>
                <h3 className="text-sm font-semibold tracking-widest text-brand-muted mb-2">RECOMMENDED ACTIONS</h3>
                <div className="space-y-2">
                  {arr(actions.data).map((a: any) => (
                    <div key={a.ACTION_ID} className="rounded-lg border border-brand-border bg-brand-surface p-3 text-sm">
                      <div className="flex justify-between items-center mb-1">
                        <span className="text-xs px-2 py-0.5 rounded bg-brand-accent/20 text-brand-primary">{a.TIME_WINDOW}</span>
                        <span className="text-xs text-brand-muted">{a.OWNER_PERSONA}</span>
                      </div>
                      <div className="text-brand-text">{a.ACTION_TEXT}</div>
                      {a.EXPECTED_RISK_REDUCTION != null && <div className="text-xs text-brand-muted mt-1">Expected risk reduction: {a.EXPECTED_RISK_REDUCTION}</div>}
                    </div>
                  ))}
                  {arr(actions.data).length === 0 && <span className="text-brand-muted text-sm">No actions.</span>}
                </div>
              </section>
            </div>

            <ArchetypePanel issueId={id} />
          </>
        )}
      </div>
    </div>
  )
}
