"""Chemicals Integrated Pricing & Supply Chain Dashboard.

Page 1: Margin Command (Strategic View)

Persona: VP Commercial
Situation: "Feedstock costs spiked 10%. Are we passing it on?"

Visuals:
- Spread Chart: Selling Price vs. Raw Material Cost trend
- Leakage Waterfall: Where margin is lost (Freight, Discounts, Rebates)
"""

import pandas as pd
import plotly.graph_objects as go
import streamlit as st
from snowflake.snowpark.context import get_active_session
from utils.theme import (
    COLORS,
    MARGIN_STATUS_COLORS,
    REGION_COLORS,
    apply_dark_theme,
    get_page_css,
    metric_card,
    section_header,
)

# Page configuration
st.set_page_config(
    page_title="Chemicals Pricing - Margin Command", page_icon="🧪", layout="wide", initial_sidebar_state="expanded"
)

# Apply custom CSS
st.markdown(get_page_css(), unsafe_allow_html=True)


@st.cache_resource
def get_session():
    """Get Snowflake session."""
    return get_active_session()


@st.cache_data(ttl=300)
def load_margin_summary(_session):
    """Load margin summary metrics."""
    query = """
    SELECT
        COUNT(DISTINCT order_id) as total_orders,
        SUM(sales_volume_mt) as total_volume_mt,
        SUM(net_revenue) as total_revenue,
        SUM(gross_margin) as total_margin,
        AVG(gross_margin_pct) as avg_margin_pct,
        SUM(CASE WHEN margin_status IN ('LOSS', 'UNDERPRICED') THEN 1 ELSE 0 END) as underpriced_deals,
        SUM(CASE WHEN margin_status IN ('LOSS', 'UNDERPRICED') THEN gross_margin ELSE 0 END)
            as underpriced_margin_impact
    FROM SF_SOLUTIONS.CHP_OPS.MARGIN_ANALYZER
    WHERE order_date >= DATEADD(day, -30, (SELECT MAX(order_date) FROM SF_SOLUTIONS.CHP_OPS.MARGIN_ANALYZER))
    """
    return _session.sql(query).to_pandas()


@st.cache_data(ttl=300)
def load_margin_by_status(_session):
    """Load margin breakdown by status."""
    query = """
    SELECT
        margin_status,
        COUNT(*) as deal_count,
        SUM(gross_margin) as total_margin,
        AVG(gross_margin_pct) as avg_margin_pct
    FROM SF_SOLUTIONS.CHP_OPS.MARGIN_ANALYZER
    WHERE order_date >= DATEADD(day, -30, (SELECT MAX(order_date) FROM SF_SOLUTIONS.CHP_OPS.MARGIN_ANALYZER))
    GROUP BY margin_status
    ORDER BY
        CASE margin_status
            WHEN 'LOSS' THEN 1
            WHEN 'UNDERPRICED' THEN 2
            WHEN 'BELOW_TARGET' THEN 3
            ELSE 4
        END
    """
    return _session.sql(query).to_pandas()


@st.cache_data(ttl=300)
def load_price_vs_cost_trend(_session):
    """Load selling price vs feedstock cost trend."""
    query = """
    SELECT
        DATE_TRUNC('week', order_date) as week,
        AVG(selling_price_per_mt) as avg_selling_price,
        AVG(feedstock_cost_per_mt) as avg_feedstock_cost,
        AVG(gross_margin_pct) as avg_margin_pct
    FROM SF_SOLUTIONS.CHP_OPS.MARGIN_ANALYZER
    WHERE order_date >= DATEADD(day, -90, (SELECT MAX(order_date) FROM SF_SOLUTIONS.CHP_OPS.MARGIN_ANALYZER))
      AND feedstock_cost_per_mt > 0
    GROUP BY DATE_TRUNC('week', order_date)
    ORDER BY week
    """
    return _session.sql(query).to_pandas()


@st.cache_data(ttl=300)
def load_margin_leakage(_session):
    """Load margin leakage breakdown."""
    query = """
    SELECT
        SUM(gross_revenue) as gross_revenue,
        SUM(discount_amount) as total_discounts,
        SUM(rebate_amount) as total_rebates,
        SUM(freight_cost) as total_freight,
        SUM(total_product_cost) as total_product_cost,
        SUM(gross_margin) as net_margin
    FROM SF_SOLUTIONS.CHP_OPS.MARGIN_ANALYZER
    WHERE order_date >= DATEADD(day, -30, (SELECT MAX(order_date) FROM SF_SOLUTIONS.CHP_OPS.MARGIN_ANALYZER))
    """
    return _session.sql(query).to_pandas()


@st.cache_data(ttl=300)
def load_margin_by_region(_session):
    """Load margin by region."""
    query = """
    SELECT
        region,
        SUM(net_revenue) as total_revenue,
        SUM(gross_margin) as total_margin,
        AVG(gross_margin_pct) as avg_margin_pct,
        SUM(sales_volume_mt) as total_volume
    FROM SF_SOLUTIONS.CHP_OPS.MARGIN_ANALYZER
    WHERE order_date >= DATEADD(day, -30, (SELECT MAX(order_date) FROM SF_SOLUTIONS.CHP_OPS.MARGIN_ANALYZER))
    GROUP BY region
    ORDER BY total_margin DESC
    """
    return _session.sql(query).to_pandas()


@st.cache_data(ttl=300)
def load_margin_by_product_family(_session):
    """Load margin by product family."""
    query = """
    SELECT
        product_family,
        SUM(net_revenue) as total_revenue,
        SUM(gross_margin) as total_margin,
        AVG(gross_margin_pct) as avg_margin_pct,
        SUM(sales_volume_mt) as total_volume
    FROM SF_SOLUTIONS.CHP_OPS.MARGIN_ANALYZER
    WHERE order_date >= DATEADD(day, -30, (SELECT MAX(order_date) FROM SF_SOLUTIONS.CHP_OPS.MARGIN_ANALYZER))
    GROUP BY product_family
    ORDER BY total_margin DESC
    """
    return _session.sql(query).to_pandas()


@st.cache_data(ttl=300)
def load_feedstock_trends(_session):
    """Load latest feedstock price trends."""
    query = """
    SELECT
        index_name,
        current_price,
        price_change_pct_7d,
        price_trend
    FROM SF_SOLUTIONS.CHP_OPS.MARKET_TRENDS
    WHERE index_code IN ('ETH-DEL-USG', 'PP-DEL-USG', 'CRUDE-BRENT', 'NAPHTHA-CIF-NWE')
    QUALIFY ROW_NUMBER() OVER (PARTITION BY index_code ORDER BY index_date DESC) = 1
    """
    return _session.sql(query).to_pandas()


def render_header():
    """Render page header."""
    st.markdown(
        f"""
    <div style="margin-bottom: 2rem;">
        <h1 style="margin-bottom: 0.5rem;">🧪 Margin Command</h1>
        <p style="color: {COLORS["text_muted"]}; font-size: 1.1rem;">
            Strategic View • VP Commercial • Last 30 Days Performance
        </p>
    </div>
    """,
        unsafe_allow_html=True,
    )


def render_kpi_cards(summary_df):
    """Render top KPI metric cards."""
    if len(summary_df) == 0:
        st.warning("No margin data available")
        return

    row = summary_df.iloc[0]

    cols = st.columns(5)

    with cols[0]:
        revenue = float(row["TOTAL_REVENUE"]) if pd.notna(row["TOTAL_REVENUE"]) else 0
        st.markdown(metric_card("Total Revenue", f"${revenue / 1e6:,.1f}M", icon="💰"), unsafe_allow_html=True)

    with cols[1]:
        margin = float(row["TOTAL_MARGIN"]) if pd.notna(row["TOTAL_MARGIN"]) else 0
        st.markdown(metric_card("Total Margin", f"${margin / 1e6:,.1f}M", icon="📈"), unsafe_allow_html=True)

    with cols[2]:
        margin_pct = float(row["AVG_MARGIN_PCT"]) if pd.notna(row["AVG_MARGIN_PCT"]) else 0
        st.markdown(metric_card("Avg Margin %", f"{margin_pct:.1f}%", icon="📊"), unsafe_allow_html=True)

    with cols[3]:
        volume = float(row["TOTAL_VOLUME_MT"]) if pd.notna(row["TOTAL_VOLUME_MT"]) else 0
        st.markdown(metric_card("Volume (MT)", f"{volume / 1000:,.0f}K", icon="📦"), unsafe_allow_html=True)

    with cols[4]:
        underpriced = int(row["UNDERPRICED_DEALS"]) if pd.notna(row["UNDERPRICED_DEALS"]) else 0
        st.markdown(
            metric_card("Underpriced Deals", f"{underpriced}", delta_color="inverse", icon="⚠️"), unsafe_allow_html=True
        )


def render_spread_chart(trend_df):
    """Render selling price vs feedstock cost spread chart."""
    st.markdown(
        section_header("Price vs Cost Spread", "Are we passing through feedstock increases?"), unsafe_allow_html=True
    )

    if len(trend_df) == 0:
        st.info("No trend data available")
        return

    fig = go.Figure()

    # Selling price line
    fig.add_trace(
        go.Scatter(
            x=trend_df["WEEK"],
            y=trend_df["AVG_SELLING_PRICE"],
            name="Selling Price",
            line=dict(color=COLORS["success"], width=3),
            mode="lines+markers",
        )
    )

    # Feedstock cost line
    fig.add_trace(
        go.Scatter(
            x=trend_df["WEEK"],
            y=trend_df["AVG_FEEDSTOCK_COST"],
            name="Feedstock Cost",
            line=dict(color=COLORS["danger"], width=3),
            mode="lines+markers",
        )
    )

    # Spread area
    fig.add_trace(
        go.Scatter(
            x=trend_df["WEEK"],
            y=trend_df["AVG_SELLING_PRICE"] - trend_df["AVG_FEEDSTOCK_COST"],
            name="Spread",
            fill="tozeroy",
            fillcolor="rgba(14, 165, 233, 0.19)",  # primary with 30% opacity
            line=dict(color=COLORS["primary"], width=1, dash="dot"),
        )
    )

    fig = apply_dark_theme(fig, height=350)
    fig.update_layout(
        yaxis_title="$/MT",
        legend=dict(orientation="h", yanchor="bottom", y=1.02, xanchor="right", x=1),
        hovermode="x unified",
    )

    st.plotly_chart(fig, use_container_width=True)


def render_leakage_waterfall(leakage_df):
    """Render margin leakage waterfall chart."""
    st.markdown(section_header("Margin Waterfall", "Where is margin being lost?"), unsafe_allow_html=True)

    if len(leakage_df) == 0:
        st.info("No leakage data available")
        return

    row = leakage_df.iloc[0]

    # Build waterfall data
    categories = ["Gross Revenue", "Discounts", "Rebates", "Freight", "Product Cost", "Net Margin"]
    values = [
        float(row["GROSS_REVENUE"]) / 1e6,
        -float(row["TOTAL_DISCOUNTS"]) / 1e6,
        -float(row["TOTAL_REBATES"]) / 1e6,
        -float(row["TOTAL_FREIGHT"]) / 1e6,
        -float(row["TOTAL_PRODUCT_COST"]) / 1e6,
        float(row["NET_MARGIN"]) / 1e6,
    ]

    fig = go.Figure(
        go.Waterfall(
            name="Margin Waterfall",
            orientation="v",
            measure=["absolute", "relative", "relative", "relative", "relative", "total"],
            x=categories,
            y=values,
            connector={"line": {"color": COLORS["border"]}},
            decreasing={"marker": {"color": COLORS["danger"]}},
            increasing={"marker": {"color": COLORS["success"]}},
            totals={"marker": {"color": COLORS["primary"]}},
            text=[f"${v:,.1f}M" for v in values],
            textposition="outside",
        )
    )

    fig = apply_dark_theme(fig, height=350)
    fig.update_layout(yaxis_title="$ Millions", showlegend=False)

    st.plotly_chart(fig, use_container_width=True)


def render_margin_by_status(status_df):
    """Render margin breakdown by status."""
    st.markdown(section_header("Deal Quality", "Margin status distribution"), unsafe_allow_html=True)

    if len(status_df) == 0:
        st.info("No status data available")
        return

    # Create donut chart
    colors = [MARGIN_STATUS_COLORS.get(s, COLORS["text_muted"]) for s in status_df["MARGIN_STATUS"]]

    fig = go.Figure(
        data=[
            go.Pie(
                labels=status_df["MARGIN_STATUS"],
                values=status_df["DEAL_COUNT"],
                hole=0.6,
                marker_colors=colors,
                textinfo="label+percent",
                textposition="outside",
            )
        ]
    )

    fig = apply_dark_theme(fig, height=300)
    fig.update_layout(
        showlegend=False,
        annotations=[dict(text="Deals", x=0.5, y=0.5, font_size=16, showarrow=False, font_color=COLORS["text_muted"])],
    )

    st.plotly_chart(fig, use_container_width=True)


def render_margin_by_region(region_df):
    """Render margin by region."""
    st.markdown(section_header("Regional Performance", "Margin by geography"), unsafe_allow_html=True)

    if len(region_df) == 0:
        st.info("No regional data available")
        return

    colors = [REGION_COLORS.get(r, COLORS["chart_1"]) for r in region_df["REGION"]]

    fig = go.Figure(
        data=[
            go.Bar(
                x=region_df["REGION"],
                y=region_df["AVG_MARGIN_PCT"],
                marker_color=colors,
                text=[f"{v:.1f}%" for v in region_df["AVG_MARGIN_PCT"]],
                textposition="outside",
            )
        ]
    )

    fig = apply_dark_theme(fig, height=300)
    fig.update_layout(yaxis_title="Margin %", xaxis_title="", showlegend=False)

    st.plotly_chart(fig, use_container_width=True)


def render_feedstock_alerts(feedstock_df):
    """Render feedstock price alerts."""
    st.markdown(section_header("Feedstock Alerts", "Market price movements"), unsafe_allow_html=True)

    if len(feedstock_df) == 0:
        st.info("No feedstock data available")
        return

    for _, row in feedstock_df.iterrows():
        # trend = row["PRICE_TREND"]
        change = float(row["PRICE_CHANGE_PCT_7D"]) if pd.notna(row["PRICE_CHANGE_PCT_7D"]) else 0
        price = float(row["CURRENT_PRICE"]) if pd.notna(row["CURRENT_PRICE"]) else 0

        trend_color = COLORS["danger"] if change > 5 else COLORS["success"] if change < -5 else COLORS["info"]
        trend_icon = "📈" if change > 0 else "📉" if change < 0 else "➡️"

        st.markdown(
            f"""
        <div style="
            background: {COLORS["card"]};
            border: 1px solid {COLORS["border"]};
            border-left: 4px solid {trend_color};
            border-radius: 8px;
            padding: 0.75rem 1rem;
            margin-bottom: 0.5rem;
        ">
            <div style="display: flex; justify-content: space-between; align-items: center;">
                <div>
                    <span style="color: {COLORS["text"]}; font-weight: 500;">{row["INDEX_NAME"]}</span>
                </div>
                <div style="text-align: right;">
                    <span style="color: {COLORS["text"]}; font-weight: 600;">${price:,.0f}</span>
                    <span style="color: {trend_color}; margin-left: 0.5rem;">{trend_icon} {change:+.1f}%</span>
                </div>
            </div>
        </div>
        """,
            unsafe_allow_html=True,
        )


def render_sidebar():
    """Render sidebar navigation."""
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

        st.markdown("""
        ### Navigation

        **Strategic**
        - 📊 Margin Command *(current)*

        **Operational**
        - 💵 Pricing Desk

        **Technical**
        - 🔬 Data Science Workbench

        **Intelligence**
        - 📄 Market Intelligence
        - 🤖 Ask Cortex
        """)

        st.markdown("---")

        st.markdown("""
        ### 🎯 What to watch

        - **Margin leakage**: LOSS and UNDERPRICED deals
        - **Cost pass-through**: price vs feedstock spread
        - **Price sensitivity**: see the Data Science Workbench
        """)


def main():
    """Main application entry point."""
    session = get_session()

    render_sidebar()
    render_header()

    # Load data
    with st.spinner("Loading margin data..."):
        summary_df = load_margin_summary(session)
        status_df = load_margin_by_status(session)
        trend_df = load_price_vs_cost_trend(session)
        leakage_df = load_margin_leakage(session)
        region_df = load_margin_by_region(session)
        feedstock_df = load_feedstock_trends(session)

    # KPI Cards
    render_kpi_cards(summary_df)

    st.markdown("---")

    # Main charts - two columns
    col1, col2 = st.columns([2, 1])

    with col1:
        render_spread_chart(trend_df)
        render_leakage_waterfall(leakage_df)

    with col2:
        render_margin_by_status(status_df)
        render_margin_by_region(region_df)
        render_feedstock_alerts(feedstock_df)

    # Footer
    st.markdown(
        f"""
    <div style="
        margin-top: 3rem;
        padding-top: 1rem;
        border-top: 1px solid {COLORS["border"]};
        color: {COLORS["text_muted"]};
        font-size: 0.85rem;
        text-align: center;
    ">
        Chemicals Integrated Pricing & Supply Chain • Powered by Snowflake Cortex
    </div>
    """,
        unsafe_allow_html=True,
    )


if __name__ == "__main__":
    main()
