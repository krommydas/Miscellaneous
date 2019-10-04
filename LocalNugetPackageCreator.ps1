 # Reference Source: https://www.clounce.com/dotnet/nuget-package-create-through-powershell
 #
 # Run Options: 
 #               1. Run from project parent folder (solution): ** input -projectFolder **
 #               2. Run from everywhere: ** input -projectFullPath **
 #               3. Run within project folder: ** no inputs **
 #
 # Prerequisites: 
 #
 #               1. Build the project in ** Release ** mode
 #               2. Install nuget CLI and make nuget command globaly available
 #
 # Nuget package information:
 #
 #               1. Inherit from AssemblyInfo file (it has to be detailed)
 #               2. Use your own (existing .nuspec file)
 #               3. Override default values (update created .nuspec file - have to rerun the script)
 #               4. Use default values (limited information)
 # 
 # Package ID (remember, it has to be UNIQUE -not Guid-):
 # https://docs.microsoft.com/en-us/nuget/create-packages/creating-a-package#choose-a-unique-package-identifier-and-setting-the-version-number
 # 
 #               1. AssmblyTitle from AssemblyInfo file (default option)
 #               2. Project name (default option, if AssemblyTitle missing)
 #               3. Use your own (you have to provide your own nuspec file or edit the default one)
 #               4. Prefix default name with domain or company name - Recommended!!
 #
 # Package ID validations:
 #
 #               1. Unique in name and version in local server 
 #               2. Unique in name (irrespectively version) on nuget server
 #
 # Final successfull result: Package uploaded to local nuget server (NOT in nuget.org)
 
 
 param ([string]$projectFolder, [string]$projectFullPath)

$truthStatemens = "yes", "y", "YES", "Y"
$falseStatemens = "no", "n", "NO", "N"
$localNugetServerKey = ""
$localNugetServerUrl = ""
$nugetServerTestPackage = "Newtonsoft";
$packageDomainPrefix = "";

function terminateSafely([string]$message){
write-host "$message`n"
exit
}

Try
{

[object] $projectLocation

if([string]::IsNullOrEmpty($projectFullPath) -ne $true) { $projectLocation = resolve-path $projectFullPath }
elseif([string]::IsNullOrEmpty($projectFolder) -ne $true) { $projectLocation = join-path -path $PSScriptRoot -childpath $projectFolder }
else { $projectLocation = $PSScriptRoot }

Set-Location $projectLocation -EA SilentlyContinue

$projectFile = get-childitem *.csproj
if($projectFile -eq $null)
  { terminateSafely -message "`nproject file not found" }

$useDefaultNuspec = $false
$nuspecFile = get-childitem *.nuspec
if($nuspecFile -ne $null)
 {
     $confirmation = Read-Host "`nA nuspec file was found. Do you want to use it (y/n) ?`nIf you do not know what this is or it is the first time you land here select no(n)"
	 
	 write-host ""
	 
	 $useDefaultNuspec = $confirmation -in $truthStatemens
 }
 else 
 {
 write-host "" 
 }

$version = ''

if($useDefaultNuspec -eq $false)
{
$projectName = [System.IO.Path]::GetFileNameWithoutExtension($projectFile)
$projectDLL = $projectName + ".dll"

$projectDLLFile = get-childitem -path "$projectLocation\bin\Release\" -include "$projectDLL" -recurse -EA SilentlyContinue
if($projectDLLFile -eq $null)
   {terminateSafely -message "you have to build the project in release mode" }

$nugetCommand = get-command nuget -EA SilentlyContinue
if($nugetCommand -eq $null)
 {terminateSafely -message "you have to install nuget" }

nuget spec $projectFile -AssemblyPath "$projectDLLFile" -force | Out-Null
$nuspecFile = get-childitem *.nuspec

$confirmation = Read-Host "The nuspec file (nuget package details manifest) was created. If you want to edit the default values select 'yes'/'y'`nIn that case, edit the file and re-run the script (y/n)"
 
write-host "" 
 
if($confirmation -in $truthStatemens)
   { terminateSafely -message "The script will terminate. Please update the nuspec file (found at the project folder))" }

[xml]$nuspecXml = Get-Content $nuspecFile -EA Stop

$metadataNode = $nuspecXml.SelectSingleNode('package/metadata')
$version = $metadataNode.SelectSingleNode('version').InnerText

$metadataNode.RemoveChild($metadataNode.SelectSingleNode('licenseUrl'))| out-null
$metadataNode.RemoveChild($metadataNode.SelectSingleNode('projectUrl'))| out-null
$metadataNode.RemoveChild($metadataNode.SelectSingleNode('iconUrl'))| out-null
$metadataNode.RemoveChild($metadataNode.SelectSingleNode('releaseNotes'))| out-null
$metadataNode.RemoveChild($metadataNode.SelectSingleNode('dependencies'))| out-null
$metadataNode.RemoveChild($metadataNode.SelectSingleNode('tags')) | out-null

$confirmation = Read-Host "Do you want to prefix the package name with $packageDomainPrefix (y/n)? `nRemember, package names have to be unique (across all nuget sources)! "
if($confirmation -in $truthStatemens)
{ $metadataNode.SelectSingleNode('id').InnerText = $packageDomainPrefix + '.' + $projectName; }

write-host "" 

$id = $metadataNode.SelectSingleNode('id').InnerText 

$nuspecXml.Save("$nuspecFile") | out-null
}
else
{
[xml]$nuspecXml = Get-Content $nuspecFile

if($nuspecXml -eq $null)  
{ terminateSafely("The .nuspec file seems to be corrupted. Please, fix it and re run the script`n(or override it using the script default settings)") }

$metadataNode = $nuspecXml.SelectSingleNode('package/metadata')
if($metadataNode -eq $null)  
{ terminateSafely("The .nuspec file seems to be corrupted. Please, fix it and re run the script`n(or override it using the script default settings)") }

$version = $metadataNode.SelectSingleNode('version').InnerText 
$id = $metadataNode.SelectSingleNode('id').InnerText 
}

if($version.StartsWith("0"))
{ terminateSafely("You have to define a package (Assembly) version starting from 1 (1.XXX)") }

write-host "Creating the package.. `n"

nuget pack $nuspecFile -properties Configuration=Release | Out-Null

$nugetPackage = get-childitem "$id.$version.nupkg" -EA Stop

write-host "Checking for existing package versions, please hold.. `n"

$existingPackageWithSameVersionOnLocalServer = find-package $id -source $localNugetServerUrl -allversions -ErrorAction Ignore | Where-Object { $_.Version -eq $version }
if($existingPackageWithSameVersionOnLocalServer -ne $null)
 { terminateSafely("A package with the same version already exists in the local nuget server. `nPlease change the assembly version and re run the script") }

#check a very popular package existence to verify that the nuget source has been correctly configured in the system
$nugetServerTestFindings = find-package -filter $nugetServerTestPackage -provider NuGet -ErrorAction Ignore
if(($nugetServerTestFindings -eq 0) -or ($nugetServerTestFindings -eq $null))
 { write-host "Could not check package name uniqueness on nuget server, please check yourself!`n" }
else
{
 $existingPackageOnNugetServer = find-package $id -provider NuGet -AllVersions -ErrorAction Ignore | Select-object -first 1
 if($existingPackageOnNugetServer -ne $null)
  { terminateSafely("A package with the same name already exists in the nuget server. `nPlease use ProfileSW prefix option or make package name unique") }
}

write-host "Pushing package to server, please hold.."

nuget push $nugetPackage.name $localNugetServerKey -Source $localNugetServerUrl | Out-Null

Remove-Item $nuspecFile;

terminateSafely("`nPackage was successfully uploaded")
}
Catch
{
  #Write-Host $_.Exception.Message
  #Write-Host $_.ScriptStackTrace
  
  terminateSafely("something went wrong, please contact someone responsible with the local nuget server")
}
Finally
{
set-location $PSScriptRoot | out-null
}
