param(
  [Parameter(Mandatory = $true)]
  [string]$BundlePath,

  [Parameter(Mandatory = $true)]
  [ValidateSet('x64', 'arm64')]
  [string]$ExpectedArchitecture
)

$ErrorActionPreference = 'Stop'

function Get-PeArchitecture {
  param([Parameter(Mandatory = $true)][string]$Path)

  $stream = [IO.File]::OpenRead($Path)
  $reader = [IO.BinaryReader]::new($stream)
  try {
    if ($stream.Length -lt 64 -or $reader.ReadUInt16() -ne 0x5A4D) {
      throw "Not a valid PE file: $Path"
    }
    $stream.Position = 0x3C
    $peOffset = $reader.ReadInt32()
    if ($peOffset -lt 0 -or $peOffset + 6 -gt $stream.Length) {
      throw "PE header is outside the file: $Path"
    }
    $stream.Position = $peOffset
    if ($reader.ReadUInt32() -ne 0x00004550) {
      throw "PE signature is missing: $Path"
    }
    $machine = $reader.ReadUInt16()
    switch ($machine) {
      0x8664 { return 'x64' }
      0xAA64 { return 'arm64' }
      0x014C { return 'x86' }
      default { return 'unknown' }
    }
  } finally {
    $reader.Dispose()
    $stream.Dispose()
  }
}

$resolvedBundle = (Resolve-Path -LiteralPath $BundlePath).Path
$binaries = @(
  Get-ChildItem -LiteralPath $resolvedBundle -File -Recurse |
    Where-Object { $_.Extension -in @('.exe', '.dll') }
)
if ($binaries.Count -eq 0) {
  throw "Windows bundle contains no EXE or DLL files: $resolvedBundle"
}

$mismatches = @()
foreach ($binary in $binaries) {
  $actual = Get-PeArchitecture -Path $binary.FullName
  if ($actual -ne $ExpectedArchitecture) {
    $relative = [IO.Path]::GetRelativePath($resolvedBundle, $binary.FullName)
    $mismatches += "$relative ($actual)"
  }
}
if ($mismatches.Count -gt 0) {
  throw "Windows bundle is not consistently ${ExpectedArchitecture}: $($mismatches -join ', ')"
}

Write-Host "Verified $($binaries.Count) Windows binaries as $ExpectedArchitecture."
