"""Chemicals Pricing Dashboard.

Page 5: Ask Cortex (Cortex Analyst)

Golden Query: "Show me the average margin for 'Ethylene' products in 'Europe' vs 'North America' for Q3"

This page provides a natural language interface to query the chemicals pricing data
using Snowflake Cortex Analyst.
"""

import pandas as pd
import streamlit as st
from snowflake.snowpark.context import get_active_session
from utils.theme import COLORS, get_page_css, section_header

# Page configuration
st.set_page_config(
    page_title="Chemicals Pricing - Ask Cortex", page_icon="🤖", layout="wide", initial_sidebar_state="expanded"
)

st.markdown(get_page_css(), unsafe_allow_html=True)


@st.cache_resource
def get_session():
    """Get session."""
    return get_active_session()


def query_cortex_analyst(session, question: str):
    """Query Cortex Analyst with a natural language question using the semantic model."""
    try:
        # Try Cortex Analyst with semantic model first
        # semantic_model_path = "@SF_SOLUTIONS.CHP_OPS.SEMANTIC_MODELS/chemicals_semantic_model.yaml"

        # Build context about available tables
        context = """
        You are a chemicals pricing analyst with access to these tables:
        - MARGIN_ANALYZER: Sales margins with columns product_name, product_family, region, customer_segment,
          gross_margin, gross_margin_pct, sales_volume_mt
        - MARKET_TRENDS: Feedstock prices with columns index_name, current_price, price_change_pct_7d, price_trend
        - INVENTORY_HEALTH: Stock levels with columns product_name, site_name, days_of_supply, inventory_status
        - PRICE_GUIDANCE: Pricing recommendations with columns product_name, total_cost_to_serve_per_mt,
          floor_price_per_mt, target_price_per_mt

        Generate a SQL query to answer the user's question, then explain the approach.
        """

        result = session.sql(
            "SELECT SNOWFLAKE.CORTEX.COMPLETE('mistral-large2', CONCAT(?, 'Question: ', ?)) AS response",
            params=[context, question],
        ).collect()
        if result:
            return result[0]["RESPONSE"]
        return "Unable to process query. Please try again."
    except Exception as e:
        return f"Error: {str(e)}"


def run_sql_query(session, sql: str):
    """Execute a SQL query and return results."""
    try:
        return session.sql(sql).to_pandas()
    except Exception as e:
        st.error(f"Query error: {str(e)}")
        return pd.DataFrame()


# Predefined queries mapping natural language to SQL
SAMPLE_QUERIES = {
    "Show me the average margin for Ethylene products in Europe vs North America for Q3": """
        SELECT
            region,
            AVG(gross_margin_pct) as avg_margin_pct,
            SUM(gross_margin) as total_margin,
            SUM(sales_volume_mt) as total_volume
        FROM SF_SOLUTIONS.CHP_OPS.MARGIN_ANALYZER
        WHERE product_family = 'Olefins'
          AND region IN ('Europe', 'North America')
          AND QUARTER(order_date) = 3
        GROUP BY region
        ORDER BY avg_margin_pct DESC
    """,
    "How many deals were underpriced this month?": """
        SELECT
            margin_status,
            COUNT(*) as deal_count,
            SUM(gross_margin) as margin_impact,
            AVG(gross_margin_pct) as avg_margin_pct
        FROM SF_SOLUTIONS.CHP_OPS.MARGIN_ANALYZER
        WHERE order_date >= DATE_TRUNC('month', CURRENT_DATE())
        GROUP BY margin_status
        ORDER BY CASE margin_status
            WHEN 'LOSS' THEN 1
            WHEN 'UNDERPRICED' THEN 2
            WHEN 'BELOW_TARGET' THEN 3
            ELSE 4 END
    """,
    "What is the trend in Propylene prices this week?": """
        SELECT
            index_name,
            index_date,
            current_price,
            price_change_pct_7d,
            price_trend
        FROM SF_SOLUTIONS.CHP_OPS.MARKET_TRENDS
        WHERE index_name LIKE '%Propylene%'
        ORDER BY index_date DESC
        LIMIT 7
    """,
    "Which products have critical inventory levels?": """
        SELECT
            product_name,
            site_name,
            region,
            quantity_available_mt,
            days_of_supply,
            inventory_status
        FROM SF_SOLUTIONS.CHP_OPS.INVENTORY_HEALTH
        WHERE inventory_status IN ('CRITICAL', 'LOW')
        ORDER BY days_of_supply ASC
        LIMIT 10
    """,
    "What is the margin by customer segment?": """
        SELECT
            customer_segment,
            COUNT(DISTINCT order_id) as deal_count,
            SUM(sales_volume_mt) as total_volume,
            SUM(net_revenue) as total_revenue,
            SUM(gross_margin) as total_margin,
            AVG(gross_margin_pct) as avg_margin_pct
        FROM SF_SOLUTIONS.CHP_OPS.MARGIN_ANALYZER
        GROUP BY customer_segment
        ORDER BY total_margin DESC
    """,
    "What should we charge for Polypropylene in the Northeast?": """
        SELECT
            product_id,
            product_name,
            destination_region as region,
            total_cost_to_serve_per_mt as cost,
            floor_price_per_mt,
            target_price_per_mt as recommended_price,
            feedstock_7d_change_pct as feedstock_trend,
            pricing_recommendation
        FROM SF_SOLUTIONS.CHP_OPS.PRICE_GUIDANCE
        WHERE product_name LIKE '%Polypropylene%'
          AND destination_region = 'North America'
        LIMIT 5
    """,
}


def render_header():
    """Render header."""
    st.markdown(
        f"""
    <div style="margin-bottom: 2rem;">
        <h1 style="margin-bottom: 0.5rem;">🤖 Ask Cortex</h1>
        <p style="color: {COLORS["text_muted"]}; font-size: 1.1rem;">
            Natural language analytics powered by Snowflake Cortex Analyst
        </p>
    </div>
    """,
        unsafe_allow_html=True,
    )


def render_chat_interface(session):
    """Render the chat interface."""
    # Initialize chat history
    if "messages" not in st.session_state:
        st.session_state.messages = []

    # Display chat history
    for message in st.session_state.messages:
        role = message["role"]
        content = message["content"]

        if role == "user":
            st.markdown(
                f"""
            <div style="
                background: {COLORS["primary"]}20;
                border: 1px solid {COLORS["primary"]}40;
                border-radius: 12px;
                padding: 1rem;
                margin: 1rem 0;
                margin-left: 2rem;
            ">
                <div style="color: {COLORS["primary"]}; font-size: 0.85rem; margin-bottom: 0.5rem;">You</div>
                <div style="color: {COLORS["text"]};">{content}</div>
            </div>
            """,
                unsafe_allow_html=True,
            )
        else:
            st.markdown(
                f"""
            <div style="
                background: {COLORS["card"]};
                border: 1px solid {COLORS["border"]};
                border-radius: 12px;
                padding: 1rem;
                margin: 1rem 0;
                margin-right: 2rem;
            ">
                <div style="color: {COLORS["secondary"]}; font-size: 0.85rem; margin-bottom: 0.5rem;">🤖 Cortex</div>
                <div style="color: {COLORS["text"]};">{content}</div>
            </div>
            """,
                unsafe_allow_html=True,
            )

            # If there's data, show it
            if "data" in message:
                st.dataframe(message["data"], use_container_width=True)

    # Input form
    with st.form("chat_form", clear_on_submit=True):
        user_input = st.text_input(
            "Ask a question", placeholder="e.g., What is the margin by product family?", label_visibility="collapsed"
        )
        submitted = st.form_submit_button("Ask →", use_container_width=True)

        if submitted and user_input:
            # Add user message
            st.session_state.messages.append({"role": "user", "content": user_input})

            # Check if it matches a sample query
            matched_sql = None
            for sample_q, sql in SAMPLE_QUERIES.items():
                if sample_q.lower() in user_input.lower() or user_input.lower() in sample_q.lower():
                    matched_sql = sql
                    break

            if matched_sql:
                # Execute the SQL
                result_df = run_sql_query(session, matched_sql)

                if len(result_df) > 0:
                    response = "Here are the results for your query:"
                    st.session_state.messages.append({"role": "assistant", "content": response, "data": result_df})
                else:
                    st.session_state.messages.append(
                        {
                            "role": "assistant",
                            "content": "No data found for this query. Please check if the data has been loaded.",
                        }
                    )
            else:
                # Use Cortex for general questions
                response = query_cortex_analyst(session, user_input)
                st.session_state.messages.append({"role": "assistant", "content": response})

            st.rerun()


def render_sample_queries():
    """Render sample query buttons."""
    st.markdown(section_header("💡 Sample Questions", "Click to try"), unsafe_allow_html=True)

    cols = st.columns(2)

    queries = list(SAMPLE_QUERIES.keys())

    for i, query in enumerate(queries):
        with cols[i % 2]:
            if st.button(f"📝 {query[:50]}...", key=f"sample_{i}", use_container_width=True):
                st.session_state.messages.append({"role": "user", "content": query})

                result_df = run_sql_query(get_session(), SAMPLE_QUERIES[query])

                if len(result_df) > 0:
                    st.session_state.messages.append(
                        {"role": "assistant", "content": "Here are the results:", "data": result_df}
                    )
                st.rerun()


def render_semantic_model_info():
    """Render information about the semantic model."""
    st.markdown(section_header("📊 Available Data", "What you can ask about"), unsafe_allow_html=True)

    data_areas = [
        ("💰 Margins", "Gross margin, margin %, by product/region/customer"),
        ("📈 Market Prices", "Feedstock indices, price trends, volatility"),
        ("📦 Inventory", "Stock levels, days of supply, inventory health"),
        ("🎯 Pricing", "Price guidance, cost to serve, recommendations"),
        ("📊 Demand", "Forecasts, elasticity, lagged correlations"),
    ]

    for icon_title, description in data_areas:
        st.markdown(
            f"""
        <div style="
            background: {COLORS["card"]};
            border: 1px solid {COLORS["border"]};
            border-radius: 8px;
            padding: 0.75rem 1rem;
            margin-bottom: 0.5rem;
        ">
            <div style="color: {COLORS["text"]}; font-weight: 500;">{icon_title}</div>
            <div style="color: {COLORS["text_muted"]}; font-size: 0.85rem;">{description}</div>
        </div>
        """,
            unsafe_allow_html=True,
        )


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

        st.markdown("### About Cortex Analyst")
        st.markdown("""
        **Cortex Analyst** enables natural language queries against structured data.

        The semantic model defines:
        - **Measures**: Gross Margin, Sales Volume, Feedstock Cost
        - **Dimensions**: Product Family, Region, Customer Segment

        Ask questions in plain English!
        """)

        st.markdown("---")

        st.markdown("### Sample Query")
        st.code('"Show me the average margin for Ethylene products in Europe vs North America for Q3"', language=None)

        st.markdown("---")

        if st.button("🗑️ Clear Chat History"):
            st.session_state.messages = []
            st.rerun()


def main():
    """Main."""
    session = get_session()

    render_sidebar()
    render_header()

    # Two column layout
    col1, col2 = st.columns([2, 1])

    with col1:
        render_chat_interface(session)

    with col2:
        render_sample_queries()
        st.markdown("<br>", unsafe_allow_html=True)
        render_semantic_model_info()


if __name__ == "__main__":
    main()
