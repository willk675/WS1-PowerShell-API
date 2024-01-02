<#	
	.NOTES
	===========================================================================
	 Created on:   	1/11/2023 1:13 PM
	 Created by:   	William Knight
	 Organization: 	
	 Filename:     	
	===========================================================================
	.DESCRIPTION
		Powershell cmdlets to do all the things I want to do in WS1 without touching the console.
		A.K.A - my own personal GOD MODE. 

		----- Command List -----
		Set-WS1APIheader
			- Use to set your console and credentials
		Test-WS1APIheader
			- Use to test you can connect to your console
		Clear-WS1APIheader
			- Use to clear the API headers to prevent unwanted access. 
		Get-WS1Device
			- Use to get device info from the console
		Delete-WS1Device
			- Use to delete device. 

	.NOTES
		----- Usage -----
		Import-module WS1_PSModule.psm
		Set-WS1APIheader 
		Test-WS1APIheader
		Get-WS1Device -SerialNumber <SerialNumber>
		Delete-WS1Device -Serial <SerialNumber>
			- Will Delete single device & create a CSV with the device info pulled from console. 
		Delete-WS1Device -importcsv <path to CSV file>
			- Should contain Device Serial Numbers under the column header "SerialNumber"
			- Sill get device details from console, will output a gridview to allow you to select which device you want to delete.
				-- If running from PWSH on macOS device Comment out line #130 to remove this.
			- Will create two CSVs in path of input file. One of deleted files, one of devices not found. 
		Clear-WS1APIheader
		
#>


function Delete-WS1Device
{
	[CmdletBinding(DefaultParameterSetName = 'SerialNumber')]
	param
	(
		[Parameter(ParameterSetName = 'SerialNumber',
				   HelpMessage = 'Please provide a valid Serial Number')]
		[string]$Serial,
		[Parameter(ParameterSetName = 'ImportCSV',
				   HelpMessage = 'CSVInput File')]
		[string]$ImportCSV,
		[Parameter(ParameterSetName = 'SerialNumber',
				   Mandatory = $true)]
		[string]$OutputCSV
	)
	
	switch ($PsCmdlet.ParameterSetName)
	{
		'SerialNumber' {
			if ([string]::IsNullOrEmpty($header))
			{
				Set-WS1APIheader
			}
			
			Test-WS1APIheader -NoOutput
			
			try
			{
				$Device = Get-WS1Device -Serial "$Serial" -NoHeaderTest
				$DeviceID = $Device.Id.Value
			}
			catch
			{
				write-host "Unable find device in WS1. Check the Serial Number and try again." -ForegroundColor Red -BackgroundColor Black
			}
			
			Write-Host "Deleting Device."
			#######################
			Invoke-RestMethod "https://$WSOServer/api/mdm/devices/$DeviceID" -Method 'DELETE' -Headers $header
			#######################
			
			$Device | Export-Csv -Path $OutputCSV -NoClobber -NoTypeInformation -Force -Append
			Write-Host "Device Deleted and Device Data saved to $OutputCSV" -ForegroundColor Black -BackgroundColor Green
			

		}
		'ImportCSV' {
			#TODO: Place script here
			if ([string]::IsNullOrEmpty($header))
			{
				Set-WS1APIheader
			}
			Test-WS1APIheader -NoOutput
			
			$InputFile = get-item $ImportCSV
			$List = Import-Csv $InputFile.FullName
			$OUtFileNotFound = New-Item -ItemType file -Name ($InputFile.BaseName + ("_NotFound") + $InputFile.Extension) -Path $InputFile.Directory -Force
			$OUtFileName = New-Item -ItemType file -Name ($InputFile.BaseName + ("_Deleted") + $InputFile.Extension) -Path $InputFile.Directory -Force
			$DeviceList = @()
			
			$TotalDevices = $List.count
			$Count = 0
			
			## Get Device info from WS1
			$List | ForEach-Object {
				$CurrentDevice = $_
				
				Write-Progress -Activity "Verifying Device List..." -Status ([string](("Processed $count of $TotalDevices") + ("; Processing") + ($CurrentDevice.SerialNumber))) -PercentComplete ($count / $TotalDevices * 100)
				
				$Serial = $CurrentDevice.SerialNumber
				$Device = Get-WS1Device -SerialNumber $Serial
				if ($Device)
				{
					$DeviceList += $Device
				}
				else
				{
					$CurrentDevice | Export-Csv -Path $OUtFileNotFound -Append -NoClobber -NoTypeInformation -Force
				}
			$Count++
			}
			<#
				Verify Which Devices to Delete from WS1. 
				This does not work in powershell on Mac. Thus is commented out for testing. 
				Uncomment and remove  line of '$deletelist = DeviceList'
			#>
			$DeleteList = $DeviceList | Out-GridView -PassThru -Title "Please select which Devices to Process, you can CTRL+Click or Select All, click OKAY to process."
			$DeleteList = $DeviceList
			
			$DeleteTotal = $DeleteList.Count
			$Count = 0
			
			$DeleteList | ForEach-Object {
				$CurrentDevice = $_
				Write-Progress -Activity "Deleting Device ..." -Status ([string](("Processed $count of $DeleteTotal") + ("; Processing ") + ($CurrentDevice.SerialNumber))) -PercentComplete ($count / $DeleteTotal * 100)
				
				$DeviceID = $CurrentDevice.Id.Value
				##############################################
				Invoke-RestMethod "https://$WSOServer/api/mdm/devices/$DeviceID" -Method 'DELETE' -Headers $header
				##############################################
				$CurrentDevice | Export-Csv -Path $OUtFileName -Append -NoClobber -NoTypeInformation -Force
				
				$Count++
			}
			break
		}
	}
}


<#
	.SYNOPSIS
		A brief description of the Set-APIheader function.
	
	.DESCRIPTION
		Gets Logon credentials and sets the headers for using PS Rest API. 
		Must be run before running other cmdlets. 
	
	.EXAMPLE
				PS C:\> Set-APIheader
	
	.NOTES
		Additional information about the function.
#>
function Set-WS1APIheader
{
	[CmdletBinding()]
	param ()
	
	if ([string]::IsNullOrEmpty($WSOServer))
	{
		$script:WSOServer = Read-Host -Prompt 'Enter the Workspace ONE UEM Server Name'
		
	}
	if ([string]::IsNullOrEmpty($header))
	{
		$creds = Get-Credential
		$apikey = Read-Host -Prompt 'Enter the API Key (aw-tenant-code)'
		
		$script:ZertoUser = $creds.UserName.ToString()
		
		#Converts the get-credential username and password to the Base64 string required by the Zerto REST API
		#####Note: This is one line
		$authInfo = [System.Text.Encoding]::UTF8.GetBytes(("{0}:{1}" -f $ZertoUser, ([Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($creds.Password)))))
		#####
		
		$cred = [System.Convert]::ToBase64String($authInfo)
		
		$script:header = @{
			"Authorization"  = "Basic $cred";
			"aw-tenant-code" = $apikey;
			"Accept"		 = "application/json;version=2";
			"Content-Type"   = "application/json";
		}
	}
	
	# Clear credential info from cache to prevent security risks. 
	$creds = $null
	$apikey = $null
	$authInfo = $null
	$cred = $null	
}


function Clear-WS1APIheader
{
	[CmdletBinding()]
	param ()
	
	$script:WSOServer = $null
	$script:header = $null
	$Script:ZertoUser = $null
}


function Get-WS1Device
{
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true)]
		[string]$SerialNumber,
		[switch]$NoHeaderTest
	)
	if ([string]::IsNullOrEmpty($header))
	{
		Set-WS1APIheader
	}
	
	IF ($NoHeaderTest.IsPresent)
	{
		### Do nothing, skipping header tests. 
	}
	else
	{
		Test-WS1APIheader -NoOutput
	}
	
	$WS1device = Invoke-RestMethod "https://$WSOServer/API/mdm/devices?searchby=SerialNumber&id=$SerialNumber" -Method 'GET' -Headers $header
	return $WS1device
}



<#
	.SYNOPSIS
		A brief description of the Test-APIheader function.
	
	.DESCRIPTION
		Verifies API credentials are correct and we are able to send API commands to WorkSpace One. 
	
	.EXAMPLE
				PS C:\> Test-APIheader
	
	.NOTES
		Additional information about the function.
#>
function Test-WS1APIheader
{
	[CmdletBinding()]
	param ([switch]$NoOutput)
	
	try
	{
		$HeaderTest = Invoke-RestMethod "https://$WSOServer/API/system/admins/search?username=$ZertoUser" -Method 'GET' -Headers $header
		if ($NoOutput.IsPresent)
		{
			# Don't do anything skipping console output of test results.
		}
		else
		{
			Write-Host "API Headers are valid" -ForegroundColor Green -BackgroundColor DarkBlue
		}
	}
	catch
	{
		write-host "Unable to connect to API: Invalid Credentials, server, or API Key. Headers have been reset. Run cmdlet for Set-WS1APIHeader" -ForegroundColor Red -BackgroundColor Black
		Clear-WS1APIheader
		break
	}
	finally
	{
		$HeaderTest = $null
	}
}


