$ErrorActionPreference = "Stop"

# Import helper scripts
. $PSScriptRoot\RestHelpers.ps1
. $PSScriptRoot\CryptHelpers.ps1
. $PSScriptRoot\Authenticate.ps1
. $PSScriptRoot\AzureStorageHelpers.ps1

function Upload-Msi
{
  [cmdletbinding()]
  param
  (
    [parameter(Mandatory = $true)]
    [ValidateNotNull()]
    [string]$AuthTokenJson,

    [parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SourceFile,

    [parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Publisher,

    [parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Description,

    [parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Name,

    [parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [version]$Version,

    [parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [guid]$ProductCode,

    [parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [guid]$UpgradeCode,

    [parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Language
  )
  try 
  {
    $AuthToken = @{ }
    (ConvertFrom-Json $AuthTokenJson).psobject.properties | ForEach-Object { $AuthToken[$_.Name] = $_.Value }

    $LOBType = "microsoft.graph.windowsMobileMSI"
    # Create a new MSI LOB app
    $FileName = [System.IO.Path]::GetFileName("$SourceFile")
    $mobileAppBody = GetMSIAppBody -displayName "$Name" -publisher "$Publisher" -description "$Description" -filename "$FileName" -identityVersion "$Version" -ProductCode "$ProductCode"
    $mobileApp = MakePostRequest "mobileApps" ($mobileAppBody | ConvertTo-Json) $AuthToken

    # Get the content version for the new app (this will always be 1 until the new app is committed).
    $appId = $mobileApp.id;
    $contentVersionUri = "mobileApps/$appId/$LOBType/contentVersions";
    $contentVersion = MakePostRequest $contentVersionUri "{}" $AuthToken;

    # Encrypt file and Get File Information
    $tempFile = [System.IO.Path]::GetDirectoryName("$SourceFile") + "\" + [System.IO.Path]::GetFileNameWithoutExtension("$SourceFile") + "_temp.bin"
    $encryptionInfo = EncryptFile $sourceFile $tempFile;
    $Size = (Get-Item "$sourceFile").Length
    $EncrySize = (Get-Item "$tempFile").Length

    # Create the manifest file used to install the application on the device
    $manifestXML = GetMsiInstallationManifest($UpgradeCode)
    $encodedManifestBytes = [System.Text.Encoding]::ASCII.GetBytes($manifestXML)
    $encodedManifestXML = [Convert]::ToBase64String($encodedManifestBytes)

    # Create a new file entry in Azure for the upload
    $contentVersionId = $contentVersion.id;
    $fileBody = GetAppFileBody "$FileName" $Size $EncrySize "$encodedManifestXML";
    $filesUri = "mobileApps/$appId/$LOBType/contentVersions/$contentVersionId/files";
    $file = MakePostRequest $filesUri ($fileBody | ConvertTo-Json) $AuthToken;
    # Wait for the file entry URI to be created
    $fileId = $file.id;
    $fileUri = "mobileApps/$appId/$LOBType/contentVersions/$contentVersionId/files/$fileId";
    $file = WaitForFileProcessing $fileUri "AzureStorageUriRequest" $AuthToken;

    # Uploade file to Azure Storage
    UploadFileToAzureStorage $file.azureStorageUri $tempFile;

    # Commit the file into Azure Storage and wait.
    $commitFileUri = "mobileApps/$appId/$LOBType/contentVersions/$contentVersionId/files/$fileId/commit";
    MakePostRequest $commitFileUri ($encryptionInfo | ConvertTo-Json) $AuthToken;
    $file = WaitForFileProcessing $fileUri "CommitFile" $AuthToken;

    # Commit the app.
    $commitAppUri = "mobileApps/$appId";
    $commitAppBody = GetAppCommitBody $contentVersionId $LOBType;
    MakePatchRequest $commitAppUri ($commitAppBody | ConvertTo-Json) $AuthToken;

    # Cleanup. Remove temp copy of MSI file.
    Remove-Item -Path "$tempFile" -Force

    # Sleep for 30 seconds to allow patch completion
    Start-Sleep 30
  }
  catch 
  {
    write-host  $_.Exception.Message
    exit(1);  
  }
}

function GetMSIAppBody(
  [parameter(Mandatory = $true)] [string] $displayName, 
  [parameter(Mandatory = $true)] [string] $publisher, 
  [parameter(Mandatory = $true)] [string] $description, 
  [parameter(Mandatory = $true)] [string] $filename, 
  [parameter(Mandatory = $true)] [string] $identityVersion, 
  [parameter(Mandatory = $true)] [string] $ProductCode)
{
  $body = @{ "@odata.type" = "#microsoft.graph.windowsMobileMSI" };
  $body.displayName = $displayName;
  $body.publisher = $publisher;
  $body.description = $description;
  $body.fileName = $filename;
  $body.identityVersion = $identityVersion;
  $body.informationUrl = $null;
  $body.isFeatured = $false;
  $body.privacyInformationUrl = $null;
  $body.developer = "";
  $body.notes = "";
  $body.owner = "";
  $body.productCode = "$ProductCode";
  $body.productVersion = "$identityVersion";

  return $body;
}
function GetMsiInstallationManifest([parameter(Mandatory = $true)] [string] $UpgradeCode)
{
  [xml]$manifestXML = '<MobileMsiData
  MsiExecutionContext="Any"
  MsiRequiresReboot="false"
  MsiUpgradeCode=""
  MsiIsMachineInstall="true"
  MsiIsUserInstall="false"
  MsiIncludesServices="false"
  MsiContainsSystemRegistryKeys="false"
  MsiContainsSystemFolders="false"></MobileMsiData>'
  $manifestXML.MobileMsiData.MsiUpgradeCode = "$UpgradeCode"
  return $manifestXML.OuterXml.ToString()
}


# SIG # Begin signature block
# MIIjqwYJKoZIhvcNAQcCoIIjnDCCI5gCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDrEQtcpbic8s1G
# 3IbZl3HNr86WFRoKcy7NnIEL/cRo36CCCWcwggSZMIIDgaADAgECAhBxoLc2ld2x
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
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgVmS6hIKl
# YO2728osOE2YX6QdUw8AKsa53abmYiCPUoswXgYKKwYBBAGCNwIBDDFQME6gJoAk
# AEEAZAB2AGEAbgBjAGUAZAAgAEkAbgBzAHQAYQBsAGwAZQByoSSAImh0dHBzOi8v
# d3d3LmFkdmFuY2VkaW5zdGFsbGVyLmNvbSAwDQYJKoZIhvcNAQEBBQAEggEAUD+O
# RyjRgt4lSZylGQDe6vuLwabQwzSL8OHn4m/ODTw2bmWsYmlKfwtKa2oc6wznMXq7
# Vl9ivobHJ2wVlqOR7THbqXcPXzNZkgEo4ZzSkpqLzHcFayxuswLj89yXPrqoh8f2
# BP9h/CZKrF3YAzAt5N5Vb3GfwgQirDfeIk0d9mq8bf0Sw08NWfsgl4uTN8mVULWr
# p7L7un5BWPsxzEt63aVqnJdclMbLvbmLUv5kVKm3jW3mP2ROyTRNrmAKCuiK/S59
# gwgnsRJ+ULKBjilUN0aTz3TdrrI9m8DK+1At2gMw9nxifMqcC5X7xASdc6lDrhqX
# GtCyFKliDeSrbW4jsKGCFz4wghc6BgorBgEEAYI3AwMBMYIXKjCCFyYGCSqGSIb3
# DQEHAqCCFxcwghcTAgEDMQ8wDQYJYIZIAWUDBAIBBQAweAYLKoZIhvcNAQkQAQSg
# aQRnMGUCAQEGCWCGSAGG/WwHATAxMA0GCWCGSAFlAwQCAQUABCC4yxupEkk36Hah
# oWO/ZBpLKjqwQ3LVBgRbegrJNQMBsgIRAMcyGSWq8xVxb7bDevUvCjUYDzIwMjMw
# MzAyMTUzMDUxWqCCEwcwggbAMIIEqKADAgECAhAMTWlyS5T6PCpKPSkHgD1aMA0G
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
# MzA1MVowKwYLKoZIhvcNAQkQAgwxHDAaMBgwFgQU84ciTYYzgpI1qZS8vY+W6f4c
# fHMwLwYJKoZIhvcNAQkEMSIEIN4JBLDeFWLTLCYXlDIQT+EDAzZLkNxq+5kzjJ8A
# 4fnDMDcGCyqGSIb3DQEJEAIvMSgwJjAkMCIEIMf04b4yKIkgq+ImOr4axPxP5ngc
# LWTQTIB1V6Ajtbb6MA0GCSqGSIb3DQEBAQUABIICAAr88bmLLeseg7VTmAfMFMJk
# 1voL9gPbqofrwzhZMBMn07p9agvH9QgtCe/EDb6OVq/gI3W5ctf37fLotADX6j+b
# jwiTmFkJhth19hKq87QDqy3qlzvsY7FsKrmKHclH58CssfiWxaTbTChsa7dy8pKL
# Yfz8mxTvmO9G0xOxB2F3KaqhcAOpDxPLiHcaclzq+IrX+SLAPd5p1Sf+ZZ63ZIt2
# MQxXii826Cqo6eh8jrEIzkyLdpZ+HnXd2w9ucXmqZMZLra3TsnL6FTRPdhbrDAne
# yijX/jmsaN5pT5wAHNWuS+HrvEr07g8G9PeS5mjv4M4c/coraA069gwx5y1sNn3k
# BvaI2eAOJwzenm3FKoJc5ptBbX0dH+rTxY8bKPkP8YHY2zKbwCWKSazazBMx4b9b
# 6VxCrjv8tVe+i0p7QOeqXvWmE+24Ww/C1FbF+w0A/6WQpWVlhmi8cOyyqBcBIaYG
# Vkygoycu5bUJ7UK47UDwMt6/Nu3sb0r5Bdk3pZLSr6hMWKV4tB+4iNErzxQ4GE2s
# 33a7dCMGQ27psO5WyqOHJYPtgsZlZ6HUH5UfVzDwESWBpeWC/QB5m22hwta/Nix0
# uzy6M6sAECYuGcmBz5WyUSfLXZC6m6cqsOkyWNAuCyD0H/inacYVeiw7D9jbK7Fs
# Cm1y/7desV+MT65nA7JQ
# SIG # End signature block
