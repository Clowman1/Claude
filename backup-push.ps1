$ErrorActionPreference = "Stop"
Set-Location "C:\Apps\Claude Back Up"

$status = git status --porcelain
if ([string]::IsNullOrWhiteSpace($status)) {
    Write-Output "$(Get-Date -Format o) No changes, skipping."
    exit 0
}

git add -A
$date = Get-Date -Format "yyyy-MM-dd HH:mm"
git commit -m "Automated backup $date"
git push origin main

Write-Output "$(Get-Date -Format o) Backup committed and pushed."
