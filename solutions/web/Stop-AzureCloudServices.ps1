#How to Run this 
#..................


Param(
    [Parameter(Mandatory = $true)]
    [String]$ServiceName,              #Service Name
    [Parameter(Mandatory = $true)]
    [String]$Slot,                    #Production / Staging
    [Parameter(Mandatory = $true)]
    [bool]$OnOff                         #True=Start ; false=Stop
 )
 #Config
 $VerbosePreference = "Continue" 

#Execution
 if ($OnOff)
 {
    Write-Verbose "Start"
     $resultado= Start-AzureService -ServiceName $ServiceName -Slot $Slot  
 }
 else
 {
    Write-Verbose "Stop"
    $resultado= Stop-AzureService -ServiceName $ServiceName -Slot $Slot
    
 }

 #Result
 Return  $resultado

 