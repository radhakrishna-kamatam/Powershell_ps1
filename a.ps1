workflow aAutotostartandstopvminallsubscription {
    Param(
        [Parameter(Mandatory = $true)]
        [String]
        $TagName,
        [Parameter(Mandatory = $true)]
        [String]
        $TagValue,
        [Parameter(Mandatory = $true)]
        [String]
        $Action
    )
     
    $connectionName = "AzureRunAsConnection";
 
    try {
        # Get the connection "AzureRunAsConnection "
        $servicePrincipalConnection = Get-AutomationConnection -Name $connectionName        
 
        "Logging in to Azure..."
        Add-AzAccount `
            -ServicePrincipal `
            -TenantId $servicePrincipalConnection.TenantId `
            -ApplicationId $servicePrincipalConnection.ApplicationId `
            -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 
    }
    catch {
 
        if (!$servicePrincipalConnection) {
            $ErrorMessage = "Connection $connectionName not found."
            throw $ErrorMessage
        }
        else {
            Write-Error -Message $_.Exception
            throw $_.Exception
        }
    }

    $updateStatuses = @()

    $subscriptions = Get-AzSubscription | Where-Object { $_.Name -eq "" -or $_.Name -eq "" }
    #####################################################################################  
    foreach ($subscription in $subscriptions) {
        Write-Output "*******************************************************************************************************************************************************"
        Select-AzSubscription -Subscription $subscription
        Write-Output "*******************************************************************************************************************************************************"
        Write-Output "                                   $($subscription.Name) Subscription selected" 
        Write-Output "************************************************* Tagged VMs ******************************************************************************************"         
        #$resourceGroupsContent = @()
        $vms = Get-AzResource -TagName $TagName -TagValue $TagValue -ResourceType "Microsoft.Compute/virtualMachines"
            
        foreach -parallel ($instance in $vms) {
                    
            $instancePowerState = (((Get-AzVM -ResourceGroupName $($instance.ResourceGroupName) -Name $($instance.Name) -Status).Statuses.Code[1]) -replace "PowerState/", "")

            sequence {
                $resourceGroupsContent = New-Object -Type PSObject -Property @{
                    "Resource_group_name" = $($instance.ResourceGroupName)
                    "Virtual_machine"     = $($instance.Name)
                    "Instance type"       = (($instance.ResourceType -split "/")[0].Substring(10))
                    "Instance state"      = ([System.Threading.Thread]::CurrentThread.CurrentCulture.TextInfo.ToTitleCase($instancePowerState))
                    $TagName              = $TagValue
                }
                        
                Write-Output "$resourceGroupsContent"
            }
        }
        Write-Output "*****************************************************************************************************************************************************"
        Foreach -Parallel ($vm in $vms) {
            #Get-AzContext
            #$deallocated = Get-AzVM -ResourceGroupName $($vm.ResourceGroupName) -Name $($vm.Name) | Where-Object {$_.PowerState -eq "deallocated" -or $_.PowerState -eq "Deallocating"}
            #$Started = Get-AzVM -ResourceGroupName $($vm.ResourceGroupName) -Name $($vm.Name) | Where-Object {$_.PowerState -eq "running" -or $_.PowerState -eq "Starting"}
            $subname = (Get-AzContext).Subscription.Name
            if ($Action -eq "Stop") {
                Write-Output "$($vm.name) is stopping ..." 
                
                $startTime = Get-Date -Format G 
                $stoppedvm = Stop-AzVm -Name $vm.Name -ResourceGroupName $vm.ResourceGroupName -Force;

                $endTime = Get-Date -Format G
                $updateStatus = New-Object -Type PSObject -Property @{
                    "Resource_group_name" = $($vm.ResourceGroupName)
                    "Virtual_Machine"     = $($vm.Name)
                    "Start time"          = $startTime
                    "End time"            = $endTime
                    "Subscription"        = $subname
                } 

                $Workflow:updateStatuses += $updateStatus

                #Write-Output "$updateStatus"
            }
        
            else { 
                Write-Output "$($vm.name) Starting VMs";
                $startTime = Get-Date -Format G 
                $Start = Start-AzVm -Name $vm.Name -ResourceGroupName $vm.ResourceGroupName;

                $endTime = Get-Date -Format G
                $updateStatus = New-Object -Type PSObject -Property @{
                    "Resource_group_name" = $($vm.ResourceGroupName)
                    "Virtual_Machine"     = $($vm.Name)
                    "Start time"          = $startTime
                    "End time"            = $endTime
                    "Subscription"        = $subname
                } 

                $Workflow:updateStatuses += $updateStatus
                #Write-Output "$updateStatus"
            } 
        }
    
    }

    Write-Output "********************************************   Final   *************************************************************************"

    InlineScript
    {
        $Using:updateStatuses | Format-Table -AutoSize
    }

    Write-Output "********************************************   END   *************************************************************************"
}
