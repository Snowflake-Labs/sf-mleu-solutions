"""CQC Quality Review Board — 3-agent adversarial debate engine.

Superforecaster-style review board for the customer-quality domain.
Three board members debate a quality-response decision (e.g. contain-lot vs field
campaign), each with their own Snowflake connection, grounded data fetch, and
SNOWFLAKE.CORTEX.COMPLETE reasoning. Emits SSE events consumed by ReviewBoard.tsx.
"""

import asyncio
import json
import os
import sys
import time
from collections.abc import AsyncGenerator
from enum import Enum

from config import COMPANY_NAME, DATABASE, INSIGHTS, ML, WAREHOUSE, get_connection
from pydantic import BaseModel
from snowflake.connector import DictCursor

LLM_MODEL = os.getenv("REVIEW_BOARD_MODEL", "claude-sonnet-4-6")


def _log(msg: str):
    print(f"[REVIEWBOARD {time.strftime('%H:%M:%S')}] {msg}", flush=True, file=sys.stderr)


class DebateState(Enum):
    """Debate state."""

    DECOMPOSING = "decomposing"
    RESEARCHING = "researching"
    ANALYZING = "analyzing"
    DEBATING = "debating"
    SYNTHESIZING = "synthesizing"
    COMPLETE = "complete"


class DebateRequest(BaseModel):
    """Request body: debate request."""

    question: str
    issue_id: str | None = None


AGENTS = {
    "reliability": {"name": "Reliability Engineer", "style": "Failure Physics", "color": "#3B82F6"},
    "field": {"name": "Field & Customer Advocate", "style": "Customer Pain", "color": "#EF4444"},
    "risk": {"name": "Risk & Cost Officer", "style": "Financial Exposure", "color": "#F59E0B"},
}

RELIABILITY_SYSTEM_PROMPT = """You are the RELIABILITY ENGINEER on {company}'s Quality Review Board.

You reason from failure physics: Weibull reliability parameters, MTBF, root-cause attribution,
lot/supplier concentration, and emerging-issue detectors. You care about whether a defect is a
genuine design/lot problem versus statistical noise, how fast it will propagate through the fleet,
and whether containment addresses the true root cause.

VOICE: precise, evidence-driven, quantitative. You cite beta/eta, z-scores, lift, MTBF, and
changepoint timing. You distrust action that does not match the physical failure mechanism.

DEBATE BEHAVIOR: challenge claims that ignore the root-cause evidence or over/under-react relative
to the statistical strength of the signal. Use ONLY the data in your briefing.""".replace("{company}", COMPANY_NAME)

FIELD_SYSTEM_PROMPT = """You are the FIELD & CUSTOMER ADVOCATE on {company}'s Quality Review Board.

You represent the customer and dealer. You reason from safety exposure (SIP), downtime,
impacted customers/fleet, NPS/experience, and the operational pain of machines-down. Safety of
human life is your non-negotiable first priority; customer trust is second.

VOICE: urgent, human-centered, but grounded in the numbers (exposed fleet, impacted customers,
SIP risk, downtime). You push for the fastest action that protects people and uptime.

DEBATE BEHAVIOR: challenge positions that trade customer safety or uptime for cost savings, or that
move too slowly given the exposed population. Use ONLY the data in your briefing.""".replace("{company}", COMPANY_NAME)

RISK_SYSTEM_PROMPT = """You are the RISK & COST OFFICER on {company}'s Quality Review Board.

You reason from financial exposure: Monte-Carlo warranty exposure (likely / plan-for / bad-case), value-to-cost,
containment cost vs field-campaign cost, and the probability-weighted downside. You steward the
division's resources and insist on proportionate, defensible spend.

VOICE: measured, probabilistic, cost-disciplined. You cite likely, plan-for and bad-case dollar figures and weigh
the cost of action against the cost of inaction. You never ignore tail risk.

DEBATE BEHAVIOR: challenge positions that spend disproportionately relative to exposure, or that
ignore the bad-case tail. Use ONLY the data in your briefing.""".replace("{company}", COMPANY_NAME)

# Plain-language exposure vocabulary, shared by every board prompt so the debate never
# surfaces percentile jargon to the audience.
PLAIN_EXPOSURE = """LANGUAGE: describe financial exposure ONLY as "likely exposure" (central estimate),
"plan-for exposure" (the figure to budget; 9-in-10 chance it is not exceeded) and "bad-case exposure"
(average of the worst 1-in-20 outcomes). Never write P50, P90, CVaR, percentile or value-at-risk."""

DECOMPOSITION_PROMPT = """You are decomposing a quality-response decision for the {company} review board.
Break the question into 3-4 sub-questions the board must resolve (root-cause certainty, exposed
population & safety, financial exposure, and the response options). Respond in EXACTLY this JSON
(no markdown, no backticks):
{
  "original_question": "...",
  "sub_questions": ["...", "..."],
  "decision_options": ["contain lot", "field service campaign", "monitor"],
  "key_metrics": ["sip_risk", "plan_for_exposure_usd", "root_cause_z"]
}""".replace("{company}", COMPANY_NAME)

CHALLENGE_PROMPT_TEMPLATE = """You are the {agent_name}. You have read the initial positions of all three board members.
Identify the SINGLE strongest point of disagreement and make a specific, data-backed challenge —
the claim that, if wrong, would most change the board's decision.
Rules: pick ONE claim; cite numbers from your briefing; be specific; 250 words max."""

RESPONSE_PROMPT_TEMPLATE = """You are the {agent_name}. Another board member challenged your position.
Respond with exactly ONE action, starting with the action word:
- CONCEDE: "You're right. I'm updating because [reason with data]."
- REBUT: "That doesn't hold because [counter-evidence with data]."
- UPDATE: "I partially agree. I'm adjusting because [reason]."
200 words max."""

FINAL_POSITION_PROMPT_TEMPLATE = """You are the {agent_name}. The debate is concluding. Give your FINAL position.
Respond in EXACTLY this JSON (no markdown, no backticks):
{{
  "agent": "{agent_id}",
  "recommended_option": "contain lot | field service campaign | monitor",
  "confidence": N,
  "what_changed": "one sentence",
  "remaining_uncertainty": "one sentence",
  "key_insight": "one sentence"
}}"""

DISAGREEMENT_PROMPT = """You are tracking disagreement between three {company} quality board members.
Read their exchange and output EXACTLY this JSON (no markdown, no backticks):
{
  "recommendations": {"reliability": "option", "field": "option", "risk": "option"},
  "disagreements": [
    {"topic": "short_label", "reliability": "pos", "field": "pos", "risk": "pos",
     "magnitude": "HIGH|MEDIUM|LOW", "trend": "NARROWING|STABLE|WIDENING"}
  ],
  "convergence_score": 0.0
}
convergence_score: 0.0 = complete disagreement, 1.0 = full consensus on the response option.""".replace(
    "{company}", COMPANY_NAME
)

BOARD_BRIEF_PROMPT = (
    """You are the Quality Review Board recorder. Read the debate between the Reliability
Engineer, Field & Customer Advocate, and Risk & Cost Officer, and produce a decision brief for the
Division Quality Sponsor. Use this EXACT structure:

QUALITY REVIEW BOARD BRIEF: [issue]

RECOMMENDED RESPONSE
Decision: [contain lot | field service campaign | monitor]
Confidence: [HIGH|MODERATE|LOW] — [one sentence why]

BOARD AGREEMENT
+ [point]
+ [point]

OPEN DISAGREEMENT (SPONSOR SHOULD RESOLVE)
! [topic]
  Reliability: [pos] | Field: [pos] | Risk: [pos]

TRADE-OFF
Act now: [cost] → [risk reduction]
Wait: [saving] → [downside / tail risk]

THE ONE QUESTION THE SPONSOR MUST ANSWER
"[question]"

Be specific. Use the numbers from the debate (SIP, exposed fleet, plan-for / bad-case exposure $, root-cause z).
Safety of human life outranks cost. Do not hedge.

"""
    + PLAIN_EXPOSURE
)


def _run_query(sql: str, params=None, conn=None) -> list:
    import datetime
    import decimal

    owns = conn is None
    if owns:
        conn = get_connection()
    try:
        cur = conn.cursor(DictCursor)
        cur.execute(f"USE DATABASE {DATABASE}")
        cur.execute(f"USE WAREHOUSE {WAREHOUSE}")
        cur.execute(sql, params) if params else cur.execute(sql)
        rows = cur.fetchall()
        cur.close()
        out = []
        for row in rows:
            clean = {}
            for k, v in row.items():
                if isinstance(v, decimal.Decimal):
                    clean[k] = float(v)
                elif isinstance(v, datetime.date | datetime.datetime):
                    clean[k] = v.isoformat()
                else:
                    clean[k] = v
            out.append(clean)
        return out
    finally:
        if owns:
            conn.close()


MAX_PROMPT_CHARS = 24000


def _truncate_position(text: str, max_chars: int = 1800) -> str:
    return text if len(text) <= max_chars else text[:max_chars] + "\n[... truncated ...]"


def _truncate_prompt(prompt: str) -> str:
    if len(prompt) <= MAX_PROMPT_CHARS:
        return prompt
    half = MAX_PROMPT_CHARS // 2
    return prompt[:half] + "\n\n[... middle truncated ...]\n\n" + prompt[-half:]


def _llm_call(prompt: str, conn=None, timeout_seconds: int = 90, label: str = "unknown") -> str:
    prompt = _truncate_prompt(prompt)
    t0 = time.time()
    owns = conn is None
    if owns:
        conn = get_connection()
    try:
        cur = conn.cursor(DictCursor)
        cur.execute(f"USE DATABASE {DATABASE}")
        cur.execute(f"USE WAREHOUSE {WAREHOUSE}")
        cur.execute(f"ALTER SESSION SET STATEMENT_TIMEOUT_IN_SECONDS = {timeout_seconds}")
        cur.execute("SELECT SNOWFLAKE.CORTEX.COMPLETE(%s, %s) AS RESPONSE", (LLM_MODEL, prompt))
        result = cur.fetchone()
        cur.close()
        resp = result["RESPONSE"] if result else ""
        _log(f"LLM done label={label} elapsed={time.time() - t0:.1f}s len={len(resp)}")
        return resp
    except Exception as e:
        _log(f"LLM error label={label} err={e}")
        if "timeout" in str(e).lower() or "cancel" in str(e).lower():
            return f"[{label} timed out]"
        raise
    finally:
        if owns:
            conn.close()


async def _safe_llm_call(prompt: str, conn=None, timeout: int = 90, label: str = "unknown") -> str:
    try:
        return await asyncio.wait_for(
            asyncio.to_thread(_llm_call, prompt, conn=conn, timeout_seconds=timeout, label=label),
            timeout=timeout + 15,
        )
    except TimeoutError:
        return f"[{label} timed out after {timeout}s]"


def _issue_filter(issue_id):
    return (" WHERE issue_id = %s", (issue_id,)) if issue_id else ("", None)


def _fmt(rows) -> str:
    return json.dumps(rows, default=str, indent=1)


def fetch_reliability_data(issue_id=None, conn=None) -> str:
    """Fetch reliability data."""
    w, p = _issue_filter(issue_id)
    issue = _run_query(
        "SELECT issue_id, title, model, system_group, failure_mode, root_cause_type, "
        "root_cause_summary, root_cause_confidence, mtbf, mttr, exposed_fleet_count "
        f"FROM {INSIGHTS}.INSIGHT_ISSUE" + w + " ORDER BY priority_rank LIMIT 1",
        p,
        conn,
    )
    rc = _run_query(
        "SELECT attribution_type, supplier_id, build_facility_cd, lift, z_score, is_significant, "
        "is_suspect_seed, failures_with_attr, fleet_with_attr "
        f"FROM {ML}.ROOT_CAUSE_ATTRIBUTION" + w + " ORDER BY z_score DESC NULLS LAST LIMIT 6",
        p,
        conn,
    )
    return f"RELIABILITY BRIEFING\nISSUE:\n{_fmt(issue)}\nROOT-CAUSE ATTRIBUTION:\n{_fmt(rc)}"


def fetch_field_data(issue_id=None, conn=None) -> str:
    """Fetch field data."""
    w, p = _issue_filter(issue_id)
    issue = _run_query(
        "SELECT issue_id, title, quality_dimension, pro_sif_risk AS sip_risk, sif_rate AS sip_rate, "
        "nps_delta, cei_score, impacted_customer_count, impacted_dealer_count, exposed_fleet_count, geography_top "
        f"FROM {INSIGHTS}.INSIGHT_ISSUE" + w + " ORDER BY priority_rank LIMIT 1",
        p,
        conn,
    )
    cust = _run_query(
        f"SELECT entity_name, exposure_count, geo FROM {INSIGHTS}.INSIGHT_IMPACTED_CUSTOMERS"
        + w
        + " ORDER BY exposure_count DESC LIMIT 8",
        p,
        conn,
    )
    return f"FIELD & CUSTOMER BRIEFING\nISSUE:\n{_fmt(issue)}\nTOP IMPACTED CUSTOMERS:\n{_fmt(cust)}"


def fetch_risk_data(issue_id=None, conn=None) -> str:
    """Fetch risk data."""
    w, p = _issue_filter(issue_id)
    issue = _run_query(
        "SELECT issue_id, title, vtc_usd, vtc_p50 AS vtc_likely_usd, vtc_p90 AS vtc_plan_for_usd, "
        "warranty_exposure_p50 AS likely_exposure_usd, warranty_exposure_p90 AS plan_for_exposure_usd, "
        f"warranty_exposure_cvar AS bad_case_exposure_usd, exposed_fleet_count FROM {INSIGHTS}.INSIGHT_ISSUE"
        + w
        + " ORDER BY priority_rank LIMIT 1",
        p,
        conn,
    )
    exp = _run_query(
        "SELECT exposed_fleet, p_fail_forward, exposure_mean, exposure_p50 AS likely_exposure_usd, "
        "exposure_p90 AS plan_for_exposure_usd, exposure_cvar95 AS bad_case_exposure_usd, "
        f"copula, n_sims FROM {ML}.EXPOSURE_SIMULATION" + w + " LIMIT 1",
        p,
        conn,
    )
    return f"RISK & COST BRIEFING\nISSUE:\n{_fmt(issue)}\nEXPOSURE SIMULATION (Monte-Carlo):\n{_fmt(exp)}"


FETCHERS = {"reliability": fetch_reliability_data, "field": fetch_field_data, "risk": fetch_risk_data}
ORDER = ["reliability", "field", "risk"]


class ReviewBoardOrchestrator:
    """Review board orchestrator."""

    def __init__(self, question: str, issue_id: str | None = None):
        self.question = question
        self.issue_id = issue_id
        self.decomposition = None
        self.agent_data = {}
        self.positions = {}
        self.transcript = []
        self.disagreements = []

    def _sys(self, agent_id: str) -> str:
        return (
            {"reliability": RELIABILITY_SYSTEM_PROMPT, "field": FIELD_SYSTEM_PROMPT, "risk": RISK_SYSTEM_PROMPT}[
                agent_id
            ]
            + "\n\n"
            + PLAIN_EXPOSURE
        )

    async def run_debate(self) -> AsyncGenerator[dict, None]:
        """Run debate."""
        conns = [get_connection() for _ in range(3)]
        try:
            async for ev in self._inner(conns):
                yield ev
        finally:
            for c in conns:
                try:
                    c.close()
                except Exception:
                    pass

    async def _inner(self, conns) -> AsyncGenerator[dict, None]:
        cmap = {ORDER[i]: conns[i] for i in range(3)}

        yield {"type": "agents", "data": AGENTS}
        yield {"type": "phase", "phase": "decomposing"}
        decomp = await _safe_llm_call(
            f"{DECOMPOSITION_PROMPT}\n\nQuestion: {self.question}",
            conn=cmap["reliability"],
            timeout=60,
            label="decomposition",
        )
        try:
            s, e = decomp.find("{"), decomp.rfind("}") + 1
            self.decomposition = json.loads(decomp[s:e])
        except Exception:
            self.decomposition = {
                "original_question": self.question,
                "sub_questions": [self.question],
                "decision_options": ["contain lot", "field campaign", "monitor"],
            }
        yield {"type": "decomposition", "data": self.decomposition}

        yield {"type": "phase", "phase": "researching"}
        data = await asyncio.gather(*[asyncio.to_thread(FETCHERS[a], self.issue_id, cmap[a]) for a in ORDER])
        self.agent_data = {ORDER[i]: data[i] for i in range(3)}
        for a in ORDER:
            yield {"type": "research", "agent": a, "data": f"{len(self.agent_data[a])} chars gathered"}

        yield {"type": "phase", "phase": "analyzing"}
        subq = "\n".join(f"  {i + 1}. {q}" for i, q in enumerate(self.decomposition.get("sub_questions", [])))
        pos_prompts = {
            a: f"{self._sys(a)}\n\n{self.agent_data[a]}\n\nQUESTION: {self.question}\n\n"
            f"SUB-QUESTIONS:\n{subq}\n\nProvide your initial position (250 words max). "
            f"End with your recommended response option and confidence 0-100."
            for a in ORDER
        }
        res = await asyncio.gather(
            *[_safe_llm_call(pos_prompts[a], conn=cmap[a], timeout=120, label=f"pos_{a}") for a in ORDER]
        )
        for i, a in enumerate(ORDER):
            self.positions[a] = {"round_0": res[i]}
            self.transcript.append({"agent": a, "round": 0, "type": "position", "text": res[i]})
            yield {"type": "position", "agent": a, "round": 0, "text": res[i]}

        yield {"type": "phase", "phase": "debating"}
        all_pos = "\n\n".join(
            f"--- {AGENTS[a]['name'].upper()} POSITION ---\n{_truncate_position(self.positions[a]['round_0'])}"
            for a in ORDER
        )
        ch_prompts = {
            a: f"{self._sys(a)}\n\n{self.agent_data[a][:2500]}\n\nALL POSITIONS:\n{all_pos}\n\n"
            f"{CHALLENGE_PROMPT_TEMPLATE.format(agent_name=AGENTS[a]['name'])}"
            for a in ORDER
        }
        ch = await asyncio.gather(
            *[_safe_llm_call(ch_prompts[a], conn=cmap[a], timeout=90, label=f"ch_{a}") for a in ORDER]
        )
        for i, a in enumerate(ORDER):
            self.transcript.append({"agent": a, "round": 1, "type": "challenge", "text": ch[i]})
            yield {"type": "challenge", "agent": a, "round": 1, "text": ch[i]}

        dis = await self._disagreements(1, cmap["reliability"])
        self.disagreements.append(dis)
        yield {"type": "disagreement", "round": 1, "data": dis}

        # responses
        resp_prompts = {}
        for a in ORDER:
            at_me = [t for t in self.transcript if t["round"] == 1 and t["type"] == "challenge" and t["agent"] != a]
            ctext = "\n\n".join(
                f"--- {AGENTS[t['agent']]['name'].upper()} CHALLENGES YOU ---\n{_truncate_position(t['text'], 1200)}"
                for t in at_me
            )
            resp_prompts[a] = (
                f"{self._sys(a)}\n\nYOUR POSITION:\n"
                f"{_truncate_position(self.positions[a]['round_0'], 1500)}\n\n"
                f"CHALLENGES:\n{ctext}\n\n{RESPONSE_PROMPT_TEMPLATE.format(agent_name=AGENTS[a]['name'])}"
            )
        rr = await asyncio.gather(
            *[_safe_llm_call(resp_prompts[a], conn=cmap[a], timeout=90, label=f"resp_{a}") for a in ORDER]
        )
        for i, a in enumerate(ORDER):
            text = rr[i]
            action = "UPDATE"
            for act in ("CONCEDE", "REBUT", "UPDATE"):
                if text.strip().upper().startswith(act):
                    action = act
                    break
            self.transcript.append({"agent": a, "round": 2, "type": "response", "action": action, "text": text})
            yield {"type": "response", "agent": a, "round": 2, "action": action, "text": text}

        dis = await self._disagreements(2, cmap["reliability"])
        self.disagreements.append(dis)
        yield {"type": "disagreement", "round": 2, "data": dis}

        yield {"type": "phase", "phase": "synthesizing"}
        compact = "\n\n".join(
            f"[{AGENTS[t['agent']]['name'].upper()} | R{t['round']} | {t['type'].upper()}]\n"
            f"{_truncate_position(t['text'], 1000)}"
            for t in self.transcript
        )
        fin_prompts = {
            a: f"{self._sys(a)}\n\nDEBATE:\n{compact}\n\n"
            f"{FINAL_POSITION_PROMPT_TEMPLATE.format(agent_name=AGENTS[a]['name'], agent_id=a)}"
            for a in ORDER
        }
        fr = await asyncio.gather(
            *[_safe_llm_call(fin_prompts[a], conn=cmap[a], timeout=90, label=f"final_{a}") for a in ORDER]
        )
        finals = []
        for i, a in enumerate(ORDER):
            text = fr[i]
            try:
                s, e = text.find("{"), text.rfind("}") + 1
                parsed = json.loads(text[s:e]) if s >= 0 and e > s else {"agent": a, "what_changed": text}
            except Exception:
                parsed = {"agent": a, "what_changed": text}
            finals.append(parsed)
            yield {"type": "final", "agent": a, "data": parsed}

        brief_prompt = (
            f"{BOARD_BRIEF_PROMPT}\n\nQUESTION: {self.question}\n\n"
            f"FINAL POSITIONS:\n{json.dumps(finals, default=str, indent=1)}\n\n"
            f"DISAGREEMENTS:\n{json.dumps(self.disagreements[-1:], default=str)}\n\n"
            f"KEY EXCHANGES:\n{compact[:5000]}\n\nGenerate the Board Brief now."
        )
        brief = await _safe_llm_call(brief_prompt, conn=cmap["reliability"], timeout=90, label="brief")
        yield {"type": "brief", "text": brief}

        yield {"type": "phase", "phase": "complete"}
        yield {"type": "done"}

    async def _disagreements(self, rnd: int, conn) -> dict:
        tr = "\n\n".join(
            f"[{AGENTS[t['agent']]['name'].upper()} | R{t['round']}]\n{_truncate_position(t['text'], 1200)}"
            for t in self.transcript
            if t["round"] == rnd
        )
        out = await _safe_llm_call(
            f"{DISAGREEMENT_PROMPT}\n\nEXCHANGE:\n{tr}", conn=conn, timeout=60, label=f"disagreement_r{rnd}"
        )
        try:
            s, e = out.find("{"), out.rfind("}") + 1
            return json.loads(out[s:e])
        except Exception:
            return {"recommendations": {}, "disagreements": [], "convergence_score": 0.5}
