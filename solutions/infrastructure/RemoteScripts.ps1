<#
.Synopsis
   Installs a given Web PI application.
.DESCRIPTION
   Checks whether the Wep PI is installed, and installs it if not, then installs the given application. 
.EXAMPLE
    Install-WebPiApplication -ApplicationId phpBB
.INPUTS
   n/a
.OUTPUTS
   n/a
#>
function Install-WebPiApplication([String] $ApplicationId, [String]$AnswerFile)
{
    Set-StrictMode -Version 3.0
    if (!(Test-WebPIInstall))
    {
        $webPiSource = "http://download.microsoft.com/download/7/0/4/704CEB4C-9F42-4962-A2B0-5C84B0682C7A/WebPlatformInstaller_amd64_en-US.msi" 
        
        $webPiDest = "$env:temp\WebPlatformInstaller_amd64_en-US.msi"
        Invoke-WebRequest -Uri $webPiSource -OutFile $webPiDest
        $msiArguments = "/i " + $webPiDest + " /qn"
        
        Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArguments -PassThru | Wait-Process
    }
    
    $webPiCmd = "$env:ProgramFiles\Microsoft\Web Platform Installer\WebpiCmd.exe"
    $webPiArguments = "/Install /Application:$ApplicationId@$AnswerFile /Log:$env:temp\WebPiLog.txt /AcceptEULA"
    Start-Process -FilePath $webPiCmd -ArgumentList $webPiArguments -PassThru | Wait-Process
}

<#
.Synopsis
   Installs a given Web PI product.
.DESCRIPTION
   Checks whether the Wep PI is installed, and installs it if not, then installs the given application. 
.EXAMPLE
    Install-WebPiProduct -ProductId IIS7
#>
function Install-WebPiProduct([String] $ProductId)
{
    Set-StrictMode -Version 3.0
    if (!(Test-WebPIInstall))
    {
        $webPiSource = "http://download.microsoft.com/download/7/0/4/704CEB4C-9F42-4962-A2B0-5C84B0682C7A/WebPlatformInstaller_amd64_en-US.msi" 
        
        $webPiDest = "$env:temp\WebPlatformInstaller_amd64_en-US.msi"
        Invoke-WebRequest -Uri $webPiSource -OutFile $webPiDest
        $msiArguments = "/i " + $webPiDest + " /qn"
        
        Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArguments -PassThru | Wait-Process
    }
    
    $webPiCmd = "$env:ProgramFiles\Microsoft\Web Platform Installer\WebpiCmd.exe"
    $webPiArguments = "/Install /Products:$ProductId /Log:$env:temp\WebPiLog.txt /AcceptEULA"
    Start-Process -FilePath $webPiCmd -ArgumentList $webPiArguments -PassThru | Wait-Process
}

<#
.Synopsis
   Tests the existence of WebPI on the system.
.DESCRIPTION
   Tests the existence of the Web PI on the system by using the uninstall registry entries.
.EXAMPLE
    Test-WebPIInstall
.INPUTS
   n/a
.OUTPUTS
   boolean
#>
function Test-WebPIInstall 
{
    $installLocation = Get-ChildItem "hklm:\software\microsoft\windows\currentversion\uninstall" | 
      foreach { Get-ItemProperty $_.PSPath } | 
      Select-Object DisplayVersion, InstallDate, ModifyPath, Publisher, UninstallString, Language, DisplayName | 
      Where-Object { $_.DisplayName -ilike "*Microsoft Web Platform Installer*" }
      return ($installLocation -ne $null) -and ($installLocation.DisplayName -ne $null)
}
