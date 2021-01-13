<#
.SYNOPSIS
    Monitors the download folder, calculates the hashes and pushes a toast notification to the user

.DESCRIPTION
    The script will run within the user context.
    If  toastmessages are disabled, it will try to active them (Thanks @PeterEgerton)
    Path to config via -Path, else scriptpath local config.xml will be used.
    To enable the autorun use -EnableAutorun
    To disable the autorun use -DisableAutorun
    To stop the running daemon use -Stop

.PARAMETER Config
    Path to config.xml

.PARAMETER DisableAutorun
    Disables the autorun of daemon

.PARAMETER EnableAutorun
    Enables the autorun of daemon

.PARAMETER Stop
    Stops the running daemon

.NOTES
    Filename: HashOnDownload.ps1
    Version: 1.0
    Author: Pascal Starke
    Twitter: @kraeftigeSchale

    Contributor: Dominique Clijsters
    Twiter: @clijsters_dom

    Excerpts taken from @PeterEgerton toast script
    https://morethanpatches.com/2020/03/16/keeping-in-touch-with-windows-toast-notifications-coronatoast/

.LINK
    https://pascalstarke.de
    https://github.com/PowerOfShells/HashOnDownload
#> 

#Requires -version 5.1 -PSEdition Desktop
#Requires #Requires -Assembly "Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, Windows.Data.Xml.Dom.XmlDocument"

[CmdletBinding()]
param(
    [Parameter(HelpMessage = "Path to the config.xml")]
    [string]$Config,

    [Parameter(HelpMessage = "Disables the autorun of daemon")]
    [Switch]$DisableAutorun,

    [Parameter(HelpMessage = "Enables the autorun of daemon")]
    [Switch]$EnableAutorun,

    [Parameter(HelpMessage = "Stops the running daemon")]
    [Switch]$Stop
)


##########################
#Region Functions

# Create write log function
function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias("LogContent")]
        [string]$Message,
        
        # with your location for the local log file
        [Parameter(Mandatory = $false)]
        [Alias('LogPath')]
        [string]$Path = "$env:APPDATA\HashOnDownload\Filewatcher.log",

        [Parameter(Mandatory = $false)]
        [ValidateSet("Error", "Warn", "Info")]
        [string]$Level = "Info"
    )

    Begin {
        # Set VerbosePreference to Continue so that verbose messages are displayed.
        $VerbosePreference = 'Continue'
    }
    Process {
        if ((Test-Path $Path)) {
            $LogSize = (Get-Item -Path $Path).Length / 1MB
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
    End {
    }
}# End function Write-Log

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
    $folder_filewatcher.Path = $PathToWatch
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

    
    $objectEventID = Register-ObjectEvent $folder_filewatcher "Created" -Action $folder_writeaction
    Write-Log -Message "Object event created, Filewatcher started. ID: $($objectEventId.Name)"
    $objectEventID

}# End function New-Filewatcher

# Create Windows Push Notification function.
# This is testing if toast notifications generally are disabled within Windows 10
function Test-WindowsPushNotificationsEnabled {
    $ToastEnabledKey = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications" -Name ToastEnabled -ErrorAction Ignore).ToastEnabled
    if ($ToastEnabledKey -eq "1") {
        Write-Log -Message "Toast notifications are enabled in Windows"
    }
    elseif ($ToastEnabledKey -eq "0") {
        Write-Log -Message "Toast notifications are not enabled in Windows. Enabling ..."
        try {
            Set-ItemProperty -path "HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications" -Name ToastEnabled -Value 1
            Write-Log -Message "Toast notifications enabled."
        }
        catch {
            Write-Log -Message "Could not enable Toast notifications. Please check your registry / permissions." -Level Warn
        }
    }
    else {
        Write-Log -Message "The registry key for determining if toast notifications are enabled does not exist. The script will run, but toasts might not be displayed" -Level Warn
    }
}

#Endregion Functions
##########################
#Region Load Config and check if toasts are enabled, if not, enable them

#Test toast notifications

$null = Test-WindowsPushNotificationsEnabled


# Getting executing directory
$global:ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition

# DaemonParams
$daemonParams = "`"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe`" -noProfile -nonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -file $($scriptpath)\hashondownload.ps1 "

# If autorun should be disabled
if ($DisableAutorun) {
    Write-Log "Disable switch detected, daemon autorun will be disabled ..."
    try {
        $autrunEnabled = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name HashOnDownloadDaemon -ErrorAction Ignore).HashOnDownloadDaemon

        # if autorunEnabled is not empty
        if ($autrunEnabled -ne $null) {
            Remove-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name HashOnDownloadDaemon -Confirm:$false -ErrorAction Ignore
            Write-Log "Success!"
        }
        else {
            Write-Log "Autorun was not enabled in the first place"
        }
        
    }
    catch {
        Write-Log "Error on disabling daemon:" -Level Error
        Write-Log $_ -Level Error+
    }

}
# If running HashOnDownload should be stopped
elseif ($stop) {
    Write-Log "Stop switch detected, stopping daemon ..."
    # Get all powershell processes
    $poshProcs = Get-WmiObject Win32_Process -Filter "name = 'powershell.exe'" | Select-Object name, commandline, processid
    # Serach for daemon

    foreach ($proc in $poshProcs) {
        if ($proc.commandline -like "*HashOnDownload.ps1*") {
            Stop-process -id $proc.processid
            Write-Log "Success!"
            $processKilled = $true
        }
    }
    if (-NOT($processKilled)) {
        Write-Log "Daemon was not running"
    }

}
elseif ($EnableAutorun) {
    Write-Log "Enable switch detected, daemon autorun will be enabled ..."
    try {
        New-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name HashOnDownloadDaemon -Value $daemonParams -PropertyType string
        Write-Log "Success!"
    }
    catch {
        Write-Log "Error on activating autorun. Try disabling the autorun first if you moved the file. Else check your permissions." -Level Error
        Write-Log $_ -level Error
    }
}
# Else launch process
else {

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

        $defaultDownloadOverride = [system.convert]::toboolean($xml.configuration.option.defaultdownloadoverride)
        #$logpath = $xml.configuration.WatcherLog.path
        $FolderToWatchPath = $xml.configuration.foldertowatch.path
        $FolderToWatchFilter = $xml.configuration.FolderToWatch.filter
        $FolderToWatchIncludeSubDirs = $xml.configuration.FolderToWatch.IncludeSubDirs
   
    

        Write-Log -Message "Successfully loaded xml content from $Config"     
    }
    catch {
        Write-Log -Message "Xml content from $Config was not loaded properly"
        Exit 1
    }




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
        # If defaultDownloadOverride is false, use default path        
        if (-NOT($defaultDownloadOverride)) {
            [array]$paths = "$env:USERPROFILE\Downloads" 
        }
        # Else use path from config
        else {
            # Check if path is empty
            if ($path -eq $null) {
                # Do Nothing
            }
            # Else add it to paths
            else {
                [array]$paths += $path
            }
        }# End Else defaultDownloadOverride
    }# End foreach path
    # Clear empty entries from filter array
    foreach ($filter in $FolderToWatchFilter) {
                
            
        # Check if filter is empty
        if ($filter -eq $null) {
            # Do Nothing
        }
        # Else add it to filters
        else {
            [array]$filters += $filter
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
            $subdirSwitchBol = [System.Convert]::ToBoolean($subdirswitch)
            [array]$includeSubDirs += $subdirSwitchBol
        }
    }# End foreach subdir
    #Create hashtable and store cleaned arrays in it

    $foldersHashtable = @{
        Path           = $paths
        Filter         = $filters
        IncludeSubdirs = $includeSubDirs
    }
    
    #Endregion Config

    # Create file watchers based on config.xml
    try {
        Write-Log "Starting daemon ..."
        for ($i = 0; $i -lt $folderToWatchCount; $i++) {

            [array]$objectEventID = New-FileWatcher -PathToWatch $foldersHashtable.Path[$i] -Filter $foldersHashtable.Filter[$i] -includeSubDirs $foldersHashtable.IncludeSubdirs[$i]

        }

        # Check every 5 Seconds
        while ($true) { Start-Sleep 5 }

    }# End try
    catch {
        #Display Error
        Write-Log -Message $_ -Level Error -Verbose

    }# End catch
    finally {
        #Unregister eventsubscriber after error
        try {
            Write-Log -Message "Stop event detected ..."
            Unregister-Event -SourceIdentifier $objectEventID.Name
            Write-Log -Message "Object event unregistered. Daemon stopped."
            Exit 1
        }
        catch {
            Write-Log -Message "Object event unregistered. Daemon stopped."
            Exit 1
        }
    }# End finally
}# End else disable / stop / noautorun
#NOTE: If you are running the deamon from the console, be sure to kill all the jobs with "Get-EventSubscriber | unregister-event"