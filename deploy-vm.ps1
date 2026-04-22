param(
    [string]$vmName,
    [string]$isoPath,
    [string]$staticIp = ""
)

$ErrorActionPreference = "Stop"

try {
    Write-Output "DEBUG: Starting deployment for $vmName"

    $templateVhd = "C:\HyperV\Templates\tmpl-ubuntu-2404.vhdx"
    $newVhd = "C:\HyperV\VMs\$vmName.vhdx"

    Copy-Item $templateVhd $newVhd -Force | Out-Null

    New-VM -Name $vmName -MemoryStartupBytes 2GB -Generation 2 -VHDPath $newVhd -SwitchName "Internet External Switch" | Out-Null

    Add-VMDvdDrive -VMName $vmName -Path $isoPath | Out-Null

    Set-VMFirmware -VMName $vmName -EnableSecureBoot Off | Out-Null

    $hdd = Get-VMHardDiskDrive -VMName $vmName
    $dvd = Get-VMDvdDrive -VMName $vmName

    Set-VMFirmware -VMName $vmName -BootOrder $hdd, $dvd | Out-Null

    Start-VM $vmName | Out-Null

    if ($staticIp -ne "") {
        Write-Output "Using static IP: $staticIp"
        Write-Output $staticIp
        exit
    }

    Write-Output "WAITING_FOR_IP"

    for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Seconds 5

        $ips = (Get-VMNetworkAdapter -VMName $vmName).IPAddresses

        Write-Output ("DEBUG: Raw IPs: " + ($ips -join ", "))

        $ipv4 = @($ips | Where-Object {
                ($_ -as [string]) -match '^\d{1,3}(\.\d{1,3}){3}$' -and
                $_ -ne '0.0.0.0' -and
                $_ -notmatch '^169\.254\.'
            })

        if ($ipv4.Count -gt 0) {
            Write-Output $ipv4[0]
            exit
        }
    }

    Write-Output "NO_IP_FOUND"
}
catch {
    Write-Output "POWERSHELL_ERROR"
    Write-Output $_
}