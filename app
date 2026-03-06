import streamlit as st
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
import numpy as np
from pathlib import Path

st.set_page_config(page_title="🏏 Cricket PPI Dashboard", layout="wide", page_icon="🏏")

@st.cache_data
def load_and_compute_ppi():
    files = {
        'BATSMEN_no_zeros.xlsx': 'batsmen',
        'ALL_ROUNDERS_no_zeros.xlsx': 'allrounders', 
        'BOWLERS_no_zeros.xlsx': 'bowlers',
        'WICKET_KEEPER_no_zeros.xlsx': 'wicketkeepers'
    }
    data = {}
    
    for file, category in files.items():
        df = pd.read_excel(f"data/{file}")
        df['Player'] = df['Player'].astype(str)
        
        if category == 'batsmen':
            # Batsmen PPI: SR + Boundary% + Avg * normalized
            df['SR'] = (df['Runs'] / df['BF'] * 100).round(2)
            df['Boundary'] = df['4s'] + df['6s']
            df['Boundary_Pct'] = (df['Boundary'] / df['BF'] * 100).round(2)
            df['PPI'] = (df['SR'] * 0.4 + df['Boundary_Pct'] * 30 + df['Runs'] * 0.001).round(2)
            
        elif category == 'allrounders':
            # Allrounders: Batting SR + Bowling Econ inverse + Wkts
            df['SR'] = (df['Runs'] / df['BF'] * 100).round(2)
            df['Bowling_PPI'] = (df['Wkts'] * 10 - df['Econ'] * 2).clip(lower=0)
            df['PPI'] = (df['SR'] * 0.3 + df['Bowling_PPI'] * 0.5 + df['Runs'] * 0.001).round(2)
            
        elif category == 'bowlers':
            # Bowlers PPI: Wkts/Overs + Econ inverse
            df['Bowling_Avg'] = (df['Runs'] / df['Wkts'].replace(0,1)).round(2)
            df['PPI'] = (df['Wkts'] * 5 - df['Econ'] * 3 - df['Bowling_Avg'] * 0.1).clip(lower=0).round(2)
            
        elif category == 'wicketkeepers':
            # Same as batsmen + dismissals bonus (assuming dismissals column exists or use Runs)
            df['SR'] = (df['Runs'] / df['BF'] * 100).round(2)
            df['Boundary_Pct'] = ((df['4s'] + df['6s']) / df['BF'] * 100).round(2)
            df['PPI'] = (df['SR'] * 0.4 + df['Boundary_Pct'] * 30 + df['Runs'] * 0.001).round(2)
        
        # Aggregate by player
        player_stats = df.groupby('Player').agg({
            'PPI': 'mean',
            'Runs': 'sum',
            'Wkts': 'sum',
            'SR': 'mean' if 'SR' in df else 'first',
            'Econ': 'mean' if 'Econ' in df else 'first',
            'Country': 'first'
        }).round(2)
        player_stats = player_stats.sort_values('PPI', ascending=False).reset_index()
        data[category] = player_stats
    return data

data = load_and_compute_ppi()

# Sidebar
st.sidebar.title("🏏 Navigation")
page = st.sidebar.selectbox("Pages", ["Home", "All Players", "Top Performers", "Player Search"])

if page == "Home":
    st.title("🏏 Cricket Performance Index Dashboard")
    st.markdown("**Live PPI computation from innings data** - Batsmen, Allrounders, Bowlers, Wicketkeepers")
    
    col1, col2, col3, col4 = st.columns(4)
    with col1: st.metric("Categories", len(data), delta="4 datasets")
    with col2: 
        total = sum(len(df) for df in data.values())
        st.metric("Players", total)
    with col3:
        top_ppi = max([df['PPI'].max() for df in data.values()])
        st.metric("Top PPI", f"{top_ppi:.1f}")
    with col4: st.metric("Innings", "No zeros")
    
    # Top player highlights
    st.subheader("🏆 Leaderboard Preview")
    tops = []
    for cat, df in data.items():
        if not df.empty:
            top = df.iloc[0]
            tops.append({"Category": cat.title(), "Player": top['Player'], "PPI": top['PPI']})
    top_df = pd.DataFrame(tops).sort_values('PPI', ascending=False)
    st.dataframe(top_df.style.format({'PPI': '{:.1f}'}).background_gradient('viridis'), use_container_width=True)

elif page == "All Players":
    st.title("📊 All Players Rankings")
    category = st.selectbox("Category", data.keys())
    df = data[category]
    
    if not df.empty:
        ppi_col = 'PPI'
        fig = px.bar(df.head(20), x='Player', y=ppi_col, 
                    title=f"Top 20 {category.title()} by PPI",
                    color=ppi_col, color_continuous_scale='Viridis_r')
        fig.update_layout(xaxis_tickangle=-45, height=500)
        st.plotly_chart(fig, use_container_width=True)
        
        st.subheader("Full Table")
        st.dataframe(df, use_container_width=True)
        
        # Country pie
        if 'Country' in df.columns:
            fig_pie = px.pie(df, names='Country', title="Players by Country")
            st.plotly_chart(fig_pie)

elif page == "Top Performers":
    st.title("⭐ Cross-Category Comparison")
    cats = st.multiselect("Categories", data.keys(), default=data.keys())
    n = st.slider("Top N", 5, 20, 10)
    
    fig = go.Figure()
    colors = px.colors.qualitative.Set3
    for i, cat in enumerate(cats):
        df_cat = data[cat].head(n)
        fig.add_trace(go.Bar(name=cat.title(), x=df_cat['Player'], y=df_cat['PPI'],
                           marker_color=colors[i % len(colors)], text=df_cat['PPI'].round(1)))
    
    fig.update_layout(barmode='group', title=f"Top {n} Across Categories", xaxis_tickangle=-45, height=600)
    st.plotly_chart(fig, use_container_width=True)

elif page == "Player Search":
    st.title("🔍 Search Players")
    player_name = st.text_input("Enter Player Name").lower()
    if player_name:
        results = []
        for cat, df in data.items():
            matches = df[df['Player'].str.lower().str.contains(player_name, na=False)]
            if not matches.empty:
                matches['Category'] = cat.title()
                results.append(matches)
        if results:
            result_df = pd.concat(results)
            st.dataframe(result_df.sort_values('PPI', ascending=False), use_container_width=True)
        else:
            st.info("No players found")

# Footer
st.markdown("---")
st.markdown("*PPI computed live from raw innings data. Deploy on Streamlit Cloud or GitHub Pages.*")
