# Publishes the exported prices so the Budget Basket app can download them.
# Merges with what is already published (nothing is lost). Needs Python and the GitHub CLI signed in once (gh auth login).
$py = (Get-Command python -ErrorAction SilentlyContinue)
if (-not $py) { $py = (Get-Command py -ErrorAction SilentlyContinue) }
if (-not $py) { Write-Host 'Python was not found. Install it from python.org, then run this again.'; exit 1 }
& $py.Source (Join-Path $PSScriptRoot 'publish.py')
