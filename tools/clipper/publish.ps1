# Uploads the exported prices so the Budget Basket app can download them.
# Needs the GitHub CLI signed in once (gh auth login).
$repo = 'michaeldsepton-arch/GroceryBuilder'
$src  = Join-Path $env:USERPROFILE 'Downloads\budget-basket-catalog.json.gz'
if (-not (Test-Path $src)) {
  Write-Host 'No export found. Open the extension, click "Export prices for the app", then run this again.'
  exit 1
}
$tmp = Join-Path $env:TEMP 'catalog.json.gz'
Copy-Item $src $tmp -Force
gh release view catalog -R $repo *> $null
if ($LASTEXITCODE -ne 0) {
  gh release create catalog -R $repo --prerelease --title 'Price catalog (auto-updated)' --notes 'Prices clipped from store sites. Not an app release.'
}
gh release upload catalog $tmp -R $repo --clobber
if ($LASTEXITCODE -eq 0) { Write-Host 'Done. In the app: More > Refresh prices.' } else { Write-Host 'Upload failed. Is gh signed in? Run: gh auth login' }
