LoWsTourAssets static resource source. Rebuild:
  powershell -File build-assets.ps1 -Poses ..\..\onboarding\poses -Out LoWsTourAssets
  cd LoWsTourAssets && C:\windows\system32\tar.exe -a -c -f out.zip poses screens && move out.zip ..\..\force-app\main\default\staticresources\LoWsTourAssets.resource
Real screenshots: drop SS-*.png (same names) into LoWsTourAssets/screens and re-zip. Never PowerShell ZipFile (writes backslash paths).
