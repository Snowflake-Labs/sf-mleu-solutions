"""Chemicals Pricing Dashboard.

Page 4: Market Intelligence (Cortex Search)

Service Name: MARKET_INTEL_SEARCH
Source Data: synthetic market reports (analyst notes, market outlooks, trade-journal style updates)
Sample Prompt: "What are the supply constraints for Propylene in Asia reported in the last month?"
"""

import json

import pandas as pd
import streamlit as st
from snowflake.snowpark.context import get_active_session
from utils.theme import COLORS, get_page_css, section_header

# Page configuration
st.set_page_config(
    page_title="Chemicals Pricing - Market Intelligence",
    page_icon="📄",
    layout="wide",
    initial_sidebar_state="expanded",
)

st.markdown(get_page_css(), unsafe_allow_html=True)


@st.cache_resource
def get_session():
    """Get session."""
    return get_active_session()


def search_market_intel(session, query: str, filters: dict = None):
    """Search market intelligence using Cortex Search."""
    try:
        request = {
            "query": query,
            "columns": ["chunk", "chemical_name", "region", "report_date", "report_source", "report_title"],
            "limit": 10,
        }
        conditions = [
            {"@eq": {col: filters[key]}}
            for key, col in (("chemical", "chemical_name"), ("region", "region"))
            if filters and filters.get(key)
        ]
        if len(conditions) == 1:
            request["filter"] = conditions[0]
        elif conditions:
            request["filter"] = {"@and": conditions}
        result = session.sql(
            "SELECT PARSE_JSON(SNOWFLAKE.CORTEX.SEARCH_PREVIEW("
            "'SF_SOLUTIONS.CHP_OPS.MARKET_INTEL_SEARCH', ?))['results'] AS results",
            params=[json.dumps(request)],
        ).collect()
        if result and result[0]["RESULTS"]:
            return pd.DataFrame(json.loads(result[0]["RESULTS"]))
        return pd.DataFrame()
    except Exception as e:
        st.error(f"Search error: {str(e)}")
        return pd.DataFrame()


def load_recent_reports(session, limit: int = 10):
    """Load recent market reports."""
    query = """
    SELECT
        report_title,
        chemical_name,
        region,
        report_date,
        report_source,
        report_summary
    FROM SF_SOLUTIONS.CHP_RAW.MARKET_REPORTS
    ORDER BY report_date DESC
    LIMIT ?
    """
    try:
        return session.sql(query, params=[int(limit)]).to_pandas()
    except Exception:
        return pd.DataFrame()


def load_filter_options(session):
    """Load distinct values for filters."""
    try:
        chemicals = session.sql(
            "SELECT DISTINCT chemical_name FROM SF_SOLUTIONS.CHP_RAW.MARKET_REPORTS ORDER BY chemical_name"
        ).to_pandas()
        regions = session.sql(
            "SELECT DISTINCT region FROM SF_SOLUTIONS.CHP_RAW.MARKET_REPORTS ORDER BY region"
        ).to_pandas()
        return chemicals["CHEMICAL_NAME"].tolist(), regions["REGION"].tolist()
    except Exception:
        return [], []


def render_header():
    """Render header."""
    st.markdown(
        f"""
    <div style="margin-bottom: 2rem;">
        <h1 style="margin-bottom: 0.5rem;">📄 Market Intelligence</h1>
        <p style="color: {COLORS["text_muted"]}; font-size: 1.1rem;">
            Search market reports, and analyst commentary using AI
        </p>
    </div>
    """,
        unsafe_allow_html=True,
    )


def render_search_interface(session):
    """Render the search interface."""
    st.markdown(section_header("🔍 Search Market Reports", "Powered by Cortex Search"), unsafe_allow_html=True)

    # Load filter options
    chemicals, regions = load_filter_options(session)

    # Search controls
    col1, col2, col3 = st.columns([3, 1, 1])

    with col1:
        search_query = st.text_input(
            "Search Query", placeholder="e.g., supply constraints for Propylene in Asia", label_visibility="collapsed"
        )

    with col2:
        chemical_filter = st.selectbox("Chemical", ["All"] + chemicals, label_visibility="collapsed")

    with col3:
        region_filter = st.selectbox("Region", ["All"] + regions, label_visibility="collapsed")

    # Sample queries
    st.markdown(
        f"""
    <p style="color: {COLORS["text_muted"]}; font-size: 0.85rem; margin-top: 0.5rem;">
        <strong>Try:</strong>
        "supply constraints for Propylene" •
        "ethylene demand outlook" •
        "polymer pricing trends" •
        "feedstock cost pressures"
    </p>
    """,
        unsafe_allow_html=True,
    )

    if st.button("🔍 Search", use_container_width=True):
        if search_query:
            filters = {}
            if chemical_filter != "All":
                filters["chemical"] = chemical_filter
            if region_filter != "All":
                filters["region"] = region_filter

            with st.spinner("Searching market intelligence..."):
                results = search_market_intel(session, search_query, filters)

                if len(results) > 0:
                    render_search_results(results)
                else:
                    st.info("No results found. Try a different query or adjust filters.")
        else:
            st.warning("Please enter a search query")


def render_search_results(results_df):
    """Render search results."""
    st.markdown(
        f"""
    <div style="margin: 1.5rem 0 1rem 0;">
        <span style="color: {COLORS["text_muted"]};">Found {len(results_df)} relevant reports</span>
    </div>
    """,
        unsafe_allow_html=True,
    )

    for idx, row in results_df.iterrows():
        # Extract fields from search result
        title = row.get("report_title", "Untitled Report")
        source = row.get("report_source", "Unknown")
        date = row.get("report_date", "")
        chemical = row.get("chemical_name", "")
        region = row.get("region", "")
        content = row.get("chunk", "")[:500] + "..." if len(row.get("chunk", "")) > 500 else row.get("chunk", "")

        st.markdown(
            f"""
        <div style="
            background: {COLORS["card"]};
            border: 1px solid {COLORS["border"]};
            border-radius: 8px;
            padding: 1.25rem;
            margin-bottom: 1rem;
        ">
            <div style="display: flex; justify-content: space-between; align-items: flex-start;
                margin-bottom: 0.75rem;">
                <div>
                    <h4 style="color: {COLORS["text"]}; margin: 0 0 0.25rem 0;">{title}</h4>
                    <span style="color: {COLORS["text_muted"]}; font-size: 0.85rem;">
                        {source} • {date}
                    </span>
                </div>
                <div style="text-align: right;">
                    <span style="
                        background: {COLORS["primary"]}20;
                        color: {COLORS["primary"]};
                        padding: 0.25rem 0.5rem;
                        border-radius: 4px;
                        font-size: 0.75rem;
                        margin-right: 0.5rem;
                    ">{chemical}</span>
                    <span style="
                        background: {COLORS["secondary"]}20;
                        color: {COLORS["secondary"]};
                        padding: 0.25rem 0.5rem;
                        border-radius: 4px;
                        font-size: 0.75rem;
                    ">{region}</span>
                </div>
            </div>
            <p style="color: {COLORS["text_muted"]}; margin: 0; font-size: 0.9rem; line-height: 1.6;">
                {content}
            </p>
        </div>
        """,
            unsafe_allow_html=True,
        )


def render_recent_reports(session):
    """Render recent reports section."""
    st.markdown(section_header("📰 Recent Reports", "Latest market intelligence updates"), unsafe_allow_html=True)

    reports_df = load_recent_reports(session)

    if len(reports_df) == 0:
        st.info("No recent reports available. Load data using the data loading scripts.")
        return

    for _, row in reports_df.iterrows():
        source_color = COLORS["chart_1"] if "Internal" in str(row.get("REPORT_SOURCE", "")) else COLORS["chart_2"]

        st.markdown(
            f"""
        <div style="
            background: {COLORS["card"]};
            border: 1px solid {COLORS["border"]};
            border-left: 4px solid {source_color};
            border-radius: 8px;
            padding: 1rem;
            margin-bottom: 0.75rem;
        ">
            <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 0.5rem;">
                <span style="color: {COLORS["text"]};
                    font-weight: 500;">{row.get("REPORT_TITLE", "Report")[:60]}...</span>
                <span style="color: {COLORS["text_muted"]}; font-size: 0.8rem;">{row.get("REPORT_DATE", "")}</span>
            </div>
            <div style="display: flex; gap: 1rem;">
                <span style="color: {COLORS["text_muted"]}; font-size: 0.85rem;">📊
                    {row.get("CHEMICAL_NAME", "Chemical")}</span>
                <span style="color: {COLORS["text_muted"]}; font-size: 0.85rem;">🌍 {row.get("REGION", "Region")}</span>
                <span style="color: {source_color}; font-size: 0.85rem;">📰 {row.get("REPORT_SOURCE", "Source")}</span>
            </div>
        </div>
        """,
            unsafe_allow_html=True,
        )


def render_report_stats(session):
    """Render report statistics."""
    st.markdown(section_header("📊 Report Coverage", "Documents indexed for search"), unsafe_allow_html=True)

    try:
        stats_query = """
        SELECT
            COUNT(*) as total_reports,
            COUNT(DISTINCT chemical_name) as unique_chemicals,
            COUNT(DISTINCT region) as unique_regions,
            COUNT(DISTINCT report_source) as unique_sources
        FROM SF_SOLUTIONS.CHP_RAW.MARKET_REPORTS
        """
        stats = session.sql(stats_query).to_pandas()

        if len(stats) > 0:
            row = stats.iloc[0]

            cols = st.columns(4)
            with cols[0]:
                st.metric("Total Reports", int(row["TOTAL_REPORTS"]))
            with cols[1]:
                st.metric("Chemicals", int(row["UNIQUE_CHEMICALS"]))
            with cols[2]:
                st.metric("Regions", int(row["UNIQUE_REGIONS"]))
            with cols[3]:
                st.metric("Sources", int(row["UNIQUE_SOURCES"]))
    except Exception:
        cols = st.columns(4)
        with cols[0]:
            st.metric("Total Reports", "~500")
        with cols[1]:
            st.metric("Chemicals", "20")
        with cols[2]:
            st.metric("Regions", "5")
        with cols[3]:
            st.metric("Sources", "7")


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

        st.markdown("### About Cortex Search")
        st.markdown("""
        This page uses **Snowflake Cortex Search** to enable semantic search across:

        - 📊 Market analyst reports
        - 📈 Market outlooks and supply analyses
        - 📰 Trade journal articles

        The search understands context and meaning, not just keywords.
        """)

        st.markdown("---")

        st.markdown("### Sample Query")
        st.code('"What are the supply constraints for Propylene in Asia reported in the last month?"', language=None)


def main():
    """Main."""
    session = get_session()

    render_sidebar()
    render_header()

    # Main search interface
    render_search_interface(session)

    st.markdown("---")

    # Two column layout
    col1, col2 = st.columns([2, 1])

    with col1:
        render_recent_reports(session)

    with col2:
        render_report_stats(session)

        st.markdown("<br>", unsafe_allow_html=True)

        # Source breakdown
        st.markdown(section_header("📰 Sources", "Report providers"), unsafe_allow_html=True)

        sources = [
            r["REPORT_SOURCE"]
            for r in session.sql(
                "SELECT DISTINCT report_source FROM SF_SOLUTIONS.CHP_RAW.MARKET_REPORTS ORDER BY 1"
            ).collect()
        ]
        for source in sources:
            st.markdown(
                f"""
            <div style="
                background: {COLORS["card"]};
                border: 1px solid {COLORS["border"]};
                border-radius: 6px;
                padding: 0.5rem 0.75rem;
                margin-bottom: 0.5rem;
                display: flex;
                justify-content: space-between;
                align-items: center;
            ">
                <span style="color: {COLORS["text_muted"]};">{source}</span>
                <span style="color: {COLORS["primary"]};">✓</span>
            </div>
            """,
                unsafe_allow_html=True,
            )


if __name__ == "__main__":
    main()
