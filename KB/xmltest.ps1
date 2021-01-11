$global:ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition

if (-NOT($Config)) {
    $global:Config = Join-Path ($global:ScriptPath) "config.xml"
}

# Load config.xml
if (Test-Path $Config) {
    try { 
        $global:Xml = [xml](Get-Content -Path $Config -Encoding UTF8)
    }
    catch {
        $ErrorMessage = $_.Exception.Message
        Exit 1
    }
}

$global:defaultDownloadOverride = $xml.configuration.option.defaultdownloadoverride 
$global:multipleFolderWatch = $xml.configuration.option.MultipleFolderWatch
$global:logpath = $xml.configuration.WatcherLog.path
$global:FolderToWatchPath = $xml.configuration.foldertowatch.path
$global:FolderToWatchFilter = $xml.configuration.FolderToWatch.filter
$global:FolderToWatchIncludeSubDirs = $xml.configuration.FolderToWatch.IncludeSubDirs

# Check if more than one path will be watched 
<# 
You might ask yourself why greater than 3. 
Well thats because all "FolderToWatch" attributes are counted in the $xml.configuration.foldertowatch.path array, even though we just requested the number of childs in path.
Filter and IncludeSubDirs are counted too and added to the array, but empty.
So 3 basically just means one set of FolderToWatch attributes. Everything greater than 3 means more folders need to be watched.
#>

if ($defaultDownloadOverride -eq $true -AND $global:FolderToWatchPath.count -gt 3) { # See above why greater than 3.

    # Get number of paths to watch
    [int]$folderToWatchCount = $FolderToWatchPath.count / 3

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
                # Else add it to paths
                else {
                    [array]$filters+=$filter
                }
        }# End foreach filter

    # Clear empty entries from array
    foreach ($subdirSwtich in $FolderToWatchIncludeSubDirs) {

        # Check if filter is empty
        if ($subdirSwitch -eq $null) {
            # Do Nothing
        }
        # Else add it to paths
        else {
            [array]$includeSubDirs+=$subdirSwitch
        }

    }# End foreach subdir

    $foldersHashtable = @{
        Path = $paths
        Filter = $filters
        IncludeSubdirs = $subdirSwtich
    }

    for ($i = 0; $i -lt $folderToWatchCount; $i++) {
        
    }
}