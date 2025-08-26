<#
.SYNOPSIS
    Collects VMware vCenter VM state information and sends metrics to InfluxDB.

.DESCRIPTION
    This script connects to a specified VMware vCenter server, gathers summary and per-VM state information,
    and writes the results to an InfluxDB instance running in a Docker container. It checks that the InfluxDB
    container is running before proceeding. VM information includes power state, OS, and datastore.

.PARAMETER influx_container
    Name of the InfluxDB Docker container. Default: "influxdb".

.PARAMETER InfluxToken
    InfluxDB API token for authentication.

.PARAMETER InfluxOrg
    InfluxDB organization name. Default: "alliancesoftware".

.PARAMETER InfluxBucket
    InfluxDB bucket name. Default: "bucket1".

.PARAMETER InfluxURL
    InfluxDB base URL. Default: "https://monitor.as.corp:8086".

.PARAMETER vcenter
    vCenter server address. Default: "p-as-vcsa.as.corp".

.PARAMETER vcenter_user
    Username for vCenter authentication.

.PARAMETER vcenter_pass
    Password for vCenter authentication.

.PARAMETER vcenter_port
    vCenter server port. Default: "34243".

.NOTES
    - Requires VMware PowerCLI and Docker CLI.
    - Expects credentials and tokens in files if not provided as parameters.
    - Designed for use in automated or scheduled environments with influx and grafana.

.EXAMPLE
    .\vm_state.ps1 -InfluxToken "token" -vcenter_user "user" -vcenter_pass "pass"
    .\vm_state.ps1
#>



param (
    [string] $influx_container = "influxdb",
    [string] $InfluxToken,
    [string] $InfluxOrg = "alliancesoftware",
    [string] $InfluxBucket = "bucket1",
    [string] $InfluxURL = 'https://monitor.as.corp:8086',
    [string] $vcenter = 'p-as-vcsa.as.corp',
    [string] $vcenter_user,
    [string] $vcenter_pass,
    [string] $vcenter_port = "34243"
)


begin {
    Import-Module VMware.PowerCLI -ErrorAction Stop

    if (-not $InfluxToken) {
        $InfluxToken = (Get-Content -Raw "/root/.env.telegraf-token").Trim()
    }
    if (-not $vcenter_user) {
        $vcenter_user = (Get-Content -Raw "/root/.env.vcenter-monitor-user-login").Trim()
    }
    if (-not $vcenter_pass) {
        $vcenter_pass = (Get-Content  "/root/.env.vcenter-monitor-readonly" -Raw).Trim()
    }

    function Escape-InfluxTag {
        param([string]$tag)
        return ($tag -replace " ", "\ " -replace ",", "\," -replace "=", "\=" -replace "\(", "\\(" -replace "\)", "\\)")
    }
    $influxURL = "$($InfluxURL)/api/v2/write?org=$($InfluxOrg)&bucket=$($InfluxBucket)&precision=s"
}

process{

    $dockerCheckInflux = docker ps --filter "name=$influx_container" --filter "status=running" --format "{{.Names}}"

    if (-not $dockerCheckInflux) {
        Write-Host "InfluxDB container not running. Exiting..."
        Write-Host -ForegroundColor yellow "Retrying after 10 secondes..."
        exit 1   # non-zero exit code → systemd will retry
    }
    Connect-VIServer -Server $vcenter -Port $vcenter_port -User $vcenter_user -Password $vcenter_pass -Force

    $allVMs     = Get-VM
    $total      = $allVMs.Count
    $poweredOn  = ($allVMs | Where-Object { $_.PowerState -eq "PoweredOn" }).Count
    $poweredOff = ($allVMs | Where-Object { $_.PowerState -eq "PoweredOff" }).Count


    $lines = @()
    $lines += "vm_summary total=$total,powered_on=$poweredOn,powered_off=$poweredOff $timestamp"


    foreach ($vm in $allVMs) {
        $vmName    = Escape-InfluxTag $vm.Name
        $v = Get-View -ViewType VirtualMachine -Filter @{ "Name" = $vmName }
        $ddss = Get-View $v.Datastore
        $datastore = ($ddss.Name).Trim()
        $os = $vm.Guest.OSFullName
        if (-not $os) { $os = "Unknown" }
        $power     = Escape-InfluxTag $vm.PowerState
        $osEscaped = Escape-InfluxTag $os
        $ds        = Escape-InfluxTag $datastore
        # Influx line (tags: name, powerstate, os, datastore | field: status=1)
        $lines += "vm_info,name=$vmName,powerstate=$power,os=$osEscaped,datastore=$ds status=1 $timestamp"
    }

    Invoke-RestMethod `
        -Uri $influxURL `
        -Method Post `
        -Headers @{ "Authorization" = "Token $InfluxToken" } `
        -Body ($lines -join "`n")

    Disconnect-VIServer -Server $vcenter -Confirm:$false
}



