#    Migrate a vSphere virtual machine between clusters, where the vdSwitch ports names are unique across clusters
#    Power down the VM, assign the nic to a temporary dummy standard switch network label which exists on both clusters, migrate
#    the VM to the new cluster, assign nic to correct port group at destination, power on, update VMtools.

# Import powerCLI snapins so that this can be run in PowerShell
Add-PSSnapin VMware.VimAutomation.Core
Add-PSSnapin VMware.VimAutomation.Vds

# Variables for the name of the VM, destination vDS port name, vCenter server, destination host, vdswitch name
$vm_to_migrate = 'servername_1'
$vcenter_server = 'vcenter_servername'
$destination_host = 'destination_esxi_host'
$vdswitch_name = 'my_dvswitch_1'
$destination_vds_port_name = 'serv-staging-vlan10-dv'

# Log into vCenter
Connect-VIServer $vcenter_server

# If the VM is running, power it down and wait for the task to complete
if ((Get-VM $vm_to_migrate).PowerState -eq "PoweredOn")
    {
    Write-Host "Shutting down $vm_to_migrate" -ForegroundColor Yellow
    Shutdown-VMGuest $vm_to_migrate -confirm:$false
    do {
        Start-Sleep -s 5
        Write-Host "Waiting until $vm_to_migrate has shut down completely..." -ForegroundColor Yellow
        $power_status = (get-vm $vm_to_migrate).PowerState
        }until($power_status -eq "PoweredOff")
    }

# Change the network to a temporary network name which exists on the source and destination clusters
Write-Host "Temporarily changing the network adapter to VM Network" -ForegroundColor Yellow
get-vm $vm_to_migrate | Get-NetworkAdapter | Set-NetworkAdapter -NetworkName "VM Network" -confirm:$false

# Move the VM to a host on the destination cluster
Write-Host "Migrating $vm_to_migrate to the new cluster" -ForegroundColor Yellow
move-vm -vm $vm_to_migrate -destination (Get-vmhost -name $destination_host)

# Variable for the destination port group name which lives within a vdswitch
$target_pg = get-vdswitch -name $vdswitch_name | get-vdportgroup -name $destination_vds_port_name

Write-Host "Setting the network adapter of $vm_to_migrate to $target_pg" -ForegroundColor Yellow

# Set the VM network adapter to the destination port group
get-vm $vm_to_migrate | Get-NetworkAdapter | Set-NetworkAdapter -portgroup $target_pg -confirm:$false

# Start up the VM
Write-Host "Starting $vm_to_migrate" -ForegroundColor Yellow
start-vm $vm_to_migrate

# Let's wait until VMware Tools is running
Write-Host "Waiting for VM Tools to start" -ForegroundColor Yellow
do {
    $vmtools_status = (Get-VM $vm_to_migrate | Get-View).Guest.ToolsStatus
    Write-Host "$vmtools_status - Waiting ..." -ForegroundColor Yellow
    Start-Sleep 5
    }until ($vmtools_status -eq 'toolsOk')

# Update VMware Tools, allow a VM reboot if required
Write-Host "VM Tools update" -ForegroundColor Yellow
# Wait just a bit longer for the tools to start up
Start-Sleep 15
Get-Vm $vm_to_migrate | Update-Tools

# Close the session
Write-Host "Disconnecting gracefully..." -ForegroundColor Yellow
Disconnect-VIServer -confirm:$false

Write-Host "#### $vm_to_migrate migration completed ####" -ForegroundColor Yellow
