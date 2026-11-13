#!/usr/bin/env bash
# Builds the sales app for the browser into backend/static/sales, where the
# office server serves it: http://<server>:8000/sales/
#
# --no-web-resources-cdn bundles the rendering engine with the app, so it
# also works on a shop Wi-Fi with no internet.
set -euo pipefail
cd "$(dirname "$0")/.."
flutter build web --release --base-href /sales/ --no-web-resources-cdn \
  --output "$PWD/backend/static/sales"
echo "Built. Start the server (cd backend && python main.py) and open http://localhost:8000/sales/"
