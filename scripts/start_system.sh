#!/bin/bash

# Open Notebook System Startup Script
# This script starts all components of the Open Notebook system

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

echo "🚀 Starting Open Notebook System..."

# Check if .env file exists
if [ ! -f ".env" ]; then
    echo "⚠️  .env file not found. Copying from .env.example..."
    cp .env.example .env
    echo "✅ Please configure .env file before running the system"
    exit 1
fi

# Function to check if a port is in use
check_port() {
    local port=$1
    if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1 ; then
        return 0
    else
        return 1
    fi
}

# Start SurrealDB
echo ""
echo "📊 Starting SurrealDB..."
if check_port 8000; then
    echo "✅ SurrealDB already running on port 8000"
else
    docker compose up -d surrealdb
    echo "⏳ Waiting for SurrealDB to be ready..."
    sleep 5
    echo "✅ SurrealDB started"
fi

# Start API Backend
echo ""
echo "🔧 Starting API Backend (port 5055)..."
if check_port 5055; then
    echo "⚠️  Port 5055 already in use. Skipping API startup."
else
    echo "Starting API in background..."
    uv run --env-file .env uvicorn api.main:app --host 0.0.0.0 --port 5055 > logs/api.log 2>&1 &
    API_PID=$!
    echo $API_PID > .api.pid
    echo "✅ API started (PID: $API_PID, logs: logs/api.log)"
    sleep 3
fi

# Start Streamlit UI
echo ""
echo "🎨 Starting Streamlit UI (port 8502)..."
if check_port 8502; then
    echo "⚠️  Port 8502 already in use. Skipping Streamlit startup."
else
    echo "Starting Streamlit in background..."
    uv run --env-file .env streamlit run app_home.py > logs/streamlit.log 2>&1 &
    STREAMLIT_PID=$!
    echo $STREAMLIT_PID > .streamlit.pid
    echo "✅ Streamlit started (PID: $STREAMLIT_PID, logs: logs/streamlit.log)"
    sleep 3
fi

echo ""
echo "✨ Open Notebook System Started!"
echo ""
echo "📍 Access Points:"
echo "   - Streamlit UI:  http://localhost:8502"
echo "   - API Backend:   http://localhost:5055"
echo "   - API Docs:      http://localhost:5055/docs"
echo "   - SurrealDB:     http://localhost:8000"
echo ""
echo "📝 Log Files:"
echo "   - API:           logs/api.log"
echo "   - Streamlit:     logs/streamlit.log"
echo ""
echo "🛑 To stop the system, run: ./stop_system.sh"
echo ""
