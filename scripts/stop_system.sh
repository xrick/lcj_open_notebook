#!/bin/bash

# Open Notebook System Shutdown Script
# This script stops all components of the Open Notebook system

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

echo "🛑 Stopping Open Notebook System..."

# Stop Streamlit
if [ -f ".streamlit.pid" ]; then
    STREAMLIT_PID=$(cat .streamlit.pid)
    if ps -p $STREAMLIT_PID > /dev/null 2>&1; then
        echo "🎨 Stopping Streamlit (PID: $STREAMLIT_PID)..."
        kill $STREAMLIT_PID
        rm .streamlit.pid
        echo "✅ Streamlit stopped"
    else
        echo "⚠️  Streamlit process not found"
        rm .streamlit.pid
    fi
else
    echo "⚠️  No Streamlit PID file found"
fi

# Stop API
if [ -f ".api.pid" ]; then
    API_PID=$(cat .api.pid)
    if ps -p $API_PID > /dev/null 2>&1; then
        echo "🔧 Stopping API (PID: $API_PID)..."
        kill $API_PID
        rm .api.pid
        echo "✅ API stopped"
    else
        echo "⚠️  API process not found"
        rm .api.pid
    fi
else
    echo "⚠️  No API PID file found"
fi

# Stop SurrealDB
echo "📊 Stopping SurrealDB..."
docker compose stop surrealdb
echo "✅ SurrealDB stopped"

echo ""
echo "✨ Open Notebook System Stopped!"
echo ""
