"""Theme utilities for Chemicals Pricing Dashboard.

Provides consistent styling, colors, and helper functions for Streamlit pages.
"""

# =============================================================================
# Color Palette - Modern dark theme with chemical industry accent colors
# =============================================================================
COLORS = {
    # Base colors
    "background": "#0a0f1a",  # Deep navy background
    "card": "#111827",  # Card background
    "card_hover": "#1f2937",  # Card hover state
    "border": "#1e3a5f",  # Border color
    # Text colors
    "text": "#f1f5f9",  # Primary text
    "text_muted": "#94a3b8",  # Secondary text
    "text_dim": "#64748b",  # Tertiary text
    # Accent colors - Chemical industry inspired
    "primary": "#0ea5e9",  # Bright cyan (primary action)
    "secondary": "#8b5cf6",  # Purple (secondary)
    "accent": "#06b6d4",  # Teal accent
    # Status colors
    "success": "#22c55e",  # Green - on target
    "warning": "#f59e0b",  # Amber - below target
    "danger": "#ef4444",  # Red - loss/underpriced
    "info": "#3b82f6",  # Blue - informational
    # Chart colors
    "chart_1": "#0ea5e9",  # Cyan
    "chart_2": "#8b5cf6",  # Purple
    "chart_3": "#22c55e",  # Green
    "chart_4": "#f59e0b",  # Amber
    "chart_5": "#ef4444",  # Red
    "chart_6": "#ec4899",  # Pink
}

# Margin status colors
MARGIN_STATUS_COLORS = {
    "ON_TARGET": COLORS["success"],
    "BELOW_TARGET": COLORS["warning"],
    "UNDERPRICED": "#fb923c",  # Orange
    "LOSS": COLORS["danger"],
}

# Price trend colors
TREND_COLORS = {
    "SPIKE": COLORS["danger"],
    "RISING": "#fb923c",  # Orange
    "STABLE": COLORS["info"],
    "FALLING": COLORS["success"],
    "CRASH": "#22c55e",  # Green (good for buyers)
}

# Inventory status colors
INVENTORY_COLORS = {
    "CRITICAL": COLORS["danger"],
    "LOW": COLORS["warning"],
    "HEALTHY": COLORS["success"],
    "EXCESS": COLORS["info"],
}


# =============================================================================
# Plotly Theme
# =============================================================================
def apply_dark_theme(fig, height=400):
    """Apply consistent dark theme to Plotly figures."""
    fig.update_layout(
        height=height,
        paper_bgcolor="rgba(0,0,0,0)",
        plot_bgcolor="rgba(0,0,0,0)",
        font=dict(color=COLORS["text"], family="Inter, system-ui, sans-serif"),
        title=dict(font=dict(size=16, color=COLORS["text"])),
        legend=dict(bgcolor="rgba(0,0,0,0)", bordercolor=COLORS["border"], font=dict(color=COLORS["text_muted"])),
        xaxis=dict(
            gridcolor=COLORS["border"],
            linecolor=COLORS["border"],
            tickfont=dict(color=COLORS["text_muted"]),
            title_font=dict(color=COLORS["text_muted"]),
        ),
        yaxis=dict(
            gridcolor=COLORS["border"],
            linecolor=COLORS["border"],
            tickfont=dict(color=COLORS["text_muted"]),
            title_font=dict(color=COLORS["text_muted"]),
        ),
        margin=dict(l=40, r=40, t=60, b=40),
    )
    return fig


# =============================================================================
# Component Helpers
# =============================================================================
def metric_card(title: str, value: str, delta: str = None, delta_color: str = "normal", icon: str = None) -> str:
    """Generate HTML for a styled metric card."""
    delta_html = ""
    if delta:
        delta_icon = "↑" if delta_color == "normal" else "↓" if delta_color == "inverse" else ""
        delta_css_color = (
            COLORS["success"]
            if delta_color == "normal"
            else COLORS["danger"]
            if delta_color == "inverse"
            else COLORS["text_muted"]
        )
        delta_html = (
            f'<div style="color: {delta_css_color}; font-size: 0.85rem; margin-top: 0.25rem;">'
            f"{delta_icon} {delta}</div>"
        )

    icon_html = f'<span style="margin-right: 0.5rem;">{icon}</span>' if icon else ""

    return f"""
    <div style="
        background: {COLORS["card"]};
        border: 1px solid {COLORS["border"]};
        border-radius: 12px;
        padding: 1.25rem;
        text-align: center;
    ">
        <div style="color: {COLORS["text_muted"]}; font-size: 0.85rem; margin-bottom: 0.5rem;">
            {icon_html}{title}
        </div>
        <div style="color: {COLORS["text"]}; font-size: 1.75rem; font-weight: 600;">
            {value}
        </div>
        {delta_html}
    </div>
    """


def status_badge(status: str, status_colors: dict = None) -> str:
    """Generate HTML for a status badge."""
    if status_colors is None:
        status_colors = MARGIN_STATUS_COLORS

    color = status_colors.get(status, COLORS["text_muted"])

    return f"""
    <span style="
        background: {color}22;
        color: {color};
        padding: 0.25rem 0.75rem;
        border-radius: 9999px;
        font-size: 0.75rem;
        font-weight: 600;
        text-transform: uppercase;
    ">{status}</span>
    """


def section_header(title: str, subtitle: str = None) -> str:
    """Generate HTML for a section header."""
    subtitle_html = (
        f'<p style="color: {COLORS["text_muted"]}; margin: 0.5rem 0 0 0; font-size: 0.95rem;">{subtitle}</p>'
        if subtitle
        else ""
    )

    return f"""
    <div style="margin-bottom: 1.5rem;">
        <h3 style="color: {COLORS["text"]}; margin: 0; font-size: 1.25rem;">{title}</h3>
        {subtitle_html}
    </div>
    """


def info_box(content: str, type: str = "info") -> str:
    """Generate HTML for an info/alert box."""
    type_colors = {
        "info": (COLORS["info"], "💡"),
        "success": (COLORS["success"], "✅"),
        "warning": (COLORS["warning"], "⚠️"),
        "danger": (COLORS["danger"], "🚨"),
    }
    color, icon = type_colors.get(type, type_colors["info"])

    return f"""
    <div style="
        background: {color}15;
        border-left: 4px solid {color};
        border-radius: 8px;
        padding: 1rem;
        margin: 1rem 0;
    ">
        <span style="margin-right: 0.5rem;">{icon}</span>
        <span style="color: {COLORS["text"]};">{content}</span>
    </div>
    """


def data_table_style() -> str:
    """Return CSS for styled data tables."""
    return f"""
    <style>
        .dataframe {{
            background: {COLORS["card"]} !important;
            border: 1px solid {COLORS["border"]} !important;
            border-radius: 8px !important;
        }}
        .dataframe th {{
            background: {COLORS["card_hover"]} !important;
            color: {COLORS["text"]} !important;
            border-bottom: 1px solid {COLORS["border"]} !important;
            padding: 12px !important;
        }}
        .dataframe td {{
            color: {COLORS["text_muted"]} !important;
            border-bottom: 1px solid {COLORS["border"]} !important;
            padding: 10px !important;
        }}
        .dataframe tr:hover td {{
            background: {COLORS["card_hover"]} !important;
        }}
    </style>
    """


# =============================================================================
# Chart Color Sequences
# =============================================================================
CHART_COLORS = [
    COLORS["chart_1"],
    COLORS["chart_2"],
    COLORS["chart_3"],
    COLORS["chart_4"],
    COLORS["chart_5"],
    COLORS["chart_6"],
]

# Product family colors
PRODUCT_FAMILY_COLORS = {
    "Olefins": "#0ea5e9",
    "Polymers": "#8b5cf6",
    "Aromatics": "#22c55e",
    "Intermediates": "#f59e0b",
}

# Region colors
REGION_COLORS = {
    "North America": "#0ea5e9",
    "Europe": "#8b5cf6",
    "Asia Pacific": "#22c55e",
    "Latin America": "#f59e0b",
    "Middle East": "#ec4899",
}


# =============================================================================
# Page CSS
# =============================================================================
def get_page_css() -> str:
    """Return common page CSS."""
    return f"""
    <style>
        /* Main app background */
        .stApp {{
            background-color: {COLORS["background"]};
        }}

        /* Main content area */
        .main .block-container {{
            padding-top: 2rem;
            max-width: 100%;
        }}

        /* Headers */
        h1, h2, h3, h4, h5, h6 {{
            color: {COLORS["text"]} !important;
        }}

        /* Paragraph text */
        p, .stMarkdown {{
            color: {COLORS["text"]};
        }}

        /* Sidebar */
        section[data-testid="stSidebar"] {{
            background-color: {COLORS["card"]};
            border-right: 1px solid {COLORS["border"]};
        }}

        section[data-testid="stSidebar"] .stMarkdown {{
            color: {COLORS["text_muted"]};
        }}

        /* Metrics */
        [data-testid="stMetricValue"] {{
            color: {COLORS["text"]} !important;
        }}

        [data-testid="stMetricLabel"] {{
            color: {COLORS["text_muted"]} !important;
        }}

        /* Tabs */
        .stTabs [data-baseweb="tab-list"] {{
            background-color: {COLORS["card"]};
            border-radius: 8px;
            padding: 4px;
        }}

        .stTabs [data-baseweb="tab"] {{
            color: {COLORS["text_muted"]};
        }}

        .stTabs [aria-selected="true"] {{
            color: {COLORS["primary"]} !important;
            background-color: {COLORS["card_hover"]} !important;
        }}

        /* Selectbox */
        .stSelectbox > div > div {{
            background-color: {COLORS["card"]};
            border-color: {COLORS["border"]};
        }}

        /* Input fields */
        .stTextInput > div > div > input {{
            background-color: {COLORS["card"]};
            border-color: {COLORS["border"]};
            color: {COLORS["text"]};
        }}

        /* Buttons */
        .stButton > button {{
            background-color: {COLORS["primary"]};
            color: white;
            border: none;
            border-radius: 8px;
            padding: 0.5rem 1rem;
        }}

        .stButton > button:hover {{
            background-color: {COLORS["accent"]};
        }}

        /* Expander */
        .streamlit-expanderHeader {{
            background-color: {COLORS["card"]};
            border: 1px solid {COLORS["border"]};
            border-radius: 8px;
            color: {COLORS["text"]};
        }}

        /* Divider */
        hr {{
            border-color: {COLORS["border"]};
        }}
    </style>
    """
