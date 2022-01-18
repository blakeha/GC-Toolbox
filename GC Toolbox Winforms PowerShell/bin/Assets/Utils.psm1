$ErrorActionPreference = 'stop'
$FILES_PATH = (Join-Path $PSScriptRoot 'Files')
$PROJECT_FILES_PATH = (Join-Path $FILES_PATH 'Project.json')
$OUTPUT_DIR = (Join-Path $PSScriptRoot "Output")
$INPUT_DIR = (Join-Path $PSScriptRoot "Files")

#region Project File Management
class ProjectParam {
    $value
    [string]$description
}

function Get-ProjectConfig
{
    <#
        .SYNOPSIS
            Get project config from directory.
        
        .DESCRIPTION
            Helper function to get project config (Project.json) from project directory. 
            Will initialize some values if not present.
    #>
    param(
        $ProjectDir = $FILES_PATH
    )
    
    if (!$ProjectDir)
    {
        $ProjectDir = $PSScriptRoot
    }

    $Config = @{}
    (Get-Content -Path ($PROJECT_FILES_PATH) -Raw | ConvertFrom-Json).psobject.properties | ForEach-Object { $Config[$_.Name] = $_.Value }
    
    $DefaultValues = @{
        Name = ''
        PackageIdPrefix = ''

    }

    foreach ($Key in $DefaultValues.Keys)
    {
        if (!$Config.ContainsKey($Key) -or $Overwrite)
        {
            $Config[$Key] = $DefaultValues[$Key]
        }
    }
    
    return $Config
}

function Set-ProjectConfigPrompt {
    [Hashtable]$Config = Get-ProjectConfig

    foreach ($item in $Config.Keys) {
        Write-Output ("Parameter: " + $item)
        Write-Output ("Description: " + $Config[$item].description)
        Write-Output ("Value: " + $Config[$item].value)
        $Config[$item].value = Read-Host "New value"   
    }
    $Config | ConvertTo-Json -depth 100 | Out-File -FilePath $PROJECT_FILES_PATH -Encoding ASCII
    pause
}

#endregion



function ConvertTo-SqlObject($ConnectionString)
{
    <#
        .SYNOPSIS
            Convert connection string to object with easy to use properties.
    #>
    $Builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder($ConnectionString)
    $Split = $Builder.DataSource.Split('\')
    $InstanceName = ''
    if ($Split.Length -gt 1)
    {
        $InstanceName = $Split[1]
    }

    $NetworkProtocol = GetNetworkProtocol -Value $Builder['Network\ Library']

    return @{
        'Database' = $Builder.InitialCatalog
        'ServerInstance' = $Builder.DataSource
        'ServerInstanceName' = $InstanceName
        'ServerName' = $Split[0]
        'ConnectionString' = $ConnectionString
        'NetworkProtocol' = $NetworkProtocol
        'NetworkLibrary' = $Builder.NetworkLibrary
    }
}

function GetNetworkProtocol($Value)
{
    <#
        .SYNOPSIS
            Mapper function.
    #>
    if (!$Value)
    {
        return 'Default'
    }
    if ($Value -match 'dbnmpntw')
    {
        return 'NamedPipes'
    }
    elseif ($Value -match 'dbmssocn')
    {
        return 'Sockets'
    }
}

function Update-BcVersionsIfNotSetInProjectFile
{
    <#
        .SYNOPSIS
            Update Business Central versions if default, if not set in project file.

        .DESCRIPTION
            If the platform and application versions (BcPlatformVersion and BcAppVersion)
            have not been set in the project file, this function will attempt
            to set appropriate version from specified LS Central version (LsCentralVerion).
    #>
    param(
        $ProjectDir = $PSScriptRoot
    )
    $Config = Get-ProjectConfig
    try {
        Import-Module GoCurrent
        $Packages = @(
            @{ Id = 'map/ls-central-to-bc'; Version = $Config["LsCentralVersion"].value}
            @{ Id = 'bc-system-symbols'; Version = ''}
            @{ Id = 'bc-base-application'; Version = ''}
        )
            
            
        $ResolvedPackages = $Packages | Get-GocUpdates
        $Config["BcPlatformVersion"].value = ($ResolvedPackages | where-Object { $_.Id -eq 'bc-server'}).Version
        $Config["BcAppVersion"].value = ($ResolvedPackages | where-Object { $_.Id -eq 'bc-base-application'}).Version
        Write-Output $Config["BcPlatformVersion"].value
            
        $Config | ConvertTo-Json -depth 100 | Out-File -FilePath $PROJECT_FILES_PATH -Encoding ASCII 
    }
    catch {
        Write-Warning "Error thrown was: $_"
        throw "Could not resolve Business Central version(s), please update Project.json manually with desired Business Central version(s)."
    }
}

function Get-Menu {
    [CmdletBinding()]
    [OutputType([string])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String[]]$MenuItems,
        [Parameter(Mandatory = $true)]
        [String]$MenuPrompt
    )
    # store initial cursor position
    $cursorPosition = $host.UI.RawUI.CursorPosition
    $pos = 0 # current item selection
    
    #==============
    # 1. Draw menu
    #==============
    function Write-Menu
    {
        param (
            [int]$selectedItemIndex
        )
        # reset the cursor position
        $Host.UI.RawUI.CursorPosition = $cursorPosition
        # Padding the menu prompt to center it
        $prompt = $MenuPrompt
        $maxLineLength = ($MenuItems | Measure-Object -Property Length -Maximum).Maximum + 4
        while ($prompt.Length -lt $maxLineLength+4)
        {
            $prompt = " $prompt "
        }
        Write-Host $prompt -ForegroundColor Green
        # Write the menu lines
        for ($i = 0; $i -lt $MenuItems.Count; $i++)
        {
            $line = "    $($MenuItems[$i])" + (" " * ($maxLineLength - $MenuItems[$i].Length))
            if ($selectedItemIndex -eq $i)
            {
                Write-Host $line -ForegroundColor Blue -BackgroundColor Gray
            }
            else
            {
                Write-Host $line
            }
        }
    }
    
    Write-Menu -selectedItemIndex $pos
    $key = $null
    while ($key -ne 13)
    {
        #============================
        # 2. Read the keyboard input
        #============================
        $press = $host.ui.rawui.readkey("NoEcho,IncludeKeyDown")
        $key = $press.virtualkeycode
        if ($key -eq 38)
        {
            $pos--
        }
        if ($key -eq 40)
        {
            $pos++
        }
        #handle out of bound selection cases
        if ($pos -lt 0) { $pos = 0 }
        if ($pos -eq $MenuItems.count) { $pos = $MenuItems.count - 1 }
        
        #==============
        # 1. Draw menu
        #==============
        Write-Menu -selectedItemIndex $pos
    }
    
    return $MenuItems[$pos]  
}


function Get-FileName($initialDirectory)
{
    [System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") | Out-Null
    
    $OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $OpenFileDialog.initialDirectory = $initialDirectory
    $OpenFileDialog.ShowDialog() | Out-Null
    $OpenFileDialog.filename
}

function Get-Directory($initialDirectory)
{
    [System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms")|Out-Null
    
    $OpenFileDialog = New-Object System.Windows.Forms.FolderBrowserDialog
    
    $OpenFileDialog.SelectedPath = $initialDirectory
    $OpenFileDialog.Description = "Please select a directory"
    $OpenFileDialog.ShowDialog() | Out-Null
    return $OpenFileDialog.SelectedPath
}

function Test-Module-Availability($moduleName)
{
	if (Get-Module -ListAvailable -Name $moduleName)
	{
		return $true;
	}
	return $false;
}

