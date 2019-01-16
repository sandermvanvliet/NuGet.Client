Param(
    [Parameter(Mandatory = $True)]
    [string] $nugetClientFilePath,
    [Parameter(Mandatory = $True)]
    [string] $solutionFilePath,
    [Parameter(Mandatory = $True)]
    [string] $resultsFilePath,
    [string] $logsFolderPath,
    [string] $testRootFolderPath,
    [int] $iterationCount = 3,
    [switch] $skipWarmup,
    [switch] $skipCleanRestores,
    [switch] $skipColdRestores,
    [switch] $skipForceRestores,
    [switch] $skipNoOpRestores
)

. "$PSScriptRoot\PerformanceTestUtilities.ps1"

# Plugins cache is only available in 4.8+. We need to be careful when using that switch for older clients because it may blow up.
# The logs location is optional
Function RunRestore(
    [string] $solutionFilePath,
    [string] $nugetClientFilePath,
    [string] $resultsFile,
    [string] $logsFolderPath,
    [string] $restoreName,
    [string] $testCaseId,
    [switch] $cleanGlobalPackagesFolder,
    [switch] $cleanHttpCache,
    [switch] $cleanPluginsCache,
    [switch] $killMsBuildAndDotnetExeProcesses,
    [switch] $force)
{
    Log "Running $nugetClientFilePath restore with cleanGlobalPackagesFolder:$cleanGlobalPackagesFolder cleanHttpCache:$cleanHttpCache cleanPluginsCache:$cleanPluginsCache killMsBuildAndDotnetExeProcesses:$killMsBuildAndDotnetExeProcesses force:$force"

    $IsClientDotnetExe = IsClientDotnetExe $nugetClientFilePath

    # Cleanup if necessary
    if($cleanGlobalPackagesFolder -Or $cleanHttpCache -Or $cleanPluginsCache)
    {
        if($cleanGlobalPackagesFolder -And $cleanHttpCache -And $cleanPluginsCache)
        {
            $localsArguments = "all"
        }
        elseif($cleanGlobalPackagesFolder -And $cleanHttpCache)
        {
            $localsArguments =  "http-cache global-packages"
        }
        elseif($cleanGlobalPackagesFolder)
        {
            $localsArguments =  "global-packages"
        }
        elseif($cleanHttpCache)
        {
            $localsArguments = "http-cache"
        }
        else
        {
            Log "Too risky to invoke a locals clear with the specified parameters." "yellow"
        }

        If ($IsClientDotnetExe)
        {
            . $nugetClientFilePath nuget locals -c $localsArguments *>>$null
        }
        Else
        {
            . $nugetClientFilePath locals -clear $localsArguments -Verbosity quiet
        }
    }

    if($killMsBuildAndDotnetExeProcesses)
    {
        Stop-Process -name msbuild*,dotnet* -Force
    }

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    If ($IsClientDotnetExe)
    {
        $logs = . $nugetClientFilePath restore $solutionFilePath $forceArg | Out-String
    }
    Else
    {
        $logs = . $nugetClientFilePath restore $solutionFilePath -noninteractive $forceArg | Out-String
    }

    $totalTime = $stopwatch.Elapsed
    $restoreCoreTime = ExtractRestoreElapsedTime $logs

    if(![string]::IsNullOrEmpty($logsFolderPath))
    {
        $logFile = [System.IO.Path]::Combine($logsFolderPath, "restoreLog-$([System.IO.Path]::GetFileNameWithoutExtension($solutionFilePath))-$(get-date -f yyyyMMddTHHmmssffff).txt")
        OutFileWithCreateFolders $logFile $logs
    }

    $folderPath = $Env:NUGET_PACKAGES
    $globalPackagesFolderNupkgFilesInfo = GetFilesInfo(GetPackageFiles $folderPath)
    $globalPackagesFolderFilesInfo = GetFilesInfo(GetFiles $folderPath)

    $folderPath = $Env:NUGET_HTTP_CACHE_PATH
    $httpCacheFilesInfo = GetFilesInfo(GetFiles $folderPath)

    $folderPath = $Env:NUGET_PLUGINS_CACHE_PATH
    $pluginsCacheFilesInfo = GetFilesInfo(GetFiles $folderPath)

    $clientName = GetClientName $nugetClientFilePath
    $clientVersion = GetClientVersion $nugetClientFilePath

    if(!(Test-Path $resultsFile))
    {
        OutFileWithCreateFolders $resultsFile "clientName,clientVersion,testCaseId,name,totalTime,restoreCoreTime,force,globalPackagesFolderNupkgCount,globalPackagesFolderNupkgSizeInMB,globalPackagesFolderFilesCount,globalPackagesFolderFilesSizeInMB,cleanGlobalPackagesFolder,httpCacheFileCount,httpCacheFilesSizeInMB,cleanHttpCache,pluginsCacheFileCount,pluginsCacheFilesSizeInMB,cleanPluginsCache,killMsBuildAndDotnetExeProcesses,processorName,cores,logicalCores"
    }

    Add-Content -Path $resultsFile -Value "$clientName,$clientVersion,$testCaseId,$restoreName,$($totalTime.ToString()),$($restoreCoreTime.ToString()),$force,$($globalPackagesFolderNupkgFilesInfo.Count),$($globalPackagesFolderNupkgFilesInfo.TotalSizeInMB),$($globalPackagesFolderFilesInfo.Count),$($globalPackagesFolderFilesInfo.TotalSizeInMB),$cleanGlobalPackagesFolder,$($httpCacheFilesInfo.Count),$($httpCacheFilesInfo.TotalSizeInMB),$cleanHttpCache,$($pluginsCacheFilesInfo.Count),$($pluginsCacheFilesInfo.TotalSizeInMB),$cleanPluginsCache,$killMsBuildAndDotnetExeProcesses,$($processorInfo.Name),$($processorInfo.NumberOfCores),$($processorInfo.NumberOfLogicalProcessors)"

    Log "Finished measuring."
}


try {
    ##### Script logic #####

    If (!(Test-Path $solutionFilePath))
    {
        Log "$solutionFilePath does not exist!" "Red"
        Exit 1
    }

    If (!(Test-Path $nugetClientFilePath))
    {
        Log "$nugetClientFilePath does not exist!" "Red"
        Exit 1
    }

    $nugetClientFilePath = GetAbsolutePath $nugetClientFilePath
    $solutionFilePath = GetAbsolutePath $solutionFilePath
    $resultsFilePath = GetAbsolutePath $resultsFilePath

    If (![string]::IsNullOrEmpty($logsFolderPath))
    {
        $logsFolderPath = GetAbsolutePath $logsFolderPath

        If ($resultsFilePath.StartsWith($logsFolderPath))
        {
            Log "$resultsFilePath cannot be under $logsFolderPath" "red"
            Exit 1
        }
    }

    LogDotNetSdkInfo

    if(Test-Path $resultsFilePath)
    {
        Log "The results file $resultsFilePath already exists. The test results of this run will be appended to the same file." "yellow"
    }

    # Setup the NuGet folders - This includes global packages folder/http/plugin caches
    SetupNuGetFolders $nugetClientFilePath $testRootFolderPath

    $processorInfo = GetProcessorInfo

    Log "Measuring restore for $solutionFilePath by $nugetClientFilePath" "Green"

    $uniqueRunID = Get-Date -f d-m-y-h:m:s

    if(!$skipWarmup)
    {
        Log "Running 1x warmup restore"
        RunRestore $solutionFilePath $nugetClientFilePath $resultsFilePath $logsFolderPath "warmup" $uniqueRunID -cleanGlobalPackagesFolder -cleanHttpCache -cleanPluginsCache -killMSBuildAndDotnetExeProcess -force
    }
    if(!$skipCleanRestores)
    {
        Log "Running $($iterationCount)x clean restores"
        1..$iterationCount | % { RunRestore $solutionFilePath $nugetClientFilePath $resultsFilePath $logsFolderPath "arctic" $uniqueRunID -cleanGlobalPackagesFolder -cleanHttpCache -cleanPluginsCache -killMSBuildAndDotnetExeProcess -force }
    }
    if(!$skipColdRestores)
    {
        Log "Running $($iterationCount)x without a global packages folder"
        1..$iterationCount | % { RunRestore $solutionFilePath $nugetClientFilePath $resultsFilePath $logsFolderPath "cold" $uniqueRunID -cleanGlobalPackagesFolder -killMSBuildAndDotnetExeProcess -force }
    }
    if(!$skipForceRestores)
    {
        Log "Running $($iterationCount)x force restores"
        1..$iterationCount | % { RunRestore $solutionFilePath $nugetClientFilePath $resultsFilePath $logsFolderPath "force" $uniqueRunID -force }
    }
    if(!$skipNoOpRestores){
        Log "Running $($iterationCount)x no-op restores"
        1..$iterationCount | % { RunRestore $solutionFilePath $nugetClientFilePath $resultsFilePath $logsFolderPath "noop" $uniqueRunID }
    }

    Log "Completed the performance measurements for $solutionFilePath, results are in $resultsFilePath" "green"
}
finally
{
    # Clean the NuGet folders.
    CleanNuGetFolders $nugetClientFilePath $testRootFolderPath
}