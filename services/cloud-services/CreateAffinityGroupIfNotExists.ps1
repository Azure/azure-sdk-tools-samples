<#
.SYNOPSIS
    Adds a new affinity group if it does not exist.
.DESCRIPTION
   Looks up the current subscription's (as set by Set-AzureSubscription cmdlet) affinity groups and creates a new
   affinity group if it does not exist.
.EXAMPLE
   New-AzureAffinityGroupIfNotExists -AffinityGroupNme newAffinityGroup -Locstion "West US"
.INPUTS
   None
.OUTPUTS
   None
#>
function New-AzureAffinityGroupIfNotExists
{
    Param
    (
        # Name of the affinity group
        [Parameter(Mandatory = $true)]
        [string]
        $AffinityGroupName,

        # Location where the affinity group will be pointing to
        [Parameter(Mandatory = $true)]
        [string]
        $Location)

        $affinityGroup = Get-AzureAffinityGroup -Name $AffinityGroupName -ErrorAction SilentlyContinue
        if ($affinityGroup -eq $null)
        {
            New-AzureAffinityGroup -Name $AffinityGroupName -Location $Location -Label $AffinityGroupName -ErrorVariable lastError -ErrorAction SilentlyContinue | Out-Null
            if (!($?))
            {
                throw "Cannot create the affinity group $AffinityGroupName on $Location"
            }
            Write-Verbose "Created affinity group $AffinityGroupName"
        }
        else
        {
            if ($affinityGroup.Location -ne $Location)
            {
                Write-Warning "Affinity group with name $AffinityGroupName already exists but in location $affinityGroup.Location, not in $Location"
            }
        }
}
