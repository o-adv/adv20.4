<#
 # Copyright 2002 - 2014 Caphyon LTD. All rights reserved.
 #
 # mailto: eng@caphyon.com
 # http://www.caphyon.com
 #
 #>

<# 
 # This script file contains helper functions that generate the XML digest
 # that is udes to create SMS_Application objects for SCCM 2012
 # 
 # VERY IMPORTANT: The script is dependent of the existence of the SCCM Admin Console
 # on the computer were it is ran.
 #
 #>


function Import-SCCMAssemblies($SCCMAdminConsolePath)
{
  $path = "$SCCMAdminConsolePath\Microsoft.ConfigurationManagement.ApplicationManagement.dll"
  if (Test-Path $path) 
  { 
    $t = [System.Reflection.Assembly]::LoadFrom($path)
  }
   
  $path = "$SCCMAdminConsolePath\Microsoft.ConfigurationManagement.ApplicationManagement.AppVInstaller.dll"
  if (Test-Path $path) 
  { 
    $t = [System.Reflection.Assembly]::LoadFrom($path)
  }
   
  $path = "$SCCMAdminConsolePath\Microsoft.ConfigurationManagement.ApplicationManagement.AppV5XInstaller.dll"
  if (Test-Path $path) 
  { 
    $t = [System.Reflection.Assembly]::LoadFrom($path)
  }

  $path = "$SCCMAdminConsolePath\Microsoft.ConfigurationManagement.ZipArchive.dll"
  if (Test-Path $path) 
  { 
    $t = [System.Reflection.Assembly]::LoadFrom($path)
  }

  $path = "$SCCMAdminConsolePath\Microsoft.ConfigurationManagement.ApplicationManagement.MsiInstaller.dll"
  if (Test-Path $path) 
  { 
    $t = [System.Reflection.Assembly]::LoadFrom($path)
  }

  $path = "$SCCMAdminConsolePath\Microsoft.ConfigurationManagement.ApplicationManagement.Win8Installer.dll"
  if (Test-Path $path) 
  { 
    $t = [System.Reflection.Assembly]::LoadFrom($path)
  }
}


function New-SmsApplication
{
  #Named parameters list for the function
  [CmdletBinding()]
  Param
  ( 
    [Parameter(Mandatory=$true)]
    [System.String]$appScopeId,
    
    [Parameter(Mandatory=$true)]
    [System.String]$appTitle,
    
    [System.String]$appDescription,
    
    [System.String]$appVersion,
    
    [System.String]$appPublisher,

    [System.String]$appLanguage
  )

  #Compute Authoring ScopeID. This should be provided by the SMS site
  $scopeid = $appScopeId   
  if ([System.String]::IsNullOrEmpty($scopeid)) 
  {
    $scopeid = "ScopeId_" + [System.Guid]::NewGuid().ToString() 
  }

  #Set the
  [Microsoft.ConfigurationManagement.ApplicationManagement.NamedObject]::DefaultScope = $scopeid

  #Create an unique id for the application and the deployment type
  $newApplicationID    = "Application_" + [System.Guid]::NewGuid().ToString()

  #Create SCCM 2012 object id for application and deployment type
  $newApplicationID = New-Object Microsoft.ConfigurationManagement.ApplicationManagement.ObjectID($scopeid, $newApplicationID)

   #Create all the objects necessary for the creation of the application
  $newApplication = New-Object Microsoft.ConfigurationManagement.ApplicationManagement.Application($newApplicationID)
  $newDisplayInfo = New-Object Microsoft.ConfigurationManagement.ApplicationManagement.AppDisplayInfo

  #Setting Display Info
  $newDisplayInfo.Title       = $appTitle 
  $newDisplayInfo.Language    = $appLanguage 
  $newDisplayInfo.Description = $appDescription
  $newDisplayInfo.Publisher   = $appPublisher 
  $newDisplayInfo.Version     = $appVersion

  #Add display info to application
  $newApplication.DisplayInfo.Add($newDisplayInfo)

  #Setting default Language must be set and display info must exists
  $newApplication.DisplayInfo.DefaultLanguage = $appLanguage 
  $newApplication.Title                       = $appTitle 
  $newApplication.Version                     = 1
  $newApplication.Publisher                   = $appPublisher 
  $newApplication.Description                 = $appDescription
  $newApplication.SoftwareVersion             = $appVersion
  $newApplication.CustomId                    = $appTitle

  return $newApplication
}

<############################################################################>
#Compute Retrieve XML digest for a Appv 4.x package 
function Get-SmsAppV4xApplicationXml
{
  #Named parameters list for the function
  [CmdletBinding()]
  Param
  (
    [Parameter(Mandatory=$true)]
    [System.String]$sccmAdminConsolePath,
    
    [Parameter(Mandatory=$true)]
    [System.String]$packagePath,
    
    [Parameter(Mandatory=$true)]
    [System.String]$appScopeId,
    
    [Parameter(Mandatory=$true)]
    [System.String]$appTitle,
    
    [System.String]$appDescription,
    
    [System.String]$appVersion,
    
    [System.String]$appPublisher,

    [System.String]$appLanguage
  )

  #Load the referenced SCCM assemblies
  Import-SCCMAssemblies $sccmAdminConsolePath 
  
  $newApplication = New-SmsApplication $appScopeId $appTitle $appDescription $appVersion $appPublisher $appLanguage

  #Deployment Type AppV
  $newAppV4xContentImporter = New-Object Microsoft.ConfigurationManagement.ApplicationManagement.AppvContentImporter
  $newAppV4xDeploymentType  = $newAppV4xContentImporter.CreateDeploymentType($packagePath)
  $newAppV4xDeploymentType.Installer.Contents[0].OnFastNetwork = [Microsoft.ConfigurationManagement.ApplicationManagement.ContentHandlingMode]::Download
  $newAppV4xDeploymentType.Installer.Contents[0].OnSlowNetwork = [Microsoft.ConfigurationManagement.ApplicationManagement.ContentHandlingMode]::Download
  $newApplication.DeploymentTypes.Add($newAppV4xDeploymentType)


  #Serialize the object to an xml blob
  $newApplicationXML = [Microsoft.ConfigurationManagement.ApplicationManagement.Serialization.SccmSerializer]::SerializeToSTring($newApplication, $true)

  return $newApplicationXML
}

<############################################################################>

function Get-SmsAppV5xApplicationXml
{
  [CmdletBinding()]
  Param
  (
    [Parameter(Mandatory=$true)]
    [System.String]$sccmAdminConsolePath,
    
    [Parameter(Mandatory=$true)]
    [System.String]$packagePath,
    
    [Parameter(Mandatory=$true)]
    [System.String]$appScopeId,
    
    [Parameter(Mandatory=$true)]
    [System.String]$appTitle,
    
    [System.String]$appDescription,
    
    [System.String]$appVersion,
    
    [System.String]$appPublisher,

    [System.String]$appLanguage
  )
  
  #Load the referenced SCCM assemblies
  Import-SCCMAssemblies $sccmAdminConsolePath 

  $newApplication = New-SmsApplication $appScopeId $appTitle $appDescription $appVersion $appPublisher $appLanguage

  #Deployment Type AppV
  $newAppV5xContentImporter  = New-Object Microsoft.ConfigurationManagement.ApplicationManagement.Appv5XContentImporter
  $newAppV5xDeploymentType   = $newAppV5xContentImporter.CreateDeploymentType($packagePath)
  $newAppV5xDeploymentType.Installer.Contents[0].OnFastNetwork = [Microsoft.ConfigurationManagement.ApplicationManagement.ContentHandlingMode]::Download
  $newAppV5xDeploymentType.Installer.Contents[0].OnSlowNetwork = [Microsoft.ConfigurationManagement.ApplicationManagement.ContentHandlingMode]::Download
  $newApplication.DeploymentTypes.Add($newAppV5xDeploymentType)



  #Serialize the object to an xml blob
  $newApplicationXML = [Microsoft.ConfigurationManagement.ApplicationManagement.Serialization.SccmSerializer]::SerializeToSTring($newApplication, $true)
  
  return $newApplicationXML
 }

<############################################################################>

function Get-SmsMsiApplicationXml
{
  [CmdletBinding()]
  Param
  (
    [Parameter(Mandatory=$true)]
    [System.String]$sccmAdminConsolePath,
    
    [Parameter(Mandatory=$true)]
    [System.String]$packagePath,
    
    [Parameter(Mandatory=$true)]
    [System.String]$appScopeId,
    
    [Parameter(Mandatory=$true)] 
    [System.String]$appTitle,
    
    [System.String]$appDescription,
    
    [System.String]$appVersion,
    
    [System.String]$appPublisher,

    [System.String]$appLanguage
  )
  
  #Load the referenced SCCM assemblies
  Import-SCCMAssemblies $sccmAdminConsolePath 

  $newApplication = New-SmsApplication $appScopeId $appTitle $appDescription $appVersion $appPublisher $appLanguage

  #Deployment Type AppV
  $newMsiContentImporter  = New-Object Microsoft.ConfigurationManagement.ApplicationManagement.MsiContentImporter
  $newMsiDeploymentType   = $newMsiContentImporter.CreateDeploymentType($packagePath)
  $newMsiDeploymentType.Installer.Contents[0].OnFastNetwork = [Microsoft.ConfigurationManagement.ApplicationManagement.ContentHandlingMode]::Download
  $newMsiDeploymentType.Installer.Contents[0].OnSlowNetwork = [Microsoft.ConfigurationManagement.ApplicationManagement.ContentHandlingMode]::Download
  $newApplication.DeploymentTypes.Add($newMsiDeploymentType)

  #Serialize the object to an xml blob
  $newApplicationXML = [Microsoft.ConfigurationManagement.ApplicationManagement.Serialization.SccmSerializer]::SerializeToSTring($newApplication, $true)
  
  return $newApplicationXML
 }

 <############################################################################>

function Get-SmsWin8ApplicationXml
{
  [CmdletBinding()]
  Param
  (
    [Parameter(Mandatory=$true)]
    [System.String]$sccmAdminConsolePath,
    
    [Parameter(Mandatory=$true)]
    [System.String]$packagePath,
    
    [Parameter(Mandatory=$true)]
    [System.String]$appScopeId,
    
    [Parameter(Mandatory=$true)]
    [System.String]$appTitle,
    
    [System.String]$appDescription,
    
    [System.String]$appVersion,
    
    [System.String]$appPublisher,

    [System.String]$appLanguage
  )
  
  #Load the referenced SCCM assemblies
  Import-SCCMAssemblies $sccmAdminConsolePath 

  $newApplication = New-SmsApplication $appScopeId $appTitle $appDescription $appVersion $appPublisher $appLanguage

  #Deployment Type AppV
  $newWin8ContentImporter  = New-Object Microsoft.ConfigurationManagement.ApplicationManagement.Windows8AppContentImporter
  $newWin8DeploymentType   = $newWin8ContentImporter.CreateDeploymentType($packagePath)
  $newWin8DeploymentType.Installer.Contents[0].OnFastNetwork = [Microsoft.ConfigurationManagement.ApplicationManagement.ContentHandlingMode]::Download
  $newWin8DeploymentType.Installer.Contents[0].OnSlowNetwork = [Microsoft.ConfigurationManagement.ApplicationManagement.ContentHandlingMode]::Download
  $newApplication.DeploymentTypes.Add($newWin8DeploymentType)



  #Serialize the object to an xml blob
  $newApplicationXML = [Microsoft.ConfigurationManagement.ApplicationManagement.Serialization.SccmSerializer]::SerializeToSTring($newApplication, $true)
  
  return $newApplicationXML
 }
# SIG # Begin signature block
# MIIjqwYJKoZIhvcNAQcCoIIjnDCCI5gCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCA8QRWnz/jYXtuP
# XWZlbnJ1czDJJkiCtfyhKwb+e9IFm6CCCWcwggSZMIIDgaADAgECAhBxoLc2ld2x
# r8I7K5oY7lTLMA0GCSqGSIb3DQEBCwUAMIGpMQswCQYDVQQGEwJVUzEVMBMGA1UE
# ChMMdGhhd3RlLCBJbmMuMSgwJgYDVQQLEx9DZXJ0aWZpY2F0aW9uIFNlcnZpY2Vz
# IERpdmlzaW9uMTgwNgYDVQQLEy8oYykgMjAwNiB0aGF3dGUsIEluYy4gLSBGb3Ig
# YXV0aG9yaXplZCB1c2Ugb25seTEfMB0GA1UEAxMWdGhhd3RlIFByaW1hcnkgUm9v
# dCBDQTAeFw0xMzEyMTAwMDAwMDBaFw0yMzEyMDkyMzU5NTlaMEwxCzAJBgNVBAYT
# AlVTMRUwEwYDVQQKEwx0aGF3dGUsIEluYy4xJjAkBgNVBAMTHXRoYXd0ZSBTSEEy
# NTYgQ29kZSBTaWduaW5nIENBMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKC
# AQEAm1UCTBcF6dBmw/wordPA/u/g6X7UHvaqG5FG/fUW7ZgHU/q6hxt9nh8BJ6u5
# 0mfKtxAlU/TjvpuQuO0jXELvZCVY5YgiGr71x671voqxERGTGiKpdGnBdLZoh6eD
# MPlk8bHjOD701sH8Ev5zVxc1V4rdUI0D+GbNynaDE8jXDnEd5GPJuhf40bnkiNIs
# KMghIA1BtwviL8KA5oh7U2zDRGOBf2hHjCsqz1v0jElhummF/WsAeAUmaRMwgDhO
# 8VpVycVQ1qo4iUdDXP5Nc6VJxZNp/neWmq/zjA5XujPZDsZC0wN3xLs5rZH58/eW
# XDpkpu0nV8HoQPNT8r4pNP5f+QIDAQABo4IBFzCCARMwLwYIKwYBBQUHAQEEIzAh
# MB8GCCsGAQUFBzABhhNodHRwOi8vdDIuc3ltY2IuY29tMBIGA1UdEwEB/wQIMAYB
# Af8CAQAwMgYDVR0fBCswKTAnoCWgI4YhaHR0cDovL3QxLnN5bWNiLmNvbS9UaGF3
# dGVQQ0EuY3JsMB0GA1UdJQQWMBQGCCsGAQUFBwMCBggrBgEFBQcDAzAOBgNVHQ8B
# Af8EBAMCAQYwKQYDVR0RBCIwIKQeMBwxGjAYBgNVBAMTEVN5bWFudGVjUEtJLTEt
# NTY4MB0GA1UdDgQWBBRXhptUuL6mKYrk9sLiExiJhc3ctzAfBgNVHSMEGDAWgBR7
# W0XPr87Lev0xkhpqtvNG61dIUDANBgkqhkiG9w0BAQsFAAOCAQEAJDv116A2E8dD
# /vAJh2jRmDFuEuQ/Hh+We2tMHoeei8Vso7EMe1CS1YGcsY8sKbfu+ZEFuY5B8Sz2
# 0FktmOC56oABR0CVuD2dA715uzW2rZxMJ/ZnRRDJxbyHTlV70oe73dww78bUbMyZ
# NW0c4GDTzWiPKVlLiZYIRsmO/HVPxdwJzE4ni0TNB7ysBOC1M6WHn/TdcwyR6hKB
# b+N18B61k2xEF9U+l8m9ByxWdx+F3Ubov94sgZSj9+W3p8E3n3XKVXdNXjYpyoXY
# RUFyV3XAeVv6NBAGbWQgQrc6yB8dRmQCX8ZHvvDEOihU2vYeT5qiGUOkb0n4/F5C
# ICiEi0cgbjCCBMYwggOuoAMCAQICEHl9WWYEkVW+vzg/+wvjKRAwDQYJKoZIhvcN
# AQELBQAwTDELMAkGA1UEBhMCVVMxFTATBgNVBAoTDHRoYXd0ZSwgSW5jLjEmMCQG
# A1UEAxMddGhhd3RlIFNIQTI1NiBDb2RlIFNpZ25pbmcgQ0EwHhcNMjAwMzA2MDAw
# MDAwWhcNMjMwMzA1MjM1OTU5WjCBgzELMAkGA1UEBhMCUk8xDTALBgNVBAgMBERv
# bGoxEDAOBgNVBAcMB0NyYWlvdmExFDASBgNVBAoMC0NhcGh5b24gU1JMMScwJQYD
# VQQLDB5TRUNVUkUgQVBQTElDQVRJT04gREVWRUxPUE1FTlQxFDASBgNVBAMMC0Nh
# cGh5b24gU1JMMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAq71V3Uuv
# a1PB2bmlpb7qeC8gIcun9DE3uuRU0EGrB+ShnGCNh6TypOGx3tRFHvOdpmvnKMR+
# uEMt5XGPD6cbUxAYm+SfXuBWidfl1OPaUzhIvfTqX2lho3sD+B+lcNpYtuyNPfEr
# mf+opPtBFeQwcjmgSQp+QZ0aPdup4xzDHkbMhMxXD5lM58ZqYF9zRJp57SSsXYvM
# d5Q/lpFtNSqVSmMOhN7n7b7ynVgQn10EOlaYH1xlMBFegX4zCnA33uc7R7Exk9jN
# +xtrCD6vQpXy0+bEMLO60txciv1VDHcTqBkgiwec2vmiDeDs62AmotkZHWbXqID6
# O+oLZGNIAvlfRQIDAQABo4IBajCCAWYwCQYDVR0TBAIwADAfBgNVHSMEGDAWgBRX
# hptUuL6mKYrk9sLiExiJhc3ctzAdBgNVHQ4EFgQUAhDZ9o5lluaECwCUOe+Oj5ld
# WeUwKwYDVR0fBCQwIjAgoB6gHIYaaHR0cDovL3RsLnN5bWNiLmNvbS90bC5jcmww
# DgYDVR0PAQH/BAQDAgeAMBMGA1UdJQQMMAoGCCsGAQUFBwMDMG4GA1UdIARnMGUw
# YwYGZ4EMAQQBMFkwJgYIKwYBBQUHAgEWGmh0dHBzOi8vd3d3LnRoYXd0ZS5jb20v
# Y3BzMC8GCCsGAQUFBwICMCMMIWh0dHBzOi8vd3d3LnRoYXd0ZS5jb20vcmVwb3Np
# dG9yeTBXBggrBgEFBQcBAQRLMEkwHwYIKwYBBQUHMAGGE2h0dHA6Ly90bC5zeW1j
# ZC5jb20wJgYIKwYBBQUHMAKGGmh0dHA6Ly90bC5zeW1jYi5jb20vdGwuY3J0MA0G
# CSqGSIb3DQEBCwUAA4IBAQCC0R0RxanMjRYWO5WMyjrhQR5YO+e16hD9rqX3398m
# 0nbakhmvw0B4Wre8A5GiwRYnBgG7sQnCwmFfjEDxIb9HuCxIWTsEc4KGIl/mjyGG
# BW3KgaOYsj95nsUIwhOHGnDx14dD+xfOxdjEhD3CThFn8vN5tG8KkmKPKW1gdPK0
# weU4iBZeoOLvx7u7aUKnauShbnalxEHANVX5F2BZ5YhqG+EAzssLWMtjulY3kDEO
# 9FPE2GGqGlaoonb7MMiqsF4hnUCkcPCoVjt4SXrYY7PmWef0crShDxBuBfvHpYG2
# iyhhxw4Jtxs5mOQd36/nmPiy8bpifxdZmIvErV9jDyqEMYIZmjCCGZYCAQEwYDBM
# MQswCQYDVQQGEwJVUzEVMBMGA1UEChMMdGhhd3RlLCBJbmMuMSYwJAYDVQQDEx10
# aGF3dGUgU0hBMjU2IENvZGUgU2lnbmluZyBDQQIQeX1ZZgSRVb6/OD/7C+MpEDAN
# BglghkgBZQMEAgEFAKCByjAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgor
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQg+TEIPItT
# iBqxKEkdL1h/sjo37Sd95Xl4kpN5UU7wiDEwXgYKKwYBBAGCNwIBDDFQME6gJoAk
# AEEAZAB2AGEAbgBjAGUAZAAgAEkAbgBzAHQAYQBsAGwAZQByoSSAImh0dHBzOi8v
# d3d3LmFkdmFuY2VkaW5zdGFsbGVyLmNvbSAwDQYJKoZIhvcNAQEBBQAEggEAF4C3
# Z06HikbX+xYhlPgfIj3a5lQqvFKeCjLK29RCXne9MQd+vJOCFmoDbrd+VVY/8lnH
# 1DsCZBdDwyRd2zqIF/Yc0rhoKVS+5QTuAp0uEXjf0m2OBe+JjfzAIgBJZadhSELo
# su3gHAg4OUigRC3FiQMwU7RlrIeYY2tPhhT7MyJWl3L2iSKMEdvfoXNGGKYdDhrW
# CJyJX78SO4LlGoRT/M+TTX5P9T2C41nC0Wu13MeeixkC3uKcQWE3Eh9PrLVWfP8V
# AkJgrfYHkWo+CnBotWn0vzRQM5DevWILuICJ26hi0mFIfpbmjTBEYBpaaAVeh+yj
# emnIRtSRB19Sji5Lu6GCFz4wghc6BgorBgEEAYI3AwMBMYIXKjCCFyYGCSqGSIb3
# DQEHAqCCFxcwghcTAgEDMQ8wDQYJYIZIAWUDBAIBBQAweAYLKoZIhvcNAQkQAQSg
# aQRnMGUCAQEGCWCGSAGG/WwHATAxMA0GCWCGSAFlAwQCAQUABCAEETzS5YECWrIS
# U3W57NW1VjJRz4wW9X/afJJMoWAiEQIRAPHrJL8ewCnb8XKZkyZXzEwYDzIwMjMw
# MzAyMTUzMTI1WqCCEwcwggbAMIIEqKADAgECAhAMTWlyS5T6PCpKPSkHgD1aMA0G
# CSqGSIb3DQEBCwUAMGMxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwg
# SW5jLjE7MDkGA1UEAxMyRGlnaUNlcnQgVHJ1c3RlZCBHNCBSU0E0MDk2IFNIQTI1
# NiBUaW1lU3RhbXBpbmcgQ0EwHhcNMjIwOTIxMDAwMDAwWhcNMzMxMTIxMjM1OTU5
# WjBGMQswCQYDVQQGEwJVUzERMA8GA1UEChMIRGlnaUNlcnQxJDAiBgNVBAMTG0Rp
# Z2lDZXJ0IFRpbWVzdGFtcCAyMDIyIC0gMjCCAiIwDQYJKoZIhvcNAQEBBQADggIP
# ADCCAgoCggIBAM/spSY6xqnya7uNwQ2a26HoFIV0MxomrNAcVR4eNm28klUMYfSd
# CXc9FZYIL2tkpP0GgxbXkZI4HDEClvtysZc6Va8z7GGK6aYo25BjXL2JU+A6LYyH
# Qq4mpOS7eHi5ehbhVsbAumRTuyoW51BIu4hpDIjG8b7gL307scpTjUCDHufLckko
# HkyAHoVW54Xt8mG8qjoHffarbuVm3eJc9S/tjdRNlYRo44DLannR0hCRRinrPiby
# tIzNTLlmyLuqUDgN5YyUXRlav/V7QG5vFqianJVHhoV5PgxeZowaCiS+nKrSnLb3
# T254xCg/oxwPUAY3ugjZNaa1Htp4WB056PhMkRCWfk3h3cKtpX74LRsf7CtGGKMZ
# 9jn39cFPcS6JAxGiS7uYv/pP5Hs27wZE5FX/NurlfDHn88JSxOYWe1p+pSVz28Bq
# mSEtY+VZ9U0vkB8nt9KrFOU4ZodRCGv7U0M50GT6Vs/g9ArmFG1keLuY/ZTDcyHz
# L8IuINeBrNPxB9ThvdldS24xlCmL5kGkZZTAWOXlLimQprdhZPrZIGwYUWC6poEP
# CSVT8b876asHDmoHOWIZydaFfxPZjXnPYsXs4Xu5zGcTB5rBeO3GiMiwbjJ5xwtZ
# g43G7vUsfHuOy2SJ8bHEuOdTXl9V0n0ZKVkDTvpd6kVzHIR+187i1Dp3AgMBAAGj
# ggGLMIIBhzAOBgNVHQ8BAf8EBAMCB4AwDAYDVR0TAQH/BAIwADAWBgNVHSUBAf8E
# DDAKBggrBgEFBQcDCDAgBgNVHSAEGTAXMAgGBmeBDAEEAjALBglghkgBhv1sBwEw
# HwYDVR0jBBgwFoAUuhbZbU2FL3MpdpovdYxqII+eyG8wHQYDVR0OBBYEFGKK3tBh
# /I8xFO2XC809KpQU31KcMFoGA1UdHwRTMFEwT6BNoEuGSWh0dHA6Ly9jcmwzLmRp
# Z2ljZXJ0LmNvbS9EaWdpQ2VydFRydXN0ZWRHNFJTQTQwOTZTSEEyNTZUaW1lU3Rh
# bXBpbmdDQS5jcmwwgZAGCCsGAQUFBwEBBIGDMIGAMCQGCCsGAQUFBzABhhhodHRw
# Oi8vb2NzcC5kaWdpY2VydC5jb20wWAYIKwYBBQUHMAKGTGh0dHA6Ly9jYWNlcnRz
# LmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFRydXN0ZWRHNFJTQTQwOTZTSEEyNTZUaW1l
# U3RhbXBpbmdDQS5jcnQwDQYJKoZIhvcNAQELBQADggIBAFWqKhrzRvN4Vzcw/HXj
# T9aFI/H8+ZU5myXm93KKmMN31GT8Ffs2wklRLHiIY1UJRjkA/GnUypsp+6M/wMkA
# mxMdsJiJ3HjyzXyFzVOdr2LiYWajFCpFh0qYQitQ/Bu1nggwCfrkLdcJiXn5CeaI
# zn0buGqim8FTYAnoo7id160fHLjsmEHw9g6A++T/350Qp+sAul9Kjxo6UrTqvwlJ
# FTU2WZoPVNKyG39+XgmtdlSKdG3K0gVnK3br/5iyJpU4GYhEFOUKWaJr5yI+RCHS
# PxzAm+18SLLYkgyRTzxmlK9dAlPrnuKe5NMfhgFknADC6Vp0dQ094XmIvxwBl8kZ
# I4DXNlpflhaxYwzGRkA7zl011Fk+Q5oYrsPJy8P7mxNfarXH4PMFw1nfJ2Ir3kHJ
# U7n/NBBn9iYymHv+XEKUgZSCnawKi8ZLFUrTmJBFYDOA4CPe+AOk9kVH5c64A0JH
# 6EE2cXet/aLol3ROLtoeHYxayB6a1cLwxiKoT5u92ByaUcQvmvZfpyeXupYuhVfA
# YOd4Vn9q78KVmksRAsiCnMkaBXy6cbVOepls9Oie1FqYyJ+/jbsYXEP10Cro4mLu
# eATbvdH7WwqocH7wl4R44wgDXUcsY6glOJcB0j862uXl9uab3H4szP8XTE0AotjW
# AQ64i+7m4HJViSwnGWH2dwGMMIIGrjCCBJagAwIBAgIQBzY3tyRUfNhHrP0oZipe
# WzANBgkqhkiG9w0BAQsFADBiMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNl
# cnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSEwHwYDVQQDExhEaWdp
# Q2VydCBUcnVzdGVkIFJvb3QgRzQwHhcNMjIwMzIzMDAwMDAwWhcNMzcwMzIyMjM1
# OTU5WjBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNlcnQsIEluYy4xOzA5
# BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBTSEEyNTYgVGltZVN0
# YW1waW5nIENBMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAxoY1Bkmz
# wT1ySVFVxyUDxPKRN6mXUaHW0oPRnkyibaCwzIP5WvYRoUQVQl+kiPNo+n3znIkL
# f50fng8zH1ATCyZzlm34V6gCff1DtITaEfFzsbPuK4CEiiIY3+vaPcQXf6sZKz5C
# 3GeO6lE98NZW1OcoLevTsbV15x8GZY2UKdPZ7Gnf2ZCHRgB720RBidx8ald68Dd5
# n12sy+iEZLRS8nZH92GDGd1ftFQLIWhuNyG7QKxfst5Kfc71ORJn7w6lY2zkpsUd
# zTYNXNXmG6jBZHRAp8ByxbpOH7G1WE15/tePc5OsLDnipUjW8LAxE6lXKZYnLvWH
# po9OdhVVJnCYJn+gGkcgQ+NDY4B7dW4nJZCYOjgRs/b2nuY7W+yB3iIU2YIqx5K/
# oN7jPqJz+ucfWmyU8lKVEStYdEAoq3NDzt9KoRxrOMUp88qqlnNCaJ+2RrOdOqPV
# A+C/8KI8ykLcGEh/FDTP0kyr75s9/g64ZCr6dSgkQe1CvwWcZklSUPRR8zZJTYsg
# 0ixXNXkrqPNFYLwjjVj33GHek/45wPmyMKVM1+mYSlg+0wOI/rOP015LdhJRk8mM
# DDtbiiKowSYI+RQQEgN9XyO7ZONj4KbhPvbCdLI/Hgl27KtdRnXiYKNYCQEoAA6E
# VO7O6V3IXjASvUaetdN2udIOa5kM0jO0zbECAwEAAaOCAV0wggFZMBIGA1UdEwEB
# /wQIMAYBAf8CAQAwHQYDVR0OBBYEFLoW2W1NhS9zKXaaL3WMaiCPnshvMB8GA1Ud
# IwQYMBaAFOzX44LScV1kTN8uZz/nupiuHA9PMA4GA1UdDwEB/wQEAwIBhjATBgNV
# HSUEDDAKBggrBgEFBQcDCDB3BggrBgEFBQcBAQRrMGkwJAYIKwYBBQUHMAGGGGh0
# dHA6Ly9vY3NwLmRpZ2ljZXJ0LmNvbTBBBggrBgEFBQcwAoY1aHR0cDovL2NhY2Vy
# dHMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0VHJ1c3RlZFJvb3RHNC5jcnQwQwYDVR0f
# BDwwOjA4oDagNIYyaHR0cDovL2NybDMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0VHJ1
# c3RlZFJvb3RHNC5jcmwwIAYDVR0gBBkwFzAIBgZngQwBBAIwCwYJYIZIAYb9bAcB
# MA0GCSqGSIb3DQEBCwUAA4ICAQB9WY7Ak7ZvmKlEIgF+ZtbYIULhsBguEE0TzzBT
# zr8Y+8dQXeJLKftwig2qKWn8acHPHQfpPmDI2AvlXFvXbYf6hCAlNDFnzbYSlm/E
# UExiHQwIgqgWvalWzxVzjQEiJc6VaT9Hd/tydBTX/6tPiix6q4XNQ1/tYLaqT5Fm
# niye4Iqs5f2MvGQmh2ySvZ180HAKfO+ovHVPulr3qRCyXen/KFSJ8NWKcXZl2szw
# cqMj+sAngkSumScbqyQeJsG33irr9p6xeZmBo1aGqwpFyd/EjaDnmPv7pp1yr8TH
# wcFqcdnGE4AJxLafzYeHJLtPo0m5d2aR8XKc6UsCUqc3fpNTrDsdCEkPlM05et3/
# JWOZJyw9P2un8WbDQc1PtkCbISFA0LcTJM3cHXg65J6t5TRxktcma+Q4c6umAU+9
# Pzt4rUyt+8SVe+0KXzM5h0F4ejjpnOHdI/0dKNPH+ejxmF/7K9h+8kaddSweJywm
# 228Vex4Ziza4k9Tm8heZWcpw8De/mADfIBZPJ/tgZxahZrrdVcA6KYawmKAr7ZVB
# tzrVFZgxtGIJDwq9gdkT/r+k0fNX2bwE+oLeMt8EifAAzV3C+dAjfwAL5HYCJtnw
# ZXZCpimHCUcr5n8apIUP/JiW9lVUKx+A+sDyDivl1vupL0QVSucTDh3bNzgaoSv2
# 7dZ8/DCCBY0wggR1oAMCAQICEA6bGI750C3n79tQ4ghAGFowDQYJKoZIhvcNAQEM
# BQAwZTELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UE
# CxMQd3d3LmRpZ2ljZXJ0LmNvbTEkMCIGA1UEAxMbRGlnaUNlcnQgQXNzdXJlZCBJ
# RCBSb290IENBMB4XDTIyMDgwMTAwMDAwMFoXDTMxMTEwOTIzNTk1OVowYjELMAkG
# A1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3LmRp
# Z2ljZXJ0LmNvbTEhMB8GA1UEAxMYRGlnaUNlcnQgVHJ1c3RlZCBSb290IEc0MIIC
# IjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAv+aQc2jeu+RdSjwwIjBpM+zC
# pyUuySE98orYWcLhKac9WKt2ms2uexuEDcQwH/MbpDgW61bGl20dq7J58soR0uRf
# 1gU8Ug9SH8aeFaV+vp+pVxZZVXKvaJNwwrK6dZlqczKU0RBEEC7fgvMHhOZ0O21x
# 4i0MG+4g1ckgHWMpLc7sXk7Ik/ghYZs06wXGXuxbGrzryc/NrDRAX7F6Zu53yEio
# ZldXn1RYjgwrt0+nMNlW7sp7XeOtyU9e5TXnMcvak17cjo+A2raRmECQecN4x7ax
# xLVqGDgDEI3Y1DekLgV9iPWCPhCRcKtVgkEy19sEcypukQF8IUzUvK4bA3VdeGbZ
# OjFEmjNAvwjXWkmkwuapoGfdpCe8oU85tRFYF/ckXEaPZPfBaYh2mHY9WV1CdoeJ
# l2l6SPDgohIbZpp0yt5LHucOY67m1O+SkjqePdwA5EUlibaaRBkrfsCUtNJhbesz
# 2cXfSwQAzH0clcOP9yGyshG3u3/y1YxwLEFgqrFjGESVGnZifvaAsPvoZKYz0YkH
# 4b235kOkGLimdwHhD5QMIR2yVCkliWzlDlJRR3S+Jqy2QXXeeqxfjT/JvNNBERJb
# 5RBQ6zHFynIWIgnffEx1P2PsIV/EIFFrb7GrhotPwtZFX50g/KEexcCPorF+CiaZ
# 9eRpL5gdLfXZqbId5RsCAwEAAaOCATowggE2MA8GA1UdEwEB/wQFMAMBAf8wHQYD
# VR0OBBYEFOzX44LScV1kTN8uZz/nupiuHA9PMB8GA1UdIwQYMBaAFEXroq/0ksuC
# MS1Ri6enIZ3zbcgPMA4GA1UdDwEB/wQEAwIBhjB5BggrBgEFBQcBAQRtMGswJAYI
# KwYBBQUHMAGGGGh0dHA6Ly9vY3NwLmRpZ2ljZXJ0LmNvbTBDBggrBgEFBQcwAoY3
# aHR0cDovL2NhY2VydHMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0QXNzdXJlZElEUm9v
# dENBLmNydDBFBgNVHR8EPjA8MDqgOKA2hjRodHRwOi8vY3JsMy5kaWdpY2VydC5j
# b20vRGlnaUNlcnRBc3N1cmVkSURSb290Q0EuY3JsMBEGA1UdIAQKMAgwBgYEVR0g
# ADANBgkqhkiG9w0BAQwFAAOCAQEAcKC/Q1xV5zhfoKN0Gz22Ftf3v1cHvZqsoYcs
# 7IVeqRq7IviHGmlUIu2kiHdtvRoU9BNKei8ttzjv9P+Aufih9/Jy3iS8UgPITtAq
# 3votVs/59PesMHqai7Je1M/RQ0SbQyHrlnKhSLSZy51PpwYDE3cnRNTnf+hZqPC/
# Lwum6fI0POz3A8eHqNJMQBk1RmppVLC4oVaO7KTVPeix3P0c2PR3WlxUjG/voVA9
# /HYJaISfb8rbII01YBwCA8sgsKxYoA5AY8WYIsGyWfVVa88nq2x2zm8jLfR+cWoj
# ayL/ErhULSd+2DrZ8LaHlv1b0VysGMNNn3O3AamfV6peKOK5lDGCA3YwggNyAgEB
# MHcwYzELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJbmMuMTswOQYD
# VQQDEzJEaWdpQ2VydCBUcnVzdGVkIEc0IFJTQTQwOTYgU0hBMjU2IFRpbWVTdGFt
# cGluZyBDQQIQDE1pckuU+jwqSj0pB4A9WjANBglghkgBZQMEAgEFAKCB0TAaBgkq
# hkiG9w0BCQMxDQYLKoZIhvcNAQkQAQQwHAYJKoZIhvcNAQkFMQ8XDTIzMDMwMjE1
# MzEyNVowKwYLKoZIhvcNAQkQAgwxHDAaMBgwFgQU84ciTYYzgpI1qZS8vY+W6f4c
# fHMwLwYJKoZIhvcNAQkEMSIEIBupSAj1K27RbYndeBw1TZ+ABplQjU+9mnhuylWb
# 6+/8MDcGCyqGSIb3DQEJEAIvMSgwJjAkMCIEIMf04b4yKIkgq+ImOr4axPxP5ngc
# LWTQTIB1V6Ajtbb6MA0GCSqGSIb3DQEBAQUABIICAD07cAWT6HsR1OBIpWFls5BU
# 5/SsqHiEodc1kXC8uDxpmoKK6k6BV2jwSh+FgvKZGCfpiFjwmvJw3AvKIv/yEB8y
# vDnrsZPgxzKWYgw/iQe35ZOn7rLea7+JOB4Wr8ndm+CpKr4mB4Lxvone83NR7M2V
# 9m1sF8kzidR/CXO95/zwMPl0ipzRO3cysJDjo8y0NpOdjedVojAneBu2PX6Uly0T
# KeWqKSI6TjFTJMqRJ1gLtQgiy3/9FfGtCwoathl5+HqXT1Bc6nKwDgNIrG/fMM2N
# cOjD/GMxUa8ZMO801EJmvbUdkKB5Y66O+1diVXpaVO6rZpiBNUTVTYirpaJkdgIN
# NGSgPfH0zPKY/FjmJJlRMR5ldktgkRw5vXgVyqqO0HjNf2dq0txqtwSCbXedaccT
# dnMsEhOdsmH/NoB8hQAxp3oHIjy2fZl1svpiOsW05NjsGBqPFWzcLROjMiHkAJSE
# DZReKufN+9YosFZyxFgZDKmxepSCEC1hvAV+IclDlT9erwcUaXWEyesKA5s28Ebd
# G/BcvEr6snbmGoql2Abm1B/e/Yg7KJRw9geLCG3m4axe8M+0otLlxiPo64TMf0by
# viT028O5yNqhLjReAkj1YV+uZ6GsAmJQOBBO3Wl2ZsQsDn7qBPromx8GwxKA/xbx
# UUJPe4XucKV1Et40KyLA
# SIG # End signature block
