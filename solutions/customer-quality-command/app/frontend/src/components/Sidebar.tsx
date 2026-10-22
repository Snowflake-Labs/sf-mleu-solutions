import { NavLink, Link } from 'react-router-dom'
import {
  Bell, Radar, LayoutDashboard, Truck, FileSearch, Users,
  MessageSquare, ListChecks, Scale, ShieldCheck, GitBranch, Database,
  type LucideIcon,
} from 'lucide-react'
import Wordmark from './Wordmark'
import { BRAND } from '../config/brand'

interface NavItem { to: string; label: string; icon: LucideIcon }
interface NavGroup { title: string; items: NavItem[] }

const GROUPS: NavGroup[] = [
  {
    title: 'DETECT',
    items: [
      { to: '/alerts', label: 'Quality Alerts', icon: Bell },
      { to: '/emerging', label: 'Emerging Issues', icon: Radar },
    ],
  },
  {
    title: 'DIAGNOSE',
    items: [
      { to: '/command', label: 'Quality Command', icon: LayoutDashboard },
      { to: '/fleet', label: 'Impacted Fleet', icon: Truck },
      { to: '/issues', label: 'Issue Detail', icon: FileSearch },
      { to: '/personas', label: 'Persona Views', icon: Users },
    ],
  },
  {
    title: 'ACT',
    items: [
      { to: '/ask', label: `Ask ${BRAND.productShort}`, icon: MessageSquare },
      { to: '/tracker', label: 'Resolution Tracker', icon: ListChecks },
      { to: '/board', label: 'Review Board', icon: Scale },
    ],
  },
  {
    title: 'FOUNDATION',
    items: [
      { to: '/readiness', label: 'Data Readiness', icon: ShieldCheck },
      { to: '/explainability', label: 'Explainability', icon: GitBranch },
      { to: '/explorer', label: 'Data Explorer', icon: Database },
    ],
  },
]

export default function Sidebar() {
  return (
    <aside className="w-60 shrink-0 bg-brand-navy border-r border-brand-navy flex flex-col h-screen sticky top-0 text-white">
      <Link to="/" className="px-5 py-5 border-b border-white/10 block hover:bg-white/5 transition-colors">
        <Wordmark inverted />
      </Link>

      <nav className="flex-1 overflow-y-auto py-3">
        {GROUPS.map(group => (
          <div key={group.title} className="mb-4">
            <div className="px-5 py-1 text-[10px] font-semibold tracking-widest text-white/60">
              {group.title}
            </div>
            {group.items.map(item => {
              const Icon = item.icon
              return (
                <NavLink
                  key={item.to}
                  to={item.to}
                  className={({ isActive }) =>
                    `flex items-center gap-3 px-5 py-2 text-sm transition-colors border-l-[3px] ${
                      isActive
                        ? 'border-brand-accent bg-brand-primary text-white font-semibold'
                        : 'border-transparent text-white/85 hover:bg-white/10 hover:text-white'
                    }`
                  }
                >
                  <Icon size={16} />
                  {item.label}
                </NavLink>
              )
            })}
          </div>
        ))}
      </nav>

      <div className="px-5 py-3 border-t border-white/10 flex items-center gap-2 text-xs text-white/70">
        <span className="h-2 w-2 rounded-full bg-brand-accent animate-pulse-live" />
        {BRAND.productShort} Agent · live
      </div>
    </aside>
  )
}
