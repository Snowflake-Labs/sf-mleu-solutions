import { useState } from 'react'
import { Layout } from './components/Layout'
import { Landing, Dashboard, Account360, Knowledge, Architecture, Insights, CustomerMap } from './pages'

export type Page = 'landing' | 'dashboard' | 'insights' | 'map' | 'account' | 'knowledge' | 'architecture'

export interface NavCtx {
  onNavigate: (p: Page) => void
  selectedAccountId: string | null
  setSelectedAccountId: (id: string | null) => void
  prefillPrompt: string | null
  setPrefillPrompt: (s: string | null) => void
}

export default function App() {
  const [page, setPage] = useState<Page>('landing')
  const [selectedAccountId, setSelectedAccountId] = useState<string | null>(null)
  const [prefillPrompt, setPrefillPrompt] = useState<string | null>(null)

  const ctx: NavCtx = { onNavigate: setPage, selectedAccountId, setSelectedAccountId, prefillPrompt, setPrefillPrompt }

  if (page === 'landing') return <Landing {...ctx} />

  const inner = (() => {
    switch (page) {
      case 'dashboard':    return <Dashboard {...ctx} />
      case 'insights':     return <Insights />
      case 'map':          return <CustomerMap />
      case 'account':      return <Account360 {...ctx} />
      case 'knowledge':    return <Knowledge {...ctx} />
      case 'architecture': return <Architecture {...ctx} />
      default:             return <Dashboard {...ctx} />
    }
  })()

  return <Layout currentPage={page} onNavigate={setPage}>{inner}</Layout>
}
