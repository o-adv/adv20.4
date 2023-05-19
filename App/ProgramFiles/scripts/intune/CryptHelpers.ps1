function GenerateKey()
{
  try
  {
    $aes = [System.Security.Cryptography.Aes]::Create();
    $aesProvider = New-Object System.Security.Cryptography.AesCryptoServiceProvider;
    $aesProvider.GenerateKey();
    return $aesProvider.Key;
  }
  finally
  {
    if ($aesProvider -ne $null) { $aesProvider.Dispose(); }
    if ($aes -ne $null) { $aes.Dispose(); }
  }
}
function GenerateIV()
{
  try
  {
    $aes = [System.Security.Cryptography.Aes]::Create();
    return $aes.IV;
  }
  finally
  {
    if ($aes -ne $null) { $aes.Dispose(); }
  }
}
function EncryptFileWithIV(
  [parameter(Mandatory = $true)] [string] $sourceFile, 
  [parameter(Mandatory = $true)] [string] $targetFile, 
  [parameter(Mandatory = $true)] [byte[]] $encryptionKey, 
  [parameter(Mandatory = $true)] [byte[]] $hmacKey, 
  [parameter(Mandatory = $true)] [byte[]] $initializationVector)
{
  $bufferBlockSize = 1024 * 4;
  $computedMac = $null;

  try
  {
    $aes = [System.Security.Cryptography.Aes]::Create();
    $hmacSha256 = New-Object System.Security.Cryptography.HMACSHA256;
    $hmacSha256.Key = $hmacKey;
    $hmacLength = $hmacSha256.HashSize / 8;

    $buffer = New-Object byte[] $bufferBlockSize;
    $bytesRead = 0;

    $targetStream = [System.IO.File]::Open($targetFile, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read);
    $targetStream.Write($buffer, 0, $hmacLength + $initializationVector.Length);

    try
    {
      $encryptor = $aes.CreateEncryptor($encryptionKey, $initializationVector);
      $sourceStream = [System.IO.File]::Open($sourceFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read);
      $cryptoStream = New-Object System.Security.Cryptography.CryptoStream -ArgumentList @($targetStream, $encryptor, [System.Security.Cryptography.CryptoStreamMode]::Write);

      $targetStream = $null;
      while (($bytesRead = $sourceStream.Read($buffer, 0, $bufferBlockSize)) -gt 0)
      {
        $cryptoStream.Write($buffer, 0, $bytesRead);
        $cryptoStream.Flush();
      }
      $cryptoStream.FlushFinalBlock();
    }
    finally
    {
      if ($cryptoStream -ne $null) { $cryptoStream.Dispose(); }
      if ($sourceStream -ne $null) { $sourceStream.Dispose(); }
      if ($encryptor -ne $null) { $encryptor.Dispose(); }
    }

    try
    {
      $finalStream = [System.IO.File]::Open($targetFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::Read)

      $finalStream.Seek($hmacLength, [System.IO.SeekOrigin]::Begin) > $null;
      $finalStream.Write($initializationVector, 0, $initializationVector.Length);
      $finalStream.Seek($hmacLength, [System.IO.SeekOrigin]::Begin) > $null;

      $hmac = $hmacSha256.ComputeHash($finalStream);
      $computedMac = $hmac;

      $finalStream.Seek(0, [System.IO.SeekOrigin]::Begin) > $null;
      $finalStream.Write($hmac, 0, $hmac.Length);
    }
    finally
    {
      if ($finalStream -ne $null) { $finalStream.Dispose(); }
    }
  }
  finally
  {
    if ($targetStream -ne $null) { $targetStream.Dispose(); }
    if ($aes -ne $null) { $aes.Dispose(); }
  }

  return $computedMac;
}
function EncryptFile(
  [parameter(Mandatory = $true)] [string] $sourceFile, 
  [parameter(Mandatory = $true)] [string] $targetFile)
{
  $encryptionKey = GenerateKey;
  $hmacKey = GenerateKey;
  $initializationVector = GenerateIV;

  # Create the encrypted target file and compute the HMAC value.
  $mac = EncryptFileWithIV $sourceFile $targetFile $encryptionKey $hmacKey $initializationVector;

  # Compute the SHA256 hash of the source file and convert the result to bytes.
  $fileDigest = (Get-FileHash $sourceFile -Algorithm SHA256).Hash;
  $fileDigestBytes = New-Object byte[] ($fileDigest.Length / 2);
  for ($i = 0; $i -lt $fileDigest.Length; $i += 2)
  {
    $fileDigestBytes[$i / 2] = [System.Convert]::ToByte($fileDigest.Substring($i, 2), 16);
  }

  # Return an object that will serialize correctly to the file commit Graph API.
  $encryptionInfo = @{};
  $encryptionInfo.encryptionKey = [System.Convert]::ToBase64String($encryptionKey);
  $encryptionInfo.macKey = [System.Convert]::ToBase64String($hmacKey);
  $encryptionInfo.initializationVector = [System.Convert]::ToBase64String($initializationVector);
  $encryptionInfo.mac = [System.Convert]::ToBase64String($mac);
  $encryptionInfo.profileIdentifier = "ProfileVersion1";
  $encryptionInfo.fileDigest = [System.Convert]::ToBase64String($fileDigestBytes);
  $encryptionInfo.fileDigestAlgorithm = "SHA256";

  $fileEncryptionInfo = @{};
  $fileEncryptionInfo.fileEncryptionInfo = $encryptionInfo;

  return $fileEncryptionInfo;
}

function ConvertTo-Base32String([parameter(Mandatory = $true)] [byte[]] $byteArray)
{
  Set-Variable CROCKFORS_ALPHABET -Value "0123456789abcdefghjkmnpqrstvwxyz";
  Set-Variable B32_BLOCK_SIZE -Value 5;

  $originalLength = $byteArray.Length;
  $groupsCount = [Math]::floor($originalLength / $B32_BLOCK_SIZE);
  $extraBytes = $originalLength % $B32_BLOCK_SIZE;

  $buffer = $byteArray.Clone();

  for ($i = 0; $i -lt $groupsCount; $i++)
  {
    $currentGroup = $i * $B32_BLOCK_SIZE;
    $result += $CROCKFORS_ALPHABET[($buffer[$currentGroup] -shr 3)];
    $result += $CROCKFORS_ALPHABET[(($buffer[$currentGroup] -band 0x07) -shl 2) -bor ($buffer[$currentGroup + 1] -shr 6)];
    $result += $CROCKFORS_ALPHABET[(($buffer[$currentGroup + 1] -band 0x3F) -shr 1)];
    $result += $CROCKFORS_ALPHABET[(($buffer[$currentGroup + 1] -band 0x01) -shl 4) -bor ($buffer[$currentGroup + 2] -shr 4)];
    $result += $CROCKFORS_ALPHABET[(($buffer[$currentGroup + 2] -band 0x0F) -shl 1) -bor ($buffer[$currentGroup + 3] -shr 7)];
    $result += $CROCKFORS_ALPHABET[(($buffer[$currentGroup + 3] -band 0x7C) -shr 2)];
    $result += $CROCKFORS_ALPHABET[(($buffer[$currentGroup + 3] -band 0x03) -shl 3) -bor ($buffer[$currentGroup + 4] -shr 5)];
    $result += $CROCKFORS_ALPHABET[(($buffer[$currentGroup + 4] -band 0x1F))];
  }

  if ( $extraBytes -gt 0 )
  {
    $endBuffer = $byteArray[($groupsCount * $B32_BLOCK_SIZE)..($originalLength - 1)];
    $currentGroup = 0;
    $result += $CROCKFORS_ALPHABET[($endBuffer[$currentGroup] -shr 3)];
    if ( $extraBytes -gt 1 )
    {
      $result += $CROCKFORS_ALPHABET[(($endBuffer[$currentGroup] -band 0x07) -shl 2) -bor ($endBuffer[$currentGroup + 1] -shr 6)];
      $result += $CROCKFORS_ALPHABET[(($endBuffer[$currentGroup + 1] -band 0x3F) -shr 1)];
      $result += $CROCKFORS_ALPHABET[(($endBuffer[$currentGroup + 1] -band 0x01) -shl 4) -bor ($endBuffer[$currentGroup + 2] -shr 4)];
    }

    if ( $extraBytes -gt 2 )
    {
      $result += $CROCKFORS_ALPHABET[(($endBuffer[$currentGroup + 2] -band 0x0F) -shl 1) -bor ($endBuffer[$currentGroup + 3] -shr 7)];
    }

    if ( $extraBytes -gt 3)
    {
      $result += $CROCKFORS_ALPHABET[(($endBuffer[$currentGroup + 3] -band 0x7C) -shr 2)];
      $result += $CROCKFORS_ALPHABET[(($endBuffer[$currentGroup + 3] -band 0x03) -shl 3) -bor ($endBuffer[$currentGroup + 4] -shr 5)];
    }
  }

  return $result;
}


# SIG # Begin signature block
# MIIjqwYJKoZIhvcNAQcCoIIjnDCCI5gCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAZc2hARflxx4Uv
# Z3+HW9X4siiI9bbGMCvOxATHz8EW6aCCCWcwggSZMIIDgaADAgECAhBxoLc2ld2x
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
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQg5mdXloSX
# gWsqZgGp540K5cexJYZvI1ItTCErvxjNOm0wXgYKKwYBBAGCNwIBDDFQME6gJoAk
# AEEAZAB2AGEAbgBjAGUAZAAgAEkAbgBzAHQAYQBsAGwAZQByoSSAImh0dHBzOi8v
# d3d3LmFkdmFuY2VkaW5zdGFsbGVyLmNvbSAwDQYJKoZIhvcNAQEBBQAEggEAiBfH
# vf8KyqK2MgGjQ4VWJ21aAwLYpHjpYj0HiWzmNxaeUj9O5ChF0HAcZpgn5x3l52c3
# 18Az8Y0eHFHau+5HkoX52R8XK+NjGso1HCvhhbQsI8faBq66kNhE2qF0CEyzKFWx
# wg8TtTKc0dyievg3mKFG+gHb75oAdI8S6hgzpOs6l9BZPWFICdCgEwZ2MDkIy3t0
# d/AeNiHgdcUpQcIBvlR39nz9WvOOMRASqU4T4LByHEO5+/+Xz9w7/M32hnmr1A0I
# uuVpLiHUYd5wcAtOXb/xzAZNJlzDPGITgY3hHelQXDI02G7TcVzXLbM1EpHx4m8+
# dYReX0I2fS82pS7WuqGCFz4wghc6BgorBgEEAYI3AwMBMYIXKjCCFyYGCSqGSIb3
# DQEHAqCCFxcwghcTAgEDMQ8wDQYJYIZIAWUDBAIBBQAweAYLKoZIhvcNAQkQAQSg
# aQRnMGUCAQEGCWCGSAGG/WwHATAxMA0GCWCGSAFlAwQCAQUABCB1liS20buTo6Ji
# MNcZ4jBlV7Dt5E7vbJ54Gdyk2qsEZgIRAPSn4O6geC+098PF7YZzUAoYDzIwMjMw
# MzAyMTUzMDU3WqCCEwcwggbAMIIEqKADAgECAhAMTWlyS5T6PCpKPSkHgD1aMA0G
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
# MzA1N1owKwYLKoZIhvcNAQkQAgwxHDAaMBgwFgQU84ciTYYzgpI1qZS8vY+W6f4c
# fHMwLwYJKoZIhvcNAQkEMSIEIO8PQpB+7d3prlaFQmH0B9Xozib/tf9bV2Oe+cdL
# 5CqkMDcGCyqGSIb3DQEJEAIvMSgwJjAkMCIEIMf04b4yKIkgq+ImOr4axPxP5ngc
# LWTQTIB1V6Ajtbb6MA0GCSqGSIb3DQEBAQUABIICAHi4S3OBwz+7vo7bkdz+xSDi
# Ll2bZfffmn5IgVBjvUvN8+U3bmlH93UT7TIL0KJpFwCdNPCgvsv0fGf67URHcbtj
# 78JP8eYVqD4nUwKGW0+C81qg7ZqyALZgpfhNoxS+9//bOB2/8CyG7D4Axd6pd3x+
# dZS5HKNZ7p9fu3KJv6+MJ428J3/lCw0CTem2jXxz4M/dsxsYkwyy2+YpVgpBkT2e
# 9qwGFKBhXvcG3gOpjewqh9ipju6OWANEqoxyzDe86Fv2M0pV9OHI0hOHBCJ/EvCx
# rGy2LjmFLeCMr885TBEiZIr5lSPoL1Xqmbhl3HoBpPUAhGyqYXq1DtG6CtZ0gaDt
# WmaZM/d9xzQBUNnKzBk016Dusw9sT0POAVU5qQk+b7TMo1ykIHewP29X/pluN+O/
# 8ius1NJkPh8cZF8w6+ifx1/0tuUyQPdX2MT0XSgThmPSqwNeVLk5l9N258gt/g5i
# 4Tee/olb5NqTVN3wv2qWvYm8W0po0xG0WxZn3R42QWOuUoH83DvduUi+ij0Lp6gE
# EJDflY6XkYh0iX9/HOQgcgfBKPnj7CNoB3EuB324c/lKLe8DifvUNen/FpNt/GN0
# P4zoisTKPkIbvarcf9z/RAlj7RGkSg9HI2+rAI1R28qJ4tL/m+k0l2NozYL6pwOT
# yRa9zKC/caha2j97Pq3L
# SIG # End signature block
