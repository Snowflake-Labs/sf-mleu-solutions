"""Chemicals Pricing Dashboard.

Page 2: Pricing Desk (Operational View)

Persona: Supply Chain Manager
Task: "Quote a price for Customer X"

Visuals:
- Price Guidance: "Target: $1.50/lb (Floor: $1.42)"
- Drivers: "Why? Feedstock +3%, Competitor Index +2%"
- Action: "Generate Quote"
"""

import pandas as pd
import plotly.graph_objects as go
import streamlit as st
from snowflake.snowpark.context import get_active_session
from utils.theme import (
    COLORS,
    MARGIN_STATUS_COLORS,
    apply_dark_theme,
    get_page_css,
    metric_card,
    section_header,
)

# Page configuration
st.set_page_config(
    page_title="Chemicals Pricing - Pricing Desk", page_icon="💵", layout="wide", initial_sidebar_state="expanded"
)

st.markdown(get_page_css(), unsafe_allow_html=True)


@st.cache_resource
def get_session():
    """Get session."""
    return get_active_session()


@st.cache_data(ttl=300)
def load_products(_session):
    """Load product list for selection."""
    query = """
    SELECT DISTINCT product_id, product_name, product_family
    FROM SF_SOLUTIONS.CHP_ATOMIC.PRODUCT
    WHERE is_active = TRUE
    ORDER BY product_family, product_name
    """
    return _session.sql(query).to_pandas()


@st.cache_data(ttl=300)
def load_customers(_session):
    """Load customer list for selection."""
    query = """
    SELECT DISTINCT customer_id, customer_name, customer_segment, customer_tier, primary_region
    FROM SF_SOLUTIONS.CHP_ATOMIC.CUSTOMER
    WHERE is_active = TRUE
    ORDER BY customer_tier, customer_name
    """
    return _session.sql(query).to_pandas()


@st.cache_data(ttl=300)
def load_price_guidance(_session, product_id: str, region: str):
    """Load price guidance for a product/region."""
    query = """
    SELECT
        product_id,
        product_name,
        destination_region,
        feedstock_cost_per_mt,
        conversion_cost_per_mt,
        freight_cost_per_mt,
        total_cost_to_serve_per_mt,
        floor_price_per_mt,
        target_price_per_mt,
        feedstock_7d_change_pct,
        avg_selling_price_30d,
        pricing_recommendation
    FROM SF_SOLUTIONS.CHP_OPS.PRICE_GUIDANCE
    WHERE product_id = ?
      AND destination_region = ?
    LIMIT 1
    """
    return _session.sql(query, params=[product_id, region]).to_pandas()


@st.cache_data(ttl=300)
def load_customer_history(_session, customer_id: str, product_id: str):
    """Load customer purchase history for a product."""
    query = """
    SELECT
        order_date,
        sales_volume_mt as quantity_mt,
        selling_price_per_mt,
        gross_margin_pct,
        margin_status
    FROM SF_SOLUTIONS.CHP_OPS.MARGIN_ANALYZER
    WHERE customer_id = ?
      AND product_id = ?
    ORDER BY order_date DESC
    LIMIT 10
    """
    return _session.sql(query, params=[customer_id, product_id]).to_pandas()


@st.cache_data(ttl=300)
def load_contract_terms(_session, customer_id: str, product_id: str):
    """Load contract terms if exists."""
    query = """
    SELECT
        contract_id,
        price_formula,
        floor_price,
        ceiling_price,
        min_volume_mt,
        effective_date,
        expiration_date
    FROM SF_SOLUTIONS.CHP_ATOMIC.CONTRACT_TERM
    WHERE customer_id = ?
      AND product_id = ?
      AND contract_status = 'ACTIVE'
      AND expiration_date >= CURRENT_DATE()
    LIMIT 1
    """
    return _session.sql(query, params=[customer_id, product_id]).to_pandas()


def render_header():
    """Render header."""
    st.markdown(
        f"""
    <div style="margin-bottom: 2rem;">
        <h1 style="margin-bottom: 0.5rem;">💵 Pricing Desk</h1>
        <p style="color: {COLORS["text_muted"]}; font-size: 1.1rem;">
            Operational View • Supply Chain Manager • Generate Customer Quotes
        </p>
    </div>
    """,
        unsafe_allow_html=True,
    )


def render_price_guidance(guidance_df):
    """Render price guidance panel."""
    if len(guidance_df) == 0:
        st.warning("No pricing guidance available for this selection")
        return

    row = guidance_df.iloc[0]

    floor_price = float(row["FLOOR_PRICE_PER_MT"]) if pd.notna(row["FLOOR_PRICE_PER_MT"]) else 0
    target_price = float(row["TARGET_PRICE_PER_MT"]) if pd.notna(row["TARGET_PRICE_PER_MT"]) else 0
    cost = float(row["TOTAL_COST_TO_SERVE_PER_MT"]) if pd.notna(row["TOTAL_COST_TO_SERVE_PER_MT"]) else 0
    historical = float(row["AVG_SELLING_PRICE_30D"]) if pd.notna(row["AVG_SELLING_PRICE_30D"]) else target_price

    st.markdown(section_header("💡 Price Guidance", row.get("PRICING_RECOMMENDATION", "")), unsafe_allow_html=True)

    cols = st.columns(4)

    with cols[0]:
        st.markdown(metric_card("Floor Price", f"${floor_price:,.0f}/MT", icon="🔽"), unsafe_allow_html=True)

    with cols[1]:
        st.markdown(metric_card("Target Price", f"${target_price:,.0f}/MT", icon="🎯"), unsafe_allow_html=True)

    with cols[2]:
        st.markdown(metric_card("Cost to Serve", f"${cost:,.0f}/MT", icon="💰"), unsafe_allow_html=True)

    with cols[3]:
        st.markdown(metric_card("30-Day Avg", f"${historical:,.0f}/MT", icon="📊"), unsafe_allow_html=True)

    # Price gauge
    st.markdown("<br>", unsafe_allow_html=True)

    fig = go.Figure(
        go.Indicator(
            mode="gauge+number+delta",
            value=target_price,
            number={"prefix": "$", "suffix": "/MT"},
            delta={"reference": historical, "relative": True, "valueformat": ".1%"},
            gauge={
                "axis": {"range": [cost * 0.9, target_price * 1.3]},
                "bar": {"color": COLORS["primary"]},
                "steps": [
                    {"range": [cost * 0.9, floor_price], "color": "rgba(239, 68, 68, 0.25)"},  # danger
                    {"range": [floor_price, target_price], "color": "rgba(245, 158, 11, 0.25)"},  # warning
                    {"range": [target_price, target_price * 1.3], "color": "rgba(34, 197, 94, 0.25)"},  # success
                ],
                "threshold": {"line": {"color": COLORS["text"], "width": 2}, "thickness": 0.75, "value": target_price},
            },
            title={"text": "Recommended Price", "font": {"color": COLORS["text"]}},
        )
    )

    fig = apply_dark_theme(fig, height=250)
    st.plotly_chart(fig, use_container_width=True)


def render_cost_breakdown(guidance_df):
    """Render cost breakdown waterfall."""
    if len(guidance_df) == 0:
        return

    row = guidance_df.iloc[0]

    st.markdown(section_header("Cost Breakdown", "Components of cost to serve"), unsafe_allow_html=True)

    feedstock = float(row["FEEDSTOCK_COST_PER_MT"]) if pd.notna(row["FEEDSTOCK_COST_PER_MT"]) else 0
    conversion = float(row["CONVERSION_COST_PER_MT"]) if pd.notna(row["CONVERSION_COST_PER_MT"]) else 0
    freight = float(row["FREIGHT_COST_PER_MT"]) if pd.notna(row["FREIGHT_COST_PER_MT"]) else 0
    total = float(row["TOTAL_COST_TO_SERVE_PER_MT"]) if pd.notna(row["TOTAL_COST_TO_SERVE_PER_MT"]) else 0

    fig = go.Figure(
        go.Waterfall(
            name="Cost Breakdown",
            orientation="v",
            measure=["absolute", "relative", "relative", "total"],
            x=["Feedstock", "Conversion", "Freight", "Total Cost"],
            y=[feedstock, conversion, freight, total],
            connector={"line": {"color": COLORS["border"]}},
            increasing={"marker": {"color": COLORS["chart_1"]}},
            totals={"marker": {"color": COLORS["primary"]}},
            text=[f"${v:,.0f}" for v in [feedstock, conversion, freight, total]],
            textposition="outside",
        )
    )

    fig = apply_dark_theme(fig, height=300)
    fig.update_layout(yaxis_title="$/MT", showlegend=False)

    st.plotly_chart(fig, use_container_width=True)


def render_market_drivers(guidance_df):
    """Render market drivers affecting price."""
    if len(guidance_df) == 0:
        return

    row = guidance_df.iloc[0]

    st.markdown(section_header("📈 Market Drivers", "Why this price recommendation?"), unsafe_allow_html=True)

    feedstock_change = float(row["FEEDSTOCK_7D_CHANGE_PCT"]) if pd.notna(row["FEEDSTOCK_7D_CHANGE_PCT"]) else 0

    drivers = [
        ("Feedstock Cost", f"{feedstock_change:+.1f}%", feedstock_change > 0),
        ("Inventory Level", "Healthy", False),
        ("Demand Trend", "Stable", False),
    ]

    for driver, value, is_negative in drivers:
        color = COLORS["danger"] if is_negative else COLORS["success"]
        icon = "⬆️" if is_negative else "✓"

        st.markdown(
            f"""
        <div style="
            background: {COLORS["card"]};
            border: 1px solid {COLORS["border"]};
            border-radius: 8px;
            padding: 0.75rem 1rem;
            margin-bottom: 0.5rem;
            display: flex;
            justify-content: space-between;
            align-items: center;
        ">
            <span style="color: {COLORS["text_muted"]};">{driver}</span>
            <span style="color: {color}; font-weight: 600;">{icon} {value}</span>
        </div>
        """,
            unsafe_allow_html=True,
        )


def render_contract_info(contract_df):
    """Render contract information if exists."""
    st.markdown(section_header("📋 Contract Terms", "Active contract details"), unsafe_allow_html=True)

    if len(contract_df) == 0:
        st.info("No active contract for this customer/product combination. Spot pricing applies.")
        return

    row = contract_df.iloc[0]

    st.markdown(
        f"""
    <div style="
        background: {COLORS["card"]};
        border: 1px solid {COLORS["border"]};
        border-radius: 8px;
        padding: 1rem;
    ">
        <div style="color: {COLORS["text"]}; font-weight: 600; margin-bottom: 0.75rem;">
            Contract: {row["CONTRACT_ID"]}
        </div>
        <div style="color: {COLORS["text_muted"]}; font-size: 0.9rem;">
            <p><strong>Formula:</strong> {row["PRICE_FORMULA"]}</p>
            <p><strong>Floor:</strong> ${row["FLOOR_PRICE"]:,.0f}/MT | <strong>Ceiling:</strong>
                ${row["CEILING_PRICE"]:,.0f}/MT</p>
            <p><strong>Min Volume:</strong> {row["MIN_VOLUME_MT"]:,.0f} MT/year</p>
            <p><strong>Valid:</strong> {row["EFFECTIVE_DATE"]} to {row["EXPIRATION_DATE"]}</p>
        </div>
    </div>
    """,
        unsafe_allow_html=True,
    )


def render_customer_history(history_df):
    """Render customer purchase history."""
    st.markdown(section_header("📜 Purchase History", "Recent transactions with this customer"), unsafe_allow_html=True)

    if len(history_df) == 0:
        st.info("No purchase history for this customer/product combination.")
        return

    for _, row in history_df.head(5).iterrows():
        status = row["MARGIN_STATUS"]
        status_color = MARGIN_STATUS_COLORS.get(status, COLORS["text_muted"])

        st.markdown(
            f"""
        <div style="
            background: {COLORS["card"]};
            border: 1px solid {COLORS["border"]};
            border-radius: 8px;
            padding: 0.75rem 1rem;
            margin-bottom: 0.5rem;
        ">
            <div style="display: flex; justify-content: space-between; align-items: center;">
                <div>
                    <span style="color: {COLORS["text_muted"]};">{row["ORDER_DATE"]}</span>
                    <span style="color: {COLORS["text"]}; margin-left: 1rem;">{row["QUANTITY_MT"]:,.0f} MT</span>
                </div>
                <div>
                    <span style="color: {COLORS["text"]};
                        font-weight: 600;">${row["SELLING_PRICE_PER_MT"]:,.0f}/MT</span>
                    <span style="
                        background: {status_color}22;
                        color: {status_color};
                        padding: 0.2rem 0.5rem;
                        border-radius: 4px;
                        font-size: 0.75rem;
                        margin-left: 0.5rem;
                    ">{row["GROSS_MARGIN_PCT"]:.1f}%</span>
                </div>
            </div>
        </div>
        """,
            unsafe_allow_html=True,
        )


def render_quote_generator():
    """Render quote generation form."""
    st.markdown(section_header("📝 Generate Quote", "Create a new price quote"), unsafe_allow_html=True)

    with st.form("quote_form"):
        cols = st.columns(2)

        with cols[0]:
            quantity = st.number_input("Quantity (MT)", min_value=1, value=100)
            st.date_input("Delivery Date")

        with cols[1]:
            quote_price = st.number_input("Quote Price ($/MT)", min_value=0.0, value=1400.0)
            st.selectbox("Incoterms", ["FOB", "CIF", "DDP", "DAP"])

        st.text_area("Notes", placeholder="Additional terms or conditions...")

        submitted = st.form_submit_button("📄 Generate Quote", use_container_width=True)

        if submitted:
            total_value = quantity * quote_price
            st.success(f"✅ Quote generated: {quantity} MT @ ${quote_price:,.0f}/MT = ${total_value:,.0f} total")


def render_sidebar():
    """Render sidebar."""
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

        st.markdown("### Quick Actions")
        st.markdown("""
        - 💵 **Pricing Desk** *(current)*
        - View price guidance
        - Generate customer quotes
        - Check contract terms
        """)


def main():
    """Main."""
    session = get_session()

    render_sidebar()
    render_header()

    # Load selection data
    products_df = load_products(session)
    customers_df = load_customers(session)

    # Selection controls
    st.markdown(
        section_header("🔍 Select Customer & Product", "Choose to get pricing guidance"), unsafe_allow_html=True
    )

    col1, col2, col3 = st.columns([2, 2, 1])

    with col1:
        customer_options = customers_df.apply(
            lambda x: f"{x['CUSTOMER_NAME']} ({x['CUSTOMER_TIER']} - {x['PRIMARY_REGION']})", axis=1
        ).tolist()
        selected_customer_idx = st.selectbox(
            "Customer", range(len(customer_options)), format_func=lambda x: customer_options[x]
        )
        selected_customer = customers_df.iloc[selected_customer_idx]

    with col2:
        product_options = products_df.apply(lambda x: f"{x['PRODUCT_NAME']} ({x['PRODUCT_FAMILY']})", axis=1).tolist()
        selected_product_idx = st.selectbox(
            "Product", range(len(product_options)), format_func=lambda x: product_options[x]
        )
        selected_product = products_df.iloc[selected_product_idx]

    with col3:
        st.markdown("<br>", unsafe_allow_html=True)
        if st.button("🔄 Refresh", use_container_width=True):
            st.cache_data.clear()
            st.rerun()

    st.markdown("---")

    # Load data for selection
    guidance_df = load_price_guidance(session, selected_product["PRODUCT_ID"], selected_customer["PRIMARY_REGION"])
    contract_df = load_contract_terms(session, selected_customer["CUSTOMER_ID"], selected_product["PRODUCT_ID"])
    history_df = load_customer_history(session, selected_customer["CUSTOMER_ID"], selected_product["PRODUCT_ID"])

    # Main content
    col1, col2 = st.columns([2, 1])

    with col1:
        render_price_guidance(guidance_df)
        render_cost_breakdown(guidance_df)
        render_quote_generator()

    with col2:
        render_market_drivers(guidance_df)
        render_contract_info(contract_df)
        render_customer_history(history_df)


if __name__ == "__main__":
    main()
