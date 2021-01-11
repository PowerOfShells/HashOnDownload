<#
.SYNOPSIS
    Monitors the download folder, calculates the hashes and pushes a toast notification to the user

.DESCRIPTION
    The script will run within the user context.
    If  toastmessages are disabled, it will try to active them (Thanks @PeterEgerton)
    It'll set up a task to start itself via the taskscheduler on logon. 
    To disable the autorun use -Disable
    To "uninstall" the daemon use -Delete
    To stop the running daemon use -Stop

.PARAMETER Disable
    Disables the HashOnDownload run on logon task in taskscheduler

.PARAMETER Delete
    Deletes the HashOnDownload task from the taskscheduler

.PARAMETER Stop
    Stops the running daemon

.NOTES
    Filename: HashOnDownload.ps1
    Version: 1.0
    Author: Pascal Starke
    Twitter: @PowerOfShells

    Contributor: Dominique Clijsters
    Twiter: @clijsters_dom

    Excerpts taken from @PeterEgerton toast script
    https://morethanpatches.com/2020/03/16/keeping-in-touch-with-windows-toast-notifications-coronatoast/

.LINK
    https://pascalstarke.de
    https://github.com/PowerOfShells/HashOnDownload
#> 

#Requires -version 5.1
#Requires #Requires -Assembly "Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, Windows.Data.Xml.Dom.XmlDocument"

[CmdletBinding()]
param(
    [Parameter(HelpMessage="Disables the HashOnDownload run on logon task in taskscheduler")]
    [Switch]$Disable,

    [Parameter(HelpMessage="Deletes the HashOnDownload task from the taskscheduler")]
    [Switch]$Delete,

    [Parameter(HelpMessage="Stops the running daemon")]
    [Switch]$Stop
)


##########################
#Region Functions

# Create write log function
function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [Alias("LogContent")]
        [string]$Message,
        
        # with your location for the local log file
        [Parameter(Mandatory=$false)]
        [Alias('LogPath')]
        [string]$Path="$env:APPDATA\HashOnDownload\Filewatcher.log",

        [Parameter(Mandatory=$false)]
        [ValidateSet("Error","Warn","Info")]
        [string]$Level="Info"
    )

    Begin
    {
        # Set VerbosePreference to Continue so that verbose messages are displayed.
        $VerbosePreference = 'Continue'
    }
    Process
    {
		if ((Test-Path $Path)) {
			$LogSize = (Get-Item -Path $Path).Length/1MB
			$MaxLogSize = 5
		}
                
        # Check for file size of the log. If greater than 5MB, it will create a new one and delete the old.
        if ((Test-Path $Path) -AND $LogSize -gt $MaxLogSize) {
            Write-Error "Log file $Path already exists and file exceeds maximum file size. Deleting the log and starting fresh."
            Remove-Item $Path -Force
            $NewLogFile = New-Item $Path -Force -ItemType File
        }

        # If attempting to write to a log file in a folder/path that doesn't exist create the file including the path.
        elseif (-NOT(Test-Path $Path)) {
            Write-Verbose "Creating $Path."
            $NewLogFile = New-Item $Path -Force -ItemType File
            }

        else {
            # Nothing to see here yet.
            }

        # Format Date for our Log File
        $FormattedDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

        # Write message to error, warning, or verbose pipeline and specify $LevelText
        switch ($Level) {
            'Error' {
                Write-Error $Message
                $LevelText = 'ERROR:'
                }
            'Warn' {
                Write-Warning $Message
                $LevelText = 'WARNING:'
                }
            'Info' {
                Write-Verbose $Message
                $LevelText = 'INFO:'
                }
            }
        
        # Write log entry to $Path
        "$FormattedDate $LevelText $Message" | Out-File -FilePath $Path -Append
    }
    End
    {
    }
}
# Create file watcher function
function New-FileWatcher {

    [CmdletBinding()]
    param (
        # Which path to watch
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $PathToWatch = "$($env:USERPROFILE)\Downloads",

        # Filter to ex- or include files
        [string]
        $Filter = "*.*",

        # Include subdirs (recursive)
        [bool]
        $includeSubDirs = $true
    )

    ### Folder to monitor
    # Create .Net filewatcher 
    $folder_filewatcher = New-Object System.IO.FileSystemWatcher
    # Which path to monitor and what
    $folder_filewatcher.Path =  $PathToWatch
    $folder_filewatcher.Filter = $Filter
    # Include subdirs and enable event generation
    $folder_filewatcher.IncludeSubdirectories = $includeSubDirs
    $folder_filewatcher.EnableRaisingEvents = $true


    $folder_writeaction = { 
        
        # Extract full path from $event
        $path = $Event.SourceEventArgs.FullPath

        #ignore firefox files (.part) for hash creation
        if ($path -like "*.part") {
        }
        
        else {
            # Extract change type
            $changeType = $Event.SourceEventArgs.ChangeType

            # Write to log
            Write-Log -message "$changeType, $path" -Level Info
            Write-Log -message "New File spotted, calculating hashes ..." -Level Info

            # Check if file is fully downloaded and if file exists so it does not run infinite when file is moved / deleted for whatever reasons
            while ((get-item $path).length -eq 0 -and (Test-path -Path $path)) {
                Write-Log -Message "File not fully loaded, waiting for file to finish" -Level Info
                Start-Sleep 5
            }

            # Calculate hashes and log them
            $hashMD5 = Get-FileHash -Path $path -Algorithm MD5
            $hashSHA1 = Get-FileHash -Path $path -Algorithm SHA1
            $hashSHA256 = Get-FileHash -Path $path -Algorithm SHA256

            Write-Log -Message "MD5: $($hashMD5.hash), SHA1: $($hashSHA1.hash), SHA256: $($hashSHA256.hash)" -Level Info
            ### Displaying Toast
            # Load needed assemblies
            $Load = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
            $Load = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]

            # App which pushes the toast; windows needs this to display the toast message
            $AppID = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'

            # Xml for toast
            [xml]$Toast = @"
            <toast scenario="reminder">
                <visual>
                <binding template="ToastGeneric">
                    <text>Hash from file</text>
                    <group>
                        <subgroup>
                            <text hint-style="title" hint-wrap="true" >$path</text>
                        </subgroup>
                    </group>
                    <group>
                        <subgroup>     
                            <text hint-style="body" hint-wrap="true" >MD5: $($hashMD5.hash)</text>
                        </subgroup>
                    </group>
                    <group>
                        <subgroup>     
                            <text hint-style="body" hint-wrap="true" >SHA1: $($hashSHA1.hash)</text>
                        </subgroup>
                    </group>
                    <group>
                        <subgroup>     
                            <text hint-style="body" hint-wrap="true" >SHA256: $($hashSHA256.hash)</text>
                        </subgroup>
                    </group>
                </binding>
                </visual>
                <actions>
                    <action activationType="system" arguments="dismiss" content="Dismiss"/>
                </actions>
            </toast>
"@
            # Load the notification into the required format
            $ToastXml = New-Object -TypeName Windows.Data.Xml.Dom.XmlDocument
            $ToastXml.LoadXml($Toast.OuterXml)

            # Display toast
            [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($AppID).Show($ToastXml)

        
            }#End else$
        }#End Writeaction

    # Register the create event which will be logged

    
    $objectEventID =  Register-ObjectEvent $folder_filewatcher "Created" -Action $folder_writeaction
    Write-Log -Message "Object event created, Filewatcher started. ID: $($objectEventId.Name)"
    $objectEventID

}# End function new-Filewatcher

#Endregion Functions

##########################
#Region Load Config and check if toasts are enabled, if not, enable them

# Getting executing directory
$global:ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition

if (-NOT($Config)) {
    Write-Log -Message "No config file set as parameter. Using local config file"
    $Config = Join-Path ($global:ScriptPath) "config.xml"
}

# Load config.xml
if (Test-Path $Config) {
    try { 
        $Xml = [xml](Get-Content -Path $Config -Encoding UTF8)
        Write-Log -Message "Successfully loaded $Config" 
    }
    catch {
        $ErrorMessage = $_.Exception.Message
        Write-Log -Message "Error, could not read $Config"
        Write-Log -Message "Error message: $ErrorMessage"
        Exit 1
    }
}
else {
    Write-Log -Message "Error, could not find or access $Config"
    Exit 1
}

# Load xml content into variables

try {
    Write-Log -Message "Loading xml content from $Config into variables"

    $defaultDownloadOverride = $xml.configuration.option.defaultdownloadoverride 
    $multipleFolderWatch = $xml.configuration.option.MultipleFolderWatch
    $logpath = $xml.configuration.WatcherLog.path
    $FolderToWatchPath = $xml.configuration.foldertowatch.path
    $FolderToWatchFilter = $xml.configuration.FolderToWatch.filter
    $FolderToWatchIncludeSubDirs = $xml.configuration.FolderToWatch.IncludeSubDirs
    

    Write-Log -Message "Successfully loaded xml content from $Config"     
}
catch {
    Write-Log -Message "Xml content from $Config was not loaded properly"
    Exit 1
}

# Check if more than one path will be watched 

    # Get number of paths to watch
    [int]$folderToWatchCount = $FolderToWatchPath.count / 3

    <# 
    You might ask yourself why we divide by 3. 
    Well thats because all "FolderToWatch" attributes are counted in the $xml.configuration.foldertowatch.path array, even though we just requested the number of childs in path.
    Filter and IncludeSubDirs are counted too and added to the array, but empty. So even if we just supplied one path through the xml, $xml.configuration.foldertowatch.path.count returns 3. Neat!
    So 3 basically just means one set of FolderToWatch attributes. Everything greater than 3 means more folders need to be watched.
    #>


    # Clear arrays
    $paths, $filters, $includeSubDirs = $null


    # Clear empty entries from path array
    foreach ($path in $FolderToWatchPath) {
        # Check if path is empty
        if ($path -eq $null) {
            # Do Nothing
        }
        # Else add it to paths
        else {
            [array]$paths+=$path
        }
    }# End foreach path

    # Clear empty entries from filter array
    foreach ($filter in $FolderToWatchFilter) {
                # Check if filter is empty
                if ($filter -eq $null) {
                    # Do Nothing
                }
                # Else add it to filters
                else {
                    [array]$filters+=$filter
                }
        }# End foreach filter

    # Clear empty entries from includeSubdirs array
    foreach ($subdirSwitch in $FolderToWatchIncludeSubDirs) {

        # Check if filter is empty
        if ($subdirSwitch -eq $null) {
            # Do Nothing
        }
        # Else add it to includeSubdirs
        else {
            # Convert from string to bool
            $subdirSwitchBol =  [System.Convert]::ToBoolean($subdirswitch)
            [array]$includeSubDirs+=$subdirSwitchBol
        }

    }# End foreach subdir

    #Create Hashtable and store cleaned arrays in it
    $foldersHashtable = @{
        Path = $paths
        Filter = $filters
        IncludeSubdirs = $includeSubDirs
    }

#Endregion Config

# Create file watchers based on config.xml
try {
    for ($i = 0; $i -lt $folderToWatchCount; $i++) {

        [array]$objectEventID =  New-FileWatcher -PathToWatch $foldersHashtable.Path[$i] -Filter $foldersHashtable.Filter[$i] -includeSubDirs $foldersHashtable.IncludeSubdirs[$i]

    }

    # Check every 5 Seconds
    while ($true) {Start-Sleep 5}

}# End try
catch {
    #Display Error
    Write-Log -Message $_ -Level Error -Verbose

}# End catch
finally{
    #Unregister eventsubscriber after error
     Unregister-Event -SourceIdentifier $objectEventID.Name
     Write-Log -Message "Object event unregistered. Daemon stopped."
     Exit 1
}# End finally
#NOTE: If you are running the deamon from the console, be sure to kill all the jobs with "Get-EventSubscriber | unregister-event"