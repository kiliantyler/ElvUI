# Fork-only: pull kiliantyler/ElvUI main into this working copy (which WoW loads through junctions).
# Run daily by the "ElvUI Fork Sync" scheduled task. Log: %LOCALAPPDATA%\ElvUI-sync\sync.log
# Never discards local work: skips if not on main or if tracked files have uncommitted changes.

$git = 'C:\Program Files\Git\cmd\git.exe'
$repo = Split-Path -Parent $PSScriptRoot
$logDir = Join-Path $env:LOCALAPPDATA 'ElvUI-sync'
$log = Join-Path $logDir 'sync.log'
New-Item -ItemType Directory -Force $logDir | Out-Null

function Log([string]$msg) {
	Add-Content -Path $log -Value ("{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg)
}

function Git {
	$out = & $git -C $repo @args 2>&1 | ForEach-Object { "$_" }
	if ($LASTEXITCODE -ne 0) { throw "git $($args -join ' ') failed ($LASTEXITCODE): $($out -join ' | ')" }
	return $out
}

# keep the log from growing forever
if ((Test-Path $log) -and (Get-Item $log).Length -gt 1MB) {
	Get-Content $log -Tail 500 | Set-Content $log
}

try {
	Git fetch --quiet origin | Out-Null

	$branch = (Git rev-parse --abbrev-ref HEAD) -join ''
	if ($branch -ne 'main') { Log "SKIP: on branch '$branch', not main"; exit 0 }

	$dirty = Git status --porcelain --untracked-files=no
	if ($dirty) { Log "SKIP: uncommitted changes in tracked files"; exit 0 }

	$ahead, $behind = ((Git rev-list --left-right --count main...origin/main) -join '') -split '\s+'
	$ahead = [int]$ahead; $behind = [int]$behind

	if ($ahead -eq 0 -and $behind -eq 0) { Log 'OK: already up to date'; exit 0 }

	$oldHead = (Git rev-parse HEAD) -join ''

	if ($behind -gt 0) {
		if ($ahead -eq 0) {
			Git merge --ff-only --quiet origin/main | Out-Null
		} else {
			Git merge --no-edit --quiet origin/main | Out-Null
		}
		$newHead = (Git rev-parse --short HEAD) -join ''
		Log "UPDATED: pulled $behind commit(s) from fork, now at $newHead"

		# packaged externals (Ace3, LibStub, ...) are gitignored and were copied in by hand;
		# if upstream changed the externals list they may need refreshing
		$pkgmeta = Git diff --name-only $oldHead HEAD -- .pkgmeta
		if ($pkgmeta) { Log 'WARNING: .pkgmeta changed upstream - external libraries in ElvUI_Libraries may need updating' }
	}

	if ($ahead -gt 0) {
		Git push --quiet origin main | Out-Null
		Log "PUSHED: $ahead local commit(s) to fork"
	}
} catch {
	Log "ERROR: $($_.Exception.Message)"
	exit 1
}
