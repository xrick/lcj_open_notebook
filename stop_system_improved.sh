#!/bin/bash

# Open Notebook System Shutdown Script (Improved)
# This script stops all components of the Open Notebook system
# Matches components started by start_system_improved.sh

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

echo "🛑 Stopping Open Notebook System..."
echo ""

# Function to safely stop a process
stop_process() {
    local NAME=$1
    local PID_FILE=$2
    local EMOJI=$3

    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if ps -p $PID > /dev/null 2>&1; then
            echo "$EMOJI Stopping $NAME (PID: $PID)..."
            kill $PID 2>/dev/null || true

            # Wait for graceful shutdown (max 5 seconds)
            for i in {1..5}; do
                if ! ps -p $PID > /dev/null 2>&1; then
                    break
                fi
                sleep 1
            done

            # Force kill if still running
            if ps -p $PID > /dev/null 2>&1; then
                echo "⚠️  Process still running, forcing shutdown..."
                kill -9 $PID 2>/dev/null || true
            fi

            rm "$PID_FILE"
            echo "✅ $NAME stopped"
        else
            echo "⚠️  $NAME process not found (PID: $PID)"
            rm "$PID_FILE"
        fi
    else
        echo "ℹ️  No $NAME PID file found ($PID_FILE)"
    fi
}

# Stop Streamlit UI
stop_process "Streamlit UI" ".streamlit.pid" "🎨"

# Stop Background Worker
echo ""
stop_process "Background Worker" ".worker.pid" "⚙️"

# Alternative: Kill by process name if PID file missing
if pgrep -f "surreal-commands-worker" > /dev/null; then
    echo "⚙️  Found Worker by process name, stopping..."
    pkill -f "surreal-commands-worker" || true
    sleep 1
    echo "✅ Worker stopped"
fi

# Stop API Backend
echo ""
stop_process "API Backend" ".api.pid" "🔧"

# Stop SurrealDB
echo ""
echo "📊 Stopping SurrealDB..."
if docker ps | grep -q "lcj_open_notebook-surrealdb"; then
    docker compose stop surrealdb
    echo "✅ SurrealDB stopped"
else
    echo "ℹ️  SurrealDB container not running"
fi

# Clean up any remaining log handles
echo ""
echo "🧹 Cleaning up..."

# Check for any orphaned processes
if pgrep -f "uvicorn api.main:app" > /dev/null; then
    echo "⚠️  Found orphaned API processes, cleaning up..."
    if pkill -f "uvicorn api.main:app" 2>/dev/null; then
        echo "✅ API processes cleaned up"
    else
        echo "❌ Failed to kill API processes (may be running as root)"
        echo "   Run manually: sudo pkill -f 'uvicorn api.main:app'"
    fi
fi

if pgrep -f "streamlit run app_home.py" > /dev/null; then
    echo "⚠️  Found orphaned Streamlit processes, cleaning up..."
    if pkill -f "streamlit run app_home.py" 2>/dev/null; then
        echo "✅ Streamlit processes cleaned up"
    else
        echo "❌ Failed to kill Streamlit processes (may be running as root)"
        echo "   Run manually: sudo pkill -f 'streamlit run app_home.py'"
    fi
fi

if pgrep -f "surreal-commands-worker" > /dev/null; then
    echo "⚠️  Found orphaned Worker processes, cleaning up..."
    if pkill -f "surreal-commands-worker" 2>/dev/null; then
        echo "✅ Worker processes cleaned up"
    else
        echo "❌ Failed to kill Worker processes (may be running as root)"
        echo "   Run manually: sudo pkill -f 'surreal-commands-worker'"
    fi
fi

echo ""
echo "✨ Open Notebook System Stopped!"
echo ""
echo "📊 System Status:"
echo "   - SurrealDB: $(docker ps | grep -q 'lcj_open_notebook-surrealdb' && echo '❌ Stopped' || echo '✅ Not running')"
echo "   - API:       $(pgrep -f 'uvicorn api.main:app' > /dev/null && echo '⚠️  Still running!' || echo '✅ Stopped')"
echo "   - Worker:    $(pgrep -f 'surreal-commands-worker' > /dev/null && echo '⚠️  Still running!' || echo '✅ Stopped')"
echo "   - Streamlit: $(pgrep -f 'streamlit run app_home.py' > /dev/null && echo '⚠️  Still running!' || echo '✅ Stopped')"
echo ""
echo "🚀 Restart: ./start_system_improved.sh"
echo ""
