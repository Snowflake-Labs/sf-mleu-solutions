"""Chemicals Pricing Dashboard.

Page 3: Data Science Workbench (Technical View)

Persona: Pricing Analyst / Data Scientist
Action: "Validate the models"

Every number on this page is read from the ML output tables filled by
SP_RUN_ML_PIPELINE (ddl/core/008_ML_PROCEDURES.sql):
- Demand forecast accuracy and drivers (DEMAND_FORECAST, XGBoost)
- Elasticity matrix vs the elasticities planted in the synthetic data
- Per-product price elasticity (PRICE_ELASTICITY)
- Lagged correlation of demand with Brent (LAGGED_CORRELATION)
"""

import pandas as pd
import plotly.graph_objects as go
import streamlit as st
from snowflake.snowpark.context import get_active_session
from utils.theme import COLORS, apply_dark_theme, get_page_css, info_box, metric_card, section_header

st.set_page_config(
    page_title="Chemicals Pricing - Data Science", page_icon="🔬", layout="wide", initial_sidebar_state="expanded"
)

st.markdown(get_page_css(), unsafe_allow_html=True)

OPS = "SF_SOLUTIONS.CHP_OPS"
ATOMIC = "SF_SOLUTIONS.CHP_ATOMIC"
NOT_RUN = "Not computed yet: run CALL SF_SOLUTIONS.CHP_OPS.SP_RUN_ML_PIPELINE();"


@st.cache_resource
def get_session():
    """Return the active Snowpark session."""
    return get_active_session()


@st.cache_data(ttl=300)
def query(_session, sql: str, params: tuple = ()):
    """Run a query with bind parameters and return a DataFrame."""
    return _session.sql(sql, params=list(params)).to_pandas()


def load_forecasts(session):
    """Weekly demand forecasts with model accuracy and drivers."""
    return query(
        session,
        f"""
        SELECT product_id, region, forecast_period_start, predicted_volume_mt,
               prediction_lower_bound, prediction_upper_bound, model_mape,
               top_driver_1, top_driver_1_impact, top_driver_2, top_driver_2_impact,
               top_driver_3, top_driver_3_impact, model_version
        FROM {OPS}.DEMAND_FORECAST
        ORDER BY product_id, region, forecast_period_start
    """,
    )


def load_weekly_actuals(session, product_id: str, region: str):
    """Actual weekly volume for one product and region."""
    return query(
        session,
        f"""
        SELECT DATE_TRUNC('week', order_date) AS week, SUM(total_quantity_mt) AS volume_mt
        FROM {OPS}.ML_TRAINING_DATA
        WHERE product_id = ? AND region = ?
        GROUP BY 1 ORDER BY 1
    """,
        (product_id, region),
    )


def load_matrix(session):
    """Estimated family elasticity matrix next to the planted values."""
    return query(
        session,
        f"""
        SELECT m.demand_product_name AS demand_family, m.price_product_name AS price_family,
               m.elasticity AS estimated, m.std_error, m.p_value, m.is_own_price,
               p.elasticity AS planted, m.model_version
        FROM {OPS}.ELASTICITY_MATRIX m
        LEFT JOIN {ATOMIC}.DEMO_PLANTED_ELASTICITY p
               ON p.demand_family = m.demand_product_name AND p.price_family = m.price_product_name
        ORDER BY 1, 2
    """,
    )


def load_product_elasticity(session):
    """Per-product own-price elasticity."""
    return query(
        session,
        f"""
        SELECT e.product_id, p.product_name, p.product_family, e.elasticity_coefficient,
               e.elasticity_std_error, e.elasticity_category, e.r_squared, e.data_points
        FROM {OPS}.PRICE_ELASTICITY e
        JOIN {ATOMIC}.PRODUCT p ON p.product_id = e.product_id
        ORDER BY e.elasticity_coefficient
    """,
    )


def load_lags(session):
    """Correlation of weekly demand with Brent at each lag."""
    return query(
        session,
        f"""
        SELECT product_id, region, lag_weeks, correlation_coefficient, correlation_p_value,
               is_significant, is_optimal_lag, predicted_demand_change_pct
        FROM {OPS}.LAGGED_CORRELATION
        ORDER BY product_id, region, lag_weeks
    """,
    )


def render_header():
    """Page title."""
    st.markdown(
        f"""
    <div style="margin-bottom: 2rem;">
        <h1 style="margin-bottom: 0.5rem;">🔬 Data Science Workbench</h1>
        <p style="color: {COLORS["text_muted"]}; font-size: 1.1rem;">
            Technical View • Pricing Analyst • Model Validation
        </p>
    </div>
    """,
        unsafe_allow_html=True,
    )


def render_model_metrics(fc, matrix):
    """Headline model metrics."""
    st.markdown(section_header("📊 Model Performance", "From the latest pipeline run"), unsafe_allow_html=True)
    if fc.empty:
        st.info(NOT_RUN)
        return
    own = matrix[matrix["IS_OWN_PRICE"]] if not matrix.empty else matrix
    gap = (own["ESTIMATED"] - own["PLANTED"]).abs().max() if not own.empty and own["PLANTED"].notna().all() else None
    cols = st.columns(4)
    with cols[0]:
        st.markdown(
            metric_card("Forecast WAPE (8-week holdout)", f"{fc['MODEL_MAPE'].iloc[0]:.1f}%", icon="🎯"),
            unsafe_allow_html=True,
        )
    with cols[1]:
        st.markdown(
            metric_card("Series Forecast", f"{fc.groupby(['PRODUCT_ID', 'REGION']).ngroups:,}", icon="📈"),
            unsafe_allow_html=True,
        )
    with cols[2]:
        st.markdown(metric_card("Forecast Rows", f"{len(fc):,}", icon="🧪"), unsafe_allow_html=True)
    with cols[3]:
        value = f"{gap:.2f}" if gap is not None else "n/a"
        st.markdown(metric_card("Max own-price error vs planted", value, icon="✓"), unsafe_allow_html=True)


def render_forecast(session, fc):
    """Actual weekly volume and the forecast for a chosen series."""
    st.markdown(
        section_header("📈 Actual vs Forecast Volume", "Weekly volume, XGBoost forecast with 95% band"),
        unsafe_allow_html=True,
    )
    if fc.empty:
        st.info(NOT_RUN)
        return
    c1, c2 = st.columns(2)
    product = c1.selectbox("Product", sorted(fc["PRODUCT_ID"].unique()), key="fc_product")
    region = c2.selectbox("Region", sorted(fc["REGION"].unique()), key="fc_region")
    actual = load_weekly_actuals(session, product, region)
    f = fc[(fc["PRODUCT_ID"] == product) & (fc["REGION"] == region)]
    fig = go.Figure()
    fig.add_trace(
        go.Scatter(
            x=actual["WEEK"],
            y=actual["VOLUME_MT"],
            name="Actual",
            line=dict(color=COLORS["chart_1"], width=2),
            mode="lines+markers",
        )
    )
    if not f.empty:
        x = list(f["FORECAST_PERIOD_START"])
        fig.add_trace(
            go.Scatter(
                x=x + x[::-1],
                y=list(f["PREDICTION_UPPER_BOUND"]) + list(f["PREDICTION_LOWER_BOUND"])[::-1],
                fill="toself",
                fillcolor="rgba(139, 92, 246, 0.13)",
                line=dict(color="rgba(0,0,0,0)"),
                name="95% band",
            )
        )
        fig.add_trace(
            go.Scatter(
                x=x,
                y=f["PREDICTED_VOLUME_MT"],
                name="Forecast",
                line=dict(color=COLORS["chart_2"], width=2, dash="dash"),
                mode="lines+markers",
            )
        )
    fig = apply_dark_theme(fig, height=350)
    fig.update_layout(
        yaxis_title="Volume (MT)", legend=dict(orientation="h", yanchor="bottom", y=1.02), hovermode="x unified"
    )
    st.plotly_chart(fig, use_container_width=True)


def render_feature_importance(fc):
    """Top forecast drivers (XGBoost gain importance)."""
    st.markdown(section_header("🔑 Forecast Drivers", "Top 3 features by XGBoost importance"), unsafe_allow_html=True)
    if fc.empty:
        st.info(NOT_RUN)
        return
    r = fc.iloc[0]
    df = pd.DataFrame(
        {
            "Feature": [r["TOP_DRIVER_1"], r["TOP_DRIVER_2"], r["TOP_DRIVER_3"]],
            "Importance": [r["TOP_DRIVER_1_IMPACT"], r["TOP_DRIVER_2_IMPACT"], r["TOP_DRIVER_3_IMPACT"]],
        }
    )
    fig = go.Figure(
        go.Bar(
            x=df["Importance"],
            y=df["Feature"],
            orientation="h",
            marker_color=[COLORS["chart_1"], COLORS["chart_2"], COLORS["chart_3"]],
            text=[f"{v:.0%}" for v in df["Importance"]],
            textposition="outside",
        )
    )
    fig = apply_dark_theme(fig, height=260)
    fig.update_layout(xaxis_title="Importance (share)", yaxis=dict(autorange="reversed"), showlegend=False)
    st.plotly_chart(fig, use_container_width=True)


def render_matrix(matrix):
    """Estimated vs planted family elasticity matrix."""
    st.markdown(
        section_header(
            "🧮 Cross-Price Elasticity Matrix (SUR)",
            "Estimated from the data vs the elasticities planted in the synthetic orders",
        ),
        unsafe_allow_html=True,
    )
    if matrix.empty:
        st.info(NOT_RUN)
        return
    est = matrix.pivot(index="DEMAND_FAMILY", columns="PRICE_FAMILY", values="ESTIMATED")
    fig = go.Figure(
        go.Heatmap(
            z=est.values,
            x=est.columns,
            y=est.index,
            colorscale="RdBu",
            zmid=0,
            text=est.round(2).values,
            texttemplate="%{text}",
            colorbar=dict(title="Elasticity"),
        )
    )
    fig = apply_dark_theme(fig, height=360)
    fig.update_layout(xaxis_title="Price change in family", yaxis_title="Demand of family")
    st.plotly_chart(fig, use_container_width=True)
    show = matrix[["DEMAND_FAMILY", "PRICE_FAMILY", "PLANTED", "ESTIMATED", "STD_ERROR", "P_VALUE"]].copy()
    st.dataframe(show.round(3), use_container_width=True, hide_index=True)
    st.markdown(
        info_box(
            "Each equation regresses a family's log volume on every family's log price index "
            "(price relative to the product's own average) plus macro controls. All equations "
            "share the same regressors, so equation-by-equation OLS equals the SUR estimate."
        ),
        unsafe_allow_html=True,
    )


def render_product_elasticity(pe):
    """Per-product own-price elasticity."""
    st.markdown(
        section_header("📉 Price Elasticity by Product", "Log-log OLS per product with macro controls"),
        unsafe_allow_html=True,
    )
    if pe.empty:
        st.info(NOT_RUN)
        return
    colors = [COLORS["warning"] if c == "ELASTIC" else COLORS["success"] for c in pe["ELASTICITY_CATEGORY"]]
    fig = go.Figure(
        go.Bar(
            x=pe["PRODUCT_NAME"],
            y=pe["ELASTICITY_COEFFICIENT"],
            marker_color=colors,
            error_y=dict(type="data", array=1.96 * pe["ELASTICITY_STD_ERROR"]),
            text=[f"{v:.2f}" for v in pe["ELASTICITY_COEFFICIENT"]],
            textposition="outside",
        )
    )
    fig.add_hline(y=-1, line_dash="dash", line_color=COLORS["text_muted"], annotation_text="Unit elastic")
    fig = apply_dark_theme(fig, height=320)
    fig.update_layout(yaxis_title="Own-price elasticity", showlegend=False)
    st.plotly_chart(fig, use_container_width=True)


def render_lags(lags):
    """Correlation of weekly demand with Brent by lag."""
    st.markdown(
        section_header(
            "⏱️ Demand vs Crude Oil: Lagged Correlation", "Correlation of weekly volume with Brent 0-8 weeks earlier"
        ),
        unsafe_allow_html=True,
    )
    if lags.empty:
        st.info(NOT_RUN)
        return
    best = lags[lags["IS_OPTIMAL_LAG"]]
    c1, c2 = st.columns(2)
    product = c1.selectbox("Product", sorted(lags["PRODUCT_ID"].unique()), key="lag_product")
    region = c2.selectbox("Region", sorted(lags["REGION"].unique()), key="lag_region")
    s = lags[(lags["PRODUCT_ID"] == product) & (lags["REGION"] == region)]
    fig = go.Figure(
        go.Scatter(
            x=s["LAG_WEEKS"],
            y=s["CORRELATION_COEFFICIENT"],
            mode="lines+markers",
            line=dict(color=COLORS["primary"], width=3),
            marker=dict(size=9),
        )
    )
    fig.add_hline(y=0, line_color=COLORS["text_muted"])
    fig = apply_dark_theme(fig, height=280)
    fig.update_layout(
        xaxis_title="Lag (weeks)",
        yaxis_title="Correlation",
        yaxis=dict(range=[-1, 1]),
        xaxis=dict(tickmode="linear", dtick=1),
    )
    st.plotly_chart(fig, use_container_width=True)
    b = s[s["IS_OPTIMAL_LAG"]]
    cols = st.columns(3)
    if not b.empty:
        b = b.iloc[0]
        with cols[0]:
            st.markdown(
                metric_card("Strongest lag (this series)", f"{int(b['LAG_WEEKS'])} weeks", icon="⏱️"),
                unsafe_allow_html=True,
            )
        with cols[1]:
            st.markdown(
                metric_card("Correlation at that lag", f"{b['CORRELATION_COEFFICIENT']:+.2f}", icon="📈"),
                unsafe_allow_html=True,
            )
    with cols[2]:
        share = best["IS_SIGNIFICANT"].mean() if not best.empty else 0
        st.markdown(metric_card("Series with a significant lag", f"{share:.0%}", icon="📦"), unsafe_allow_html=True)


def render_what_if(matrix):
    """Volume and margin impact of a price change, using the estimated own-price elasticity."""
    st.markdown(
        section_header("🎮 What-If Simulator", "Uses the estimated own-price elasticity"), unsafe_allow_html=True
    )
    if matrix.empty:
        st.info(NOT_RUN)
        return
    own = matrix[matrix["IS_OWN_PRICE"]].set_index("DEMAND_FAMILY")["ESTIMATED"]
    c1, c2 = st.columns(2)
    with c1:
        family = st.selectbox("Product family", list(own.index), key="whatif_family")
        price_change = st.slider("Price change (%)", -15, 15, 5)
        margin = st.slider("Current margin (%)", 5, 60, 25)
    e = float(own[family])
    q = (1 + price_change / 100) ** e
    p = 1 + price_change / 100
    new_margin_value = (p - (1 - margin / 100)) * q
    old_margin_value = margin / 100
    with c2:
        st.markdown(
            f"""
        <div style="background: {COLORS["card"]}; border: 1px solid {COLORS["border"]}; border-radius: 8px;
            padding: 1rem;">
            <h4 style="color: {COLORS["text"]}; margin: 0 0 1rem 0;">Impact ({family}, elasticity {e:.2f})</h4>
            <p style="color: {COLORS["text_muted"]};">
                <strong>Volume impact:</strong> {(q - 1) * 100:+.1f}%<br>
                <strong>Revenue impact:</strong> {(p * q - 1) * 100:+.1f}%<br>
                <strong>Margin impact:</strong> {(new_margin_value / old_margin_value - 1) * 100:+.1f}%
            </p>
        </div>
        """,
            unsafe_allow_html=True,
        )


def render_sidebar():
    """Sidebar with the models used."""
    with st.sidebar:
        st.markdown(
            f"""
        <div style="padding: 1rem 0; border-bottom: 1px solid {COLORS["border"]}; margin-bottom: 1rem;">
            <h2 style="margin: 0; color: {COLORS["text"]};">🧪 Chemicals Pricing</h2>
            <p style="color: {COLORS["text_muted"]}; margin: 0.5rem 0 0 0; font-size: 0.9rem;">Supply Chain
                Optimization</p>
        </div>
        """,
            unsafe_allow_html=True,
        )
        st.markdown("### ML Models")
        st.markdown("""
        - **Demand forecast**: XGBoost (weekly, 4-week horizon)
        - **Price elasticity**: log-log OLS per product
        - **Cross-price elasticity**: SUR over product families
        - **Price optimization**: scipy SLSQP
        """)
        st.caption("Recompute: CALL SF_SOLUTIONS.CHP_OPS.SP_RUN_ML_PIPELINE();")


def main():
    """Render the page."""
    session = get_session()
    render_sidebar()
    render_header()
    fc = load_forecasts(session)
    matrix = load_matrix(session)
    render_model_metrics(fc, matrix)
    st.markdown("---")
    render_matrix(matrix)
    st.markdown("---")
    col1, col2 = st.columns(2)
    with col1:
        render_forecast(session, fc)
        render_what_if(matrix)
    with col2:
        render_feature_importance(fc)
        render_product_elasticity(load_product_elasticity(session))
    st.markdown("---")
    render_lags(load_lags(session))


if __name__ == "__main__":
    main()
