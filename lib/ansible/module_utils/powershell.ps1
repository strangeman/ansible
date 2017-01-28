# This particular file snippet, and this file snippet only, is BSD licensed.
# Modules you write using this snippet, which is embedded dynamically by Ansible
# still belong to the author of the module, and may assign their own license
# to the complete work.
#
# Copyright (c), Michael DeHaan <michael.dehaan@gmail.com>, 2014, and others
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without modification,
# are permitted provided that the following conditions are met:
#
#    * Redistributions of source code must retain the above copyright
#      notice, this list of conditions and the following disclaimer.
#    * Redistributions in binary form must reproduce the above copyright notice,
#      this list of conditions and the following disclaimer in the documentation
#      and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
# IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
# INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
# PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE
# USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#

Set-StrictMode -Version 2.0

# Ansible v2 will insert the module arguments below as a string containing
# JSON; assign them to an environment variable and redefine $args so existing
# modules will continue to work.
$complex_args = @'
<<INCLUDE_ANSIBLE_MODULE_JSON_ARGS>>
'@
Set-Content env:MODULE_COMPLEX_ARGS -Value $complex_args
$args = @('env:MODULE_COMPLEX_ARGS')

# Helper function to set an "attribute" on a psobject instance in powershell.
# This is a convenience to make adding Members to the object easier and
# slightly more pythonic
# Example: Set-Attr $result "changed" $true
Function Set-Attr($obj, $name, $value)
{
    # If the provided $obj is undefined, define one to be nice
    If (-not $obj.GetType)
    {
        $obj = New-Object psobject
    }

    Try
    {
        $obj.$name = $value
    }
    Catch
    {
        $obj | Add-Member -Force -MemberType NoteProperty -Name $name -Value $value
    }
}

# Helper function to convert a powershell object to JSON to echo it, exiting
# the script
# Example: Exit-Json $result
Function Exit-Json($obj)
{
    # If the provided $obj is undefined, define one to be nice
    If (-not $obj.GetType)
    {
        $obj = New-Object psobject
    }

    echo $obj | ConvertTo-Json -Compress -Depth 99
    Exit
}

# Helper function to add the "msg" property and "failed" property, convert the
# powershell object to JSON and echo it, exiting the script
# Example: Fail-Json $result "This is the failure message"
Function Fail-Json($obj, $message = $null)
{
    # If we weren't given 2 args, and the only arg was a string, create a new
    # psobject and use the arg as the failure message
    If ($message -eq $null -and $obj.GetType().Name -eq "String")
    {
        $message = $obj
        $obj = New-Object psobject
    }
    # If the first args is undefined or not an object, make it an object
    ElseIf (-not $obj -or -not $obj.GetType -or $obj.GetType().Name -ne "PSCustomObject")
    {
        $obj = New-Object psobject
    }

    Set-Attr $obj "msg" $message
    Set-Attr $obj "failed" $true
    echo $obj | ConvertTo-Json -Compress -Depth 99
    Exit 1
}

Function Expand-Environment($value)
{
    [System.Environment]::ExpandEnvironmentVariables($value)
}

# Helper function to get an "attribute" from a psobject instance in powershell.
# This is a convenience to make getting Members from an object easier and
# slightly more pythonic
# Example: $attr = Get-AnsibleParam $response "code" -default "1"
#Get-AnsibleParam also supports Parameter validation to save you from coding that manually:
#Example: Get-AnsibleParam -obj $params -name "State" -default "Present" -ValidateSet "Present","Absent" -resultobj $resultobj -failifempty $true
#Note that if you use the failifempty option, you do need to specify resultobject as well.
Function Get-AnsibleParam($obj, $name, $default = $null, $resultobj = @{}, $failifempty = $false, $emptyattributefailmessage, $ValidateSet, $ValidateSetErrorMessage, $type = $null, $aliases = @())
{
    # Check if the provided Member $name or aliases exist in $obj and return it or the default.
    try {

        $found = $null
        # First try to find preferred parameter $name
        $aliases = @($name) + $aliases

        # Iterate over aliases to find acceptable Member $name
        foreach ($alias in $aliases) {
            if (Get-Member -InputObject $obj -Name $alias) {
                $found = $alias
                break
            }
        }

        if ($found -eq $null) {
            throw
        }
        $name = $found

        if ($ValidateSet) {

            if ($ValidateSet -contains ($obj.$name)) {
                $value = $obj.$name
            } else {
                if ($ValidateSetErrorMessage -eq $null) {
                    #Auto-generated error should be sufficient in most use cases
                    $ValidateSetErrorMessage = "Argument $name needs to be one of $($ValidateSet -join ",") but was $($obj.$name)."
                }
                Fail-Json -obj $resultobj -message $ValidateSetErrorMessage
            }

        } else {
            $value = $obj.$name
        }

    } catch {
        if ($failifempty -eq $false) {
            $value = $default
        } else {
            if (!$emptyattributefailmessage) {
                $emptyattributefailmessage = "Missing required argument: $name"
            }
            Fail-Json -obj $resultobj -message $emptyattributefailmessage
        }

    }

    if ($value -ne $null -and $type -eq "path") {
        # Expand environment variables on path-type (Beware: turns $null into "")
        $value = Expand-Environment($value)
    } elseif ($type -eq "bool") {
        # Convert boolean types to real Powershell booleans
        $value = $value | ConvertTo-Bool
    }

    return $value
}

#Alias Get-attr-->Get-AnsibleParam for backwards compat. Only add when needed to ease debugging of scripts
If (!(Get-Alias -Name "Get-attr" -ErrorAction SilentlyContinue))
{
    New-Alias -Name Get-attr -Value Get-AnsibleParam
}


# Helper filter/pipeline function to convert a value to boolean following current
# Ansible practices
# Example: $is_true = "true" | ConvertTo-Bool
Function ConvertTo-Bool
{
    param(
        [parameter(valuefrompipeline=$true)]
        $obj
    )

    $boolean_strings = "yes", "on", "1", "true", 1
    $obj_string = [string]$obj

    if (($obj.GetType().Name -eq "Boolean" -and $obj) -or $boolean_strings -contains $obj_string.ToLower())
    {
        return $true
    }
    Else
    {
        return $false
    }
}

# Helper function to parse Ansible JSON arguments from a "file" passed as
# the single argument to the module.
# Example: $params = Parse-Args $args
Function Parse-Args($arguments, $supports_check_mode = $false)
{
    $params = New-Object psobject
    If ($arguments.Length -gt 0)
    {
        $params = Get-Content $arguments[0] | ConvertFrom-Json
    }
    $check_mode = Get-AnsibleParam -obj $params -name "_ansible_check_mode" -type "bool" -default $false
    If ($check_mode -and -not $supports_check_mode)
    {
        Exit-Json @{
            skipped = $true
            changed = $false
            msg = "remote module does not support check mode"
        }
    }
    return $params
}

# Helper function to calculate a hash of a file in a way which powershell 3
# and above can handle:
Function Get-FileChecksum($path, $algorithm = 'sha1')
{
    If (Test-Path -PathType Leaf $path)
    {
        switch ($algorithm)
        {
            'md5' { $sp = New-Object -TypeName System.Security.Cryptography.MD5CryptoServiceProvider }
            'sha1' { $sp = New-Object -TypeName System.Security.Cryptography.SHA1CryptoServiceProvider }
            'sha256' { $sp = New-Object -TypeName System.Security.Cryptography.SHA256CryptoServiceProvider }
            'sha384' { $sp = New-Object -TypeName System.Security.Cryptography.SHA384CryptoServiceProvider }
            'sha512' { $sp = New-Object -TypeName System.Security.Cryptography.SHA512CryptoServiceProvider }
            default { Fail-Json (New-Object PSObject) "Unsupported hash algorithm supplied '$algorithm'" }
        }

        If ($PSVersionTable.PSVersion.Major -ge 4) {
            $raw_hash = Get-FileHash $path -Algorithm $algorithm
            $hash = $raw_hash.Hash.ToLower()
        } Else {
            $fp = [System.IO.File]::Open($path, [System.IO.Filemode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite);
            $hash = [System.BitConverter]::ToString($sp.ComputeHash($fp)).Replace("-", "").ToLower();
            $fp.Dispose();
        }
    }
    ElseIf (Test-Path -PathType Container $path)
    {
        $hash = "3";
    }
    Else
    {
        $hash = "1";
    }
    return $hash
}

Function Get-PendingRebootStatus
{
    # Check if reboot is required, if so notify CA. The MSFT_ServerManagerTasks provider is missing on client SKUs
    #Function returns true if computer has a pending reboot
    $featureData = invoke-wmimethod -EA Ignore -Name GetServerFeature -namespace root\microsoft\windows\servermanager -Class MSFT_ServerManagerTasks
    $regData = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" "PendingFileRenameOperations" -EA Ignore
    $CBSRebootStatus = Get-ChildItem "HKLM:\\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing"  -ErrorAction SilentlyContinue| where {$_.PSChildName -eq "RebootPending"}
    if(($featureData -and $featureData.RequiresReboot) -or $regData -or $CBSRebootStatus)
    {
        return $True
    }
    else
    {
        return $False
    }
}