import { useNavigate } from 'react-router-dom'
import { LayoutDashboard, MessageSquare, Bell, ArrowRight, ShieldAlert, Activity, Smile, PlayCircle } from 'lucide-react'
import { useDemo } from '../demo/DemoContext'
import Wordmark from '../components/Wordmark'
import { ANCHOR, BRAND, THEME } from '../config/brand'

const PILLARS = [
  { icon: ShieldAlert, label: 'Safety', desc: 'Proactively surface serious-injury potential (SIP) before it reaches the operator.', color: THEME.pillar.safety },
  { icon: Activity, label: 'Productivity', desc: 'Cut unplanned downtime and protect Value-to-Cost.', color: THEME.pillar.productivity },
  { icon: Smile, label: 'Experience', desc: 'Track every customer touchpoint through one Experience Index.', color: THEME.pillar.experience },
]

const CTAS = [
  { to: '/command', icon: LayoutDashboard, title: 'Quality Command', desc: 'Live command view of prioritized customer-quality issues.' },
  { to: '/ask', icon: MessageSquare, title: `Ask ${BRAND.productShort}`, desc: 'From months to seconds — analytics in natural language.' },
  { to: '/alerts', icon: Bell, title: 'Quality Alerts', desc: 'Real-time awareness of emerging machine-level issues.' },
]

export default function Landing() {
  const nav = useNavigate()
  const demo = useDemo()

  return (
    <div className="min-h-screen w-full overflow-y-auto bg-brand-bg text-brand-text">
      {/* Hero */}
      <section className="relative overflow-hidden bg-white border-b border-brand-border">
        {/* diagonal blue wedge with dot texture (replaces equipment photo) */}
        <div
          className="absolute inset-0 hidden lg:block bg-gradient-to-br from-brand-accent to-brand-primary"
          style={{ clipPath: 'polygon(72% 0, 100% 0, 100% 100%, 56% 100%)' }}
        />
        <div
          className="absolute inset-0 hidden lg:block"
          style={{
            clipPath: 'polygon(72% 0, 100% 0, 100% 100%, 56% 100%)',
            backgroundImage: 'radial-gradient(rgba(255,255,255,0.22) 1.5px, transparent 1.5px)',
            backgroundSize: '22px 22px',
          }}
        />

        <button
          onClick={() => demo.start()}
          className="absolute top-6 right-6 lg:top-8 lg:right-10 z-20 flex items-center gap-2 px-4 py-2 rounded-full bg-white/95 backdrop-blur border border-white text-brand-primary text-sm font-semibold shadow-sm hover:bg-white transition-colors"
          title={`Play the guided ${ANCHOR.model} story`}
        >
          <PlayCircle size={16} />
          Play the {ANCHOR.model} Story
          <span className="text-[10px] font-normal uppercase tracking-widest opacity-60">3 min</span>
        </button>

        <div className="relative px-10 lg:px-20 py-24 lg:py-32 max-w-[1600px] mx-auto">
          <div className="mb-14">
            <Wordmark />
          </div>

          <h1 className="font-bold leading-[1.0] tracking-tight text-brand-primary text-5xl xl:text-7xl max-w-xl animate-fade-in-up">
            Customer Quality,
            <br />
            Command &amp; Response
          </h1>
          <p className="mt-6 text-xl xl:text-2xl text-brand-text max-w-lg">
            {BRAND.companyName} · <span className="text-brand-primary">{BRAND.businessUnit}</span>
          </p>
          <p className="mt-5 text-sm lg:text-base text-brand-muted max-w-md leading-relaxed">
            One command-and-response system that detects quality signals early,
            translates them into business impact, and routes the right action to
            the right team — with velocity.
          </p>

          <div className="mt-10 flex flex-wrap gap-4">
            <button
              onClick={() => nav('/command')}
              className="group flex items-center gap-2 px-6 py-3 rounded-md bg-brand-primary text-white font-semibold text-sm hover:bg-brand-primary-dark transition-colors"
            >
              Enter Quality Command
              <ArrowRight size={16} className="group-hover:translate-x-0.5 transition-transform" />
            </button>
            <button
              onClick={() => nav('/ask')}
              className="flex items-center gap-2 px-6 py-3 rounded-md border border-brand-border bg-brand-surface text-brand-text font-semibold text-sm hover:border-brand-accent transition-colors"
            >
              <MessageSquare size={16} />
              Ask {BRAND.productShort}
            </button>
          </div>
        </div>
      </section>

      {/* Pillar strip */}
      <section className="border-y border-brand-border bg-brand-subtle">
        <div className="max-w-[1600px] mx-auto px-10 lg:px-20 py-10 grid grid-cols-1 md:grid-cols-3 gap-6">
          {PILLARS.map(p => {
            const Icon = p.icon
            return (
              <div
                key={p.label}
                className="rounded-xl border border-brand-border bg-brand-surface p-6"
                style={{ borderTop: `3px solid ${p.color}` }}
              >
                <div className="flex items-center gap-3">
                  <Icon size={22} style={{ color: p.color }} />
                  <div className="font-bold uppercase tracking-wide text-lg">{p.label}</div>
                </div>
                <p className="mt-3 text-sm text-brand-muted leading-relaxed">{p.desc}</p>
              </div>
            )
          })}
        </div>
      </section>

      {/* Entry cards */}
      <section className="max-w-[1600px] mx-auto px-10 lg:px-20 py-16">
        <div className="text-[11px] uppercase tracking-[0.35em] text-brand-muted mb-6">
          Start where the customer feels the pain
        </div>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
          {CTAS.map(c => {
            const Icon = c.icon
            return (
              <button
                key={c.to}
                onClick={() => nav(c.to)}
                className="group text-left rounded-xl border border-brand-border bg-brand-surface p-7 hover:border-brand-accent transition-colors"
              >
                <div className="flex items-center justify-between">
                  <div className="h-11 w-11 rounded-lg bg-brand-accent/10 flex items-center justify-center">
                    <Icon size={20} className="text-brand-primary" />
                  </div>
                  <ArrowRight
                    size={18}
                    className="text-slate-500 group-hover:text-brand-primary group-hover:translate-x-0.5 transition-all"
                  />
                </div>
                <div className="mt-5 font-bold text-lg">{c.title}</div>
                <p className="mt-2 text-sm text-brand-muted leading-relaxed">{c.desc}</p>
              </button>
            )
          })}
        </div>

        {/* anchor scenario footer */}
        <div className="mt-14 rounded-xl border border-brand-border bg-brand-surface overflow-hidden grid grid-cols-1 lg:grid-cols-[380px_1fr]">
          <div className="h-56 lg:h-full bg-gradient-to-br from-brand-navy to-brand-primary flex flex-col items-center justify-center text-white">
            <div className="text-[11px] uppercase tracking-[0.35em] text-white/70">{ANCHOR.family}</div>
            <div className="text-5xl font-bold tracking-tight mt-1">{ANCHOR.model}</div>
          </div>
          <div className="p-8">
            <div className="text-[11px] uppercase tracking-[0.35em] text-brand-primary mb-2">
              Anchor scenario
            </div>
            <h3 className="text-2xl font-bold">{ANCHOR.model} · Fuel-System Defect</h3>
            <p className="mt-3 text-sm text-brand-muted leading-relaxed max-w-2xl">
              Customers report sudden engine shutdowns during high-load operation.
              Dealer diagnostics trace the issue to the same fuel-system component,
              and procurement confirms a shared plant origin. Follow it across every
              persona — from dealer to executive — inside {BRAND.productShort}.
            </p>
            <button
              onClick={() => nav('/command')}
              className="mt-6 flex items-center gap-2 px-5 py-2.5 rounded-md bg-brand-primary text-white font-semibold text-sm hover:bg-brand-primary-dark transition-colors"
            >
              Investigate in Command
              <ArrowRight size={15} />
            </button>
          </div>
        </div>
      </section>
    </div>
  )
}
