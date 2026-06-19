[CmdletBinding()]
param(
    [string]$ResourceGroupName = 'b2b2carchitecture',
    [string]$Location = 'westus',
    [string]$TemplateFile = '.\main.bicep',
    [string]$DeploymentName = 'b2b2carchitecture-static-site'
)

$ErrorActionPreference = 'Stop'

function Assert-CommandAvailable {
    param([Parameter(Mandatory)][string]$Name)

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' was not found on PATH."
    }
}

Assert-CommandAvailable -Name 'az'

$templatePath = Resolve-Path -Path $TemplateFile
$sourcePath = Split-Path -Parent $templatePath

function Invoke-Az {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    $output = & az @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI command failed: az $($Arguments -join ' ')"
    }

    return $output
}

Write-Host 'Checking Azure CLI account...'
Invoke-Az -Arguments @('account', 'show', '--query', '{subscription:name, user:user.name, subscriptionId:id}', '-o', 'table')

Write-Host 'Checking Bicep CLI...'
$bicepVersion = & az bicep version 2>$null
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($bicepVersion)) {
    Write-Host 'Installing Bicep CLI for Azure CLI...'
    Invoke-Az -Arguments @('bicep', 'install')
}

Write-Host 'Validating Bicep template...'
Invoke-Az -Arguments @(
    'deployment', 'sub', 'validate',
    '--name', $DeploymentName,
    '--location', $Location,
    '--template-file', $templatePath,
    '--parameters', "resourceGroupName=$ResourceGroupName", "location=$Location",
    '-o', 'table'
)

Write-Host 'Deploying Azure resources...'
$deploymentJson = Invoke-Az -Arguments @(
    'deployment', 'sub', 'create',
    '--name', $DeploymentName,
    '--location', $Location,
    '--template-file', $templatePath,
    '--parameters', "resourceGroupName=$ResourceGroupName", "location=$Location",
    '-o', 'json'
)

$deployment = $deploymentJson | ConvertFrom-Json
$storageAccountName = $deployment.properties.outputs.storageAccountName.value

if ([string]::IsNullOrWhiteSpace($storageAccountName)) {
    throw 'Deployment did not return a storageAccountName output.'
}

Write-Host "Enabling static website hosting on storage account '$storageAccountName'..."
Invoke-Az -Arguments @(
    'storage', 'blob', 'service-properties', 'update',
    '--account-name', $storageAccountName,
    '--static-website',
    '--index-document', 'index.html',
    '--404-document', 'index.html',
    '--auth-mode', 'key',
    '-o', 'table'
)

Write-Host "Uploading index.html to storage account '$storageAccountName'..."
Invoke-Az -Arguments @(
    'storage', 'blob', 'upload-batch',
    '--account-name', $storageAccountName,
    '--auth-mode', 'key',
    '--destination', '$web',
    '--source', $sourcePath,
    '--pattern', 'index.html',
    '--overwrite', 'true',
    '-o', 'table'
)

$staticWebsiteEndpoint = Invoke-Az -Arguments @(
    'storage', 'account', 'show',
    '--resource-group', $ResourceGroupName,
    '--name', $storageAccountName,
    '--query', 'primaryEndpoints.web',
    '-o', 'tsv'
)

Write-Host ''
Write-Host 'Deployment complete.'
Write-Host "Resource group: $ResourceGroupName"
Write-Host "Storage account: $storageAccountName"
Write-Host "Website URL: $staticWebsiteEndpoint"
