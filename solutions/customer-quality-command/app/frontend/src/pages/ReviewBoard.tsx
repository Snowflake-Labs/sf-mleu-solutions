import { useState, useRef, useEffect } from 'react'
import { useSearchParams } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import ReactMarkdown from 'react-markdown'
import remarkGfm from 'remark-gfm'
import { LineChart, Line, XAxis, YAxis, CartesianGrid, ResponsiveContainer, Tooltip, BarChart, Bar, Cell, LabelList } from 'recharts'
import { CheckCircle2, AlertTriangle, Scale, HelpCircle, ChevronRight } from 'lucide-react'
import PageHeader from '../components/PageHeader'
import Gauge from '../components/charts/Gauge'
import { CHART, tooltipStyle } from '../components/charts/theme'
import { fetchCuratedIssues, fetchIssue, streamDebate } from '../services/api'

const arr = (d: any) => (Array.isArray(d) ? d : [])

const AGENT_META: Record<string, { name: string; color: string; tag: string }> = {
  reliability: { name: 'Reliability Engineer', color: '#11567F', tag: 'Failure Physics' },
  field: { name: 'Field & Customer Advocate', color: '#C62828', tag: 'Customer Pain' },
  risk: { name: 'Risk & Cost Officer', color: '#B45309', tag: 'Financial Exposure' },
}
const PHASES = ['decomposing', 'researching', 'analyzing', 'debating', 'synthesizing', 'complete']
const PHASE_LABEL: Record<string, string> = {
  decomposing: 'Decompose', researching: 'Research', analyzing: 'Positions',
  debating: 'Cross-examine', synthesizing: 'Synthesize', complete: 'Brief',
}

interface Turn { agent: string; round: number | string; type: string; text: string; action?: string }

const clean = (s: string) => s.replace(/\*\*/g, '').replace(/^[#>+!\-\s]+/, '').trim()

function parseBrief(raw: string) {
  if (!raw) return null
  const lines = raw.replace(/\r/g, '').split('\n')
  const sec: Record<string, string[]> = { recommended: [], agreement: [], disagreement: [], tradeoff: [], question: [] }
  let title = ''
  let cur = ''
  const H: [string, RegExp][] = [
    ['recommended', /^[#*\s]*RECOMMENDED RESPONSE/i],
    ['agreement', /^[#*\s]*BOARD AGREEMENT/i],
    ['disagreement', /^[#*\s]*OPEN DISAGREEMENT/i],
    ['tradeoff', /^[#*\s]*TRADE.?OFF/i],
    ['question', /^[#*\s]*THE ONE QUESTION/i],
  ]
  for (const line of lines) {
    if (/QUALITY REVIEW BOARD BRIEF/i.test(line)) { title = line.replace(/^[#*\s]*QUALITY REVIEW BOARD BRIEF:?\s*/i, '').replace(/\*+$/, '').trim(); continue }
    const h = H.find(([, re]) => re.test(line))
    if (h) { cur = h[0]; continue }
    if (cur && line.trim()) sec[cur].push(line)
  }
  const hasContent = Object.values(sec).some(v => v.length > 0)
  if (!hasContent) return null

  const decision = clean((sec.recommended.find(l => /Decision:/i.test(l)) || '').replace(/.*Decision:/i, ''))
  const confRaw = clean((sec.recommended.find(l => /Confidence:/i.test(l)) || '').replace(/.*Confidence:/i, ''))
  const confMatch = confRaw.match(/^(HIGH|MODERATE|LOW)\b[\s.:—–-]*(.*)$/i)
  const [confLevel, ...confWhyParts] = confMatch ? [confMatch[1], confMatch[2]] : confRaw.split(/\s*[—–-]\s*/)
  const confWhy = confWhyParts.join(' — ')
  const recNarrative = sec.recommended.filter(l => !/Decision:|Confidence:/i.test(l)).map(clean).filter(Boolean)

  const agreement = sec.agreement.map(clean).filter(Boolean)

  const disagreement: { topic: string; positions: { label: string; text: string; color: string }[] }[] = []
  for (const line of sec.disagreement) {
    const t = line.trim()
    if (/\|/.test(t) && /reliab|field|risk/i.test(t)) {
      const positions = t.split('|').map(p => {
        const [lbl, ...rest] = p.split(':')
        const label = clean(lbl)
        const key = /reliab/i.test(label) ? 'reliability' : /field/i.test(label) ? 'field' : /risk/i.test(label) ? 'risk' : ''
        return { label, text: rest.join(':').trim(), color: AGENT_META[key]?.color || '#5B6B7A' }
      })
      if (disagreement.length) disagreement[disagreement.length - 1].positions = positions
    } else {
      disagreement.push({ topic: clean(t), positions: [] })
    }
  }

  const splitArrow = (l: string) => {
    const c = clean(l.replace(/^(Act now|Wait):/i, ''))
    const [a, b] = c.split(/\s*(?:→|->)\s*/)
    return { a: (a || '').trim(), b: (b || '').trim() }
  }
  const actNow = sec.tradeoff.find(l => /Act now:/i.test(l))
  const wait = sec.tradeoff.find(l => /^[#*\s]*Wait:/i.test(l))
  const tradeoff = { act: actNow ? splitArrow(actNow) : null, wait: wait ? splitArrow(wait) : null }

  const question = clean(sec.question.join(' ')).replace(/^["']|["']$/g, '')

  return { title, decision, confLevel, confWhy, recNarrative, agreement, disagreement, tradeoff, question }
}

const CONF_TONE: Record<string, { bg: string; text: string; ring: string }> = {
  HIGH: { bg: 'bg-emerald-500/15', text: 'text-emerald-700', ring: 'ring-emerald-500/40' },
  MODERATE: { bg: 'bg-brand-accent/15', text: 'text-brand-primary', ring: 'ring-brand-accent/40' },
  LOW: { bg: 'bg-pillar-safety/15', text: 'text-pillar-safety', ring: 'ring-pillar-safety/40' },
}

function BriefReadout({ raw }: { raw: string }) {
  const b = parseBrief(raw)
  if (!b) {
    return (
      <div className="prose prose-invert prose-sm max-w-none text-brand-text">
        <ReactMarkdown remarkPlugins={[remarkGfm]}>{raw}</ReactMarkdown>
      </div>
    )
  }
  const tone = CONF_TONE[(b.confLevel || '').toUpperCase()] || CONF_TONE.MODERATE
  return (
    <div className="space-y-5">
      {/* Decision banner */}
      <div className="rounded-xl border border-brand-accent/30 bg-gradient-to-br from-brand-accent/10 to-transparent p-5">
        <div className="text-[10px] uppercase tracking-widest text-brand-muted mb-1">Recommended response</div>
        <div className="flex flex-wrap items-center gap-3">
          <span className="text-2xl font-bold text-brand-primary capitalize">{b.decision || '—'}</span>
          {b.confLevel && (
            <span className={`text-[11px] font-semibold uppercase tracking-wider px-2.5 py-1 rounded-full ring-1 ${tone.bg} ${tone.text} ${tone.ring}`}>
              {b.confLevel} confidence
            </span>
          )}
        </div>
        {b.confWhy && <p className="text-sm text-brand-text mt-2 leading-relaxed">{b.confWhy}</p>}
        {b.recNarrative.map((l, i) => <p key={i} className="text-sm text-brand-muted mt-1 leading-relaxed">{l}</p>)}
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        {/* Agreement */}
        {b.agreement.length > 0 && (
          <section className="rounded-xl border border-brand-border bg-brand-surface p-4">
            <div className="flex items-center gap-2 mb-3">
              <CheckCircle2 size={15} className="text-emerald-700" />
              <h4 className="text-xs font-semibold tracking-widest text-emerald-700 uppercase">Board Agreement</h4>
            </div>
            <ul className="space-y-2">
              {b.agreement.map((a, i) => (
                <li key={i} className="flex gap-2 text-sm text-brand-text leading-relaxed">
                  <span className="text-emerald-700 mt-0.5">✓</span><span>{a}</span>
                </li>
              ))}
            </ul>
          </section>
        )}

        {/* Trade-off */}
        {(b.tradeoff.act || b.tradeoff.wait) && (
          <section className="rounded-xl border border-brand-border bg-brand-surface p-4">
            <div className="flex items-center gap-2 mb-3">
              <Scale size={15} className="text-pillar-experience" />
              <h4 className="text-xs font-semibold tracking-widest text-pillar-experience uppercase">Trade-off</h4>
            </div>
            <div className="space-y-3">
              {b.tradeoff.act && (
                <div className="rounded-lg bg-brand-subtle p-3 border-l-2 border-brand-accent">
                  <div className="text-[10px] uppercase tracking-widest text-brand-primary mb-1">Act now</div>
                  <div className="text-sm text-brand-text">{b.tradeoff.act.a}</div>
                  {b.tradeoff.act.b && <div className="text-xs text-emerald-700 mt-1">→ {b.tradeoff.act.b}</div>}
                </div>
              )}
              {b.tradeoff.wait && (
                <div className="rounded-lg bg-brand-subtle p-3 border-l-2 border-slate-300">
                  <div className="text-[10px] uppercase tracking-widest text-brand-muted mb-1">Wait</div>
                  <div className="text-sm text-brand-text">{b.tradeoff.wait.a}</div>
                  {b.tradeoff.wait.b && <div className="text-xs text-pillar-safety mt-1">→ {b.tradeoff.wait.b}</div>}
                </div>
              )}
            </div>
          </section>
        )}
      </div>

      {/* Open disagreement */}
      {b.disagreement.length > 0 && (
        <section className="rounded-xl border border-pillar-productivity/30 bg-pillar-productivity/5 p-4">
          <div className="flex items-center gap-2 mb-3">
            <AlertTriangle size={15} className="text-pillar-productivity" />
            <h4 className="text-xs font-semibold tracking-widest text-pillar-productivity uppercase">Open Disagreement · Sponsor to Resolve</h4>
          </div>
          <div className="space-y-3">
            {b.disagreement.map((d, i) => (
              <div key={i} className="rounded-lg bg-brand-subtle p-3">
                <div className="text-sm font-medium text-brand-text mb-2">{d.topic}</div>
                {d.positions.length > 0 && (
                  <div className="grid grid-cols-1 sm:grid-cols-3 gap-2">
                    {d.positions.map((p, j) => (
                      <div key={j} className="rounded border-l-2 pl-2 py-1" style={{ borderColor: p.color }}>
                        <div className="text-[10px] uppercase tracking-wider font-semibold" style={{ color: p.color }}>{p.label}</div>
                        <div className="text-xs text-brand-text leading-snug">{p.text}</div>
                      </div>
                    ))}
                  </div>
                )}
              </div>
            ))}
          </div>
        </section>
      )}

      {/* The one question */}
      {b.question && (
        <section className="rounded-xl border border-brand-accent/40 bg-brand-primary/[0.07] p-5">
          <div className="flex items-center gap-2 mb-2">
            <HelpCircle size={15} className="text-brand-primary" />
            <h4 className="text-xs font-semibold tracking-widest text-brand-primary uppercase">The One Question for the Sponsor</h4>
          </div>
          <blockquote className="text-lg font-medium text-brand-text leading-snug italic">“{b.question}”</blockquote>
        </section>
      )}
    </div>
  )
}

const PRESETS = [
  'Do we launch a field campaign now on all exposed units, or wait for more failure data to avoid a costly over-recall? Make the call.',
  'Is this a contained supplier-lot problem or an emerging systemic design flaw? Our response changes completely depending on the answer.',
  'Scope the containment: only the suspect lots, the full plant build window, or the entire fleet? Justify the boundary.',
  'How much do we trust the plan-for exposure figure, and does the confidence justify a board-level decision today?',
  'If we do nothing for 60 days, what is the worst credible outcome — and who is accountable?',
]

export default function ReviewBoard() {
  const issues = useQuery({ queryKey: ['curated'], queryFn: () => fetchCuratedIssues(15) })
  const list = arr(issues.data)
  const [params, setParams] = useSearchParams()
  const id = params.get('issue') || list[0]?.ISSUE_ID
  const setSel = (v: string) => setParams(p => { p.set('issue', v); return p }, { replace: true })
  const inList = list.some((i: any) => i.ISSUE_ID === id)
  const meta = useQuery({ queryKey: ['issue', id], queryFn: () => fetchIssue(id), enabled: !!id && !inList && list.length > 0 })
  const metaOne = Array.isArray(meta.data) ? meta.data[0] : meta.data
  const selIssue = list.find((i: any) => i.ISSUE_ID === id) || (metaOne && !metaOne._pending ? metaOne : null)
  const optList = !inList && selIssue
    ? [{ ISSUE_ID: id, PRIORITY_RANK: selIssue.PRIORITY_RANK, TITLE: selIssue.TITLE, QUALITY_DIMENSION: selIssue.QUALITY_DIMENSION }, ...list]
    : list

  const [prompt, setPrompt] = useState('')
  const [running, setRunning] = useState(false)
  const [phase, setPhase] = useState<string>('')
  const [turns, setTurns] = useState<Turn[]>([])
  const [convergence, setConvergence] = useState<number | null>(null)
  const [convHistory, setConvHistory] = useState<number[]>([])
  const [finals, setFinals] = useState<Record<string, any>>({})
  const [brief, setBrief] = useState<string>('')
  const scrollRef = useRef<HTMLDivElement>(null)

  const start = async () => {
    if (!id) return
    setRunning(true); setPhase(''); setTurns([]); setConvergence(null); setConvHistory([]); setFinals({}); setBrief('')
    const fallback = `The quality signal "${selIssue?.TITLE ?? 'this issue'}" (${selIssue?.QUALITY_DIMENSION ?? ''}) has been detected. `
      + `Should we contain the implicated lot, launch a field service campaign, or continue to monitor? Weigh safety, exposure, and cost.`
    const q = prompt.trim() || fallback
    try {
      await streamDebate(q, id, (e: any) => {
        if (e.type === 'phase') setPhase(e.phase)
        else if (e.type === 'position') setTurns(t => [...t, { agent: e.agent, round: 0, type: 'position', text: e.text }])
        else if (e.type === 'challenge') setTurns(t => [...t, { agent: e.agent, round: e.round, type: 'challenge', text: e.text }])
        else if (e.type === 'response') setTurns(t => [...t, { agent: e.agent, round: e.round, type: 'response', action: e.action, text: e.text }])
        else if (e.type === 'disagreement') {
          const cs = e.data?.convergence_score ?? null
          setConvergence(cs)
          if (cs != null) setConvHistory(h => [...h, cs])
        }
        else if (e.type === 'final') {
          // Models differ: some return confidence as 0–1, others as 0–100. Store as a percent.
          const c = e.data?.confidence
          const data = typeof c === 'number' ? { ...e.data, confidence: Math.round(c <= 1 ? c * 100 : c) } : e.data
          setFinals(f => ({ ...f, [e.agent]: data }))
        }
        else if (e.type === 'brief') setBrief(e.text)
        else if (e.type === 'error') setBrief(`Debate error: ${e.message}`)
        setTimeout(() => scrollRef.current?.scrollTo({ top: scrollRef.current.scrollHeight, behavior: 'smooth' }), 50)
      })
    } catch (err: any) {
      setBrief(`Debate error: ${err?.message ?? 'Review Board run failed'}`)
    } finally {
      setRunning(false)
    }
  }

  const conf = convergence != null ? Math.round(convergence * 100) : null

  // Story Mode spotlight anchor: follow the debate as it streams, then settle on the Board Brief.
  //   pre-debate -> board members · during -> live transcript · complete -> brief
  const focusKey = brief ? 'brief' : turns.length > 0 ? 'debate' : 'members'
  const briefRef = useRef<HTMLDivElement>(null)
  useEffect(() => {
    if (brief) briefRef.current?.scrollIntoView({ behavior: 'smooth', block: 'center' })
  }, [brief])

  // Story Mode: auto-convene once when ?convene=1 and the issue is loaded
  const convenedRef = useRef(false)
  useEffect(() => {
    if (params.get('convene') === '1' && id && !running && !convenedRef.current) {
      convenedRef.current = true
      start()
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [id, params])

  return (
    <div className="flex-1">
      <PageHeader title="Quality Review Board" subtitle="Three grounded board members debate the quality response — live" />
      <div className="p-8 space-y-5">
        <div className="flex gap-3 items-center">
          <select value={id || ''} onChange={e => setSel(e.target.value)} disabled={running}
            className="bg-brand-surface border border-brand-border rounded px-3 py-2 text-sm flex-1 max-w-xl">
            {optList.map((i: any) => <option key={i.ISSUE_ID} value={i.ISSUE_ID}>#{i.PRIORITY_RANK} · {i.TITLE} ({i.QUALITY_DIMENSION})</option>)}
          </select>
          <button onClick={start} disabled={running || !id}
            className="px-4 py-2 rounded bg-brand-primary text-white font-semibold text-sm disabled:opacity-50">
            {running ? 'Board in session…' : 'Convene Review Board'}
          </button>
        </div>

        <div className="space-y-2">
          <label className="text-[11px] uppercase tracking-widest text-brand-muted">Question for the board</label>
          <textarea value={prompt} onChange={e => setPrompt(e.target.value)} disabled={running} rows={2}
            placeholder={selIssue ? `Default: Should we contain the lot, launch a field service campaign, or keep monitoring "${selIssue.TITLE}"? Weigh safety, exposure, and cost.` : 'Select an issue…'}
            className="w-full bg-brand-surface border border-brand-border rounded px-3 py-2 text-sm text-brand-text placeholder:text-slate-500 resize-y focus:border-brand-accent/60 outline-none" />
          <div className="flex flex-wrap gap-2">
            {PRESETS.map((p, i) => (
              <button key={i} onClick={() => setPrompt(p)} disabled={running}
                className="text-[11px] px-2.5 py-1 rounded-full border border-brand-border text-brand-muted hover:border-brand-accent/60 hover:text-brand-primary transition-colors disabled:opacity-40">
                {p.length > 54 ? p.slice(0, 54) + '…' : p}
              </button>
            ))}
          </div>
        </div>

        {/* Board members + phase stepper */}
        <div className="grid grid-cols-3 gap-3" data-spotlight={focusKey === 'members' ? 'board-live' : undefined}>
          {Object.entries(AGENT_META).map(([k, m]) => (
            <div key={k} className="rounded-lg border border-brand-border bg-brand-surface p-3" style={{ borderTopColor: m.color, borderTopWidth: 3 }}>
              <div className="font-semibold text-sm" style={{ color: m.color }}>{m.name}</div>
              <div className="text-[10px] uppercase tracking-widest text-brand-muted">{m.tag}</div>
              {finals[k] && (
                <div className="mt-2 text-xs text-brand-text">
                  <span className="text-brand-primary font-semibold">{finals[k].recommended_option}</span>
                  {finals[k].confidence != null ? ` · ${finals[k].confidence}%` : ''}
                </div>
              )}
            </div>
          ))}
        </div>

        {(running || phase) && (
          <div className="flex items-center gap-2">
            {PHASES.map(p => (
              <div key={p} className={`text-[11px] px-2.5 py-1 rounded-full border ${phase === p ? 'border-brand-accent text-brand-primary' : PHASES.indexOf(phase) > PHASES.indexOf(p) ? 'border-pillar-productivity/40 text-pillar-productivity' : 'border-brand-border text-slate-500'}`}>
                {PHASE_LABEL[p]}
              </div>
            ))}
          </div>
        )}

        {(conf != null || Object.keys(finals).length > 0) && (
          <div className="grid grid-cols-3 gap-4">
            <section className="rounded-lg border border-brand-border bg-brand-surface p-4 flex flex-col items-center justify-center">
              <h3 className="text-xs font-semibold tracking-widest text-brand-muted mb-2 self-start">CONVERGENCE</h3>
              <Gauge value={conf ?? 0} max={100} suffix="%" label="Board agreement"
                color={conf != null && conf >= 70 ? '#059669' : conf != null && conf >= 40 ? CHART.primary : '#C62828'} size={150} />
            </section>
            <section className="rounded-lg border border-brand-border bg-brand-surface p-4">
              <h3 className="text-xs font-semibold tracking-widest text-brand-muted mb-2">CONVERGENCE OVER ROUNDS</h3>
              {convHistory.length > 1 ? (
                <ResponsiveContainer width="100%" height={150}>
                  <LineChart data={convHistory.map((v, i) => ({ round: `R${i + 1}`, pct: Math.round(v * 100) }))} margin={{ top: 8, right: 12, bottom: 0, left: -12 }}>
                    <CartesianGrid stroke={CHART.grid} strokeDasharray="3 3" vertical={false} />
                    <XAxis dataKey="round" tick={{ fill: CHART.textDim, fontSize: 11 }} stroke={CHART.grid} />
                    <YAxis domain={[0, 100]} tick={{ fill: CHART.textDim, fontSize: 10 }} stroke={CHART.grid} />
                    <Tooltip {...tooltipStyle} formatter={(v: any) => `${v}%`} />
                    <Line type="monotone" dataKey="pct" stroke={CHART.primary} strokeWidth={2} dot={{ r: 3, fill: CHART.primary }} isAnimationActive={false} />
                  </LineChart>
                </ResponsiveContainer>
              ) : <div className="h-[150px] flex items-center justify-center text-xs text-slate-500">Single-round convergence — no trajectory yet.</div>}
            </section>
            <section className="rounded-lg border border-brand-border bg-brand-surface p-4">
              <h3 className="text-xs font-semibold tracking-widest text-brand-muted mb-2">RECOMMENDATION MATRIX</h3>
              {Object.keys(finals).length > 0 ? (
                <ResponsiveContainer width="100%" height={150}>
                  <BarChart data={Object.entries(finals).map(([k, v]: any) => ({ name: AGENT_META[k]?.name.split(' ')[0] || k, conf: v.confidence ?? 0, opt: v.recommended_option, color: AGENT_META[k]?.color || '#5B6B7A' }))}
                    layout="vertical" margin={{ top: 4, right: 60, bottom: 0, left: 8 }}>
                    <XAxis type="number" domain={[0, 100]} hide />
                    <YAxis type="category" dataKey="name" width={72} tick={{ fill: CHART.text, fontSize: 11 }} stroke={CHART.grid} />
                    <Tooltip {...tooltipStyle} formatter={(v: any, _n: any, p: any) => [`${v}% · ${p?.payload?.opt || ''}`, 'confidence']} />
                    <Bar dataKey="conf" radius={[0, 3, 3, 0]}>
                      {Object.entries(finals).map(([k], i) => <Cell key={i} fill={AGENT_META[k]?.color || '#5B6B7A'} />)}
                      <LabelList dataKey="opt" position="right" fill={CHART.text} fontSize={9} />
                    </Bar>
                  </BarChart>
                </ResponsiveContainer>
              ) : <div className="h-[150px] flex items-center justify-center text-xs text-slate-500">Awaiting final positions…</div>}
            </section>
          </div>
        )}

        {/* Board brief — executive readout */}
        {brief && (
          <section ref={briefRef} data-spotlight={focusKey === 'brief' ? 'board-live' : undefined}
            className="rounded-xl border border-brand-accent/40 bg-brand-accent/5 p-5">
            <h3 className="text-sm font-semibold tracking-widest text-brand-primary mb-4">BOARD BRIEF</h3>
            <BriefReadout raw={brief} />
          </section>
        )}

        {/* Debate transcript — collapsible by round */}
        {turns.length > 0 && (() => {
          const groups: { key: string; label: string; items: Turn[] }[] = []
          for (const t of turns) {
            const gkey = t.type === 'position' ? 'positions' : `round-${t.round}`
            const glabel = t.type === 'position' ? 'Opening Positions' : `Cross-Examination · Round ${t.round}`
            let g = groups.find(x => x.key === gkey)
            if (!g) { g = { key: gkey, label: glabel, items: [] }; groups.push(g) }
            g.items.push(t)
          }
          return (
            <div ref={scrollRef} data-spotlight={focusKey === 'debate' ? 'board-live' : undefined}
              className="space-y-2 max-h-[520px] overflow-auto pr-1">
              <div className="text-[11px] uppercase tracking-widest text-brand-muted mb-1">Full deliberation · {turns.length} exchanges</div>
              {groups.map((g, gi) => (
                <details key={g.key} open={running && gi === groups.length - 1}
                  className="rounded-lg border border-brand-border bg-brand-surface group">
                  <summary className="flex items-center gap-2 px-3 py-2 cursor-pointer select-none list-none hover:bg-brand-subtle">
                    <ChevronRight size={14} className="text-brand-muted transition-transform group-open:rotate-90" />
                    <span className="text-sm font-medium text-brand-text">{g.label}</span>
                    <span className="text-[10px] text-brand-muted">{g.items.length} turns</span>
                    <div className="ml-auto flex gap-1">
                      {[...new Set(g.items.map(i => i.agent))].map(a => (
                        <span key={a} className="h-2 w-2 rounded-full" style={{ background: AGENT_META[a]?.color || '#5B6B7A' }} />
                      ))}
                    </div>
                  </summary>
                  <div className="space-y-2 p-3 pt-0">
                    {g.items.map((t, i) => {
                      const m = AGENT_META[t.agent] || { name: t.agent, color: '#5B6B7A' }
                      return (
                        <div key={i} className="rounded-lg border border-brand-border bg-brand-surface p-3 border-l-4" style={{ borderLeftColor: m.color }}>
                          <div className="flex items-center gap-2 mb-1">
                            <span className="text-xs font-semibold" style={{ color: m.color }}>{m.name}</span>
                            <span className="text-[10px] px-1.5 py-0.5 rounded bg-brand-subtle text-brand-muted uppercase">{t.type}{t.action ? ` · ${t.action}` : ''}</span>
                          </div>
                          <p className="text-sm text-brand-text whitespace-pre-wrap">{t.text}</p>
                        </div>
                      )
                    })}
                  </div>
                </details>
              ))}
            </div>
          )
        })()}

        {!running && !turns.length && (
          <p className="text-brand-muted text-sm">Select an issue and convene the board to run a live 3-agent debate grounded in its evidence.</p>
        )}
      </div>
    </div>
  )
}
