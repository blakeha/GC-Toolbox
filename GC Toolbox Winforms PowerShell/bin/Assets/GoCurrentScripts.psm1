<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2021 v5.8.196
	 Created on:   	1/7/2022 9:41 PM
	 Created by:   	blakeha
	 Organization: 	
	 Filename:     	GoCurrentScriptsModule.ps1
	===========================================================================
	.DESCRIPTION
		A description of the file.
#>

#region Classes

class Package {
	[string]$Id;
	[string]$Version;
	[string]$Name;
	[string]$Path;
	[string]$OutputDir;
	[Package[]]$Dependencies;
	
	
	
	static [Package]Create(
		[string]$Id,
		[string]$Version,
		[string]$Name,
		[string]$Path,
		[string]$OutputDir,
		[Package[]]$Dependencies)
	{
		$Package = [Package]::New();
		
		$Package.Id = $Id;
		$Package.Version = $Version;
		$Package.Name = $Name;
		$Package.Path = $Path;
		$Package.OutputDir = $OutputDir;
		$Package.Dependencies = $Dependencies;
		
		return $Package;
	}
	
	static [Package]Create(
		[string]$Id,
		[string]$Version) {
		
		return [Package]::Create($Id, $Version, $null, $null, $null, $null);
	}
	
}

#endregion Classes

#region Functions

function Get-Ls-Packages {
	
	param
	(
		[string][Parameter(HelpMessage = "Source Go Current Server (default is gocurrent.lsretail.com)")]
		$PackageSourceServer = "gocurrent.lsretail.com",
		[string][Parameter(HelpMessage = "Source Go Current Port (default is 443)")]
		$PackageSourcePort = "443",
		[boolean][Parameter(HelpMessage = "Does the source server use SSL")]
		$PackageSourceUseSSL = $true,
		[string][Parameter(HelpMessage = "This is the domain of the package source (default is lsretail.com)")]
		$PackageSourceIdentity = "lsretail.com",
		[string][Parameter(Mandatory, HelpMessage = "LS Central Version")]
		$LsCentralVersion,
		[string][Parameter(HelpMessage = "Business Central Platform Version")]
		$BcPlatformVersion,
		[string][Parameter(HelpMessage = "Business Central App Version")]
		$BcAppVersion,
		[string][Parameter(HelpMessage = "Business Central Localization")]
		$Localization,
		[boolean][Parameter(HelpMessage = "Use locale for localization instead of ls-central-app-localization-runtime")]
		$Locale = $false,
		[System.Collections.ArrayList][Parameter(HelpMessage = "Use locale for localization instead of ls-central-app-localization-runtime")]
		$Packages
	)
	
	Import-Module GoCurrentServer
	
	if (!($Packages) -and !($BcAppVersion) -and !($BcPlatformVersion))
	{
		$Packages = @(
			@{ Id = 'map/ls-central-to-bc'; Version = $LsCentralVersion }
		)
		$Packages | Copy-GocsPackagesFromServer -SourceServer $PackageSourceServer -SourcePort $PackageSourcePort -SourceUseSsl:$PackageSourceUseSSL -SourceIdentity $PackageSourceIdentity -Server $null -Port $null
		
		try
		{
			$BcPackages = Resolve-GocsDependencies -Id 'map/ls-central-to-bc' -Version "$LsCentralVersion"
			$BcPlatformVersion = ($BcPackages | Where-Object { $_.id -eq 'bc-server' }).Version
			$BcAppVersion = ($BcPackages | Where-Object { $_.id -eq 'bc-base-application' }).Version
		}
		catch
		{
			Write-Output "Error resolving ls-central-to-bc version. Please manually provide versions for BC Platform and App."
			return
		}
	}
	
	#if no provided packages, use default
	if ($Packages.Count -eq 0)
	{
		$Packages = @(
			@{ Id = 'sql-server-express'; Version = '^' }
			@{ Id = "bc-system-symbols"; Version = $BcPlatformVersion }
			@{ Id = "bc-db-components"; Version = $BcPlatformVersion }
			@{ Id = "bc-web-client"; Version = $BcPlatformVersion }
			@{ Id = "bc-system-application-runtime"; Version = $BcAppVersion }
			@{ Id = "bc-base-application-runtime"; Version = $BcAppVersion }
			
			@{ Id = "bc-application-runtime"; Version = $BcAppVersion }
			@{ Id = 'ls-central-demo-database'; Version = $LsCentralVersion }
			@{ Id = 'ls-central-toolbox-server'; Version = $LsCentralVersion }
			$(if ($Localization)
				{
					if ($Locale)
					{
						@{ Id = "locale/ls-central-$($Localization)-runtime"; Version = $LsCentralVersion }
					}
					else
					{
						@{ Id = "ls-central-app-$($Localization)-runtime"; Version = $LsCentralVersion }
					}
				}
				@{ Id = 'ls-central-app-runtime'; Version = $LsCentralVersion })
			@{ Id = 'ls-dd-server-addin'; Version = '^ >=3.0 <4.0' }
			@{ Id = 'ls-dd-service'; Version = '^ >=3.0 <4.0' }
			@{ Id = 'ls-hardware-station'; Version = $LsCentralVersion }
		)
	}
	
	$Packages | Copy-GocsPackagesFromServer -SourceServer $PackageSourceServer -SourcePort $PackageSourcePort -SourceUseSsl:$PackageSourceUseSSL -SourceIdentity $PackageSourceIdentity -Server $null -Port $null
	
	$Packages
}

function Get-Package-Tools
{
	Install-GocPackage -Id 'ls-package-tools'
}

function New-App-Package
{
	Param (
		[string][Parameter(Mandatory, HelpMessage = "Package prefix. Used to relate package with other packages of the same prefix.")]
		$PackageId,
		[string][Parameter(Mandatory, HelpMessage = "Human readable form of the package id.")]
		$PackageName,
		[string][Parameter(ParameterSetName = 'Paths', Mandatory, HelpMessage = "Path to the location the created package should be stored at.")]
		$PackageOutputPath,
		[string][Parameter(Mandatory, HelpMessage = "LS Central Version")]
		$LsCentralVersion,
		[string][Parameter(HelpMessage = "Business Central Platform Version")]
		$BcPlatformVersion,
		[string][Parameter(HelpMessage = "Business Central App Version")]
		$BcAppVersion,
		[string][Parameter(Mandatory, HelpMessage = "Business Central Localization")]
		$Version,
		[switch][Parameter(HelpMessage = "Runs the command and outputs what would happen without making any changes.")]
		$WhatIf,
		[switch][Parameter(ParameterSetName = 'Dialogs', HelpMessage = "Use dialogs where possible.")]
		$Dialogs,
		[string][Parameter(Mandatory, HelpMessage = "Path to the location of the App file.")]
		$PackageDataPath,
		[System.Collections.ArrayList][Parameter(HelpMessage = "All package dependencies that should be included with this app package")]
		$Dependencies
	)
	
	
	$ErrorActionPreference = 'stop'
	
	Import-Module LsPackageTools\AppPackageCreator
	Import-Module GoCurrentServer
	Import-Module (Join-Path $PSScriptRoot 'Utils.psm1')
	
	$Package = @{
		Id = "$($PackageId)"
		Name = "$PackageName"
		Version = $Version
		Path = $PackageDataPath
		OutputDir = $PackageOutputPath
		Dependencies = $null
	}
	
	if (!($Dependencies))
	{
		$Package.Dependencies.Add(@{ Id = 'bc-system-symbols'; Version = $BcPlatformVersion})
	}
	else
	{
		$Package.Dependencies = [System.Collections.ArrayList]::new();
		$Package.Dependencies.AddRange($Dependencies);
	}
	
	$Package = New-AppPackage @Package -Force:$Force
	$Package | Import-GocsPackage -Server $Server -Port $Port -Force:$Force
}

function New-Bundle-Package {
	[CmdletBinding(DefaultParameterSetName = 'Paths')]
	param (
		[string][Parameter(Mandatory, HelpMessage = "Package prefix. Used to relate package with other packages of the same prefix.")]
		$PackagePrefix,
		[string][Parameter(Mandatory, HelpMessage = "Human readable form of the package id.")]
		$PackageName,
		[string][Parameter(ParameterSetName = 'Paths', Mandatory, HelpMessage = "Path to the location the created package should be stored at.")]
		$PackageOutputPath,
		[string][Parameter(Mandatory, HelpMessage = "LS Central Version")]
		$LsCentralVersion,
		[string][Parameter(HelpMessage = "Business Central Platform Version")]
		$BcPlatformVersion,
		[string][Parameter(HelpMessage = "Business Central App Version")]
		$BcAppVersion,
		[string][Parameter(HelpMessage = "Business Central Localization")]
		$Localization,
		[string][Parameter(Mandatory, HelpMessage = "Business Central Localization")]
		$Version = "1.0.0",
		[switch][Parameter(HelpMessage = "Runs the command and outputs what would happen without making any changes.")]
		$WhatIf,
		[switch][Parameter(ParameterSetName = 'Dialogs', HelpMessage = "Use dialogs where possible.")]
		$Dialogs,
		[switch][Parameter(HelpMessage = "Include license package in bundle.")]
		$WithLicense,
		[switch][Parameter(HelpMessage = "Include database package in bundle.")]
		$WithDatabase,
		[string][Parameter(HelpMessage = "Include database package in bundle.")]
		$DatabasePackageId,
		[string][Parameter(HelpMessage = "Include database package in bundle.")]
		$DatabasePackageVersion = "^-",
		[string][Parameter(Mandatory, HelpMessage = "Bundle is of type (NAS, HO, POS)")]
		$Type
		
	)
	
	function GetPOSDepend
	{
		$dependencies = @(
			@{ Id = 'sql-server-express'; 'Version' = "^-"; 'Optional' = $True }
			
			$(
				if ($WithDatabase)
				{
					if ($DatabasePackageId)
					{
						@{ Id = $DatabasePackageId; 'Version' = $DatabasePackageVersion }
					}
					else
					{
						if ($Localization)
						{
							@{ Id = "$($PackagePrefix)-$($Localization)-database"; Version = $DatabasePackageVersion }
						}
						else
						{
							@{ Id = "$($PackagePrefix)-database"; Version = $DatabasePackageVersion }
						}
					}
				}
			)
			
			$(GetRootDepend)
			
			
			@{ Id = 'ls-central-toolbox-server'; 'Version' = $LsCentralVersion }
			@{ Id = 'ls-dd-server-addin'; 'Version' = "^ >=3.0 <4.0" }
			
			$(if ($WithLicense)
				{
					if ($Localization)
					{
						@{ Id = "$($PackagePrefix)-$($Localization)-license"; 'Version' = "^" }
					}
					else
					{
						@{ Id = "$($PackagePrefix)-license"; 'Version' = "^" }
					}
					
				})
			
			@{ Id = 'ls-hardware-station'; Version = $LsCentralVersion }
		)
		return $dependencies;
	}
	
	function GetHODepend
	{
		$dependencies = @(
			$(
				if ($WithDatabase)
				{
					if ($DatabasePackageId)
					{
						@{ Id = $DatabasePackageId; 'Version' = $DatabasePackageVersion }
					}
					else
					{
						if ($Localization)
						{
							@{ Id = "$($PackagePrefix)-$($Localization)-database"; Version = $DatabasePackageVersion }
						}
						else
						{
							@{ Id = "$($PackagePrefix)-database"; Version = $DatabasePackageVersion }
						}
					}
				}
			)
			
			$(GetRootDepend)
			
			@{ Id = 'ls-central-toolbox-server'; Version = $LsCentralVersion }
			@{ Id = 'ls-dd-server-addin'; Version = "^ >=3.0 <4.0" }
			
			
		)
		
		return $dependencies;
	}
	
	function GetNASDepend
	{
		$dependencies = @(
			@{ Id = 'bc-server'; Version = $BcPlatformVersion }
			
			@{ Id = 'ls-central-toolbox-server'; Version = $LsCentralVersion }
			@{ Id = 'ls-dd-server-addin'; Version = "^ >=3.0 <4.0" }
			
			
		)
		
		return $dependencies;
	}
	
	function GetRootDepend
	{
		$dependencies = @(
			@{ Id = "bc-web-client"; Version = $BcPlatformVersion }
			@{ Id = "bc-system-symbols"; Version = $BcPlatformVersion }
			@{ Id = "bc-system-application-runtime"; Version = $BcAppVersion }
			@{ Id = "bc-base-application-runtime"; Version = $BcAppVersion }
			
			$(if ($Localization)
				{
					if ($Locale)
					{
						@{ Id = "locale/ls-central-$($Localization)-runtime"; Version = $LsCentralVersion }
						@{ Id = 'ls-central-app-runtime'; Version = $LsCentralVersion }
					}
					else
					{
						@{ Id = "ls-central-app-$($Localization)-runtime"; Version = $LsCentralVersion }
					}
				}
				else
				{
					@{ Id = 'ls-central-app-runtime'; Version = $LsCentralVersion }
				})
		);
		return $dependencies;
	}
	
	$ErrorActionPreference = 'stop'
	
	if (!(Get-Module -ListAvailable -Name GoCurrentServer))
	{
		Import-Module GoCurrentServer
	}
	if (!(Get-Module -ListAvailable -Name Utils))
	{
		Import-Module (Join-path $(Split-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) -Parent) 'Utils.psm1') -Force
	}
	
	
	if ($Dialogs)
	{
		Write-Output "Please select the package output directory with the dialog."
		$PackageOutputPath = Get-Directory $PSScriptRoot
	}
	
	
	try
	{
		$BcPackages = Resolve-GocsDependencies -Id 'map/ls-central-to-bc' -Version "$LsCentralVersion"
		$BcPlatformVersion = ($BcPackages | Where-Object { $_.id -eq 'bc-server' }).Version
		$BcAppVersion = ($BcPackages | Where-Object { $_.id -eq 'bc-base-application' }).Version
	}
	catch
	{
		Write-Output "Error resolving ls-central-to-bc version. Please manually provide versions for BC Platform and App."
		return
	}
	
	
	
	
	switch ($Type)
	{
		"NAS" {
			$Dependencies = GetNASDepend;
		}
		"HO" {
			$Dependencies = GetHODepend;
		}
		"POS" {
			$Dependencies = GetPOSDepend;
		}
		Default {
			Write-Output "Invalid type provided. "
			return;
		}
	}
	
	
	$packageID
	if ($Localization)
	{
		$packageID = "bundle/$($PackagePrefix)-$($Localization)-$($Type.ToLower())"
	}
	else
	{
		$packageID = "bundle/$($PackagePrefix)-$($Type.ToLower())"
	}
	
	$Bundle = @{
		Id		     = $packageID
		Version	     = $Version
		Name		 = $PackageName
		Instance	 = $true
		Dependencies = $Dependencies
		OutputDir    = $PackageOutputPath
	}
	
	
	if ($WhatIf)
	{
		Write-Output "Bundle"
		Write-Output $Bundle
		Write-Output "Dependencies"
		Write-Output $Dependencies
		pause
		return
	}
	
	$Package = New-GocsPackage @Bundle -Force:$Force | Import-GocsPackage
	$Package
}

function New-Database-Package
{
	[CmdletBinding(DefaultParameterSetName = 'Paths')]
	param (
		[switch][Parameter(ParameterSetName = 'Dialogs', HelpMessage = "Use dialogs where possible.")]
		$Dialogs,
		[string][Parameter(Mandatory, HelpMessage = "Package prefix. Used to relate package with other packages of the same prefix.")]
		$PackagePrefix,
		[string][Parameter(Mandatory, HelpMessage = "Human readable form of the package id.")]
		$PackageName,
		[String][Parameter(ParameterSetName = 'Paths', Mandatory, HelpMessage = "Path to the location the created package should be stored at.")]
		$PackageOutputPath = $OUTPUT_DIR,
		[string][Parameter(Mandatory, HelpMessage = "LS Central Version")]
		$LsCentralVersion,
		[string][Parameter(HelpMessage = "Business Central Platform Version")]
		$BcPlatformVersion,
		[string][Parameter(HelpMessage = "Business Central App Version")]
		$BcAppVersion,
		[string][Parameter(HelpMessage = "Business Central Localization")]
		$Localization,
		[string][Parameter(Mandatory, HelpMessage = "Business Central Localization")]
		$Version = "1.0.0",
		[String][Parameter(ParameterSetName = 'Paths', Mandatory, HelpMessage = "Path to the database backup to use in the package.")]
		$DatabaseBackupPath,
		[switch][Parameter(HelpMessage = "Runs the command and outputs what would happen without making any changes.")]
		$WhatIf
		
	)
	
	$ErrorActionPreference = 'stop'
	
	Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
	
	Import-Module GoCurrent
	
	Install-GocPackage -Id 'ls-package-tools'
	
	Import-Module LsPackageTools\DatabasePackageCreator
	Import-Module GoCurrentServer
	Import-Module (Join-path $(Split-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) -Parent) 'Utils.psm1') -Force
	
	$BcPackages = Resolve-GocsDependencies -Id 'map/ls-central-to-bc' -Version $LsCentralVersion
	$BcPlatformVersion = ($BcPackages | Where-Object { $_.id -eq 'bc-server' }).Version
	$BcAppVersion = ($BcPackages | Where-Object { $_.id -eq 'bc-base-application' }).Version
	
	
	
	if ($Dialogs)
	{
		Write-Output "Please select the database backup file with the dialog."
		$DatabaseBackupPath = Get-FileName $PSScriptRoot
		Write-Output "Please select the package output directory with the dialog."
		$PackageOutputPath = Get-Directory $PSScriptRoot
	}
	
	$packageID
	if ($Localization)
	{
		$packageID = "$($PackagePrefix)-$($Localization)-database"
	}
	else
	{
		$packageID = "$($PackagePrefix)-database"
	}
	
	
	$Arguments = @{
		Id   = $packageID
		Name = "$($PackageName) Database"
		Version = $Version
		OutputDir = $PackageOutputPath
		Path = $DatabaseBackupPath;
		BcPlatformVersion = $BcPlatformVersion # This must match the Business Central (platform) database version
	}
	
	if ($WhatIf)
	{
		$Arguments
		return
	}
	
	New-DatabasePackage @Arguments | Import-GocsPackage
}

function New-Dot-Net-Addin-Package
{
	
}

function New-License-Package
{
	param (
		[string][Parameter(Mandatory, HelpMessage = "Package prefix. Used to relate package with other packages of the same prefix.")]
		$PackagePrefix,
		[string][Parameter(Mandatory, HelpMessage = "Human readable form of the package id.")]
		$PackageName,
		[String][Parameter(ParameterSetName = 'Paths', HelpMessage = "Path to the location the created package should be stored at.")]
		$PackageOutputPath = $OUTPUT_DIR,
		[String][Parameter(ParameterSetName = 'Paths', HelpMessage = "Path to the file to be included in the package.")]
		$PackageDataPath,
		[string][Parameter(HelpMessage = "Human readable form of the package id.")]
		$Localization,
		[string][Parameter(Mandatory, HelpMessage = "Human readable form of the package id.")]
		$Version,
		[switch][Parameter(HelpMessage = "Runs the command and outputs what would happen without making any changes.")]
		$WhatIf,
		[switch][Parameter(ParameterSetName = 'Paths', HelpMessage = "Use dialogs where possible.")]
		$Dialogs
	)
	
	Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
	
	$ErrorActionPreference = 'stop'
	
	Install-GocPackage -Id 'ls-package-tools'
	
	Import-Module LsPackageTools\LicensePackageCreator
	Import-Module GoCurrentServer
	Import-Module (Join-path $(Split-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) -Parent) 'Utils.psm1') -Force
	$OUTPUT_DIR = (Join-path $(Split-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) -Parent) 'Output')
	
	if ($Dialogs)
	{
		Write-Output "Please select the license file with the dialog."
		$PackageDataPath = Get-FileName $PSScriptRoot
		Write-Output "Please select the package output directory with the dialog."
		$PackageOutputPath = Get-Directory $PSScriptRoot
	}
	
	$packageID
	if ($Localization)
	{
		$packageID = "$($PackagePrefix)-$($Localization)-license"
	}
	else
	{
		$packageID = "$($PackagePrefix)-license"
	}
	
	$Arguments = @{
		Id		    = $packageID
		Name	    = $PackageName
		Version	    = $Version
		LicensePath = $PackageDataPath
		OutputDir   = $PackageOutputPath
	}
	
	if ($WhatIf)
	{
		$Arguments
		pause
		return
	}
	
	New-LicensePackage @Arguments -Force | Import-GocsPackage
}

function Remove-Package
{	
	Import-Module GoCurrentServer
	
	$packagesToRemove = (Invoke-RestMethod "http://localhost:16551/api/packages").data | Out-GridView -OutputMode Multiple
	
	Write-Output "!!!! IMPORTANT !!!!"
	Write-Output "Please make sure there are no active installers using the to-be-deleted packages"
	pause
	
	Foreach ($package in $packagesToRemove)
	{
		Remove-GocsPackage -Id $package.id -Force
		
		$Version = "";
		Write-Output "$($package.id) was removed"
	}
}

function Get-Version-Map
{
	Param
	(
		[string][Parameter(HelpMessage = "Source Go Current Server (default is gocurrent.lsretail.com)")]
		$PackageSourceServer = "gocurrent.lsretail.com",
		[string][Parameter(HelpMessage = "Source Go Current Port (default is 443)")]
		$PackageSourcePort = "443",
		[boolean][Parameter(HelpMessage = "Does the source server use SSL")]
		$PackageSourceUseSSL = $true,
		[string][Parameter(HelpMessage = "This is the domain of the package source (default is lsretail.com)")]
		$PackageSourceIdentity = "lsretail.com",
		[string][Parameter(HelpMessage = "The version of LS Central that should be used for mapping")]
		$LsCentralVersion
	)
	Import-Module GoCurrentServer
	
	$Packages = @(
		@{ Id = 'map/ls-central-to-bc'; Version = $LsCentralVersion }
	)
	$Packages | Copy-GocsPackagesFromServer -SourceServer $PackageSourceServer -SourcePort $PackageSourcePort -SourceUseSsl:$PackageSourceUseSSL -SourceIdentity $PackageSourceIdentity -Server $null -Port $null
	
}

#endregion Functions


