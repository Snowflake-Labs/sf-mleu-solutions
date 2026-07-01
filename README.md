# Snowflake MLEU Industry Solutions

**MLEU: Manufacturing, Logistics, Energy and Utilities**

End-to-end solution accelerators for the MLEU industry vertical, built on Snowflake and Cortex Code, showcasing Cortex AI, Snowflake ML, and the modern data platform.

---

## Solution Catalog

| # | Solution | Industry | Directory | Key Snowflake Features | Status |
|---|----------|----------|-----------|----------------------|--------|
| 1 | **Predictive Maintenance** | Manufacturing | `solutions/predictive-maintenance/` | Snowflake Intelligence, Cortex Analyst, Semantic View, Streamlit, SPCS | ✅ Done |
| 2 | **Supply Chain Intelligence Platform** | Manufacturing | `solutions/supply-chain-intelligence/` | Snowflake Intelligence, Cortex Analyst, Cortex Search, Semantic Model, Streamlit | ✅ Done |
| 3 | **GNN Supply Chain Risk Intelligence** | Manufacturing | `solutions/gnn-supply-chain-risk/` | Graph Neural Networks, PyTorch Geometric, Cortex Agent, Cortex Analyst, SPCS GPU, Streamlit | ✅ Done |

---

## Quick Install (via Cortex Code)

Install any solution using the Cortex Code plugin:

```bash
# Permanent install (copies plugin to cache — survives restarts)
# TBA: Public install (available after repo goes public) cortex plugin install "Snowflake-Labs/sf-mleu-solutions/plugins/cortex-code"

# Or load locally during development (reads directly from disk, always up-to-date)
git clone git@github.com:Snowflake-Labs/sf-mleu-solutions.git
cd sf-mleu-solutions
cortex --plugin-dir ./plugins/cortex-code
```

> **Note:** `cortex plugin install` copies the plugin into a local cache. If you add new skills later, you must `cortex plugin uninstall sf-mleu-solutions && cortex plugin install ...` to refresh. During development, use `--plugin-dir` instead — it always reads the latest files from disk without caching.

Then in a Cortex Code session, run a solution by name:

```
$sf-mleu-solutions:<solution-name>
```

Example:
```
$sf-mleu-solutions:predictive-maintenance
$sf-mleu-solutions:predictive-maintenance teardown
```

## Quick Install (via Claude Code)

```bash
# TBA: Public install (available after repo goes public)

# Or load locally during development
git clone git@github.com:Snowflake-Labs/sf-mleu-solutions.git
cd sf-mleu-solutions
claude --plugin-dir ./plugins/claude-code
```

Then in a Claude Code session, run a solution by name:
```
/sf-mleu-solutions:predictive-maintenance
```

---

## Getting Started

Each solution is self-contained in its own directory with:

```
solutions/<solution-name>/
├── README.md          # Overview, architecture, prerequisites
├── manifest.json      # Solution metadata for the installer
├── scripts/           # SQL setup and teardown scripts
└── data/              # Sample data generation scripts (if applicable)
```

## Prerequisites

- Snowflake account (Enterprise edition recommended)
- Appropriate role with CREATE DATABASE / SCHEMA privileges
- Warehouse (default: `COMPUTE_WH`)

---

## Related Resources

### Web Pages

- [Snowflake ML](https://www.snowflake.com/en/data-cloud/snowflake-ml/) - Integrated set of capabilities for development, MLOps and inference leading with agentic ML
- [Snowflake Notebooks](https://www.snowflake.com/en/data-cloud/notebooks/) - Jupyter-based notebooks in Snowflake Workspaces
- [Cortex Code](https://www.snowflake.com/en/data-cloud/cortex/cortex-code/) - Snowflake's AI native coding agent that boosts ML productivity

### Technical Documentation

- [Cortex Code Documentation](https://docs.snowflake.com/en/user-guide/cortex-code/cortex-code) - Getting started with Cortex Code
- [Cortex Code in Snowsight](https://docs.snowflake.com/en/user-guide/cortex-code/cortex-code-snowsight) - Browser-based experience
- [Cortex Code CLI](https://docs.snowflake.com/en/user-guide/cortex-code/cortex-code-cli) - Command-line experience
- [Snowflake ML Documentation](https://docs.snowflake.com/en/developer-guide/snowflake-ml/overview) - Official Snowflake ML developer guide
- [Snowflake ML Quickstart](https://quickstarts.snowflake.com/guide/getting-started-with-snowflake-ml/) - Hands-on guides to get started with Snowflake ML
