# Contains all the utility methods used by the performance tests.

# The format of the URL is assumed to be https://github.com/NuGet/NuGet.Client.git. The result would be NuGet-Client-git
function GenerateNameFromGitUrl([string]$gitUrl)
{
    return $gitUrl.Substring($($gitUrl.LastIndexOf('/') + 1)).Replace('.','-')
}

# Appends the log time in front of the log statement with the color specified. 
function Log([string]$logStatement, [string]$color)
{
    if([string]::IsNullOrEmpty($color))
    {
        Write-Host "$($(Get-Date).ToString()): $logStatement"
    }
    else
    { 
        Write-Host "$($(Get-Date).ToString()): $logStatement" -ForegroundColor $color
    }
}

# Given a relative path, gets the absolute path from the current directory
function GetAbsolutePath([string]$Path)
{
    $Path = [System.IO.Path]::Combine((pwd).Path, $Path);
    $Path = [System.IO.Path]::GetFullPath($Path);
    return $Path;
}

# Writes the content to the given path. Creates the folder structure if needed
function OutFileWithCreateFolders([string]$path, [string]$content){
    $folder = [System.IO.Path]::GetDirectoryName($path)
    If(!(Test-Path $folder))
    {
        & New-Item -ItemType Directory -Force -Path $folder > $null
    }
    Add-Content -Path $path -Value $content
}

# Gets a list of all the files recursively in the given folder
Function GetFiles(
    [Parameter(Mandatory = $True)]
    [string] $folderPath,
    [string] $pattern)
{
    If (Test-Path $folderPath)
    {
        $files = Get-ChildItem -Path $folderPath -Filter $pattern -Recurse -File

        Return $files
    }

    Return $Null
}

# Gets a list of all the nupkgs recursively in the given folder
Function GetPackageFiles(
    [Parameter(Mandatory = $True)]
    [string] $folderPath)
{
    Return GetFiles $folderPath "*.nupkg"
}

Function GetFilesInfo([System.IO.FileInfo[]] $files)
{
    If ($files -eq $Null)
    {
        $count = 0
        $totalSizeInMB = 0
    }
    Else
    {
        $count = $files.Count
        $totalSizeInMB = ($files | Measure-Object -Property Length -Sum).Sum / 1000000
    }

    Return @{
        Count = $count
        TotalSizeInMB = $totalSizeInMB
    }
}

# Determines if the client is dotnet.exe by checking the path.
function GetClientName([string]$nugetClient)
{
    return [System.IO.Path]::GetFileName($nugetClient)
}

function IsClientDotnetExe([string]$nugetClient)
{
    return $nugetClient.EndsWith("dotnet.exe")
}

# Downloads the repository at the given path.
function DownloadRepository([string]$repository, [string]$commitHash, [string]$sourceDirectoryPath)
{
    if(Test-Path $sourceDirectoryPath)
    {
        Log "Skipping the cloning of $repository as $sourceDirectoryPath is not empty" -color "Yellow"
    }
    else 
    {
        git clone $repository $sourceDirectoryPath
        git -c $sourceDirectoryPath checkout $commitHash
    }
}
    
# Find the appropriate solution file for the repository. Looks for a solution file matching the repo name, 
# if not it takes the first available sln file in the repo. 
function GetSolutionFile([string]$repository,[string]$sourceDirectoryPath) {

    $gitRepoName = $repository.Substring($($repository.LastIndexOf('/') + 1))
    $potentialSolutionFile = [System.IO.Path]::Combine($sourceDirectoryPath, "$($gitRepoName.Substring(0, $gitRepoName.Length - 4)).sln")

    if(Test-Path $potentialSolutionFile)
    {
        $solutionFile = $potentialSolutionFile
    } 
    else 
    {
        $possibleSln = Get-ChildItem $sourceDirectoryPath *.sln
        if($possibleSln.Length -eq 0)
        {
            Log "No solution files found in $sourceDirectoryPath" "red"
        } 
        else 
        {
        $solutionFile = $possibleSln[0] | Select-Object -f 1 | Select-Object -ExpandProperty FullName
        }
    }
    return $solutionFile;
}

# Given a repository and a hash, checks out the revision in the given source directory. The return is a solution file if found. 
function SetupGitRepository([string]$repository, [string]$commitHash, [string]$sourceDirectoryPath)
{
    Log "Setting up $repository into $sourceDirectoryPath"
    DownloadRepository $repository $commitHash $sourceDirectoryPath
    $solutionFile = GetSolutionFile $repository $sourceDirectoryPath
    Log "Completed the repository setup. The solution file is $solutionFile" -color "Green"
    return $solutionFile
}

# runs locals clear all with the given client
function LocalsClearAll([string]$nugetClient)
{
    $nugetClient = GetAbsolutePath $nugetClient
    if($(IsClientDotnetExe $nugetClient))
    {
        . $nugetClient nuget locals -c all *>>$null
    } 
    else 
    {
        . $nugetClient locals -clear all -Verbosity quiet
    }
}

# Gets the client version
Function GetClientVersion([string] $nugetClientFilePath)
{
    $nugetClientFilePath = GetAbsolutePath $nugetClientFilePath

    If (IsClientDotnetExe $nugetClientFilePath)
    {
        $version = . $nugetClientFilePath --version
    }
    Else
    {
        $output = . $nugetClientFilePath
        $version = $(($output -split '\n')[0]).Substring("NuGet Version: ".Length)
    }

    Return $version
}

# Gets the NuGet folders path where all of the discardable data from the tests will be put.
Function GetNuGetFoldersPath([string] $testRootFolderPath)
{
    If ([string]::IsNullOrEmpty($testRootFolderPath))
    {
        $testRootFolderPath = $Env:UserProfile
    }

    $nugetFoldersPath = [System.IO.Path]::Combine($testRootFolderPath, "np")

    Return $nugetFoldersPath
}

# Sets up the global packages folder, http cache and plugin caches and cleans them before starting.
# TODO NK - How about temp?
Function SetupNuGetFolders([string] $nugetClientFilePath, [string] $testRootFolderPath)
{
    $nugetFoldersPath = GetNuGetFoldersPath $testRootFolderPath

    $Env:NUGET_PACKAGES = [System.IO.Path]::Combine($nugetFoldersPath, "gpf")
    $Env:NUGET_HTTP_CACHE_PATH = [System.IO.Path]::Combine($nugetFoldersPath, "hcp")
    $Env:NUGET_PLUGINS_CACHE_PATH = [System.IO.Path]::Combine($nugetFoldersPath, "pcp")

    LocalsClearAll $nugetClientFilePath
}

# Cleanup the nuget folders and delete the nuget folders path.
# This should only be invoked by the the performance tests
Function CleanNuGetFolders([string] $nugetClientFilePath, [string] $testRootFolderPath)
{
    Log "Cleanup up the NuGet folders - global packages folder, http/plugins caches"

    LocalsClearAll $nugetClientFilePath

    $nugetFoldersPath = GetNuGetFoldersPath $testRootFolderPath

    Remove-Item $nugetFoldersPath -Recurse -Force -ErrorAction Ignore

    [Environment]::SetEnvironmentVariable("NUGET_PACKAGES", $Null)
    [Environment]::SetEnvironmentVariable("NUGET_HTTP_CACHE_PATH", $Null)
    [Environment]::SetEnvironmentVariable("NUGET_PLUGINS_CACHE_PATH", $Null)
}

# Given a repository, a client and directories for the results/logs, runs the configured performance tests.
function RunPerformanceTestsOnGitRepository([string]$nugetClient, [string]$sourceRootDirectory, [string]$testCaseName, [string]$repoUrl,  [string]$commitHash, [string]$resultsFilePath, [string]$logsPath)
{
    $solutionFilePath = SetupGitRepository -repository $repoUrl -commitHash $commitHash -sourceDirectoryPath  $([System.IO.Path]::Combine($sourceRootDirectory, $testCaseName))
    SetupNuGetFolders $nugetClient
    . "$PSScriptRoot\RunPerformanceTests.ps1" $nugetClient $solutionFilePath $resultsFilePath $logsPath
}

Function GetProcessorInfo()
{
    $processorInfo = Get-WmiObject Win32_processor

    Return @{
        Name = $processorInfo | Select-Object -ExpandProperty Name
        NumberOfCores = $processorInfo | Select-Object -ExpandProperty NumberOfCores
        NumberOfLogicalProcessors = $processorInfo | Select-Object -ExpandProperty NumberOfLogicalProcessors
    }
}

Function LogDotNetSdkInfo()
{
    Try
    {
        $currentVersion = dotnet --version
        $currentSdk = dotnet --list-sdks | Where { $_.StartsWith("$currentVersion ") } | Select -First 1

        Log "Using .NET Core SDK $currentSdk."
    }
    Catch [System.Management.Automation.CommandNotFoundException]
    {
        Log ".NET Core SDK not found." -Color "Yellow"
    }
}

# Note:  System.TimeSpan rounds to the nearest millisecond.
Function ParseElapsedTime([decimal] $value, [string] $unit)
{
    Switch ($unit)
    {
        "ms" { Return [System.TimeSpan]::FromMilliseconds($value) }
        "sec" { Return [System.TimeSpan]::FromSeconds($value) }
        "min" { Return [System.TimeSpan]::FromMinutes($value) }
        Default { throw "Unsupported unit of time:  $unit" }
    }
}

Function ExtractRestoreElapsedTime(
    [Parameter(Mandatory = $True)]
    [string[]] $lines)
{
    $prefix = "Restore completed in "

    $lines = $lines | Where { $_.IndexOf($prefix) -gt -1 }

    ForEach ($line In $lines)
    {
        $index = $line.IndexOf($prefix)

        $parts = $line.Substring($index + $prefix.Length).Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries)

        $value = [System.Double]::Parse($parts[0])
        $unit = $parts[1]

        $temp = ParseElapsedTime $value $unit

        If ($elapsedTime -eq $Null -Or $elapsedTime -lt $temp)
        {
            $elapsedTime = $temp
        }
    }

    Return $elapsedTime
}