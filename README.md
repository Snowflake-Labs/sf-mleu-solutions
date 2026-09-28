# Snowflake MLEU Industry Solutions

Disclaimer: This application is not part of the Snowflake Service and is governed by the terms in LICENSE, unless expressly agreed to in writing. You use this application at your own risk, and Snowflake has no obligation to support your use of this application. [Learn more](./LEGAL.md)

**MLEU: Manufacturing, Logistics, Energy and Utilities**

End-to-end solution accelerators for the MLEU industry vertical, built on Snowflake and Cortex Code, showcasing Cortex AI, Snowflake ML, and the modern data platform.


## Requirements

- Snowflake Trial account
- Enterprise edition+
- Python 3.12+
- [uv](https://docs.astral.sh/uv/) (Python package manager)

---

## Solution Catalog

| # | Solution | Industry | Directory | Key Snowflake Features | Status |
|---|----------|----------|-----------|----------------------|--------|
| 1 | **Predictive Maintenance** | Manufacturing | `solutions/predictive-maintenance/` | Snowflake Intelligence, Cortex Analyst, Semantic View, Streamlit, SPCS | ✅ Done |
| 2 | **Supply Chain Intelligence Platform** | Manufacturing | `solutions/supply-chain-intelligence/` | Snowflake Intelligence, Cortex Analyst, Cortex Search, Semantic Model, Streamlit | ✅ Done |
| 3 | **GNN Supply Chain Risk Intelligence** | Manufacturing | `solutions/gnn-supply-chain-risk/` | Graph Neural Networks, PyTorch Geometric, Cortex Agent, Cortex Analyst, SPCS GPU, Streamlit | ✅ Done |

---

## Quick Install (via Cortex Code)

> **TBA** — Plugin install command will be available after public release.

```
$sf-solutions                              # List all available solutions
$sf-solutions mleu                         # Filter by MLEU industry
$sf-solutions:predictive-maintenance       # Install a solution
$sf-solutions:predictive-maintenance teardown  # Remove a solution
```

---

## Getting Started

Each solution is self-contained in its own directory with:

```
solutions/<solution-name>/
├── README.md          # Overview, architecture, prerequisites
├── manifest.json      # Solution metadata for the installer
├── NEXT_ACTIONS.md    # Post-install verification steps and example queries
├── scripts/           # SQL setup and teardown scripts
└── streamlit/         # Streamlit app (if applicable)
```

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
