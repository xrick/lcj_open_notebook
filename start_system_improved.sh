# start_system_improved.sh
#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

echo "🚀 Starting Open Notebook System..."

# Create logs directory
mkdir -p logs

# Check and fix .env for local mode
if [ ! -f ".env" ]; then
    echo "⚠️  .env file not found. Copying from setup_guide/docker.env..."
    cp setup_guide/docker.env .env
fi

if grep -q "ws://surrealdb" .env; then
    echo "⚠️  Fixing SURREAL_URL for local mode..."
    sed -i.bak 's|ws://surrealdb/rpc:8000|ws://localhost/rpc:8000|g' .env
    echo "✅ Updated SURREAL_URL to ws://localhost/rpc:8000"
fi

# Function to check if a port is in use
check_port() {
    lsof -Pi :$1 -sTCP:LISTEN -t >/dev/null 2>&1
}

# Start SurrealDB
echo ""
echo "📊 Starting SurrealDB..."
if check_port 8000; then
    echo "✅ SurrealDB already running"
else
    # Try to start existing container first (faster, no registry check)
    if docker ps -a | grep -q "lcj_open_notebook-surrealdb-1"; then
        echo "Starting existing SurrealDB container..."
        docker start lcj_open_notebook-surrealdb-1
    else
        # Create new container if doesn't exist
        echo "Creating new SurrealDB container..."
        docker compose up -d surrealdb --no-pull || docker compose up -d surrealdb
    fi
    sleep 5
    echo "✅ SurrealDB started"
fi

# Start API
echo ""
echo "🔧 Starting API Backend..."
if check_port 5055; then
    echo "⚠️  Port 5055 in use, skipping"
else
    uv run --env-file .env uvicorn api.main:app --host 0.0.0.0 --port 5055 > logs/api.log 2>&1 &
    echo $! > .api.pid
    echo "✅ API started (PID: $(cat .api.pid))"
    sleep 3
fi

# Start Worker
echo ""
echo "⚙️  Starting Background Worker..."
if pgrep -f "surreal-commands-worker" > /dev/null; then
    echo "✅ Worker already running"
else
    uv run --env-file .env surreal-commands-worker --import-modules commands > logs/worker.log 2>&1 &
    echo $! > .worker.pid
    echo "✅ Worker started (PID: $(cat .worker.pid))"
    sleep 2
fi

# Start Streamlit
echo ""
echo "🎨 Starting Streamlit UI..."
if check_port 8502; then
    echo "⚠️  Port 8502 in use, skipping"
else
    uv run --env-file .env streamlit run app_home.py > logs/streamlit.log 2>&1 &
    echo $! > .streamlit.pid
    echo "✅ Streamlit started (PID: $(cat .streamlit.pid))"
fi

echo ""
echo "✨ All services started!"
echo ""
echo "📍 Access Points:"
echo "   - UI:        http://localhost:8502"
echo "   - API:       http://localhost:5055"
echo "   - API Docs:  http://localhost:5055/docs"
echo ""
echo "📝 Logs:"
echo "   - API:       tail -f logs/api.log"
echo "   - Worker:    tail -f logs/worker.log"
echo "   - Streamlit: tail -f logs/streamlit.log"
echo ""
echo "🛑 Stop: ./stop_system.sh"
