# Function to check binaries for a dependency on MSVC runtime (vcruntime*.dll)
# Inspired by: https://github.com/microsoft/vcpkg/blob/master/scripts/buildsystems/msbuild/applocal.ps1
function Check-WZBinaryDependencies([string]$targetBinary) {
    $targetBinaryPath = Resolve-Path $targetBinary -ErrorAction Stop
    Write-Verbose "Checking dependencies: $targetBinaryPath ..."
    $targetBinaryDir = Split-Path $targetBinaryPath -Parent

    if (Get-Command "dumpbin" -ErrorAction SilentlyContinue) {
        $a = $(dumpbin /DEPENDENTS $targetBinary | ? { $_ -match "^    [^ ].*\.dll" } | % { $_ -replace "^    ","" })
    } else {
        Write-Error "dumpbin could not be found. Unable to detect dependencies."
        return $false
    }
    $retValue = $true
    $a | % {
        if ([string]::IsNullOrEmpty($_)) {
            return
        }
        Write-Verbose " - Checking: $_"
        if ($_ -like "vcruntime*.dll") {
          Write-Error "File has `"$_`" dependency: ${targetBinary}"
          $retValue = $false
          return
        }
    }
    return $retValue
}

# Expects a path to the extracted contents of a WZ release archive
function Check-WZArchiveContents() {
  param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string] $path
  )

  $fileList = @(Get-ChildItem -Path "$($path)" -File -Recurse)
  $retValue = $true

  foreach ($fileobj in $fileList)
  {
    # First, check for an Authenticode signature
    $file = $($fileobj.FullName)
    $signature = Get-AuthenticodeSignature -LiteralPath "${file}"
    if ($signature.Status -eq "Valid")
    {
      $dnDict = ($signature.SignerCertificate.Subject -split ', ') |
             foreach `
                 { $dnDict = @{} } `
                 { $item = $_.Split('='); $dnDict[$item[0]] = $item[1] } `
                 { $dnDict }
      $signer_common_name = $dnDict['CN']
      Write-Information -MessageData "Has Authenticode Signature: ${file}; (Signer: ${signer_common_name})" -InformationAction Continue
      if (($signer_common_name -like '*Microsoft*') -or ($signer_common_name -like '*Windows*'))
      {
        # Do not permit distributing files that are signed by Microsoft
        Write-Error "File has Microsoft Authenticode Signature: ${file}"
        $retValue = $false
        continue
      }
    }
    
    # Then check for specific filenames
    $file_name = $(Split-Path -Path "${file}" -Leaf)
    if ($file_name -like 'vcruntime*')
    {
      Write-Error "Archive appears to include MSVC runtime: ${file}"
      $retValue = $false
      continue
    }
    if ($file_name -like 'ucrtbase*')
    {
      Write-Error "Archive appears to include UCRT: ${file}"
      $retValue = $false
      continue
    }
    if ($file_name -eq '.portable')
    {
      Write-Warning "Archive should not include .portable file: ${file}"
    }
    
    # Then check binaries
    if (($file_name -like "*.exe") -or ($file_name -like "*.dll") -or ($file_name -like "*.ocx"))
    {
      $binaryCheck = $(Check-WZBinaryDependencies "${file}")
      if(-not $binaryCheck)
      {
        Write-Error "Failed binary check: ${file}"
        $retValue = $false
        continue
      }
    }
  }

  return $retValue
}
