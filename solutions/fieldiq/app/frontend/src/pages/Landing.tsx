import { useState, useEffect } from 'react'
import { NavCtx, Page } from '../App'

const COPILOT_NAME = 'FIELDIQ'
// Sentence-case form for prose (the wordmark stays uppercase).
const COPILOT_LABEL = 'FieldIQ'

const features = [
  {
    icon: 'M21 5c-1.11-.35-2.33-.5-3.5-.5-1.95 0-4.05.4-5.5 1.5-1.45-1.1-3.55-1.5-5.5-1.5S2.45 4.9 1 6v14.65c0 .25.25.5.5.5.1 0 .15-.05.25-.05C3.1 20.45 5.05 20 6.5 20c1.95 0 4.05.4 5.5 1.5 1.35-.85 3.8-1.5 5.5-1.5 1.65 0 3.35.3 4.75 1.05.1.05.15.05.25.05.25 0 .5-.25.5-.5V6c-.6-.45-1.25-.75-2-1z',
    title: 'Multi-Tool Cortex Agent',
    description: 'A single orchestrating agent routes to Cortex Analyst for structured data, Cortex Search for unstructured docs, and action stored procedures for workflow automation.',
    color: 'purple',
  },
  {
    icon: 'M15.5 14h-.79l-.28-.27C15.41 12.59 16 11.11 16 9.5 16 5.91 13.09 3 9.5 3S3 5.91 3 9.5 5.91 16 9.5 16c1.61 0 3.09-.59 4.23-1.57l.27.28v.79l5 4.99L20.49 19l-4.99-5z',
    title: 'Semantic Document Search',
    description: 'Instant retrieval over product datasheets, engineering drawings, playbooks, and pricing sheets with grounded, cited answers.',
    color: 'green',
  },
  {
    icon: 'M3 13h2v8H3v-8zm4-6h2v14H7V7zm4-4h2v18h-2V3zm4 8h2v10h-2V11zm4 4h2v6h-2v-6z',
    title: 'Natural-Language Analytics',
    description: 'Ask questions in plain English and get real-time answers grounded in live CRM, ERP, and service data via Cortex Analyst text-to-SQL.',
    color: 'blue',
  },
  {
    icon: 'M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 15l-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z',
    title: 'AI-Powered Actions',
    description: 'Automated call plans, meeting agendas, multilingual email drafts, geo-proximity queries, and route planning — all triggered via natural language.',
    color: 'red',
  },
]

const stats = [
  { value: 'Accounts', label: 'Full CRM Coverage' },
  { value: 'Pipeline', label: 'Real-Time Visibility' },
  { value: 'Docs', label: 'Semantic Search' },
  { value: 'Tools', label: 'Agent Orchestration' },
]

export function Landing(ctx: NavCtx) {
  const [mounted, setMounted] = useState(false)
  const [typedText, setTypedText] = useState('')
  const fullText = `Hello, I'm ${COPILOT_LABEL}. Your intelligent sales co-pilot built on Snowflake Cortex.`

  useEffect(() => {
    setMounted(true)
    let index = 0
    const interval = setInterval(() => {
      if (index <= fullText.length) {
        setTypedText(fullText.slice(0, index))
        index++
      } else {
        clearInterval(interval)
      }
    }, 40)
    return () => clearInterval(interval)
  }, [])

  return (
    <div className="min-h-screen bg-white overflow-y-auto">
      <div className="relative">
        <div className="absolute inset-0 overflow-hidden">
          <div className="absolute -top-40 -right-40 w-96 h-96 bg-apex-red/10 rounded-full blur-3xl animate-pulse" />
          <div className="absolute -bottom-40 -left-40 w-96 h-96 bg-orange-400/10 rounded-full blur-3xl animate-pulse" style={{ animationDelay: '1s' }} />
        </div>
        <div className="absolute inset-0 bg-gradient-to-b from-white/50 via-transparent to-white" />

        <div className="relative max-w-7xl mx-auto px-6 pt-16 pb-24">
          <div className={`text-center transition-all duration-1000 ${mounted ? 'opacity-100 translate-y-0' : 'opacity-0 translate-y-10'}`}>
            <div className="relative inline-block mb-6">
              <div className="w-20 h-20 rounded-2xl bg-gradient-to-br from-apex-red to-orange-500 flex items-center justify-center shadow-2xl shadow-apex-red/30">
                <svg viewBox="0 0 24 24" className="w-10 h-10 text-white"><path d="M20 6h-2.18c.11-.31.18-.65.18-1 0-1.66-1.34-3-3-3-1.05 0-1.96.54-2.5 1.35l-.5.67-.5-.68C10.96 2.54 10.05 2 9 2 7.34 2 6 3.34 6 5c0 .35.07.69.18 1H4c-1.11 0-1.99.89-1.99 2L2 19c0 1.11.89 2 2 2h16c1.11 0 2-.89 2-2V8c0-1.11-.89-2-2-2z" fill="currentColor"/></svg>
              </div>
              <div className="absolute inset-0 w-20 h-20 rounded-2xl bg-gradient-to-br from-apex-red to-orange-500 blur-xl opacity-40" />
            </div>

            <h1 className="text-5xl font-bold mb-3">
              <span className="bg-gradient-to-r from-apex-red via-orange-500 to-apex-red bg-clip-text text-transparent">
                {COPILOT_NAME}
              </span>
            </h1>
            <p className="text-lg text-canvas-500 mb-1">AI Sales Co-Pilot for Industrial Manufacturers</p>
            <p className="text-sm text-canvas-400 mb-6">Powered by Snowflake Cortex AI</p>

            <div className="max-w-2xl mx-auto mb-10">
              <div className="bg-canvas-50 border border-canvas-300 rounded-xl p-5 text-left shadow-sm">
                <div className="flex items-start gap-4">
                  <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-apex-red to-orange-500 flex items-center justify-center flex-shrink-0">
                    <svg viewBox="0 0 24 24" className="w-5 h-5 text-white"><path d="M7 18c-1.1 0-1.99.9-1.99 2S5.9 22 7 22s2-.9 2-2-.9-2-2-2zM1 2v2h2l3.6 7.59-1.35 2.45c-.16.28-.25.61-.25.96 0 1.1.9 2 2 2h12v-2H7.42c-.14 0-.25-.11-.25-.25l.03-.12.9-1.63h7.45c.75 0 1.41-.41 1.75-1.03l3.58-6.49c.08-.14.12-.31.12-.48 0-.55-.45-1-1-1H5.21l-.94-2H1z" fill="currentColor"/></svg>
                  </div>
                  <div>
                    <p className="text-lg text-apex-dark">
                      {typedText}
                      <span className="inline-block w-0.5 h-5 bg-apex-red ml-1 animate-pulse" />
                    </p>
                  </div>
                </div>
              </div>
            </div>

            <div className="flex items-center justify-center gap-4">
              <button
                onClick={() => ctx.onNavigate('dashboard')}
                className="group flex items-center gap-3 px-7 py-3.5 bg-gradient-to-r from-apex-red to-orange-500 rounded-xl text-white font-semibold text-lg shadow-xl shadow-apex-red/25 hover:shadow-apex-red/40 hover:scale-105 transition-all"
              >
                Launch Sales Command Center
                <svg viewBox="0 0 24 24" className="w-5 h-5 group-hover:translate-x-1 transition-transform"><path d="M12 4l-1.41 1.41L16.17 11H4v2h12.17l-5.58 5.59L12 20l8-8z" fill="currentColor"/></svg>
              </button>
              <button
                onClick={() => ctx.onNavigate('architecture')}
                className="flex items-center gap-2 px-5 py-3.5 bg-canvas-50 border border-canvas-300 rounded-xl text-apex-dark font-medium hover:bg-canvas-100 hover:border-canvas-400 transition-all"
              >
                View Architecture
              </button>
            </div>
          </div>
        </div>
      </div>

      <div className={`bg-canvas-50 border-y border-canvas-200 py-6 transition-all duration-1000 delay-300 ${mounted ? 'opacity-100' : 'opacity-0'}`}>
        <div className="max-w-7xl mx-auto px-6">
          <div className="grid grid-cols-4 gap-8">
            {stats.map((stat, i) => (
              <div key={i} className="text-center">
                <p className="text-xl font-bold text-apex-red">{stat.value}</p>
                <p className="text-sm text-canvas-500 mt-1">{stat.label}</p>
              </div>
            ))}
          </div>
        </div>
      </div>

      <div className="max-w-7xl mx-auto px-6 py-16">
        <div className={`text-center mb-10 transition-all duration-1000 delay-500 ${mounted ? 'opacity-100 translate-y-0' : 'opacity-0 translate-y-10'}`}>
          <h2 className="text-2xl font-bold text-apex-dark mb-3">Agentic AI for Field Sales Teams</h2>
          <p className="text-canvas-500 max-w-2xl mx-auto">
            A repeatable solution pattern that unifies CRM, ERP, service, and product knowledge into a single conversational AI co-pilot.
          </p>
        </div>

        <div className="grid grid-cols-2 gap-5">
          {features.map((feature, i) => {
            const colorClass: Record<string, string> = {
              purple: 'from-purple-50 to-purple-100/50 border-purple-200 text-purple-600',
              green: 'from-emerald-50 to-emerald-100/50 border-emerald-200 text-emerald-600',
              blue: 'from-blue-50 to-blue-100/50 border-blue-200 text-blue-600',
              red: 'from-red-50 to-red-100/50 border-red-200 text-red-600',
            }

            return (
              <div
                key={i}
                className={`bg-gradient-to-br ${colorClass[feature.color]} border rounded-xl p-6 transition-all duration-500 hover:scale-[1.02] ${mounted ? 'opacity-100 translate-y-0' : 'opacity-0 translate-y-10'}`}
                style={{ transitionDelay: `${600 + i * 100}ms` }}
              >
                <div className="w-11 h-11 rounded-xl bg-white/80 border border-canvas-200 flex items-center justify-center mb-4">
                  <svg viewBox="0 0 24 24" className="w-5 h-5"><path d={feature.icon} fill="currentColor"/></svg>
                </div>
                <h3 className="text-lg font-semibold text-apex-dark mb-2">{feature.title}</h3>
                <p className="text-canvas-500 text-sm">{feature.description}</p>
              </div>
            )
          })}
        </div>
      </div>

      <div className="max-w-7xl mx-auto px-6 pb-16">
        <div className="grid grid-cols-4 gap-3">
          {([
            { icon: 'M3 13h2v8H3v-8zm4-6h2v14H7V7zm4-4h2v18h-2V3zm4 8h2v10h-2V11zm4 4h2v6h-2v-6z', label: 'Insights', page: 'insights' as Page, desc: 'Interactive charts & analytics' },
            { icon: 'M20.5 3l-.16.03L15 5.1 9 3 3.36 4.9c-.21.07-.36.25-.36.48V20.5c0 .28.22.5.5.5l.16-.03L9 18.9l6 2.1 5.64-1.9c.21-.07.36-.25.36-.48V3.5c0-.28-.22-.5-.5-.5z', label: 'Customer Map', page: 'map' as Page, desc: 'Geographic account visualization' },
            { icon: 'M12 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z', label: 'Account 360', page: 'account' as Page, desc: 'Deep-dive into any customer' },
            { icon: 'M21 5c-1.11-.35-2.33-.5-3.5-.5-1.95 0-4.05.4-5.5 1.5-1.45-1.1-3.55-1.5-5.5-1.5S2.45 4.9 1 6v14.65c0 .25.25.5.5.5.1 0 .15-.05.25-.05C3.1 20.45 5.05 20 6.5 20c1.95 0 4.05.4 5.5 1.5 1.35-.85 3.8-1.5 5.5-1.5 1.65 0 3.35.3 4.75 1.05.1.05.15.05.25.05.25 0 .5-.25.5-.5V6c-.6-.45-1.25-.75-2-1z', label: 'Knowledge', page: 'knowledge' as Page, desc: 'Product catalog & documents' },
          ]).map((link, i) => (
            <button
              key={i}
              onClick={() => ctx.onNavigate(link.page)}
              className="bg-white border border-canvas-300 rounded-xl p-4 text-left group hover:border-apex-red/30 hover:shadow-sm transition-all"
            >
              <div className="flex items-center gap-3 mb-2">
                <svg viewBox="0 0 24 24" className="w-4 h-4 text-apex-red"><path d={link.icon} fill="currentColor"/></svg>
                <span className="font-medium text-apex-dark group-hover:text-apex-red transition-colors text-sm">{link.label}</span>
                <svg viewBox="0 0 24 24" className="w-3.5 h-3.5 text-canvas-400 ml-auto group-hover:translate-x-1 transition-transform"><path d="M10 6L8.59 7.41 13.17 12l-4.58 4.59L10 18l6-6z" fill="currentColor"/></svg>
              </div>
              <p className="text-xs text-canvas-500">{link.desc}</p>
            </button>
          ))}
        </div>
      </div>

      <div className="max-w-7xl mx-auto px-6 pb-16">
        <div className={`bg-gradient-to-r from-amber-50 to-red-50 border border-amber-200 rounded-xl p-6 transition-all duration-1000 delay-700 ${mounted ? 'opacity-100' : 'opacity-0'}`}>
          <div className="flex items-start gap-4">
            <div className="w-12 h-12 rounded-xl bg-amber-100 flex items-center justify-center flex-shrink-0">
              <svg viewBox="0 0 24 24" className="w-6 h-6 text-amber-600"><path d="M9.4 16.6L4.8 12l4.6-4.6L8 6l-6 6 6 6 1.4-1.4zm5.2 0l4.6-4.6-4.6-4.6L16 6l6 6-6 6-1.4-1.4z" fill="currentColor"/></svg>
            </div>
            <div>
              <h3 className="text-lg font-semibold text-amber-700 mb-2">Repeatable Solution Pattern</h3>
              <p className="text-apex-dark text-sm mb-3">
                This accelerator demonstrates how to build a <strong>production-grade agentic AI co-pilot</strong> on Snowflake.
                Swap the data model, update the semantic layer, and deploy for any manufacturing vertical.
              </p>
              <p className="text-canvas-500 text-sm">
                <strong className="text-apex-dark">Cortex Agent</strong> (orchestration) +
                <strong className="text-apex-dark"> Cortex Analyst</strong> (text-to-SQL) +
                <strong className="text-apex-dark"> Cortex Search</strong> (RAG) +
                <strong className="text-amber-600"> Action Procs</strong> (workflow automation)
              </p>
            </div>
          </div>
        </div>
      </div>

      <div className="border-t border-canvas-200 py-6">
        <div className="max-w-7xl mx-auto px-6 text-center">
          <p className="text-sm text-canvas-500">
            Built on <span className="text-apex-red font-medium">Snowflake</span> &bull; Cortex Agents &bull; Cortex Analyst &bull; Cortex Search &bull; SPCS
          </p>
        </div>
      </div>
    </div>
  )
}
