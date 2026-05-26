#!/bin/bash

# Run Flutter web app in Chrome without web security on port 9090
# This allows local development without CORS restrictions

PORT=9090

echo "🚀 Starting Flutter web on port $PORT without web security..."

# Detect Chrome executable path based on OS
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    CHROME_PATH="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # Linux
    CHROME_PATH="google-chrome"
elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
    # Windows
    CHROME_PATH="C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe"
else
    echo "❌ Unsupported OS"
    exit 1
fi

# Check if Chrome exists
if [ ! -e "$CHROME_PATH" ]; then
    echo "❌ Chrome not found at: $CHROME_PATH"
    exit 1
fi

# Launch Chrome with disabled web security
"$CHROME_PATH" \
    --disable-web-security \
    --user-data-dir=/tmp/flutter_web_dev \
    http://localhost:$PORT > /dev/null 2>&1 &

CHROME_PID=$!
echo "✓ Chrome started (PID: $CHROME_PID) with disabled web security"

# Start Flutter web server
echo "✓ Starting Flutter web server on port $PORT..."
flutter run -d chrome --web-port=$PORT

# Kill Chrome when Flutter exits
kill $CHROME_PID 2>/dev/null
echo "✓ Done"
