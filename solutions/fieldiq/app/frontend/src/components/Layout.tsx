import React, { useState } from 'react'
import { Page } from '../App'

interface Props { currentPage: Page; onNavigate: (p: Page) => void; children: React.ReactNode }

const NAV: { id: Page; label: string; icon: string }[] = [
  { id: 'dashboard',    label: 'Sales Command Center', icon: 'M3 13h2v-2H3v2zm0 4h2v-2H3v2zm0-8h2V7H3v2zm4 4h14v-2H7v2zm0 4h14v-2H7v2zM7 7v2h14V7H7z' },
  { id: 'insights',     label: 'Insights',             icon: 'M3 13h2v8H3v-8zm4-6h2v14H7V7zm4-4h2v18h-2V3zm4 8h2v10h-2V11zm4 4h2v6h-2v-6z' },
  { id: 'map',          label: 'Customer Map',         icon: 'M20.5 3l-.16.03L15 5.1 9 3 3.36 4.9c-.21.07-.36.25-.36.48V20.5c0 .28.22.5.5.5l.16-.03L9 18.9l6 2.1 5.64-1.9c.21-.07.36-.25.36-.48V3.5c0-.28-.22-.5-.5-.5zM15 19l-6-2.11V5l6 2.11V19z' },
  { id: 'account',      label: 'Account 360',          icon: 'M12 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z' },
  { id: 'knowledge',    label: 'Knowledge & Catalog',  icon: 'M21 5c-1.11-.35-2.33-.5-3.5-.5-1.95 0-4.05.4-5.5 1.5-1.45-1.1-3.55-1.5-5.5-1.5S2.45 4.9 1 6v14.65c0 .25.25.5.5.5.1 0 .15-.05.25-.05C3.1 20.45 5.05 20 6.5 20c1.95 0 4.05.4 5.5 1.5 1.35-.85 3.8-1.5 5.5-1.5 1.65 0 3.35.3 4.75 1.05.1.05.15.05.25.05.25 0 .5-.25.5-.5V6c-.6-.45-1.25-.75-2-1z' },
  { id: 'architecture', label: 'Architecture',         icon: 'M12 3 1 9l4 2.18v6L12 21l7-3.82v-6l2-1.09V17h2V9L12 3zm6.82 6L12 12.72 5.18 9 12 5.28 18.82 9zM17 15.99l-5 2.73-5-2.73v-3.72L12 15l5-2.73v3.72z' },
]

export function Layout({ currentPage, onNavigate, children }: Props) {
  const [collapsed, setCollapsed] = useState(false)

  return (
    <div className="h-full flex bg-canvas-100 text-apex-dark">
      {/* Sidebar */}
      <aside className={`${collapsed ? 'w-16' : 'w-60'} transition-all duration-200 bg-white border-r border-canvas-300 flex flex-col`}>
        {/* Brand */}
        <div className="relative h-16 border-b border-canvas-300 flex items-center px-3 overflow-hidden">
          <div className="apex-corner absolute top-0 left-0 w-12 h-10" />
          {!collapsed && (
            <div className="ml-14">
              <div className="font-bold tracking-tight text-apex-dark text-base leading-none">FIELDIQ</div>
              <div className="text-[10px] text-apex-gray uppercase tracking-wider">by Apex Industrial</div>
            </div>
          )}
        </div>

        {/* Nav */}
        <nav className="flex-1 py-4 space-y-1 px-2">
          {NAV.map(n => {
            const active = currentPage === n.id
            return (
              <button key={n.id} onClick={() => onNavigate(n.id)}
                className={`w-full flex items-center gap-3 px-3 py-2 rounded-md text-sm transition-colors ${
                  active ? 'bg-apex-100 text-apex-red font-semibold' : 'text-apex-dark hover:bg-canvas-100'
                }`}>
                <svg className={`w-5 h-5 flex-shrink-0 ${active ? 'fill-apex-red' : 'fill-apex-gray'}`} viewBox="0 0 24 24"><path d={n.icon}/></svg>
                {!collapsed && <span>{n.label}</span>}
              </button>
            )
          })}
        </nav>

        {/* Collapse */}
        <button onClick={() => setCollapsed(c => !c)}
                className="m-2 px-3 py-2 text-xs text-apex-gray hover:text-apex-red border-t border-canvas-300 self-stretch">
          {collapsed ? '›' : '‹ Collapse'}
        </button>
      </aside>

      {/* Main */}
      <div className="flex-1 flex flex-col min-w-0">
        {/* Topbar */}
        <header className="h-16 bg-white border-b border-canvas-300 px-6 flex items-center justify-between">
          <div className="flex items-center gap-3">
            <button onClick={() => onNavigate('landing')}
                    className="text-sm text-apex-gray hover:text-apex-red">← Home</button>
            <div className="w-px h-5 bg-canvas-300" />
            <div className="text-sm font-medium text-apex-dark">{NAV.find(n => n.id === currentPage)?.label || ''}</div>
          </div>
          <div className="flex items-center gap-3">
            <span className="text-xs px-2 py-0.5 bg-apex-100 text-apex-red rounded font-medium">DEMO</span>
            <span className="text-sm text-apex-gray">Apex Industrial / FieldIQ v1.0</span>
          </div>
        </header>

        <main className="flex-1 overflow-auto">{children}</main>
      </div>
    </div>
  )
}
