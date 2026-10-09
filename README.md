# PowerShell Temp Junk Cleaner

This script safely removes old junk files from known temporary folders while prompting for elevation and supporting `-WhatIf` before real deletion.

## Usage

Run from PowerShell:

```powershell
.\TempJunkCleaner.ps1
```

Optional switches:

```powershell
.\TempJunkCleaner.ps1 -MaxAgeDays 3
.\TempJunkCleaner.ps1 -WhatIf
.\TempJunkCleaner.ps1 -IncludeSystemTemp
```

## Safety features

- Elevates to Administrator automatically when needed
- Deletes only from known temporary locations
- Ignores system-critical folders by default
- Uses `-WhatIf` for a safe preview
- Filters files older than a configurable age
- Logs all actions to `TempJunkCleaner.log`

## Notes

This is intentionally conservative. It does not remove large system folders or essential Windows files unless you explicitly pass `-IncludeSystemTemp`.
