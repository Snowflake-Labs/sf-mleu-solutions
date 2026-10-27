# Variable names follow the optimisation notation (P, Q, C, E, P0, Q0).
# ruff: noqa: N803, N806
"""Pricing Optimizer - Advanced Optimal Price Recommendation Engine.

Sophisticated portfolio optimization with visualizations for:
- Profit/Revenue curves
- Demand response surfaces
- Sensitivity analysis
- Trade-off frontiers
"""

import numpy as np
import pandas as pd
import plotly.graph_objects as go
import streamlit as st
from plotly.subplots import make_subplots
from scipy.optimize import minimize
from snowflake.snowpark.context import get_active_session

# Page config
st.set_page_config(page_title="Pricing Optimizer", page_icon="🎯", layout="wide")

# Get Snowflake session
session = get_active_session()

# =============================================================================
# STYLING
# =============================================================================
st.markdown(
    """
<style>
    .main-header {
        font-size: 2.5rem;
        font-weight: 800;
        background: linear-gradient(135deg, #22c55e 0%, #3b82f6 50%, #8b5cf6 100%);
        -webkit-background-clip: text;
        -webkit-text-fill-color: transparent;
        margin-bottom: 0.5rem;
    }
    .sub-header {
        color: #94a3b8;
        font-size: 1.1rem;
        margin-bottom: 2rem;
    }
    .kpi-container {
        background: linear-gradient(135deg, rgba(34, 197, 94, 0.15), rgba(59, 130, 246, 0.15));
        border: 1px solid rgba(255,255,255,0.1);
        border-radius: 16px;
        padding: 1.5rem;
        text-align: center;
        margin-bottom: 1rem;
    }
    .kpi-value {
        font-size: 2.5rem;
        font-weight: 800;
        color: #22c55e;
        line-height: 1.2;
    }
    .kpi-value-blue {
        font-size: 2.5rem;
        font-weight: 800;
        color: #3b82f6;
        line-height: 1.2;
    }
    .kpi-delta {
        font-size: 1.2rem;
        font-weight: 600;
        color: #22c55e;
    }
    .kpi-label {
        font-size: 0.9rem;
        color: #94a3b8;
        margin-top: 0.5rem;
        text-transform: uppercase;
        letter-spacing: 1px;
    }
    .insight-card {
        background: rgba(59, 130, 246, 0.1);
        border: 1px solid rgba(59, 130, 246, 0.3);
        border-radius: 12px;
        padding: 1.25rem;
        margin: 0.75rem 0;
    }
    .math-box {
        background: rgba(139, 92, 246, 0.1);
        border: 1px solid rgba(139, 92, 246, 0.3);
        border-radius: 12px;
        padding: 1.25rem;
        font-family: 'Courier New', monospace;
    }
    .action-card {
        background: linear-gradient(135deg, rgba(34, 197, 94, 0.2), rgba(34, 197, 94, 0.05));
        border: 1px solid rgba(34, 197, 94, 0.3);
        border-radius: 12px;
        padding: 1rem;
    }
    .section-title {
        font-size: 1.5rem;
        font-weight: 700;
        color: #e2e8f0;
        margin: 1.5rem 0 1rem 0;
        border-bottom: 2px solid rgba(59, 130, 246, 0.3);
        padding-bottom: 0.5rem;
    }
</style>
""",
    unsafe_allow_html=True,
)

# =============================================================================
# OPTIMIZATION FUNCTIONS
# =============================================================================


def demand_function(P, Q0, E_matrix, P0):
    """Log-linear demand with cross-elasticities: Q_i = Q0_i * exp(Σ E_ij * ln(P_j/P0_j))."""
    log_price_ratio = np.log(P / P0)
    log_Q_change = E_matrix @ log_price_ratio
    return Q0 * np.exp(log_Q_change)


def profit_function(P, Q0, C, E_matrix, P0):
    """Total contribution margin: Π = Σ (P_i - C_i) * Q_i."""
    Q = demand_function(P, Q0, E_matrix, P0)
    return np.sum((P - C) * Q)


def revenue_function(P, Q0, C, E_matrix, P0):
    """Total revenue: R = Σ P_i * Q_i."""
    Q = demand_function(P, Q0, E_matrix, P0)
    return np.sum(P * Q)


def negative_profit(P, Q0, C, E_matrix, P0):
    """Negative profit."""
    return -profit_function(P, Q0, C, E_matrix, P0)


def negative_revenue(P, Q0, C, E_matrix, P0):
    """Negative revenue."""
    return -revenue_function(P, Q0, C, E_matrix, P0)


# =============================================================================
# DATA LOADING
# =============================================================================


@st.cache_data(ttl=300)
def load_elasticity_matrix():
    """Load elasticity matrix."""
    query = """
    SELECT demand_product_id, price_product_id, elasticity, is_own_price, is_significant
    FROM SF_SOLUTIONS.CHP_OPS.ELASTICITY_MATRIX
    WHERE model_version = (SELECT MAX(model_version) FROM SF_SOLUTIONS.CHP_OPS.ELASTICITY_MATRIX)
    """
    return session.sql(query).to_pandas()


@st.cache_data(ttl=300)
def load_current_state():
    """Load current state."""
    query = """
    SELECT product_family, AVG(avg_price_per_mt) as current_price,
           AVG(avg_variable_cost) as variable_cost, SUM(total_quantity_mt) as total_quantity
    FROM SF_SOLUTIONS.CHP_OPS.ML_TRAINING_DATA
    WHERE order_date >= DATEADD(day, -30, (SELECT MAX(order_date) FROM SF_SOLUTIONS.CHP_OPS.ML_TRAINING_DATA))
    GROUP BY product_family
    """
    return session.sql(query).to_pandas()


# =============================================================================
# VISUALIZATION FUNCTIONS
# =============================================================================


def create_profit_revenue_curves(P0, Q0, C, E_matrix, product_idx, available_products):
    """Create profit and revenue curves for a single product."""
    product_name = available_products[product_idx].replace("_", " ").title()

    # Price range: -30% to +30%
    price_range = np.linspace(P0[product_idx] * 0.7, P0[product_idx] * 1.3, 50)

    profits = []
    revenues = []
    quantities = []
    margins = []

    for p in price_range:
        P_test = P0.copy()
        P_test[product_idx] = p

        Q = demand_function(P_test, Q0, E_matrix, P0)
        profit = np.sum((P_test - C) * Q)
        revenue = np.sum(P_test * Q)

        profits.append(profit)
        revenues.append(revenue)
        quantities.append(Q[product_idx])
        margins.append((p - C[product_idx]) / p * 100)

    # Create subplot
    fig = make_subplots(
        rows=2,
        cols=2,
        subplot_titles=[
            f"<b>Profit Curve</b> - {product_name}",
            f"<b>Revenue Curve</b> - {product_name}",
            f"<b>Demand Curve</b> - {product_name}",
            f"<b>Margin vs Price</b> - {product_name}",
        ],
        vertical_spacing=0.12,
        horizontal_spacing=0.08,
    )

    # Profit curve
    fig.add_trace(
        go.Scatter(
            x=price_range,
            y=profits,
            mode="lines",
            name="Total Profit",
            line=dict(color="#22c55e", width=3),
            fill="tozeroy",
            fillcolor="rgba(34, 197, 94, 0.1)",
        ),
        row=1,
        col=1,
    )
    fig.add_vline(x=P0[product_idx], line_dash="dash", line_color="#fbbf24", annotation_text="Current", row=1, col=1)

    # Revenue curve
    fig.add_trace(
        go.Scatter(
            x=price_range,
            y=revenues,
            mode="lines",
            name="Total Revenue",
            line=dict(color="#3b82f6", width=3),
            fill="tozeroy",
            fillcolor="rgba(59, 130, 246, 0.1)",
        ),
        row=1,
        col=2,
    )
    fig.add_vline(x=P0[product_idx], line_dash="dash", line_color="#fbbf24", row=1, col=2)

    # Demand curve
    fig.add_trace(
        go.Scatter(
            x=price_range,
            y=quantities,
            mode="lines",
            name="Quantity",
            line=dict(color="#f59e0b", width=3),
            fill="tozeroy",
            fillcolor="rgba(245, 158, 11, 0.1)",
        ),
        row=2,
        col=1,
    )
    fig.add_vline(x=P0[product_idx], line_dash="dash", line_color="#fbbf24", row=2, col=1)

    # Margin curve
    fig.add_trace(
        go.Scatter(
            x=price_range,
            y=margins,
            mode="lines",
            name="Margin %",
            line=dict(color="#8b5cf6", width=3),
            fill="tozeroy",
            fillcolor="rgba(139, 92, 246, 0.1)",
        ),
        row=2,
        col=2,
    )
    fig.add_vline(x=P0[product_idx], line_dash="dash", line_color="#fbbf24", row=2, col=2)
    fig.add_hline(y=15, line_dash="dot", line_color="#ef4444", annotation_text="Min Margin", row=2, col=2)

    fig.update_layout(height=550, template="plotly_dark", showlegend=False, margin=dict(l=60, r=20, t=60, b=40))

    # Update axes
    fig.update_xaxes(title_text="Price ($/MT)", row=1, col=1)
    fig.update_xaxes(title_text="Price ($/MT)", row=1, col=2)
    fig.update_xaxes(title_text="Price ($/MT)", row=2, col=1)
    fig.update_xaxes(title_text="Price ($/MT)", row=2, col=2)
    fig.update_yaxes(title_text="Profit ($)", tickformat=",.0f", row=1, col=1)
    fig.update_yaxes(title_text="Revenue ($)", tickformat=",.0f", row=1, col=2)
    fig.update_yaxes(title_text="Quantity (MT)", tickformat=",.0f", row=2, col=1)
    fig.update_yaxes(title_text="Margin (%)", row=2, col=2)

    return fig


def create_3d_profit_surface(P0, Q0, C, E_matrix, idx1, idx2, available_products):
    """Create 3D profit surface for two products."""
    name1 = available_products[idx1].replace("_", " ").title()
    name2 = available_products[idx2].replace("_", " ").title()

    # Create price grid
    p1_range = np.linspace(P0[idx1] * 0.85, P0[idx1] * 1.15, 25)
    p2_range = np.linspace(P0[idx2] * 0.85, P0[idx2] * 1.15, 25)

    P1, P2 = np.meshgrid(p1_range, p2_range)
    Z = np.zeros_like(P1)

    for i in range(len(p1_range)):
        for j in range(len(p2_range)):
            P_test = P0.copy()
            P_test[idx1] = p1_range[i]
            P_test[idx2] = p2_range[j]
            Z[j, i] = profit_function(P_test, Q0, C, E_matrix, P0)

    fig = go.Figure(
        data=[go.Surface(x=P1, y=P2, z=Z, colorscale="Viridis", colorbar=dict(title="Profit ($)", tickformat=",.0f"))]
    )

    # Add current point
    current_profit = profit_function(P0, Q0, C, E_matrix, P0)
    fig.add_trace(
        go.Scatter3d(
            x=[P0[idx1]],
            y=[P0[idx2]],
            z=[current_profit],
            mode="markers",
            marker=dict(size=10, color="#ef4444", symbol="diamond"),
            name="Current",
        )
    )

    fig.update_layout(
        title=f"<b>Profit Response Surface</b><br><sup>{name1} × {name2}</sup>",
        scene=dict(
            xaxis_title=f"{name1} Price",
            yaxis_title=f"{name2} Price",
            zaxis_title="Total Profit",
            xaxis=dict(tickformat="$,.0f"),
            yaxis=dict(tickformat="$,.0f"),
            zaxis=dict(tickformat="$,.0f"),
        ),
        height=500,
        template="plotly_dark",
    )

    return fig


def create_pareto_frontier(P0, Q0, C, E_matrix, available_products):
    """Generate Profit vs Revenue Pareto frontier."""
    results = []

    # Sample different weight combinations
    for w in np.linspace(0, 1, 30):

        def combined_obj(P):
            """Combined obj."""
            profit = profit_function(P, Q0, C, E_matrix, P0)
            revenue = revenue_function(P, Q0, C, E_matrix, P0)
            return -(w * profit / 1e6 + (1 - w) * revenue / 1e6)  # Normalize

        bounds = [(P0[i] * 0.9, P0[i] * 1.1) for i in range(len(P0))]

        try:
            result = minimize(combined_obj, x0=P0, method="SLSQP", bounds=bounds)
            if result.success:
                profit = profit_function(result.x, Q0, C, E_matrix, P0)
                revenue = revenue_function(result.x, Q0, C, E_matrix, P0)
                results.append({"profit": profit, "revenue": revenue, "weight": w})
        except Exception:
            pass

    if not results:
        return None

    df = pd.DataFrame(results)

    # Current state
    current_profit = profit_function(P0, Q0, C, E_matrix, P0)
    current_revenue = np.sum(P0 * Q0)

    fig = go.Figure()

    # Pareto frontier
    fig.add_trace(
        go.Scatter(
            x=df["revenue"],
            y=df["profit"],
            mode="lines+markers",
            name="Pareto Frontier",
            line=dict(color="#22c55e", width=3),
            marker=dict(size=8),
        )
    )

    # Current point
    fig.add_trace(
        go.Scatter(
            x=[current_revenue],
            y=[current_profit],
            mode="markers",
            name="Current State",
            marker=dict(size=15, color="#ef4444", symbol="star"),
        )
    )

    # Add annotations for extremes
    max_profit_idx = df["profit"].idxmax()
    max_revenue_idx = df["revenue"].idxmax()

    fig.add_annotation(
        x=df.loc[max_profit_idx, "revenue"],
        y=df.loc[max_profit_idx, "profit"],
        text="Max Profit",
        showarrow=True,
        arrowhead=2,
        ax=40,
        ay=-40,
    )

    fig.add_annotation(
        x=df.loc[max_revenue_idx, "revenue"],
        y=df.loc[max_revenue_idx, "profit"],
        text="Max Revenue",
        showarrow=True,
        arrowhead=2,
        ax=-40,
        ay=40,
    )

    fig.update_layout(
        title=(
            "<b>Profit-Revenue Trade-off Frontier</b>"
            "<br><sup>Efficient combinations of profit and revenue objectives</sup>"
        ),
        xaxis_title="Total Revenue ($)",
        yaxis_title="Total Profit ($)",
        height=450,
        template="plotly_dark",
        xaxis=dict(tickformat="$,.0f"),
        yaxis=dict(tickformat="$,.0f"),
    )

    return fig


def create_waterfall_chart(P0, P_optimal, Q0, Q_optimal, C, available_products):
    """Create waterfall chart showing margin decomposition."""
    current_margins = (P0 - C) * Q0
    optimal_margins = (P_optimal - C) * Q_optimal
    changes = optimal_margins - current_margins

    labels = [p.replace("_", " ").title() for p in available_products] + ["Total"]
    values = list(changes) + [sum(changes)]
    measures = ["relative"] * len(available_products) + ["total"]

    fig = go.Figure(
        go.Waterfall(
            x=labels,
            y=values,
            measure=measures,
            text=[f"${v:+,.0f}" for v in values],
            textposition="outside",
            connector=dict(line=dict(color="rgba(255,255,255,0.3)")),
            increasing=dict(marker=dict(color="#22c55e")),
            decreasing=dict(marker=dict(color="#ef4444")),
            totals=dict(marker=dict(color="#3b82f6", line=dict(color="#3b82f6", width=2))),
        )
    )

    fig.update_layout(
        title="<b>Margin Impact Waterfall</b><br><sup>Contribution to total profit change by product</sup>",
        yaxis_title="Margin Change ($)",
        height=400,
        template="plotly_dark",
        yaxis=dict(tickformat="$,.0f"),
    )

    return fig


# =============================================================================
# MAIN PAGE
# =============================================================================


def main():
    # Header
    """Main."""
    st.markdown('<p class="main-header">🎯 Optimal Pricing Engine</p>', unsafe_allow_html=True)
    st.markdown(
        """<p class="sub-header">
        Portfolio Optimization • Cross-Elasticity Driven • Profit & Revenue Curves • Constraint-Aware
    </p>""",
        unsafe_allow_html=True,
    )

    # Load data
    try:
        elast_df = load_elasticity_matrix()
        current_df = load_current_state()

        if elast_df.empty:
            st.warning("⚠️ No elasticity matrix found. Please run the SUR model notebook first.")
            st.stop()
    except Exception as e:
        st.error(f"Error loading data: {e}")
        st.stop()

    # Prepare data
    products = elast_df["DEMAND_PRODUCT_ID"].unique().tolist()
    E = pd.DataFrame(index=products, columns=products, dtype=float)
    for _, row in elast_df.iterrows():
        E.loc[row["DEMAND_PRODUCT_ID"], row["PRICE_PRODUCT_ID"]] = row["ELASTICITY"]

    current_df["PRODUCT_ID"] = current_df["PRODUCT_FAMILY"].str.replace(" ", "_").str.upper()
    current_df = current_df.set_index("PRODUCT_ID")
    available_products = [p for p in products if p in current_df.index]

    if not available_products:
        st.warning("No matching products found between elasticity matrix and current pricing data.")
        st.stop()

    P0 = np.array([current_df.loc[p, "CURRENT_PRICE"] for p in available_products])
    Q0 = np.array([current_df.loc[p, "TOTAL_QUANTITY"] for p in available_products])
    C = np.array([current_df.loc[p, "VARIABLE_COST"] for p in available_products])
    E_matrix = E.loc[available_products, available_products].values.astype(float)

    # Current metrics
    current_profit = profit_function(P0, Q0, C, E_matrix, P0)
    current_revenue = np.sum(P0 * Q0)

    # ==========================================================================
    # SIDEBAR
    # ==========================================================================
    with st.sidebar:
        st.header("⚙️ Optimization Settings")

        st.markdown('<p class="section-title">🎯 Objective</p>', unsafe_allow_html=True)
        objective = st.radio("Maximize:", ["Profit (Contribution Margin)", "Revenue"], index=0)

        st.markdown('<p class="section-title">📊 Constraints</p>', unsafe_allow_html=True)
        min_margin = st.slider("Minimum Margin %", 5, 30, 15, 5) / 100
        max_increase = st.slider("Max Price Increase %", 1, 25, 10, 1) / 100
        max_decrease = st.slider("Max Price Decrease %", 1, 25, 10, 1) / 100

        st.divider()
        run_optimization = st.button("🚀 Run Optimization", type="primary", use_container_width=True)

    # ==========================================================================
    # TABS
    # ==========================================================================
    tab1, tab2, tab3, tab4, tab5 = st.tabs(
        [
            "📈 Profit & Demand Curves",
            "🔢 Elasticity Matrix",
            "🎯 Optimization Results",
            "⚖️ Trade-off Analysis",
            "🌐 3D Surface",
        ]
    )

    # --------------------------------------------------------------------------
    # TAB 1: PROFIT & DEMAND CURVES
    # --------------------------------------------------------------------------
    with tab1:
        st.markdown('<p class="section-title">📈 Profit, Revenue & Demand Response</p>', unsafe_allow_html=True)

        col1, col2 = st.columns([3, 1])
        with col2:
            selected_product = st.selectbox(
                "Select Product", available_products, format_func=lambda x: x.replace("_", " ").title()
            )

        product_idx = available_products.index(selected_product)
        fig_curves = create_profit_revenue_curves(P0, Q0, C, E_matrix, product_idx, available_products)
        st.plotly_chart(fig_curves, use_container_width=True)

        # Insights
        own_elast = E_matrix[product_idx, product_idx]
        col1, col2, col3 = st.columns(3)

        with col1:
            st.markdown(
                f"""
            <div class="insight-card">
                <strong>📊 Own-Price Elasticity</strong><br>
                <span style="font-size: 1.8rem; color: #3b82f6;">{own_elast:.2f}</span><br>
                <small>{"Elastic: ↑Price → ↓↓Revenue" if own_elast < -1 else "Inelastic: ↑Price → ↑Revenue"}</small>
            </div>
            """,
                unsafe_allow_html=True,
            )

        with col2:
            current_margin_pct = (P0[product_idx] - C[product_idx]) / P0[product_idx] * 100
            st.markdown(
                f"""
            <div class="insight-card">
                <strong>💰 Current Margin</strong><br>
                <span style="font-size: 1.8rem; color: #22c55e;">{current_margin_pct:.1f}%</span><br>
                <small>${P0[product_idx] - C[product_idx]:,.0f}/MT contribution</small>
            </div>
            """,
                unsafe_allow_html=True,
            )

        with col3:
            # Find price at max profit (approximately)
            # best_price = P0[product_idx]  # Placeholder
            st.markdown(
                f"""
            <div class="insight-card">
                <strong>🎯 Current Price</strong><br>
                <span style="font-size: 1.8rem; color: #f59e0b;">${P0[product_idx]:,.0f}</span><br>
                <small>per metric ton</small>
            </div>
            """,
                unsafe_allow_html=True,
            )

    # --------------------------------------------------------------------------
    # TAB 2: ELASTICITY MATRIX
    # --------------------------------------------------------------------------
    with tab2:
        st.markdown('<p class="section-title">🔢 Cross-Price Elasticity Matrix</p>', unsafe_allow_html=True)

        col1, col2 = st.columns([2, 1])

        with col1:
            E_display = E.loc[available_products, available_products]
            fig_elast = go.Figure(
                data=go.Heatmap(
                    z=E_display.values.astype(float),
                    x=[p.replace("_", " ").title() for p in E_display.columns],
                    y=[p.replace("_", " ").title() for p in E_display.index],
                    colorscale="RdBu",
                    zmid=0,
                    zmin=-2.5,
                    zmax=1,
                    text=E_display.round(2).values,
                    texttemplate="%{text}",
                    textfont={"size": 16, "color": "white"},
                    colorbar=dict(title="ε"),
                )
            )
            fig_elast.update_layout(
                height=400, template="plotly_dark", xaxis_title="Price Product (j)", yaxis_title="Demand Product (i)"
            )
            st.plotly_chart(fig_elast, use_container_width=True)

        with col2:
            st.markdown(
                """
            <div class="math-box">
                <strong>📐 Mathematical Definition</strong><br><br>
                ε<sub>ij</sub> = ∂ln(Q<sub>i</sub>)/∂ln(P<sub>j</sub>)<br><br>
                <strong>Interpretation:</strong><br>
                1% ↑ in P<sub>j</sub> → ε<sub>ij</sub>% Δ in Q<sub>i</sub>
            </div>
            """,
                unsafe_allow_html=True,
            )

            st.markdown(
                """
            <div class="insight-card" style="margin-top: 1rem;">
                <strong>🔍 Reading the Matrix</strong><br><br>
                • <span style="color: #ef4444;">Red diagonal</span>: Own-price (negative)<br>
                • <span style="color: #3b82f6;">Blue off-diagonal</span>: Substitutes<br>
                • <span style="color: #ef4444;">Red off-diagonal</span>: Complements
            </div>
            """,
                unsafe_allow_html=True,
            )

    # --------------------------------------------------------------------------
    # TAB 3: OPTIMIZATION RESULTS
    # --------------------------------------------------------------------------
    with tab3:
        if run_optimization or "opt_results" in st.session_state:
            if run_optimization:
                with st.spinner("🔄 Optimizing portfolio prices..."):
                    bounds = []
                    for i in range(len(P0)):
                        lower = max(P0[i] * (1 - max_decrease), C[i] / (1 - min_margin))
                        upper = P0[i] * (1 + max_increase)
                        bounds.append((lower, upper))

                    obj_func = negative_profit if "Profit" in objective else negative_revenue
                    result = minimize(
                        obj_func,
                        x0=P0,
                        args=(Q0, C, E_matrix, P0),
                        method="SLSQP",
                        bounds=bounds,
                        options={"maxiter": 1000},
                    )

                    P_optimal = result.x
                    Q_optimal = demand_function(P_optimal, Q0, E_matrix, P0)

                    st.session_state["opt_results"] = {
                        "P_optimal": P_optimal,
                        "Q_optimal": Q_optimal,
                        "success": result.success,
                        "bounds": bounds,
                    }

            opt = st.session_state["opt_results"]
            P_optimal, Q_optimal = opt["P_optimal"], opt["Q_optimal"]

            optimal_profit = profit_function(P_optimal, Q0, C, E_matrix, P0)
            optimal_revenue = np.sum(P_optimal * Q_optimal)
            profit_delta = optimal_profit - current_profit
            profit_delta_pct = (optimal_profit / current_profit - 1) * 100

            # KPIs
            st.markdown('<p class="section-title">📊 Optimization Impact</p>', unsafe_allow_html=True)

            col1, col2, col3, col4 = st.columns(4)
            with col1:
                st.markdown(
                    f"""
                <div class="kpi-container">
                    <div class="kpi-label">Current Profit</div>
                    <div class="kpi-value-blue">${current_profit / 1e6:.2f}M</div>
                </div>
                """,
                    unsafe_allow_html=True,
                )
            with col2:
                st.markdown(
                    f"""
                <div class="kpi-container">
                    <div class="kpi-label">Optimal Profit</div>
                    <div class="kpi-value">${optimal_profit / 1e6:.2f}M</div>
                    <div class="kpi-delta">+{profit_delta_pct:.1f}%</div>
                </div>
                """,
                    unsafe_allow_html=True,
                )
            with col3:
                st.markdown(
                    f"""
                <div class="kpi-container">
                    <div class="kpi-label">Profit Gain</div>
                    <div class="kpi-value">${profit_delta / 1e3:+,.0f}K</div>
                </div>
                """,
                    unsafe_allow_html=True,
                )
            with col4:
                revenue_delta_pct = (optimal_revenue / current_revenue - 1) * 100
                st.markdown(
                    f"""
                <div class="kpi-container">
                    <div class="kpi-label">Revenue Change</div>
                    <div class="kpi-value-blue">{revenue_delta_pct:+.1f}%</div>
                </div>
                """,
                    unsafe_allow_html=True,
                )

            # Waterfall chart
            st.markdown('<p class="section-title">💧 Margin Waterfall</p>', unsafe_allow_html=True)
            fig_waterfall = create_waterfall_chart(P0, P_optimal, Q0, Q_optimal, C, available_products)
            st.plotly_chart(fig_waterfall, use_container_width=True)

            # Detailed results table
            st.markdown('<p class="section-title">📋 Recommended Price Changes</p>', unsafe_allow_html=True)

            results_data = []
            for i, prod in enumerate(available_products):
                price_change = (P_optimal[i] - P0[i]) / P0[i] * 100
                vol_change = (Q_optimal[i] - Q0[i]) / Q0[i] * 100
                margin_change = (P_optimal[i] - C[i]) * Q_optimal[i] - (P0[i] - C[i]) * Q0[i]

                at_floor = abs(P_optimal[i] - opt["bounds"][i][0]) < 0.01
                at_ceiling = abs(P_optimal[i] - opt["bounds"][i][1]) < 0.01

                if price_change > 2:
                    action = "↑ INCREASE"
                elif price_change < -2:
                    action = "↓ DECREASE"
                else:
                    action = "→ HOLD"

                results_data.append(
                    {
                        "Product": prod.replace("_", " ").title(),
                        "Current": f"${P0[i]:,.0f}",
                        "Optimal": f"${P_optimal[i]:,.0f}",
                        "Δ Price": f"{price_change:+.1f}%",
                        "Δ Volume": f"{vol_change:+.1f}%",
                        "Δ Margin": f"${margin_change:+,.0f}",
                        "Action": action,
                        "Constraint": "📍 Floor" if at_floor else ("📍 Ceiling" if at_ceiling else "✓"),
                    }
                )

            st.dataframe(pd.DataFrame(results_data), use_container_width=True, hide_index=True)

        else:
            st.info("👈 Configure constraints in the sidebar and click **Run Optimization** to see results")

            # Current state
            st.markdown('<p class="section-title">📋 Current Portfolio State</p>', unsafe_allow_html=True)
            state_data = []
            for i, prod in enumerate(available_products):
                state_data.append(
                    {
                        "Product": prod.replace("_", " ").title(),
                        "Price": f"${P0[i]:,.0f}",
                        "Cost": f"${C[i]:,.0f}",
                        "Margin": f"{(P0[i] - C[i]) / P0[i] * 100:.1f}%",
                        "Volume": f"{Q0[i]:,.0f} MT",
                        "Revenue": f"${P0[i] * Q0[i] / 1e6:.2f}M",
                    }
                )
            st.dataframe(pd.DataFrame(state_data), use_container_width=True, hide_index=True)

    # --------------------------------------------------------------------------
    # TAB 4: TRADE-OFF ANALYSIS
    # --------------------------------------------------------------------------
    with tab4:
        st.markdown('<p class="section-title">⚖️ Profit-Revenue Trade-off Frontier</p>', unsafe_allow_html=True)

        st.caption(
            "The Pareto frontier shows efficient combinations of profit and revenue objectives. "
            "Points on the frontier represent optimal trade-offs."
        )

        with st.spinner("Computing Pareto frontier..."):
            fig_pareto = create_pareto_frontier(P0, Q0, C, E_matrix, available_products)

        if fig_pareto:
            st.plotly_chart(fig_pareto, use_container_width=True)

            st.markdown(
                """
            <div class="insight-card">
                <strong>💡 Interpretation</strong><br><br>
                • <span style="color: #ef4444;">★ Red star</span>: Current state<br>
                • <span style="color: #22c55e;">Green line</span>: Efficient frontier<br>
                • Moving along the frontier trades off profit for revenue (or vice versa)<br>
                • Any point <em>below</em> the frontier is suboptimal
            </div>
            """,
                unsafe_allow_html=True,
            )

    # --------------------------------------------------------------------------
    # TAB 5: 3D SURFACE
    # --------------------------------------------------------------------------
    with tab5:
        st.markdown('<p class="section-title">🌐 3D Profit Response Surface</p>', unsafe_allow_html=True)

        col1, col2, col3 = st.columns([1, 1, 2])
        with col1:
            prod1 = st.selectbox(
                "X-axis Product",
                available_products,
                index=0,
                format_func=lambda x: x.replace("_", " ").title(),
                key="surf1",
            )
        with col2:
            prod2 = st.selectbox(
                "Y-axis Product",
                available_products,
                index=1 if len(available_products) > 1 else 0,
                format_func=lambda x: x.replace("_", " ").title(),
                key="surf2",
            )

        idx1 = available_products.index(prod1)
        idx2 = available_products.index(prod2)

        if idx1 != idx2:
            with st.spinner("Rendering 3D surface..."):
                fig_3d = create_3d_profit_surface(P0, Q0, C, E_matrix, idx1, idx2, available_products)
            st.plotly_chart(fig_3d, use_container_width=True)

            st.markdown(
                """
            <div class="insight-card">
                <strong>🔍 Surface Interpretation</strong><br><br>
                • <span style="color: #ef4444;">◆ Red diamond</span>: Current prices<br>
                • Higher surface = more profit<br>
                • The peak shows the joint optimal prices for these two products<br>
                • Curvature indicates cross-price effects
            </div>
            """,
                unsafe_allow_html=True,
            )
        else:
            st.warning("Please select two different products to view the surface")


if __name__ == "__main__":
    main()
