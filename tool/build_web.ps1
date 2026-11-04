# Builds the sales app for the browser into backend\static\sales, where the
# office server serves it: http://<server>:8000/sales/
#
# --no-web-resources-cdn bundles the rendering engine with the app, so it
# also works on a shop Wi-Fi with no internet.
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
$out = Join-Path (Get-Location) 'backend\static\sales'
flutter build web --release --base-href /sales/ --no-web-resources-cdn --output $out
Write-Host "Built. Start the server (cd backend; python main.py) and open http://localhost:8000/sales/"
