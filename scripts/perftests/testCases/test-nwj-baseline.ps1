Param(
    [Parameter(Mandatory=$true)]
    [string]$nugetClient,
    [Parameter(Mandatory=$true)]
    [string]$sourceRootDirectory,
    [Parameter(Mandatory=$true)]
    [string]$resultsDirectoryPath,
    [Parameter(Mandatory=$true)]
    [string]$logsPath
)


    . "$PSScriptRoot\..\PerformanceTestUtilities.ps1"
    
    $repoUrl = "https://github.com/skofman1/PerfTest1.git"
    $testCaseName = GenerateNameFromGitUrl $repoUrl
    $resultsFilePath = [System.IO.Path]::Combine($resultsDirectoryPath, "$testCaseName.csv")
    
    $solutionFilePath = SetupGitRepository -repository $repoUrl -commitHash $commitHash -sourceDirectoryPath  $([System.IO.Path]::Combine($sourceRootDirectory, $testCaseName))

    SetupNuGetFolders $nugetClient
    . "$PSScriptRoot\..\RunPerformanceTests.ps1" $nugetClient $solutionFilePath $resultsFilePath $logsPath -skipColdRestores -skipForceRestores -skipNoOpRestores -iterationCount 100