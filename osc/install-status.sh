#!/bin/sh

# Simple HTTP server to show installation status
# Runs on port 8080 during Nextcloud installation

PORT=${1:-8080}
STATUS_FILE="/tmp/install_status"
PID_FILE="/tmp/install_server.pid"

# Default status
echo "Initializing..." > "$STATUS_FILE"

# Function to create HTML response
create_html() {
    local status_text
    status_text=$(cat "$STATUS_FILE" 2>/dev/null || echo "Installing...")
    
    # Get current timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S UTC')
    
    cat << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Nextcloud Installation</title>
    <meta http-equiv="refresh" content="5">
    <style>
        body { 
            font-family: Arial, sans-serif; 
            text-align: center; 
            margin: 50px;
            background-color: #f8f9fa;
        }
        .container {
            max-width: 600px;
            margin: 0 auto;
            padding: 40px;
            background: white;
            border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        .spinner {
            border: 4px solid #f3f3f3;
            border-top: 4px solid #0082c9;
            border-radius: 50%;
            width: 40px;
            height: 40px;
            animation: spin 1s linear infinite;
            margin: 20px auto;
        }
        @keyframes spin {
            0% { transform: rotate(0deg); }
            100% { transform: rotate(360deg); }
        }
        .status {
            font-size: 18px;
            color: #333;
            margin: 20px 0;
        }
        .timestamp {
            font-size: 12px;
            color: #666;
            margin-top: 30px;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🔧 Nextcloud Installation in Progress</h1>
        <div class="spinner"></div>
        <div class="status">$status_text</div>
        <p>Please wait while Nextcloud is being installed and configured.</p>
        <p>This page will automatically refresh every 5 seconds.</p>
        <div class="timestamp">Last updated: $timestamp</div>
    </div>
</body>
</html>
EOF
}

# Start the server using PHP built-in server
echo "Starting installation status server on port $PORT"
echo $$ > "$PID_FILE"

# Create a simple PHP script to serve our content
cat > /tmp/status_server.php << 'PHPEOL'
<?php
// Simple status server
if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    $statusFile = '/tmp/install_status';
    $status = file_exists($statusFile) ? trim(file_get_contents($statusFile)) : 'Installing...';
    $timestamp = date('Y-m-d H:i:s T');
    
    header('Content-Type: text/html; charset=utf-8');
    header('Cache-Control: no-cache, no-store, must-revalidate');
    header('Pragma: no-cache');
    header('Expires: 0');
    
    echo '<!DOCTYPE html>
<html>
<head>
    <title>Nextcloud Installation</title>
    <meta http-equiv="refresh" content="5">
    <style>
        body { 
            font-family: Arial, sans-serif; 
            text-align: center; 
            margin: 50px;
            background-color: #f8f9fa;
        }
        .container {
            max-width: 600px;
            margin: 0 auto;
            padding: 40px;
            background: white;
            border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        .spinner {
            border: 4px solid #f3f3f3;
            border-top: 4px solid #0082c9;
            border-radius: 50%;
            width: 40px;
            height: 40px;
            animation: spin 1s linear infinite;
            margin: 20px auto;
        }
        @keyframes spin {
            0% { transform: rotate(0deg); }
            100% { transform: rotate(360deg); }
        }
        .status {
            font-size: 18px;
            color: #333;
            margin: 20px 0;
        }
        .timestamp {
            font-size: 12px;
            color: #666;
            margin-top: 30px;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🔧 Nextcloud Installation in Progress</h1>
        <div class="spinner"></div>
        <div class="status">' . htmlspecialchars($status) . '</div>
        <p>Please wait while Nextcloud is being installed and configured.</p>
        <p>This page will automatically refresh every 5 seconds.</p>
        <div class="timestamp">Last updated: ' . $timestamp . '</div>
    </div>
</body>
</html>';
}
?>
PHPEOL

# Start PHP development server
php -S "0.0.0.0:$PORT" -t /tmp /tmp/status_server.php > /dev/null 2>&1 &
SERVER_PID=$!
echo $SERVER_PID > /tmp/php_server.pid

# Monitor for completion
while true; do
    # Check if server is still running
    if ! kill -0 $SERVER_PID 2>/dev/null; then
        echo "Status server stopped unexpectedly"
        break
    fi
    
    # Exit if installation is complete
    if [ -f "/tmp/install_complete" ]; then
        echo "Installation complete, stopping status server"
        kill $SERVER_PID 2>/dev/null || true
        break
    fi
    
    sleep 2
done

# Cleanup
kill $SERVER_PID 2>/dev/null || true
rm -f "$PID_FILE" "$STATUS_FILE" /tmp/status_server.php /tmp/php_server.pid