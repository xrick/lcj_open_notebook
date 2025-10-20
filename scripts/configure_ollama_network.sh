#!/bin/bash

# Configure Ollama to listen on 0.0.0.0 (all network interfaces)
# This allows external access to Ollama API

echo "🔧 Configuring Ollama Network Settings..."

# Detect systemd service file location
SYSTEMD_DIR="/etc/systemd/system"
SERVICE_FILE="$SYSTEMD_DIR/ollama.service.d/override.conf"
SERVICE_DIR="$SYSTEMD_DIR/ollama.service.d"

# Check if running with sudo
if [ "$EUID" -ne 0 ]; then
    echo "⚠️  This script requires sudo privileges to modify systemd service"
    echo "Please run: sudo $0"
    exit 1
fi

# Check if Ollama service exists
if ! systemctl list-unit-files | grep -q "ollama.service"; then
    echo "❌ Ollama service not found"
    echo "Please install Ollama first: https://ollama.ai"
    exit 1
fi

# Create override directory if it doesn't exist
if [ ! -d "$SERVICE_DIR" ]; then
    echo "📁 Creating override directory: $SERVICE_DIR"
    mkdir -p "$SERVICE_DIR"
fi

# Create or update override configuration
echo "✍️  Writing override configuration..."
cat > "$SERVICE_FILE" << 'EOF'
[Service]
# Allow Ollama to listen on all network interfaces (0.0.0.0)
Environment="OLLAMA_HOST=0.0.0.0:11434"

# Optional: Increase timeout for large model loads
# TimeoutStartSec=300

# Optional: Set custom models directory
# Environment="OLLAMA_MODELS=/path/to/models"
EOF

echo "✅ Override configuration written to: $SERVICE_FILE"

# Reload systemd daemon
echo "🔄 Reloading systemd daemon..."
systemctl daemon-reload

# Restart Ollama service
echo "🔄 Restarting Ollama service..."
systemctl restart ollama.service

# Wait a moment for service to start
sleep 2

# Check service status
echo ""
echo "📊 Ollama Service Status:"
systemctl status ollama.service --no-pager -l | head -20

echo ""
echo "🔍 Verifying Network Configuration:"
if systemctl show ollama.service -p Environment | grep -q "OLLAMA_HOST=0.0.0.0"; then
    echo "✅ OLLAMA_HOST is set to 0.0.0.0:11434"
else
    echo "⚠️  Warning: Could not verify OLLAMA_HOST setting"
fi

echo ""
echo "🌐 Network Binding:"
if ss -tlnp | grep -q ":11434"; then
    ss -tlnp | grep ":11434"
    echo "✅ Ollama is listening on port 11434"
else
    echo "⚠️  Warning: Ollama does not appear to be listening on port 11434"
fi

echo ""
echo "✨ Configuration Complete!"
echo ""
echo "📝 To verify external access, try from another machine:"
echo "   curl http://$(hostname -I | awk '{print $1}'):11434/api/tags"
echo ""
echo "🔧 To revert this change, remove the override file:"
echo "   sudo rm $SERVICE_FILE"
echo "   sudo systemctl daemon-reload"
echo "   sudo systemctl restart ollama.service"
echo ""
