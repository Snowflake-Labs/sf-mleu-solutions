import { useSearchParams } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import PageHeader from '../components/PageHeader'
import { CHART } from '../components/charts/theme'
import { fetchCuratedIssues, fetchPersonaViews, fetchIssue } from '../services/api'
import ArchetypeAxisStrip from '../components/ArchetypeAxisStrip'

function fmtMetric(v: number): string {
  if (v == null) return '—'
  const a = Math.abs(v)
  if (a >= 1e6) return `${(v / 1e6).toFixed(1)}M`
  if (a >= 1e4) return `${(v / 1e3).toFixed(0)}K`
  return Number(v).toLocaleString()
}

const PERSONA_LABEL: Record<string, string> = {
  DEALER: 'Dealer', PRODUCT: 'Product', MANUFACTURING: 'Manufacturing',
  SUPPLY_CHAIN: 'Supply Chain', EXECUTIVE: 'Executive',
}

const METRIC_LABEL: Record<string, string> = { PLAN_FOR_EXPOSURE_USD: 'Plan-for exposure ($)' }
const metricLabel = (m: string) => METRIC_LABEL[m] ?? String(m ?? '').replace(/_/g, ' ')

const PERSONA_ACCENT: Record<string, string> = {
  DEALER: '#0F766E', PRODUCT: '#7D44CF', MANUFACTURING: '#B45309',
  SUPPLY_CHAIN: '#059669', EXECUTIVE: '#29B5E8',
}

function deltaTone(delta: string | null): string {
  if (!delta) return 'text-brand-muted'
  const s = delta.toLowerCase().trim()
  if (/^-|below|under|improv|down/.test(s)) return 'text-emerald-700'
  if (/^\+|above|over|exceed|up/.test(s)) return 'text-pillar-safety'
  return 'text-brand-text'
}

export default function PersonaViews() {
  const issues = useQuery({ queryKey: ['curated'], queryFn: () => fetchCuratedIssues(15) })
  const list = Array.isArray(issues.data) ? issues.data : []
  const [params, setParams] = useSearchParams()
  const issueId = params.get('issue') || list[0]?.ISSUE_ID
  const setSel = (v: string) => setParams(p => { p.set('issue', v); return p }, { replace: true })
  const views = useQuery({ queryKey: ['personas', issueId], queryFn: () => fetchPersonaViews(issueId), enabled: !!issueId })
  const vlist = Array.isArray(views.data) ? views.data : []
  const inList = list.some((i: any) => i.ISSUE_ID === issueId)
  const meta = useQuery({ queryKey: ['issue', issueId], queryFn: () => fetchIssue(issueId), enabled: !!issueId && !inList && list.length > 0 })
  const metaOne = Array.isArray(meta.data) ? meta.data[0] : meta.data
  const cur = list.find((i: any) => i.ISSUE_ID === issueId) || (metaOne && !metaOne._pending ? metaOne : null)
  const optList = !inList && cur ? [{ ISSUE_ID: issueId, PRIORITY_RANK: cur.PRIORITY_RANK, TITLE: cur.TITLE, QUALITY_DIMENSION: cur.QUALITY_DIMENSION }, ...list] : list

  return (
    <div className="flex-1">
      <PageHeader title="Persona Views" subtitle="One issue → five persona decision surfaces" />
      <div className="p-8 space-y-6">
        <div className="flex flex-col gap-2">
          <label className="text-xs uppercase tracking-widest text-brand-muted">Issue</label>
          <select value={issueId || ''} onChange={e => setSel(e.target.value)}
            className="block bg-brand-surface border border-brand-border rounded px-3 py-2 text-sm w-full max-w-2xl">
            {optList.map((i: any) => <option key={i.ISSUE_ID} value={i.ISSUE_ID}>#{i.PRIORITY_RANK} · {i.TITLE} ({i.QUALITY_DIMENSION})</option>)}
          </select>
          {cur && (
            <div className="text-sm text-brand-muted">
              One customer pain point → five views · <span className="text-brand-primary">{cur.QUALITY_DIMENSION}</span> · {cur.EXPOSED_FLEET_COUNT} exposed fleet
            </div>
          )}
        </div>

        {issueId && <ArchetypeAxisStrip issueId={issueId} />}

        <div className="space-y-4" data-spotlight="persona-cards">
          {vlist.map((v: any) => {
            const accent = PERSONA_ACCENT[v.PERSONA] || CHART.primary
            const val = v.PRIMARY_METRIC_VALUE
            const tgt = v.PRIMARY_METRIC_TARGET
            const hasVal = val != null
            const onTarget = tgt != null && Number(tgt) > 0 ? Number(val) <= Number(tgt) : true
            const max = tgt != null && Number(tgt) > 0
              ? Math.max(Number(val) || 0, Number(tgt)) * 1.3
              : (Number(val) || 1) * 1.3
            return (
              <div key={v.PERSONA}
                className="rounded-xl border border-brand-border bg-brand-surface overflow-hidden"
                style={{ borderLeft: `4px solid ${accent}` }}>
                <div className="grid grid-cols-1 lg:grid-cols-[300px_1fr_340px]">
                  {/* Left rail — identity + metric */}
                  <div className="p-6 flex flex-col justify-center border-b lg:border-b-0 lg:border-r border-brand-border">
                    <div className="mb-4">
                      <div className="text-sm font-semibold uppercase tracking-widest" style={{ color: accent }}>
                        {PERSONA_LABEL[v.PERSONA] || v.PERSONA}
                      </div>
                      <div className="text-[11px] uppercase tracking-wider text-brand-muted">{v.VIEW_LEVEL} view</div>
                    </div>
                    {hasVal ? (
                      <>
                        <div className="text-[10px] uppercase tracking-widest text-brand-muted mb-1">{metricLabel(v.PRIMARY_METRIC_NAME)}</div>
                        <div className="flex items-baseline gap-2 mb-3">
                          <span className="text-4xl font-bold leading-none tracking-tight"
                            style={{ color: onTarget ? '#059669' : CHART.primary }}>
                            {fmtMetric(Number(val))}
                          </span>
                          {tgt != null && Number(tgt) > 0 && (
                            <span className="text-xs text-brand-muted">/ {fmtMetric(Number(tgt))} target</span>
                          )}
                        </div>
                        <div className="h-1.5 w-full rounded-full bg-brand-subtle overflow-hidden">
                          <div className="h-full rounded-full transition-all"
                            style={{
                              width: `${Math.max(2, Math.min(100, (Number(val) / max) * 100))}%`,
                              background: onTarget ? '#059669' : CHART.primary,
                            }} />
                        </div>
                        {v.PRIMARY_METRIC_DELTA && (
                          <div className={`text-xs font-medium mt-3 ${deltaTone(v.PRIMARY_METRIC_DELTA)}`}>{v.PRIMARY_METRIC_DELTA}</div>
                        )}
                      </>
                    ) : (
                      <div className="text-3xl font-bold text-slate-500">—</div>
                    )}
                  </div>

                  {/* Center — diagnose question + answer */}
                  <div className="p-6 flex flex-col justify-center border-b lg:border-b-0 lg:border-r border-brand-border">
                    <div className="text-[11px] uppercase tracking-widest text-brand-muted mb-1">Diagnose</div>
                    <p className="text-sm font-medium text-brand-text mb-3 leading-relaxed">{v.DIAGNOSE_QUESTION}</p>
                    <p className="text-sm text-brand-muted leading-relaxed">{v.DIAGNOSE_ANSWER_TEXT}</p>
                  </div>

                  {/* Right — recommended action */}
                  <div className="p-6 flex flex-col justify-center bg-brand-subtle">
                    <div className="text-[11px] uppercase tracking-widest text-brand-muted mb-2">Recommended action</div>
                    <p className="text-sm text-brand-text leading-relaxed">{v.ACTION_SUMMARY}</p>
                  </div>
                </div>
              </div>
            )
          })}
        </div>
      </div>
    </div>
  )
}
