cls

Enable-WSManCredSSP -Role Client -DelegateComputer "test.cloudapp.net" -Force
 
New-Item HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation -ErrorAction SilentlyContinue
New-Item HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation\AllowFreshCredentials -ErrorAction SilentlyContinue
New-Item HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation\AllowFreshCredentialsWhenNTLMOnly -ErrorAction SilentlyContinue


if((Get-ItemProperty HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation -Name AllowFreshCredentials -ErrorAction SilentlyContinue) -eq $null)
{
    New-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation -Name "AllowFreshCredentials" -PropertyType "DWord" -Value ([UInt32]1)
}
else
{
    Set-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation -Name "AllowFreshCredentials" -Value ([UInt32]1)
}

if((Get-ItemProperty HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation -Name AllowFreshCredentialsWhenNTLMOnly -ErrorAction SilentlyContinue) -eq $null)
{
    New-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation -Name "AllowFreshCredentialsWhenNTLMOnly" -PropertyType "DWord" -Value ([UInt32]1)
}
else
{
    Set-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation -Name "AllowFreshCredentialsWhenNTLMOnly" -Value ([UInt32]1)
}


if((Get-ItemProperty HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation -Name ConcatenateDefaults_AllowFresh -ErrorAction SilentlyContinue) -eq $null)
{
    New-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation -Name "ConcatenateDefaults_AllowFresh" -PropertyType "DWord" -Value ([UInt32]1)
}
else
{
    Set-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation -Name "ConcatenateDefaults_AllowFresh" -Value ([UInt32]1)
}

if((Get-ItemProperty HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation -Name ConcatenateDefaults_AllowSavedNTLMOnly -ErrorAction SilentlyContinue) -eq $null)
{
    New-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation -Name "ConcatenateDefaults_AllowSavedNTLMOnly" -PropertyType "DWord" -Value ([UInt32]1)
}
else
{
    Set-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation -Name "ConcatenateDefaults_AllowSavedNTLMOnly" -Value ([UInt32]1)
}

if((Get-ItemProperty HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation\AllowFreshCredentials -Name "1" -ErrorAction SilentlyContinue) -eq $null)
{
    New-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation\AllowFreshCredentials -Name "1" -PropertyType "String" -Value "WSMAN/test.cloudapp.net"
}
else
{
    Set-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation\AllowFreshCredentials -Name "1" -Value "WSMAN/test.cloudapp.net"
}

if((Get-ItemProperty HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation\AllowFreshCredentialsWhenNTLMOnly -Name "1" -ErrorAction SilentlyContinue) -eq $null)
{
    New-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation\AllowFreshCredentialsWhenNTLMOnly -Name "1" -PropertyType "String" -Value "WSMAN/test.cloudapp.net"
}
else
{
    Set-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation\AllowFreshCredentialsWhenNTLMOnly -Name "1" -Value "WSMAN/test.cloudapp.net"
}




