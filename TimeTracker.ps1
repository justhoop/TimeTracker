<#
.SYNOPSIS
    A simple time tracking script
.DESCRIPTION
    This script allows users to track their time spent working by recording start and stop times.
.NOTES
    This script is meant to be run continuously in the background by a scheduled task.
#>

function Get-SortableDate {
    [CmdletBinding()]
    param (
        [Parameter()]
        [DateTime]
        $date
    )
    $now = get-date -Date $date
    $month = $now.Month.ToString()
    if ($month.Length -eq 1) { $month = "0" + $month }  
    $day = $now.Day.ToString()
    if ($day.Length -eq 1) { $day = "0" + $day }  
    $result = $now.Year.ToString() + "-" + $month + "-" + $day
    return $result
}

function Get-Time {
    param (
        [TimeSpan]$span
    )
    $hours = $span.Hours
    $minutes = $span.Minutes
    If ($minutes -gt 52) {
        $hours += 1
        return $hours.ToString()
    }
    elseif (($minutes -gt 7) -and ($minutes -lt 23) ) {
        return $hours.ToString() + ".25"
    }
    elseif (($minutes -gt 22) -and ($minutes -lt 38)) {
        return $hours.ToString() + ".50"
    }
    elseif (($minutes -gt 37) -and ($minutes -lt 53)) {
        return $hours.ToString() + ".75"
    }
    else {
        return $hours.ToString()
    }
}

function Update-RecordedTime {
    param (
        [string]$today
    )
    $changed = $false
    $day = Import-Csv ".\Data\$today.csv"
    foreach ($entry in $day) {
        $span = New-TimeSpan -Start $entry.Start -End $entry.Stop
        $hours = Get-Time -span $span
        if (-not($hours -eq $entry.Total)) {
            $entry.Total = $hours
            $changed = $true
        }
    }
    if ($changed) {
        $day | Export-Csv ".\Data\$today.csv" -NoTypeInformation
    }
}

function New-TimeFile {
    param (
        [string]$today
    )
    $now = Get-Date
    $entry = [PSCustomObject]@{
        Start = $now
        Stop  = $now
        Total = "0"
    }
    $entry | Export-Csv ".\Data\$today.csv" -NoTypeInformation
}

function Set-HoursWorkedEnv {
    # This function sets the total hours worked in the registry under HKCU\Software\TimeTracker. 
    # I use this to display the total hours worked in my PowerShell prompt 
    # https://gist.github.com/justhoop/4c22ce0352d8119f9f3ac59e61bd7a30.
    $MyDocs = [Environment]::GetFolderPath("MyDocuments")
    $file = Get-ChildItem -Path .\Data\ -Filter "*.csv" | Select-Object -Last 1
    $entry = Import-Csv -Path $file.FullName
    $total = 0
    foreach ($time in $entry) {
        $span = New-TimeSpan -Start $time[-1].Start -End $time[-1].Stop
        $total += [double](Get-Time -span $span)
    }
    if (-not (test-path 'HKCU:\Software\TimeTracker')) {
        New-Item 'hkcu:\Software\TimeTracker'
        New-ItemProperty hkcu:\Software\TimeTracker -Name 'HoursWorked' -Value $total -PropertyType String
    }
    else {
        Set-ItemProperty -Path 'HKCU:\Software\TimeTracker' -Name 'HoursWorked' -Value $total
    }
}

if (-not (Test-Path ".\Data")) {
    New-Item -Path ".\Data" -ItemType Directory
}
$today = Get-SortableDate -date (Get-Date)
$complete = $false
if (Test-Path ".\Data\$today.csv") {
    $now = Get-Date
    $entry = [PSCustomObject]@{
        Start = $now
        Stop  = $now
        Total = "0"
    }
    $entry | Export-Csv ".\Data\$today.csv" -Append -NoTypeInformation
}
else {
    New-TimeFile -today $today
}
Update-RecordedTime -today $today
while ($true) {
    $entry = Import-Csv -Path ".\Data\$today.csv"
    #start a new file if the program is still running in the next day
    if ((Get-SortableDate $entry[-1].start) -ne (Get-SortableDate (Get-Date))) {
        New-TimeFile -today $today
    }
    else {
        $entry[-1].Stop = Get-Date
        $span = New-TimeSpan -Start $entry[-1].Start -End $entry[-1].Stop
        $entry[-1].Total = Get-Time -span $span
        $entry | Export-Csv ".\Data\$today.csv" -NoTypeInformation
        $total = 0
        foreach ($time in $entry) {
            $total += [double]$time.Total
            if (($total -ge 8) -and ($complete -eq $false)) {
                Start-Process "msg" -ArgumentList "$env:USERNAME $total hours"
                $complete = $true
            }
        }
    }
    Set-HoursWorkedEnv
    Start-Sleep -Seconds 180
}
