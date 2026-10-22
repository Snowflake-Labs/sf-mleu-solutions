export type Pillar = 'SAFETY' | 'PRODUCTIVITY' | 'EXPERIENCE'
export type Persona = 'dealer' | 'product' | 'manufacturing' | 'supply_chain' | 'executive'

export interface AppConfig {
  app: string
  subtitle: string
  database: string
  agent: string
  anchor_machine: string
  spcs: boolean
  personas: Persona[]
}

export interface Issue {
  issue_id: string
  title: string
  pillar: Pillar
  severity: string
  status: string
  exposure_p90?: number
  units_impacted?: number
  priority_rank?: number
}

export interface RibbonMetric {
  pillar: string
  status: string
  headline_metric: string
  delta?: string
}

export interface AlertItem {
  alert_id: string
  issue_id: string
  pillar: Pillar
  severity: string
  title: string
  body?: string
  workflow_state?: string
  units_impacted?: number
  data_confidence?: string
  created_ts?: string
}

// SSE agent event (matches CortexAgentClient parse output)
export interface AgentEvent {
  type: 'status' | 'thinking' | 'text' | 'tool_status' | 'tool_result' | 'chart' | 'error' | 'done'
  title?: string
  content?: string
  status?: string
  sql?: string
  data?: unknown
  chart_spec?: Record<string, unknown>
  search_results?: unknown
}
