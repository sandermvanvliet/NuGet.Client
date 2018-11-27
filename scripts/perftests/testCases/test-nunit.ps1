Param(
    [Parameter(Mandatory=$true)]
    [string]$nugetClient,
    [Parameter(Mandatory=$true)]
    [string]$sourceRootDirectory,
    [Parameter(Mandatory=$true)]
    [string]$resultsDirectoryPath,
    [Parameter(Mandatory=$true)]
    [string]$logsPath,
    [Parameter(Mandatory=$false)]
    [string]$testNamePrefix,
    [Parameter(Mandatory=$false)]
    [int]$iterationCount = 1000
)


    . "$PSScriptRoot\..\PerformanceTestUtilities.ps1"
    
    $repoUrl = "https://github.com/cristinamanum/PerfTest.git"
    $testCaseName = GenerateNameFromGitUrl $repoUrl
    
    $resultsFilePath = [System.IO.Path]::Combine($resultsDirectoryPath, "Restore$testCaseName.csv")
    
    $solutionFilePath = SetupGitRepository -repository $repoUrl -commitHash $commitHash -sourceDirectoryPath  $([System.IO.Path]::Combine($sourceRootDirectory, $testCaseName))

    $name = "NUnit" + $testNamePrefix + $testCaseName
    $packageDownloadPath = "https://api.nuget.org/v3-flatcontainer/nunit/3.11.0/nunit.3.11.0.nupkg"
    # run only clean restore
    SetupNuGetFolders $nugetClient
    . "$PSScriptRoot\..\RunPerformanceTests.ps1" $nugetClient $solutionFilePath $resultsFilePath $packageDownloadPath $logsPath $name  -skipWarmup -skipColdRestores -skipForceRestores -skipNoOpRestores -iterationCount $iterationCount