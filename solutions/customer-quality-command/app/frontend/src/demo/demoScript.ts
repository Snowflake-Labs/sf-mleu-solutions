// CQC Story Mode — the entire guided narrative as data.
// Editing this file re-scripts the executive demo. Nothing else needs to change.
//
// Anchor issues are derived at build time from config/brand.ts ANCHOR
// (see vite.config.ts): MD5(model|system_group_cd|failure_mode_cd).
//   SAFETY  = Sudden Shutdown on the anchor fuel system (safety-gated, VTC $0)
//   MONEY   = Power Loss / Derate on the anchor fuel system (LOT root cause)
import { ANCHOR, BRAND } from '../config/brand'

export const SAFETY_ISSUE = __STORY_SAFETY_ISSUE__
export const MONEY_ISSUE = __STORY_MONEY_ISSUE__
const PRODUCT = BRAND.productShort

export interface DemoStep {
  id: string
  act: string
  chapter: string
  theme: string          // the "speed" theme this beat proves
  path: string           // full route incl. query params — Story Mode navigates here
  caption: string        // the narration line shown in the Director Bar
  spotlight?: string      // data-spotlight key of the element to highlight
  hold?: boolean          // true = live/long step; auto-play will NOT advance on a timer
  dwellMs?: number        // auto-play dwell before advancing (ignored if hold)
  prewarm?: string[]      // /api paths to warm before the NEXT step lands
}

const P = (id: string) =>
  [`/issues/${id}`, `/issues/${id}/risk`, `/issues/${id}/actions`, `/issues/${id}/evidence`]

export const DEMO_STEPS: DemoStep[] = [
  {
    id: 'signal',
    act: 'Act I',
    chapter: 'The Signal',
    theme: 'Detect',
    path: `/emerging?model=${ANCHOR.model}&sg=${ANCHOR.systemGroup}`,
    caption:
      `${PRODUCT} sees it first. ${ANCHOR.model} fuel-system faults break trend — EWMA, CUSUM and a change-point all fire. No one filed a report yet.`,
    spotlight: 'emerging-trend',
    dwellMs: 11000,
    prewarm: P(SAFETY_ISSUE),
  },
  {
    id: 'safety-first',
    act: 'Act II',
    chapter: 'Safety First',
    theme: 'Customer-Back Prioritization',
    path: `/issues?issue=${SAFETY_ISSUE}`,
    caption:
      `A sudden-shutdown safety risk. Its dollar value is $0 — yet ${PRODUCT} ranks it above a multi-million-dollar issue. Safety outranks cost, by design.`,
    spotlight: 'issue-stats',
    dwellMs: 13000,
    prewarm: P(MONEY_ISSUE),
  },
  {
    id: 'money',
    act: 'Act III',
    chapter: 'The Money',
    theme: 'Diagnose',
    path: `/issues?issue=${MONEY_ISSUE}`,
    caption:
      `Same fuel system, the productivity story: the likely, plan-for and bad-case exposure, traced to injector lot ${ANCHOR.badLot} built at ${ANCHOR.plant}. Monte-Carlo, not a guess.`,
    spotlight: 'issue-exposure',
    dwellMs: 13000,
    prewarm: [`/archetype/mix/${MONEY_ISSUE}`, `/archetype/routing/${MONEY_ISSUE}`, `/archetype/customer-back/${MONEY_ISSUE}`],
  },
  {
    id: 'archetype',
    act: 'Act IV',
    chapter: 'One Defect, Four Customers',
    theme: 'Customer-Back · What Quality Means to the Customer',
    path: `/issues?issue=${MONEY_ISSUE}`,
    caption:
      'The same exposure is not felt equally. Independent operators are a minority of the exposed fleet but bear most of the felt pain — and each tier is reached through a different channel: account team, account manager, dealer, service counter.',
    spotlight: 'issue-archetype',
    dwellMs: 15000,
    prewarm: ['/command/curated-issues?limit=15'],
  },
  {
    id: 'ask',
    act: 'Act V',
    chapter: `Ask ${PRODUCT}`,
    theme: 'Insight · months → seconds',
    path:
      `/ask?issue=${MONEY_ISSUE}&ask=` +
      encodeURIComponent(
        `For the ${ANCHOR.model} fuel-system power-loss issue: quantify the warranty exposure, confirm whether it is a contained lot or systemic, and recommend the action for the next 72 hours.`,
      ),
    caption:
      `Ask ${PRODUCT} — in plain English. It reasons over the grounded medallion, runs the SQL live, and returns an executive answer with a recommended containment.`,
    spotlight: 'ask-thread',
    hold: true,
  },
  {
    id: 'board',
    act: 'Act VI',
    chapter: 'The Review Board',
    theme: 'Defensible Rigor',
    path: `/board?issue=${MONEY_ISSUE}&convene=1`,
    caption:
      'Three AI board members — Reliability, Field, Risk — debate the call with real numbers, challenge each other, and converge on a recommendation.',
    spotlight: 'board-live',
    hold: true,
  },
  {
    id: 'close',
    act: 'Act VII',
    chapter: 'The Close',
    theme: 'Act · Closed Loop',
    path: `/tracker?focus=${SAFETY_ISSUE}`,
    caption:
      `The ${ANCHOR.model} safety item — detected, acknowledged, assigned to an owner, resolved and audited against its SLA. This is the loop closing end-to-end.`,
    spotlight: 'tracker-focus',
    dwellMs: 13000,
    prewarm: [`/personas/issue/${MONEY_ISSUE}`],
  },
  {
    id: 'personas',
    act: 'Act VIII',
    chapter: 'One Truth, Five Personas',
    theme: 'One Foundation',
    path: `/personas?issue=${MONEY_ISSUE}`,
    caption:
      'One customer pain point becomes five decision surfaces — Dealer, Product, Manufacturing, Supply Chain, Executive — from a single source of truth.',
    spotlight: 'persona-cards',
    dwellMs: 14000,
  },
]
