import { useState, useRef, useEffect } from 'react'
import { useSearchParams } from 'react-router-dom'
import { Send, Loader2 } from 'lucide-react'
import ReactMarkdown from 'react-markdown'
import remarkGfm from 'remark-gfm'
import PageHeader from '../components/PageHeader'
import VegaChart from '../components/charts/VegaChart'
import { streamAsk } from '../services/api'
import type { AgentEvent } from '../types'
import { ANCHOR, BRAND } from '../config/brand'
import { BrandMark } from '../components/Wordmark'

interface Msg { role: 'user' | 'assistant'; text: string; steps: string[]; sql?: string; chartSpec?: Record<string, unknown> }

function AgentMarkdown({ text }: { text: string }) {
  return (
    <ReactMarkdown
      remarkPlugins={[remarkGfm]}
      components={{
        h1: ({ children }) => <h1 className="text-base font-bold text-brand-text mt-3 mb-1.5">{children}</h1>,
        h2: ({ children }) => <h2 className="text-sm font-bold text-brand-text mt-3 mb-1.5">{children}</h2>,
        h3: ({ children }) => <h3 className="text-sm font-semibold text-brand-primary uppercase tracking-wide mt-3 mb-1">{children}</h3>,
        p: ({ children }) => <p className="text-sm text-brand-text leading-relaxed mb-2">{children}</p>,
        strong: ({ children }) => <strong className="font-semibold text-brand-text">{children}</strong>,
        em: ({ children }) => <em className="italic text-brand-muted">{children}</em>,
        ul: ({ children }) => <ul className="list-disc pl-5 space-y-1 mb-2 text-sm text-brand-text">{children}</ul>,
        ol: ({ children }) => <ol className="list-decimal pl-5 space-y-1 mb-2 text-sm text-brand-text">{children}</ol>,
        li: ({ children }) => <li className="leading-relaxed marker:text-brand-primary">{children}</li>,
        a: ({ children, href }) => <a href={href} className="text-brand-primary underline hover:opacity-80">{children}</a>,
        blockquote: ({ children }) => <blockquote className="border-l-2 border-brand-accent/60 pl-3 text-brand-text italic my-2">{children}</blockquote>,
        hr: () => <hr className="border-brand-border my-3" />,
        code: ({ children }) => <code className="bg-brand-subtle rounded px-1 py-0.5 text-[12px] text-brand-primary font-mono">{children}</code>,
        pre: ({ children }) => <pre className="bg-brand-subtle rounded p-2 overflow-x-auto text-[12px] text-brand-text my-2">{children}</pre>,
        table: ({ children }) => <div className="overflow-x-auto my-2"><table className="w-full text-xs border border-brand-border">{children}</table></div>,
        thead: ({ children }) => <thead className="bg-brand-subtle text-brand-text">{children}</thead>,
        th: ({ children }) => <th className="text-left px-2 py-1 border border-brand-border font-semibold">{children}</th>,
        td: ({ children }) => <td className="px-2 py-1 border border-brand-border text-brand-text">{children}</td>,
      }}
    >
      {text}
    </ReactMarkdown>
  )
}

const SUGGESTIONS = [
  "What's our biggest safety-priority quality issue and why?",
  `What is the warranty exposure if the ${ANCHOR.model} fuel-system issue spreads?`,
  'Is the fuel-system issue systemic or isolated to a lot?',
  'What should we do in the next 72 hours?',
]

export default function AskAssistant() {
  const [msgs, setMsgs] = useState<Msg[]>([])
  const [input, setInput] = useState('')
  const [busy, setBusy] = useState(false)
  const endRef = useRef<HTMLDivElement>(null)
  const [params] = useSearchParams()

  useEffect(() => { endRef.current?.scrollIntoView({ behavior: 'smooth' }) }, [msgs])

  async function ask(q: string) {
    if (!q.trim() || busy) return
    setInput('')
    const history = msgs.map(m => ({ role: m.role, content: m.text }))
    setMsgs(m => [...m, { role: 'user', text: q, steps: [] }, { role: 'assistant', text: '', steps: [] }])
    setBusy(true)
    try {
      await streamAsk(q, history, undefined, (e: AgentEvent) => {
        setMsgs(m => {
          const last = m[m.length - 1]
          const a: Msg = { ...last, steps: [...last.steps] }
          if (e.type === 'text' && e.content) a.text = last.text + e.content
          else if (e.type === 'thinking' && e.content) a.steps.push('🧠 ' + e.content.slice(0, 80))
          else if (e.type === 'status' && e.title) a.steps.push('▸ ' + e.title)
          else if (e.type === 'tool_result' && e.sql) a.sql = e.sql
          else if (e.type === 'chart' && e.chart_spec) a.chartSpec = e.chart_spec
          else if (e.type === 'error') a.text = last.text + `\n\n_Error: ${e.content}_`
          return [...m.slice(0, -1), a]
        })
      })
    } finally {
      setBusy(false)
    }
  }

  // Story Mode: auto-ask once when ?ask=<prompt> is present
  const askedRef = useRef(false)
  useEffect(() => {
    const q = params.get('ask')
    if (q && !askedRef.current && !busy && msgs.length === 0) {
      askedRef.current = true
      ask(q)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [params])

  return (
    <div className="flex-1 flex flex-col h-screen">
      <PageHeader title="Quality Insights" subtitle={`Ask ${BRAND.productShort} — grounded conversational analytics`} />
      <div className="flex-1 overflow-y-auto p-8 space-y-4" data-spotlight="ask-thread">
        {msgs.length === 0 && (
          <div className="max-w-2xl mx-auto text-center mt-10 animate-fade-in-up">
            <div className="flex justify-center mb-3"><BrandMark size={40} /></div>
            <p className="text-brand-text mb-6">Ask {BRAND.productShort} about quality issues, exposure, root cause, or what to do next. From months to seconds.</p>
            <div className="grid grid-cols-2 gap-3">
              {SUGGESTIONS.map(s => (
                <button key={s} onClick={() => ask(s)}
                  className="text-left text-sm rounded-lg border border-brand-border bg-brand-surface px-4 py-3 hover:border-brand-accent text-brand-text">
                  {s}
                </button>
              ))}
            </div>
          </div>
        )}
        {msgs.map((m, i) => (
          <div key={i} className={`max-w-3xl ${m.role === 'user' ? 'ml-auto' : ''}`}>
            <div className={`rounded-lg px-4 py-3 ${m.role === 'user' ? 'bg-brand-primary text-white font-medium' : 'bg-brand-surface border border-brand-border'}`}>
              {m.role === 'assistant' && m.steps.length > 0 && (
                <div className="mb-2 space-y-0.5 text-xs text-brand-muted border-l-2 border-brand-border pl-2">
                  {m.steps.slice(-5).map((s, k) => <div key={k}>{s}</div>)}
                </div>
              )}
              {m.role === 'assistant' && !m.text && busy && (
                <div className="flex items-center gap-2 text-brand-muted text-sm"><Loader2 size={14} className="animate-spin" /> {BRAND.productShort} is analyzing…</div>
              )}
              {m.role === 'assistant'
                ? <div className="cqc-md">{m.text && <AgentMarkdown text={m.text} />}</div>
                : <div className="whitespace-pre-wrap text-sm">{m.text}</div>}
              {m.chartSpec && <VegaChart spec={m.chartSpec} />}
              {m.sql && (
                <details className="mt-3 group">
                  <summary className="cursor-pointer text-[11px] uppercase tracking-widest text-brand-muted hover:text-brand-primary select-none">
                    ▸ Generated SQL
                  </summary>
                  <pre className="mt-1.5 text-[11px] bg-brand-subtle rounded p-2 overflow-auto max-h-56 text-brand-muted border border-brand-border">{m.sql}</pre>
                </details>
              )}
            </div>
          </div>
        ))}
        <div ref={endRef} />
      </div>
      <div className="border-t border-brand-border bg-white p-4 flex gap-2">
        <input value={input} onChange={e => setInput(e.target.value)} onKeyDown={e => e.key === 'Enter' && ask(input)}
          placeholder={`Ask ${BRAND.productShort} anything about ${BRAND.businessUnitShort} quality…`}
          className="flex-1 bg-brand-surface border border-brand-border rounded-lg px-4 py-2 text-sm focus:border-brand-accent outline-none" />
        <button onClick={() => ask(input)} disabled={busy}
          className="bg-brand-primary text-white rounded-lg px-4 py-2 font-semibold disabled:opacity-50 flex items-center gap-1">
          {busy ? <Loader2 size={16} className="animate-spin" /> : <Send size={16} />}
        </button>
      </div>
    </div>
  )
}
