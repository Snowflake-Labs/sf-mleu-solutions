import axios from 'axios'
import type { AgentEvent } from '../types'

const api = axios.create({
  baseURL: '/api',
  headers: { 'Content-Type': 'application/json' },
})

// --- config ---
export const fetchConfig = () => api.get('/config').then(r => r.data)

// --- command ---
export const fetchRibbon = () => api.get('/command/ribbon').then(r => r.data)
export const fetchCuratedIssues = (limit = 10) =>
  api.get('/command/curated-issues', { params: { limit } }).then(r => r.data)
export const fetchImpacted = (dim: 'customers' | 'dealers' | 'facilities' | 'areas', issueId?: string) =>
  api.get(`/command/impacted/${dim}`, { params: issueId ? { issue_id: issueId } : {} }).then(r => r.data)
export const fetchTrend = () => api.get('/command/trend').then(r => r.data)

// --- issues ---
export const fetchIssues = (pillar?: string) =>
  api.get('/issues', { params: pillar ? { pillar } : {} }).then(r => r.data)
export const fetchIssue = (id: string) => api.get(`/issues/${id}`).then(r => r.data)
export const fetchIssueEvidence = (id: string) => api.get(`/issues/${id}/evidence`).then(r => r.data)
export const fetchIssueRisk = (id: string) => api.get(`/issues/${id}/risk`).then(r => r.data)
export const fetchIssueActions = (id: string) => api.get(`/issues/${id}/actions`).then(r => r.data)

// --- personas ---
export const fetchPersonaViews = (issueId: string) =>
  api.get(`/personas/issue/${issueId}`).then(r => r.data)

// --- customer archetype (customer-back) ---
export const fetchArchetypeReference = () =>
  api.get('/archetype/reference').then(r => r.data)
export const fetchArchetypeDistribution = () =>
  api.get('/archetype/distribution').then(r => r.data)
export const fetchArchetypeMix = (issueId: string) =>
  api.get(`/archetype/mix/${issueId}`).then(r => r.data)
export const fetchArchetypeRouting = (issueId: string) =>
  api.get(`/archetype/routing/${issueId}`).then(r => r.data)
export const fetchCustomerBack = (issueId: string) =>
  api.get(`/archetype/customer-back/${issueId}`).then(r => r.data)
export const fetchCustomerBackBoard = (pillar?: string, limit = 15) =>
  api.get('/archetype/customer-back-board', { params: { ...(pillar ? { pillar } : {}), limit } }).then(r => r.data)

// --- alerts ---
export const fetchAlerts = (pillar?: string) =>
  api.get('/alerts', { params: pillar ? { pillar } : {} }).then(r => r.data)
export const forwardAlert = (alertId: string, ownerId: string, actor: string, channel = 'IN_APP') =>
  api.post(`/alerts/${alertId}/forward`, { owner_id: ownerId, actor, channel }).then(r => r.data)
export const ackAlert = (alertId: string, actor: string) =>
  api.post(`/alerts/${alertId}/ack`, { actor }).then(r => r.data)

// --- actions / workflow ---
export const fetchRecommendedActions = (issueId: string) =>
  api.get(`/actions/recommended/${issueId}`).then(r => r.data)
export const fetchOpenWorkflow = () => api.get('/workflow/open').then(r => r.data)
export const fetchWorkflowTimeline = (id: string) =>
  api.get(`/workflow/${id}/timeline`).then(r => r.data)
export const fetchOwners = () => api.get('/owners').then(r => r.data)
export const fetchSlaBreaches = () => api.get('/sla/breaches').then(r => r.data)
export const transitionWorkflow = (id: string, toState: string, actor = 'app_user', note = '') =>
  api.post(`/workflow/${id}/transition`, { to_state: toState, actor, note }).then(r => r.data)
export const assignWorkflow = (id: string, ownerId: string, actor = 'app_user') =>
  api.post(`/workflow/${id}/assign`, { owner_id: ownerId, actor }).then(r => r.data)

// --- readiness ---
export const fetchDqChecks = () => api.get('/readiness/dq-checks').then(r => r.data)
export const fetchConfidence = () => api.get('/readiness/confidence').then(r => r.data)

// --- emerging ---
export const fetchEmergingSummary = () => api.get('/emerging/summary').then(r => r.data)
export const fetchEmergingSignals = () => api.get('/emerging/signals').then(r => r.data)
export const fetchEmergingSeries = (model: string, systemGroup: string) =>
  api.get('/emerging/series', { params: { model, system_group: systemGroup } }).then(r => r.data)

// --- explorer ---
export const fetchExplorerTables = (schema?: string) =>
  api.get('/explorer/tables', { params: schema ? { schema } : {} }).then(r => r.data)
export const fetchExplorerPreview = (schema: string, table: string) =>
  api.get('/explorer/preview', { params: { schema, table } }).then(r => r.data)

// --- Ask CQC SSE ---
export async function streamAsk(
  message: string,
  history: { role: string; content: string }[],
  persona: string | undefined,
  onEvent: (e: AgentEvent) => void,
): Promise<void> {
  const resp = await fetch('/api/agent/chat/stream', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ message, history, persona }),
  })
  if (!resp.body) return
  const reader = resp.body.getReader()
  const decoder = new TextDecoder()
  let buffer = ''
  while (true) {
    const { done, value } = await reader.read()
    if (done) break
    buffer += decoder.decode(value, { stream: true })
    let idx
    while ((idx = buffer.indexOf('\n\n')) !== -1) {
      const chunk = buffer.slice(0, idx).trim()
      buffer = buffer.slice(idx + 2)
      if (chunk.startsWith('data:')) {
        try {
          onEvent(JSON.parse(chunk.slice(5).trim()))
        } catch {
          /* ignore parse errors on keepalives */
        }
      }
    }
  }
}

// --- Review Board ---
// The debate runs ~2 minutes server-side, longer than the SPCS ingress reliably holds
// a streaming response open, so the client polls short requests for new events.
export async function streamDebate(
  question: string,
  issueId: string | undefined,
  onEvent: (e: any) => void,
): Promise<void> {
  const { run_id } = await api
    .post('/reviewboard/debate/start', { question, issue_id: issueId })
    .then(r => r.data)
  let next = 0
  let misses = 0
  // ~6 minutes ceiling; tolerate transient poll failures.
  for (let i = 0; i < 240; i++) {
    try {
      const r = await api
        .get(`/reviewboard/debate/${run_id}/events`, { params: { after: next } })
        .then(res => res.data)
      misses = 0
      for (const e of r.events) onEvent(e)
      next = r.next
      if (r.done) return
    } catch {
      if (++misses >= 5) throw new Error('Lost contact with the Review Board run')
    }
    await new Promise(res => setTimeout(res, 1500))
  }
}

export default api
