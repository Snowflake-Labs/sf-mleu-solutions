import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { BrowserRouter, Routes, Route } from 'react-router-dom'
import Sidebar from './components/Sidebar'
import Landing from './pages/Landing'
import QualityCommand from './pages/QualityCommand'
import QualityAlerts from './pages/QualityAlerts'
import EmergingIssues from './pages/EmergingIssues'
import ImpactedFleet from './pages/ImpactedFleet'
import IssueDetail from './pages/IssueDetail'
import PersonaViews from './pages/PersonaViews'
import AskAssistant from './pages/AskAssistant'
import ResolutionTracker from './pages/ResolutionTracker'
import ReviewBoard from './pages/ReviewBoard'
import DataReadiness from './pages/DataReadiness'
import Explainability from './pages/Explainability'
import DataExplorer from './pages/DataExplorer'
import { DemoProvider } from './demo/DemoContext'
import DirectorBar from './demo/DirectorBar'

const queryClient = new QueryClient({
  defaultOptions: { queries: { retry: false, refetchOnWindowFocus: false } },
})

function AppShell() {
  return (
    <div className="flex min-h-screen bg-brand-bg text-brand-text">
      <Sidebar />
      <main className="flex-1 min-w-0 flex flex-col">
        <Routes>
          <Route path="/command" element={<QualityCommand />} />
          <Route path="/alerts" element={<QualityAlerts />} />
          <Route path="/emerging" element={<EmergingIssues />} />
          <Route path="/fleet" element={<ImpactedFleet />} />
          <Route path="/issues" element={<IssueDetail />} />
          <Route path="/personas" element={<PersonaViews />} />
          <Route path="/ask" element={<AskAssistant />} />
          <Route path="/tracker" element={<ResolutionTracker />} />
          <Route path="/board" element={<ReviewBoard />} />
          <Route path="/readiness" element={<DataReadiness />} />
          <Route path="/explainability" element={<Explainability />} />
          <Route path="/explorer" element={<DataExplorer />} />
        </Routes>
      </main>
    </div>
  )
}

export default function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <BrowserRouter>
        <DemoProvider>
          <Routes>
            <Route path="/" element={<Landing />} />
            <Route path="/*" element={<AppShell />} />
          </Routes>
          <DirectorBar />
        </DemoProvider>
      </BrowserRouter>
    </QueryClientProvider>
  )
}
