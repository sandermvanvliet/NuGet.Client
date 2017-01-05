﻿// Copyright (c) .NET Foundation. All rights reserved.
// Licensed under the Apache License, Version 2.0. See License.txt in the project root for license information.

using System;
using System.Collections.Generic;
using System.IO;
using Microsoft.Extensions.CommandLineUtils;
using Moq;
using NuGet.CommandLine.XPlat;
using NuGet.Packaging;
using NuGet.Test.Utility;
using Xunit;

namespace NuGet.XPlat.FuncTest
{
    public class XPlatRemovePkgTests
    {
        private static readonly string projectName = "test_project_removepkg";

        private static MSBuildAPIUtility MsBuild
        {
            get { return new MSBuildAPIUtility(new TestCommandOutputLogger()); }
        }

        // Argument parsing related tests

        [Theory]
        [InlineData("--package", "package_foo", "--project", "project_foo.csproj")]
        [InlineData("--package", "package_foo", "-p", "project_foo.csproj")]
        public void AddPkg_ArgParsing(string packageOption, string package,
            string projectOption, string project)
        {
            // Arrange
            var projectPath = Path.Combine(Path.GetTempPath(), project);
            File.Create(projectPath).Dispose();
            var argList = new List<string>() {
                "remove",
                packageOption,
                package,
                projectOption,
                projectPath};

            var logger = new TestCommandOutputLogger();
            var testApp = new CommandLineApplication();
            var mockCommandRunner = new Mock<IPackageReferenceCommandRunner>();
            mockCommandRunner
                .Setup(m => m.ExecuteCommand(It.IsAny<PackageReferenceArgs>(), It.IsAny<MSBuildAPIUtility>()))
                .ReturnsAsync(0);

            testApp.Name = "dotnet nuget_test";
            RemovePackageReferenceCommand.Register(testApp,
                () => logger,
                () => mockCommandRunner.Object);

            // Act
            var result = testApp.Execute(argList.ToArray());

            XPlatTestUtils.DisposeTemporaryFile(projectPath);

            // Assert
            mockCommandRunner.Verify(m => m.ExecuteCommand(It.Is<PackageReferenceArgs>(p =>
            p.PackageDependency.Id == package &&
            p.ProjectPath == projectPath),
            It.IsAny<MSBuildAPIUtility>()));

            Assert.Equal(0, result);
        }

        // Remove Related Tests

        [Fact]
        public async void RemovePkg_UnconditionalRemove_Success()
        {
            // Arrange

            using (var pathContext = new SimpleTestPathContext())
            {
                // Generate Package
                var packageX = XPlatTestUtils.CreatePackage();
                await SimpleTestPackageUtility.CreateFolderFeedV3(
                    pathContext.PackageSource,
                    PackageSaveMode.Defaultv3,
                    packageX);

                var projectA = XPlatTestUtils.CreateProject(projectName, pathContext, packageX, "net46");

                // Verify that the package reference exists before removing.
                var projectXmlRoot = XPlatTestUtils.LoadCSProj(projectA.ProjectPath).Root;
                var itemGroup = XPlatTestUtils.GetItemGroupForAllFrameworks(projectXmlRoot);

                Assert.NotNull(itemGroup);
                Assert.True(XPlatTestUtils.ValidateReference(itemGroup, packageX.Id, "1.0.0"));

                var packageArgs = XPlatTestUtils.GetPackageReferenceArgs(packageX.Id, projectA);
                var commandRunner = new RemovePackageReferenceCommandRunner();

                // Act
                var result = commandRunner.ExecuteCommand(packageArgs, MsBuild).Result;
                projectXmlRoot = XPlatTestUtils.LoadCSProj(projectA.ProjectPath).Root;

                // Assert
                Assert.Equal(0, result);
                Assert.True(XPlatTestUtils.ValidateNoReference(projectXmlRoot, packageX.Id));
            }
        }

        [Fact]
        public void RemovePkg_RemoveInvalidPackage_Failure()
        {
            // Arrange

            var unknownPackageId = "package_foo";
            using (var pathContext = new SimpleTestPathContext())
            {
                var projectA = XPlatTestUtils.CreateProject(projectName, pathContext, "net46");

                var packageArgs = XPlatTestUtils.GetPackageReferenceArgs(unknownPackageId, projectA);
                var commandRunner = new RemovePackageReferenceCommandRunner();
                var projectXmlRoot = XPlatTestUtils.LoadCSProj(projectA.ProjectPath).Root;

                Assert.True(XPlatTestUtils.ValidateNoReference(projectXmlRoot, unknownPackageId));
                var msBuild = MsBuild;

                // Act
                var result = commandRunner.ExecuteCommand(packageArgs, msBuild).Result;
                projectXmlRoot = XPlatTestUtils.LoadCSProj(projectA.ProjectPath).Root;

                // Assert
                Assert.Equal(1, result);
                Assert.True(XPlatTestUtils.ValidateNoReference(projectXmlRoot, unknownPackageId));
            }
        }

        [Theory]
        [InlineData("net46")]
        [InlineData("netcoreapp1.0")]
        public async void RemovePkg_ConditionalRemove_Success(string packageframework)
        {
            // Arrange

            using (var pathContext = new SimpleTestPathContext())
            {
                // Generate Package
                var packageX = XPlatTestUtils.CreatePackage(frameworkString: packageframework);
                await SimpleTestPackageUtility.CreateFolderFeedV3(
                    pathContext.PackageSource,
                    PackageSaveMode.Defaultv3,
                    packageX);

                var projectA = XPlatTestUtils.CreateProject(projectName, pathContext, packageX, "net46; netcoreapp1.0", packageframework);

                // Verify that the package reference exists before removing.
                var projectXmlRoot = XPlatTestUtils.LoadCSProj(projectA.ProjectPath).Root;
                var itemGroup = XPlatTestUtils.GetItemGroupForFramework(projectXmlRoot, packageframework);

                Assert.NotNull(itemGroup);
                Assert.True(XPlatTestUtils.ValidateReference(itemGroup, packageX.Id, "1.0.0"));

                var packageArgs = XPlatTestUtils.GetPackageReferenceArgs(packageX.Id, projectA);
                var commandRunner = new RemovePackageReferenceCommandRunner();

                // Act
                var result = commandRunner.ExecuteCommand(packageArgs, MsBuild).Result;
                projectXmlRoot = XPlatTestUtils.LoadCSProj(projectA.ProjectPath).Root;

                // Assert
                Assert.Equal(0, result);
                Assert.True(XPlatTestUtils.ValidateNoReference(projectXmlRoot, packageX.Id));
            }
        }
    }
}