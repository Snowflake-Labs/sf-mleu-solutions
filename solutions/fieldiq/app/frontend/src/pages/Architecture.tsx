import { useState } from 'react'
import { NavCtx } from '../App'

interface ComponentInfo {
  id: string
  name: string
  shortName: string
  description: string
  tech: string[]
  stats?: string
  color: string
}

const components: Record<string, ComponentInfo> = {
  frontend: {
    id: 'frontend',
    name: 'React Frontend',
    shortName: 'UI',
    description: 'Modern real-time UI built with React, TypeScript, and Tailwind CSS. Features interactive chat interface, customer map with Leaflet, Economist-style Recharts visualisations, and the Sales Command Center dashboard.',
    tech: ['React 18', 'TypeScript', 'Tailwind CSS', 'Vite', 'Recharts', 'Leaflet', 'Vega-Lite'],
    stats: '7 pages, real-time SSE updates',
    color: 'cyan',
  },
  backend: {
    id: 'backend',
    name: 'FastAPI Backend',
    shortName: 'API',
    description: 'Python middleware handling API requests and SSE streaming. Routes chat queries to the Cortex Agent, serves account/pipeline/inventory data, and proxies the Cortex Agent REST API.',
    tech: ['Python 3.11', 'FastAPI', 'Uvicorn', 'Pydantic', 'httpx'],
    stats: '20+ endpoints',
    color: 'blue',
  },
  agent: {
    id: 'agent',
    name: 'Cortex Agent — FIELDIQ_AGENT',
    shortName: 'Agent',
    description: 'The intelligent orchestrator that classifies user intent and delegates to specialised tools: Cortex Analyst for CRM/ERP data, Cortex Search for engineering docs, and 5 action stored procedures for call plans, emails, routes, and more.',
    tech: ['Orchestration (auto)', '7 Tools', 'Multi-turn Context', 'Chart Spec Generation'],
    stats: '7 tools, 14 capabilities',
    color: 'purple',
  },
  analyst: {
    id: 'analyst',
    name: 'Cortex Analyst',
    shortName: 'Analyst',
    description: 'Text-to-SQL engine grounded in the FieldIQ semantic model. Answers quantitative questions about pricing, inventory, pipeline, orders, assets, and service activities with generated SQL over 9 tables.',
    tech: ['Semantic Model YAML', 'Text-to-SQL', 'Auto-Charts', 'SF_SOLUTIONS_WH'],
    stats: '9 tables, 100+ metrics',
    color: 'green',
  },
  search: {
    id: 'search',
    name: 'Cortex Search',
    shortName: 'Search',
    description: 'Semantic document retrieval over 263 chunked markdown documents — datasheets, GA drawings, submittals, sales playbooks, and pricing sheets. Powered by snowflake-arctic-embed-m-v1.5.',
    tech: ['Cortex Search Service', 'Arctic Embed', '263 Chunks', 'DOC_TITLE + CHUNK_ID'],
    stats: '262 documents indexed',
    color: 'yellow',
  },
  actions: {
    id: 'actions',
    name: 'Action Stored Procedures',
    shortName: 'Actions',
    description: 'Five SQL stored procedures that use SNOWFLAKE.CORTEX.COMPLETE (claude-sonnet-4-6) to generate grounded outputs: sales call plans, meeting agendas, email drafts (multilingual), nearby-customer geo queries, and multi-day route plans.',
    tech: ['SQL Scripting', 'Cortex Complete', 'claude-sonnet-4-6', 'Geospatial'],
    stats: '5 procs, 6 languages',
    color: 'red',
  },
  snowflake: {
    id: 'snowflake',
    name: 'Snowflake Data Cloud',
    shortName: 'Data',
    description: 'SF_SOLUTIONS stores 9 atomic tables (accounts, contacts, products, inventory, opportunities, open orders, assets, service activities, docs registry), 8 datamart views, and staged documents + parquet.',
    tech: ['SF_SOLUTIONS', 'ATOMIC Schema', 'ANALYTICS Views', 'STAGES'],
    stats: '120 accounts, 506 assets',
    color: 'blue',
  },
  spcs: {
    id: 'spcs',
    name: 'Snowpark Container Services',
    shortName: 'SPCS',
    description: 'Single-container deployment (nginx + uvicorn) running the full-stack app inside Snowflake. OAuth token auto-injected at /snowflake/session/token. Zero external egress required.',
    tech: ['Docker', 'nginx', 'OAuth Token', 'Compute Pool', 'Image Registry'],
    stats: '1 container, port 8080',
    color: 'cyan',
  },
}

const svgIcons: Record<string, string> = {
  frontend: 'M21 3H3c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h18c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zm0 16H3V5h18v14zM5 15h14v2H5z',
  backend: 'M20 13H4c-.55 0-1 .45-1 1v6c0 .55.45 1 1 1h16c.55 0 1-.45 1-1v-6c0-.55-.45-1-1-1zM7 19c-1.1 0-2-.9-2-2s.9-2 2-2 2 .9 2 2-.9 2-2 2zM20 3H4c-.55 0-1 .45-1 1v6c0 .55.45 1 1 1h16c.55 0 1-.45 1-1V4c0-.55-.45-1-1-1zM7 9c-1.1 0-2-.9-2-2s.9-2 2-2 2 .9 2 2-.9 2-2 2z',
  agent: 'M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 18c-4.42 0-8-3.58-8-8 0-1.85.63-3.55 1.69-4.9L16.9 18.31C15.55 19.37 13.85 20 12 20zm6.31-3.1L7.1 5.69C8.45 4.63 10.15 4 12 4c4.42 0 8 3.58 8 8 0 1.85-.63 3.55-1.69 4.9z',
  analyst: 'M3 13h2v8H3v-8zm4-6h2v14H7V7zm4-4h2v18h-2V3zm4 8h2v10h-2V11zm4 4h2v6h-2v-6z',
  search: 'M15.5 14h-.79l-.28-.27C15.41 12.59 16 11.11 16 9.5 16 5.91 13.09 3 9.5 3S3 5.91 3 9.5 5.91 16 9.5 16c1.61 0 3.09-.59 4.23-1.57l.27.28v.79l5 4.99L20.49 19l-4.99-5z',
  actions: 'M13 3c-4.97 0-9 4.03-9 9H1l3.89 3.89.07.14L9 12H6c0-3.87 3.13-7 7-7s7 3.13 7 7-3.13 7-7 7c-1.93 0-3.68-.79-4.94-2.06l-1.42 1.42C8.27 19.99 10.51 21 13 21c4.97 0 9-4.03 9-9s-4.03-9-9-9z',
  snowflake: 'M12 2l-5.5 9h11L12 2zm0 3.84L13.93 9h-3.87L12 5.84zM17.5 13c-2.49 0-4.5 2.01-4.5 4.5s2.01 4.5 4.5 4.5 4.5-2.01 4.5-4.5-2.01-4.5-4.5-4.5zm0 7c-1.38 0-2.5-1.12-2.5-2.5s1.12-2.5 2.5-2.5 2.5 1.12 2.5 2.5-1.12 2.5-2.5 2.5zM3 21.5h8v-8H3v8zm2-6h4v4H5v-4z',
  spcs: 'M19.35 10.04C18.67 6.59 15.64 4 12 4 9.11 4 6.6 5.64 5.35 8.04 2.34 8.36 0 10.91 0 14c0 3.31 2.69 6 6 6h13c2.76 0 5-2.24 5-5 0-2.64-2.05-4.78-4.65-4.96z',
}

export function Architecture(_: NavCtx) {
  const [selectedComponent, setSelectedComponent] = useState<string | null>(null)
  const [hoveredFlow, setHoveredFlow] = useState<string | null>(null)

  const selectedInfo = selectedComponent ? components[selectedComponent] : null

  const getColorClasses = (color: string, isActive: boolean) => {
    const colors: Record<string, { fill: string; stroke: string; text: string; bg: string; border: string; textHex: string }> = {
      cyan:   { fill: isActive ? '#cffafe' : '#ecfeff', stroke: isActive ? '#22d3ee' : '#a5f3fc', textHex: '#0891b2', bg: isActive ? 'bg-cyan-100' : 'bg-cyan-50', border: 'border-cyan-200', text: 'text-cyan-600' },
      blue:   { fill: isActive ? '#dbeafe' : '#eff6ff', stroke: isActive ? '#60a5fa' : '#bfdbfe', textHex: '#2563eb', bg: isActive ? 'bg-blue-100' : 'bg-blue-50', border: 'border-blue-200', text: 'text-blue-600' },
      purple: { fill: isActive ? '#f3e8ff' : '#faf5ff', stroke: isActive ? '#c084fc' : '#e9d5ff', textHex: '#9333ea', bg: isActive ? 'bg-purple-100' : 'bg-purple-50', border: 'border-purple-200', text: 'text-purple-600' },
      green:  { fill: isActive ? '#d1fae5' : '#ecfdf5', stroke: isActive ? '#34d399' : '#a7f3d0', textHex: '#059669', bg: isActive ? 'bg-emerald-100' : 'bg-emerald-50', border: 'border-emerald-200', text: 'text-emerald-600' },
      yellow: { fill: isActive ? '#fef3c7' : '#fffbeb', stroke: isActive ? '#fbbf24' : '#fde68a', textHex: '#d97706', bg: isActive ? 'bg-amber-100' : 'bg-amber-50', border: 'border-amber-200', text: 'text-amber-600' },
      red:    { fill: isActive ? '#fee2e2' : '#fef2f2', stroke: isActive ? '#f87171' : '#fecaca', textHex: '#dc2626', bg: isActive ? 'bg-red-100' : 'bg-red-50', border: 'border-red-200', text: 'text-red-600' },
    }
    return colors[color] || colors.blue
  }

  const ComponentNode = ({ id, x, y }: { id: string; x: number; y: number }) => {
    const comp = components[id]
    const isActive = selectedComponent === id
    const colors = getColorClasses(comp.color, isActive)

    return (
      <g
        transform={`translate(${x}, ${y})`}
        onClick={() => setSelectedComponent(isActive ? null : id)}
        className="cursor-pointer"
      >
        {isActive && (
          <rect x="-4" y="-4" width="88" height="88" rx="14"
            fill="none" stroke="#E03C31" strokeWidth="2" strokeDasharray="4 2" opacity="0.6">
            <animate attributeName="stroke-dashoffset" values="0;-12" dur="1.5s" repeatCount="indefinite"/>
          </rect>
        )}
        <rect x="0" y="0" width="80" height="80" rx="12"
          fill={colors.fill} stroke={colors.stroke} strokeWidth="2"
          className="transition-all duration-300"
          style={{ filter: isActive ? 'drop-shadow(0 4px 12px rgba(224,60,49,0.2))' : 'none' }}
        />
        <foreignObject x="20" y="12" width="40" height="40">
          <div className="flex items-center justify-center w-full h-full">
            <svg viewBox="0 0 24 24" className="w-7 h-7"><path d={svgIcons[id]} fill={colors.textHex}/></svg>
          </div>
        </foreignObject>
        <text x="40" y="68" textAnchor="middle" className="text-[10px] font-semibold fill-gray-700">
          {comp.shortName}
        </text>
        <circle cx="70" cy="10" r="4" className="fill-emerald-400">
          <animate attributeName="opacity" values="1;0.4;1" dur="2s" repeatCount="indefinite"/>
        </circle>
      </g>
    )
  }

  const FlowLine = ({ from, to, label, curved = false }: { from: { x: number; y: number }; to: { x: number; y: number }; label?: string; curved?: boolean }) => {
    const isActive = hoveredFlow === label
    let path: string
    if (curved) {
      const midX = (from.x + to.x) / 2
      const midY = Math.min(from.y, to.y) - 30
      path = `M ${from.x} ${from.y} Q ${midX} ${midY} ${to.x} ${to.y}`
    } else {
      path = `M ${from.x} ${from.y} L ${to.x} ${to.y}`
    }

    return (
      <g onMouseEnter={() => setHoveredFlow(label || null)} onMouseLeave={() => setHoveredFlow(null)}>
        <path d={path} fill="none" stroke="#E03C31" strokeWidth={isActive ? 4 : 2} strokeOpacity={isActive ? 0.3 : 0.12} style={{ filter: isActive ? 'blur(3px)' : 'none' }}/>
        <path d={path} fill="none" stroke="#E03C31" strokeWidth="1.5" strokeDasharray="8 4" strokeOpacity={isActive ? 1 : 0.5}>
          <animate attributeName="stroke-dashoffset" values="0;-12" dur="1s" repeatCount="indefinite"/>
        </path>
        <circle cx={to.x} cy={to.y} r="3" fill="#E03C31" opacity="0.7">
          <animate attributeName="r" values="2;4;2" dur="1.5s" repeatCount="indefinite"/>
        </circle>
        {label && (
          <text x={(from.x + to.x) / 2} y={(from.y + to.y) / 2 - 8} textAnchor="middle" className={`text-[9px] ${isActive ? 'fill-apex-red' : 'fill-gray-400'}`}>
            {label}
          </text>
        )}
      </g>
    )
  }

  return (
    <div className="p-6 min-h-full overflow-y-auto bg-canvas-50">
      <div className="max-w-7xl mx-auto">
        <div className="mb-8">
          <h1 className="text-3xl font-bold text-apex-dark flex items-center gap-3">
            <div className="relative">
              <svg viewBox="0 0 24 24" className="w-8 h-8 text-apex-red"><path d="M13 3c-4.97 0-9 4.03-9 9H1l3.89 3.89.07.14L9 12H6c0-3.87 3.13-7 7-7s7 3.13 7 7-3.13 7-7 7c-1.93 0-3.68-.79-4.94-2.06l-1.42 1.42C8.27 19.99 10.51 21 13 21c4.97 0 9-4.03 9-9s-4.03-9-9-9z" fill="currentColor"/></svg>
              <div className="absolute inset-0 animate-ping opacity-20">
                <svg viewBox="0 0 24 24" className="w-8 h-8 text-apex-red"><path d="M13 3c-4.97 0-9 4.03-9 9H1l3.89 3.89.07.14L9 12H6c0-3.87 3.13-7 7-7s7 3.13 7 7-3.13 7-7 7c-1.93 0-3.68-.79-4.94-2.06l-1.42 1.42C8.27 19.99 10.51 21 13 21c4.97 0 9-4.03 9-9s-4.03-9-9-9z" fill="currentColor"/></svg>
              </div>
            </div>
            System Architecture
          </h1>
          <p className="text-canvas-500 mt-2">
            Interactive blueprint of the FieldIQ system. Click any component to learn more.
          </p>
        </div>

        <div className="grid grid-cols-5 gap-4 mb-8">
          {[
            { label: 'Agent Tools', value: '7', color: 'text-purple-600' },
            { label: 'Accounts', value: '120', color: 'text-emerald-600' },
            { label: 'Documents', value: '262', color: 'text-amber-600' },
            { label: 'Installed Assets', value: '506', color: 'text-blue-600' },
            { label: 'API Endpoints', value: '20+', color: 'text-cyan-600' },
          ].map((stat, i) => (
            <div key={i} className="bg-white border border-canvas-300 rounded-lg text-center py-4 shadow-sm">
              <p className={`text-2xl font-mono font-bold ${stat.color}`}>{stat.value}</p>
              <p className="text-[11px] text-canvas-500 mt-1 uppercase tracking-wide">{stat.label}</p>
            </div>
          ))}
        </div>

        <div className="bg-white border border-canvas-300 rounded-lg p-8 relative overflow-hidden shadow-sm">
          <div className="absolute inset-0 pointer-events-none" style={{
            backgroundImage: 'linear-gradient(rgba(224,60,49,0.02) 1px, transparent 1px), linear-gradient(90deg, rgba(224,60,49,0.02) 1px, transparent 1px)',
            backgroundSize: '40px 40px',
          }}/>

          <svg viewBox="0 0 1000 420" className="w-full h-auto relative" style={{ minHeight: '350px' }}>
            <text x="50" y="28" className="text-[11px] fill-gray-400 uppercase" style={{letterSpacing:'0.05em'}}>Presentation</text>
            <text x="240" y="28" className="text-[11px] fill-gray-400 uppercase" style={{letterSpacing:'0.05em'}}>API Layer</text>
            <text x="430" y="28" className="text-[11px] fill-gray-400 uppercase" style={{letterSpacing:'0.05em'}}>Orchestration</text>
            <text x="650" y="28" className="text-[11px] fill-gray-400 uppercase" style={{letterSpacing:'0.05em'}}>Tools</text>
            <text x="870" y="28" className="text-[11px] fill-gray-400 uppercase" style={{letterSpacing:'0.05em'}}>Data</text>

            <FlowLine from={{ x: 130, y: 200 }} to={{ x: 240, y: 200 }} label="HTTP/SSE" />
            <FlowLine from={{ x: 330, y: 200 }} to={{ x: 440, y: 200 }} label="REST" />
            <FlowLine from={{ x: 530, y: 160 }} to={{ x: 650, y: 120 }} label="Text-to-SQL" />
            <FlowLine from={{ x: 530, y: 200 }} to={{ x: 650, y: 200 }} label="Search" />
            <FlowLine from={{ x: 530, y: 240 }} to={{ x: 650, y: 290 }} label="CALL" />
            <FlowLine from={{ x: 740, y: 120 }} to={{ x: 860, y: 180 }} label="Query" />
            <FlowLine from={{ x: 740, y: 200 }} to={{ x: 860, y: 200 }} />
            <FlowLine from={{ x: 740, y: 290 }} to={{ x: 860, y: 220 }} />
            <FlowLine from={{ x: 940, y: 140 }} to={{ x: 500, y: 130 }} curved label="Response" />

            <ComponentNode id="frontend" x={50} y={160} />
            <ComponentNode id="backend" x={240} y={160} />
            <ComponentNode id="agent" x={440} y={160} />
            <ComponentNode id="analyst" x={650} y={80} />
            <ComponentNode id="search" x={650} y={160} />
            <ComponentNode id="actions" x={650} y={250} />
            <ComponentNode id="snowflake" x={860} y={160} />
            <ComponentNode id="spcs" x={440} y={310} />

            {[...Array(4)].map((_, i) => (
              <circle key={i} r="2.5" fill="#E03C31" opacity="0.7">
                <animateMotion dur={`${3 + i * 0.7}s`} repeatCount="indefinite" path="M 130 200 L 330 200 L 500 200 L 690 200 L 900 200"/>
                <animate attributeName="opacity" values="0;0.8;0.8;0" dur={`${3 + i * 0.7}s`} repeatCount="indefinite"/>
              </circle>
            ))}
          </svg>

          <div className="flex items-center justify-center gap-6 mt-4 text-[11px] text-canvas-500">
            <div className="flex items-center gap-2">
              <div className="w-8 h-0.5" style={{ backgroundImage: 'repeating-linear-gradient(90deg, #E03C31 0, #E03C31 8px, transparent 8px, transparent 12px)' }} />
              <span>Data Flow</span>
            </div>
            <div className="flex items-center gap-2">
              <div className="w-2 h-2 bg-emerald-400 rounded-full" style={{ boxShadow: '0 0 6px #10b981' }} />
              <span>Active</span>
            </div>
            <div className="flex items-center gap-2">
              <div className="w-3 h-3 border-2 border-apex-red/30 rounded" />
              <span>Click for details</span>
            </div>
          </div>
        </div>

        {selectedInfo && (
          <div className="fixed inset-0 bg-black/40 backdrop-blur-sm flex items-center justify-center p-4 z-50" onClick={() => setSelectedComponent(null)}>
            <div className="bg-white rounded-xl border border-canvas-300 max-w-lg w-full relative shadow-xl" onClick={e => e.stopPropagation()}>
              <button onClick={() => setSelectedComponent(null)} className="absolute top-4 right-4 p-2 rounded-lg hover:bg-canvas-100 transition-colors">
                <svg viewBox="0 0 24 24" className="w-5 h-5 text-canvas-500"><path d="M19 6.41L17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z" fill="currentColor"/></svg>
              </button>

              <div className="flex items-start gap-4 p-6 pb-0">
                <div className={`w-14 h-14 rounded-xl flex items-center justify-center ${getColorClasses(selectedInfo.color, true).bg}`}>
                  <svg viewBox="0 0 24 24" className={`w-7 h-7 ${getColorClasses(selectedInfo.color, true).text}`}><path d={svgIcons[selectedInfo.id]} fill="currentColor"/></svg>
                </div>
                <div>
                  <h3 className="text-xl font-bold text-apex-dark">{selectedInfo.name}</h3>
                  {selectedInfo.stats && <p className="text-sm text-apex-red font-mono">{selectedInfo.stats}</p>}
                </div>
              </div>

              <div className="px-6 pt-4">
                <p className="text-sm text-apex-dark leading-relaxed mb-6">{selectedInfo.description}</p>
                <div>
                  <p className="text-[10px] text-canvas-500 uppercase tracking-wider mb-2">Technologies</p>
                  <div className="flex flex-wrap gap-2">
                    {selectedInfo.tech.map((tech, i) => (
                      <span key={i} className="text-xs px-3 py-1.5 bg-apex-100 text-apex-red rounded-full border border-apex-200">
                        {tech}
                      </span>
                    ))}
                  </div>
                </div>
              </div>

              <div className="mt-6 mx-6 mb-6 pt-4 border-t border-canvas-200 flex items-center justify-between">
                <span className="text-[10px] text-canvas-500">Component ID: {selectedInfo.id}</span>
                <div className="flex items-center gap-2">
                  <div className="w-2 h-2 bg-emerald-400 rounded-full animate-pulse" />
                  <span className="text-[11px] text-emerald-600 font-medium">Online</span>
                </div>
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
