import { useEffect, useRef, useState } from 'react'
import Markdown from 'react-markdown'
import remarkGfm from 'remark-gfm'
import { streamChat, ChatEvent } from '../lib/api'
import { VegaChart } from './VegaChart'
import { DataTable } from './DataTable'

interface Msg {
  role: 'user' | 'assistant'
  content: string
  thinking?: string[]
  toolStatus?: string[]
  sql?: string
  data?: any
  charts?: any[]
  error?: string
}

interface Props {
  initialPrompt?: string | null
  onConsumed?: () => void
  className?: string
}

export function Chat({ initialPrompt, onConsumed, className }: Props) {
  const [messages, setMessages] = useState<Msg[]>([])
  const [input, setInput] = useState('')
  const [busy, setBusy] = useState(false)
  const scroll = useRef<HTMLDivElement>(null)

  useEffect(() => { scroll.current?.scrollTo({ top: 999999, behavior: 'smooth' }) }, [messages, busy])

  useEffect(() => {
    if (initialPrompt && !busy) {
      send(initialPrompt)
      onConsumed && onConsumed()
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [initialPrompt])

  async function send(text: string) {
    if (!text.trim() || busy) return
    setInput('')
    const userMsg: Msg = { role: 'user', content: text }
    const aiMsg: Msg = { role: 'assistant', content: '', thinking: [], toolStatus: [], charts: [] }
    setMessages(m => [...m, userMsg, aiMsg])
    setBusy(true)
    try {
      const history = messages.map(m => ({ role: m.role, content: m.content }))
      for await (const ev of streamChat(text, history)) {
        setMessages(prev => {
          const next = [...prev]
          const last = next[next.length - 1]
          if (last.role !== 'assistant') return next
          handleEvent(last, ev)
          return next
        })
      }
    } catch (e: any) {
      setMessages(m => { const n = [...m]; n[n.length - 1].error = String(e); return n })
    } finally { setBusy(false) }
  }

  function handleEvent(msg: Msg, ev: ChatEvent) {
    switch (ev.type) {
      case 'text':         msg.content += ev.content; break
      case 'thinking':     msg.thinking!.push(ev.content); break
      case 'status':       msg.toolStatus!.push(ev.title); break
      case 'tool_status':  msg.toolStatus!.push(ev.title); break
      case 'tool_result':
        if (ev.sql)   msg.sql = ev.sql
        if (ev.data)  msg.data = ev.data
        if (ev.error) msg.error = ev.error
        break
      case 'chart':
        if (ev.chart_spec) (msg.charts ||= []).push(ev.chart_spec)
        break
      case 'error':        msg.error = ev.content; break
    }
  }

  return (
    <div className={`flex flex-col h-full bg-white ${className || ''}`}>
      <div ref={scroll} className="flex-1 overflow-y-auto p-4 space-y-4">
        {messages.length === 0 && (
          <div className="text-center py-8">
            <div className="inline-block apex-corner w-12 h-10 mb-3" />
            <div className="text-sm text-apex-gray">Ask FieldIQ anything about your customers, products, pipeline, or documents.</div>
          </div>
        )}
        {messages.map((m, i) => (
          <div key={i} className={`flex ${m.role === 'user' ? 'justify-end' : 'justify-start'}`}>
            <div className={`max-w-[85%] rounded-lg p-3 ${m.role === 'user' ? 'bg-apex-red text-white' : 'bg-canvas-100 border border-canvas-300'}`}>
              {m.role === 'assistant' && (
                <>
                  {m.toolStatus && m.toolStatus.length > 0 && (
                    <div className="text-[11px] text-apex-gray mb-2 space-y-0.5">
                      {m.toolStatus.slice(-3).map((t,j) => <div key={j}>· {t}</div>)}
                    </div>
                  )}
                  {m.sql && (
                    <details className="mb-2">
                      <summary className="text-[11px] text-apex-gray cursor-pointer">Generated SQL</summary>
                      <pre className="text-[11px] bg-canvas-200 p-2 rounded mt-1 overflow-x-auto">{m.sql}</pre>
                    </details>
                  )}
                  {m.error && <div className="text-xs text-apex-red mb-2">⚠ {m.error}</div>}
                </>
              )}
              {m.role === 'assistant' && m.data && Array.isArray(m.data) && m.data.length > 0 && (
                <div className="my-2"><DataTable rows={m.data} maxRows={8} /></div>
              )}
              {m.role === 'assistant' && m.charts && m.charts.length > 0 && (
                <div className="my-2 space-y-2">
                  {m.charts.map((s, k) => <div key={k} className="bg-white rounded border border-canvas-300 p-2"><VegaChart spec={s} /></div>)}
                </div>
              )}
              <div className={m.role === 'assistant' ? 'markdown-content text-sm' : 'text-sm'}>
                {m.content ? (
                  m.role === 'assistant' ? <Markdown remarkPlugins={[remarkGfm]}>{m.content}</Markdown> : m.content
                ) : (
                  m.role === 'assistant' && busy && i === messages.length - 1 ? <em className="text-apex-gray">Thinking…</em> : ''
                )}
              </div>
            </div>
          </div>
        ))}
      </div>
      <form onSubmit={e => { e.preventDefault(); send(input) }} className="border-t border-canvas-300 p-3 flex gap-2">
        <input value={input} onChange={e => setInput(e.target.value)} disabled={busy}
               placeholder="Ask FieldIQ…"
               className="flex-1 px-3 py-2 border border-canvas-300 rounded-md text-sm focus:outline-none focus:border-apex-red"/>
        <button type="submit" disabled={busy || !input.trim()} className="apex-btn-primary">
          {busy ? '…' : 'Send'}
        </button>
      </form>
    </div>
  )
}
