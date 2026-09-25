[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Purely local fault injection for the documented P3.5b execution protocol.
# No module, credential, HTTP client, or real resource is used here.
function Assert-P35b {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Invoke-P35bMockRun {
    param([string]$Fault = '')

    $state = [ordered]@{
        Records = [System.Collections.Generic.List[object]]::new()
        Events = [System.Collections.Generic.List[string]]::new()
        CreateCount = 0
        DeleteCount = 0
        Failure = ''
        CleanupFailure = ''
        FinalCount = -1
    }
    $state.Records.Add([pscustomobject]@{ Id = 'unrelated-id'; Zone = 'fixture-zone'; Name = 'unrelated.fixture.invalid'; Owner = 'other-owner'; Content = 'untouched' })
    if ($Fault -eq 'preexisting-exact') {
        $state.Records.Add([pscustomobject]@{ Id = 'preexisting-id'; Zone = 'fixture-zone'; Name = 'p35b.fixture.invalid'; Owner = 'fixture-owner'; Content = 'untouched' })
    }
    $createdId = $null
    $createUncertain = $false
    $deleted = $false
    $deleteAttempted = $false

    function Scan-Exact {
        $state.Events.Add('exact-scan')
        return @($state.Records | Where-Object { $_.Zone -ceq 'fixture-zone' -and $_.Name -ceq 'p35b.fixture.invalid' -and $_.Owner -ceq 'fixture-owner' })
    }
    function Delete-Exact {
        param([string]$Id)
        $matches = @(Scan-Exact)
        if ($matches.Count -ne 1 -or $matches[0].Id -cne $Id) { throw 'target identity is ambiguous' }
        $state.Events.Add('delete')
        $state.DeleteCount++
        if ($Fault -eq 'cleanup-delete') { throw 'injected cleanup delete failure' }
        for ($i = 0; $i -lt $state.Records.Count; $i++) {
            if ($state.Records[$i].Id -ceq $Id) { $state.Records.RemoveAt($i); break }
        }
    }

    try {
        if (@(Scan-Exact).Count -ne 0) { throw 'pre-test inventory is not empty' }
        $state.Events.Add('create')
        $state.CreateCount++
        if ($Fault -eq 'create-uncertain-empty') {
            $createUncertain = $true
            throw 'injected uncertain create'
        }
        $state.Records.Add([pscustomobject]@{ Id = 'fixture-id'; Zone = 'fixture-zone'; Name = 'p35b.fixture.invalid'; Owner = 'fixture-owner'; Content = 'initial' })
        if ($Fault -like 'create-uncertain-*') {
            if ($Fault -eq 'create-uncertain-ambiguous') {
                $state.Records.Add([pscustomobject]@{ Id = 'other-id'; Zone = 'fixture-zone'; Name = 'p35b.fixture.invalid'; Owner = 'fixture-owner'; Content = 'other' })
            }
            $createUncertain = $true
            throw 'injected uncertain create'
        }
        $createdId = 'fixture-id'
        if ($Fault -eq 'after-create') { throw 'injected post-create failure' }

        $state.Events.Add('read-1')
        if ($Fault -eq 'read-1') { throw 'injected first-read failure' }
        $state.Events.Add('edit')
        if ($Fault -eq 'edit') { throw 'injected edit failure' }
        $state.Records[1].Content = 'updated'
        $state.Events.Add('read-2')
        if ($Fault -eq 'read-2') { throw 'injected second-read failure' }
        Assert-P35b ($state.Records[1].Content -ceq 'updated') 'updated read boundary was not reached'

        $deleteAttempted = $true
        Delete-Exact $createdId
        $deleted = $true
    }
    catch {
        $state.Failure = $_.Exception.Message
    }
    finally {
        try {
            if (-not $deleted -and -not $deleteAttempted) {
                if ($createUncertain) {
                    # Never retry create. Resolve only through the exact owner/name scan.
                    $matches = @(Scan-Exact)
                    if ($matches.Count -gt 1) { throw 'uncertain create has ambiguous exact matches' }
                    if ($matches.Count -eq 1) { $createdId = $matches[0].Id }
                }
                if ($createdId) { Delete-Exact $createdId }
            }
            $remaining = @(Scan-Exact)
            $state.FinalCount = $remaining.Count
            if ($remaining.Count -ne 0) { throw 'exact cleanup scan found residue' }
        }
        catch {
            $state.CleanupFailure = $_.Exception.Message
            $state.FinalCount = @(Scan-Exact).Count
        }
    }
    return [pscustomobject]$state
}

foreach ($fault in @('', 'after-create', 'read-1', 'edit', 'read-2', 'create-uncertain-empty', 'create-uncertain-one')) {
    $result = Invoke-P35bMockRun -Fault $fault
    Assert-P35b ($result.CreateCount -eq 1) "${fault}: create was retried"
    Assert-P35b ($result.FinalCount -eq 0 -and -not $result.CleanupFailure) "${fault}: exact cleanup did not succeed"
    $expectedDeleteCount = if ($fault -eq 'create-uncertain-empty') { 0 } else { 1 }
    Assert-P35b ($result.DeleteCount -eq $expectedDeleteCount) "${fault}: delete count was not bounded"
    if ($fault) { Assert-P35b ([bool]$result.Failure) "${fault}: injected failure was not observed" }
    else { Assert-P35b (-not $result.Failure) 'normal path failed' }
    Assert-P35b ($result.Events[-1] -eq 'exact-scan') "${fault}: final exact scan was skipped"
    Assert-P35b ($result.Records.Count -eq 1 -and $result.Records[0].Id -ceq 'unrelated-id') "${fault}: unrelated record was changed"
    Write-Output "PASS P3.5b mock protocol: $(if ($fault) { $fault } else { 'normal' })"
}

$ambiguous = Invoke-P35bMockRun -Fault 'create-uncertain-ambiguous'
Assert-P35b ($ambiguous.CreateCount -eq 1 -and $ambiguous.DeleteCount -eq 0) 'ambiguous create was retried or deleted'
Assert-P35b ($ambiguous.FinalCount -eq 2 -and $ambiguous.CleanupFailure -match 'ambiguous') 'ambiguous create did not stop for operator review'
Assert-P35b ($ambiguous.Records.Count -eq 3 -and $ambiguous.Records[0].Id -ceq 'unrelated-id') 'ambiguous cleanup changed unrelated records'
Write-Output 'PASS P3.5b mock protocol: ambiguous uncertain create stops without deletion'

$cleanupFailure = Invoke-P35bMockRun -Fault 'cleanup-delete'
Assert-P35b ($cleanupFailure.CreateCount -eq 1 -and $cleanupFailure.DeleteCount -eq 1) 'cleanup failure was retried or skipped'
Assert-P35b ($cleanupFailure.FinalCount -eq 1 -and $cleanupFailure.CleanupFailure) 'cleanup failure was hidden or misreported as zero residue'
Write-Output 'PASS P3.5b mock protocol: cleanup failure remains blocking'

$preexisting = Invoke-P35bMockRun -Fault 'preexisting-exact'
Assert-P35b ($preexisting.CreateCount -eq 0 -and $preexisting.DeleteCount -eq 0) 'nonempty pre-test inventory permitted mutation'
Assert-P35b ($preexisting.FinalCount -eq 1 -and $preexisting.CleanupFailure) 'nonempty pre-test inventory was hidden'
Write-Output 'PASS P3.5b mock protocol: nonempty inventory stops before mutation'
