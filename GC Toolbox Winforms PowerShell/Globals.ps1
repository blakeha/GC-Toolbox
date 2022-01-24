#--------------------------------------------
# Declare Global Variables and Functions here
#--------------------------------------------


#Sample function that provides the location of the script
function Get-ScriptDirectory
{
<#
	.SYNOPSIS
		Get-ScriptDirectory returns the proper location of the script.
		
	.OUTPUTS
		System.String
	
	.NOTES
		Returns the correct path within a packaged executable.
#>
	[OutputType([string])]
	param ()
	if ($null -ne $hostinvocation)
	{
		Split-Path $hostinvocation.MyCommand.path
	}
	else
	{
		Split-Path $script:MyInvocation.MyCommand.Path
	}
}

#Sample variable that provides the location of the script
[string]$ScriptDirectory = Get-ScriptDirectory

$JobTrackerList = New-Object System.Collections.ArrayList;

function Add-JobTracker
{
    <#
        .SYNOPSIS
            Add a new job to the JobTracker and starts the timer.
    
        .DESCRIPTION
            Add a new job to the JobTracker and starts the timer.
    
        .PARAMETER  Name
            The name to assign to the Job
    
        .PARAMETER  JobScript
            The script block that the Job will be performing. 
            Important: Do not access form controls from this script block.
    
        .PARAMETER ArgumentList
            The arguments to pass to the job
    
        .PARAMETER  CompleteScript
            The script block that will be called when the job is complete.
            The job is passed as an argument. The Job argument is null when the job fails.
    
        .PARAMETER  UpdateScript
            The script block that will be called each time the timer ticks. 
            The job is passed as an argument. Use this to get the Job's progress.
    
        .EXAMPLE
            Job-Begin -Name "JobName" `
            -JobScript {    
                Param($Argument1)#Pass any arguments using the ArgumentList parameter
                #Important: Do not access form controls from this script block.
                Get-WmiObject Win32_Process -Namespace "root\CIMV2"
            }`
            -CompletedScript {
                Param($Job)        
                $results = Receive-Job -Job $Job        
            }`
            -UpdateScript {
                Param($Job)
                #$results = Receive-Job -Job $Job -Keep
            }
    
        .LINK
            
    #>
	
	Param (
		[ValidateNotNull()]
		[Parameter(Mandatory = $true)]
		[string]$Name,
		[ValidateNotNull()]
		[Parameter(Mandatory = $true)]
		[ScriptBlock]$JobScript,
		$ArgumentList = $null,
		[ScriptBlock]$CompletedScript,
		[ScriptBlock]$UpdateScript)
	
	#Start the Job
	$job = Start-Job -Name $Name -ScriptBlock $JobScript -ArgumentList $ArgumentList
	
	if ($job -ne $null)
	{
		#Create a Custom Object to keep track of the Job & Script Blocks
		$psObject = New-Object System.Management.Automation.PSObject
		
		Add-Member -InputObject $psObject -MemberType 'NoteProperty' -Name Job -Value $job
		Add-Member -InputObject $psObject -MemberType 'NoteProperty' -Name CompleteScript -Value $CompletedScript
		Add-Member -InputObject $psObject -MemberType 'NoteProperty' -Name UpdateScript -Value $UpdateScript
		
		[void]$JobTrackerList.Add($psObject)
		
		#Start the Timer
		if (-not $timerJobTracker.Enabled)
		{
			$timerJobTracker.Start()
		}
	}
	elseif ($CompletedScript -ne $null)
	{
		#Failed
		Invoke-Command -ScriptBlock $CompletedScript -ArgumentList $null
	}
	
}

function Update-JobTracker
{
    <#
        .SYNOPSIS
            Checks the status of each job on the list.
    #>
	
	#Poll the jobs for status updates
	$timerJobTracker.Stop() #Freeze the Timer
	
	for ($index = 0; $index -lt $JobTrackerList.Count; $index++)
	{
		$psObject = $JobTrackerList[$index]
		
		if ($psObject -ne $null)
		{
			if ($psObject.Job -ne $null)
			{
				if ($psObject.Job.State -ne "Running")
				{
					#Call the Complete Script Block
					if ($psObject.CompleteScript -ne $null)
					{
						#$results = Receive-Job -Job $psObject.Job
						Invoke-Command -ScriptBlock $psObject.CompleteScript -ArgumentList $psObject.Job
					}
					
					$JobTrackerList.RemoveAt($index)
					Remove-Job -Job $psObject.Job
					$index-- #Step back so we don't skip a job
				}
				elseif ($psObject.UpdateScript -ne $null)
				{
					#Call the Update Script Block
					Invoke-Command -ScriptBlock $psObject.UpdateScript -ArgumentList $psObject.Job
				}
			}
		}
		else
		{
			$JobTrackerList.RemoveAt($index)
			$index-- #Step back so we don't skip a job
		}
	}
	
	if ($JobTrackerList.Count -gt 0)
	{
		$timerJobTracker.Start() #Resume the timer    
	}
}

function Stop-JobTracker
{
   <#
        .SYNOPSIS
            Stops and removes all Jobs from the list.
    #>
	#Stop the timer
	$timerJobTracker.Stop()
	
	#Remove all the jobs
	while ($JobTrackerList.Count -gt 0)
	{
		$job = $JobTrackerList[0].Job
		$JobTrackerList.RemoveAt(0)
		Stop-Job $job
		Remove-Job $job
	}
}
