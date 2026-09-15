Set-StrictMode -Version Latest

function Get-P32PortableFileHash {
    param([Parameter(Mandatory)][string]$Path)

    # P3.2 source inputs are UTF-8 text artifacts. Normalize line endings before
    # hashing so a CRLF checkout and an LF checkout describe the same input.
    $encoding = [Text.UTF8Encoding]::new($false)
    $text = [IO.File]::ReadAllText($Path, $encoding)
    $normalized = $text.Replace("`r`n", "`n").Replace("`r", "`n")
    return ([Security.Cryptography.SHA256]::HashData($encoding.GetBytes($normalized)) | ForEach-Object ToString x2) -join ''
}
