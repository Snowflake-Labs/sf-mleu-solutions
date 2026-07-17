# IROPS Intelligence Center for Network Operations Control

> **Industry:** Airlines & Transportation

## Overview

AI-powered flight operations command center for Network Operations Control (OCC).
Ranks explainable flight delay risk, quantifies disruption cascade and revenue-at-risk,
monitors route-day OTP and flight-leg average delay via governed Dynamic Tables,
and orchestrates SOP-grounded recovery using Cortex Analyst and Cortex Search.

## Architecture

```
RAW_FLIGHTS (IROPS_RAW)
        │
        ├── DT_AVG_DELAY_FLIGHT_LEG   (Dynamic Table — flight-leg grain)
        ├── DT_OTP_RATE_ROUTE_DAY     (Dynamic Table — route-day grain)
        └── DT_FLIGHT_RISK_REALTIME   (View — risk score proxy)
                │
                └── IROP_OPERATIONS_SV  (Semantic View → Cortex Analyst)
```

## Key Snowflake Features

- **Dynamic Tables** — incremental OTP rate and average delay metrics (60-min lag)
- **Cortex Analyst** — natural language queries over the semantic view
- **Semantic View** — governed flight operations model with dimensions and measures
- **Least-privilege RBAC** — scoped analytics role (`IROPS_OCC_ROLE`) via SYSADMIN

## Solution Objects

| Object | Type | Schema | Description |
|--------|------|--------|-------------|
| `RAW_FLIGHTS` | Table | `IROPS_RAW` | Raw flight legs with status and delay data |
| `DT_FLIGHT_RISK_REALTIME` | View | `IROPS_DATA_MART` | Delay risk score and revenue-at-risk per flight |
| `DT_AVG_DELAY_FLIGHT_LEG` | Dynamic Table | `IROPS_DATA_MART` | Average delay per flight leg (60-min refresh) |
| `DT_OTP_RATE_ROUTE_DAY` | Dynamic Table | `IROPS_DATA_MART` | On-time departure rate per route per day |
| `IROP_OPERATIONS_SV` | Semantic View | `IROPS_CORTEX` | Cortex Analyst semantic model |
| `IROPS_OCC_ROLE` | Role | — | Least-privilege analytics role |

## Prerequisites

- Snowflake account (Standard edition or above)
- `ACCOUNTADMIN` role
- Warehouse: `SF_SOLUTIONS_WH` (created by setup.sql, LARGE)

## Quick Install

Use Cortex Code:

```
$sf-mleu-solutions:irops-intelligence-center
```

Teardown:

```
$sf-mleu-solutions:irops-intelligence-center teardown
```

## Skills

| Skill | Description |
|-------|-------------|
| `primary-workflow` | End-to-end OCC IROPS triage loop |
| `delay-risk-triage` | Rank and explain at-risk legs |
| `disruption-pnl` | Network cascade and revenue-at-risk analysis |
| `otp-trend-monitor` | Route-day OTP and flight-leg delay trends |
| `kpi-definitions` | OCC metric contract (governed vs net-new vs ungoverned) |
| `domain-glossary` | Shared OCC/aviation vocabulary and grains |
| `recovery-orchestration` | SOP-grounded rebooking and crew/aircraft swaps |

## Metric Governance

| Metric | Status | Notes |
|--------|--------|-------|
| Delay risk score | Proxy | Derived from flight status; connect ML scorer for production |
| On-time departure rate | Net-new | Route-day grain via Dynamic Table |
| Average delay minutes | Net-new | Flight-leg grain via Dynamic Table |
| Cost per disruption | Ungoverned | Gap metric — not fabricated |
| Rebooking success rate | Ungoverned | Gap metric — not fabricated |
