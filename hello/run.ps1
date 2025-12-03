using namespace System.Net
# Simple Hello World function to test Flex Consumption runtime
param($Request, $TriggerMetadata)

Write-Host "Hello World function triggered!"

$name = $Request.Query.name
if (-not $name) {
    $name = $Request.Body.name
}

if (-not $name) {
    $name = "World"
}

$responseBody = @{
    message = "Hello, $name!"
    timestamp = (Get-Date).ToString('o')
    functionApp = $env:WEBSITE_SITE_NAME
    status = "success"
}

Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [System.Net.HttpStatusCode]::OK
    Body = $responseBody
})