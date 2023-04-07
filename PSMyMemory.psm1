$script:LanguagesCsv = ConvertFrom-Csv -InputObject (Get-Content "$PSScriptRoot/Languages.csv" -Raw)

$LanguageToCode = @{}
$CodeToLanguage = @{}

foreach ($row in $script:LanguagesCsv)
{
    $LanguageToCode[$row.Language] = $row.CountryLanguageCode
    $CodeToLanguage[$row.CountryLanguageCode] = $row.Language
    $CodeToLanguage[$row.LanguageCode] = $row.Language
}

$script:PairOfSourceLanguageAndCode = $script:LanguagesCsv | ForEach-Object { $_.Language, $_.CountryLanguageCode }
$script:PairOfTargetLanguageAndCode = $script:LanguagesCsv | Where-Object { $_.CountryLanguageCode -ne 'Autodetect' } | ForEach-Object { $_.Language, $_.CountryLanguageCode } 

class SourceLanguage : System.Management.Automation.IValidateSetValuesGenerator
{
    [String[]] GetValidValues()
    {
        return $script:PairOfSourceLanguageAndCode
    }
}

class TargetLanguage : System.Management.Automation.IValidateSetValuesGenerator
{
    [String[]] GetValidValues()
    {
        return $script:PairOfTargetLanguageAndCode
    }
}


<#
    .DESCRIPTION
    A function that uses the free MyMemory translation API.

    .PARAMETER InputObject
    Text to translate.

    .PARAMETER SourceLanguage
    Source language as code or English word.

    .PARAMETER TargetLanguage
    Target language as code or English word.

    .PARAMETER AvailableLanguages
    Return an array with all the available languages with the English name and country-language code.

    .OUTPUTS
    PSCustomObject
    PSCustomObject[]

    .NOTES
    More information on https://mymemory.translated.net/doc/spec.php
#>
function Invoke-MyMemory
{
    [OutputType([PSCustomObject], [PSCustomObject[]])]
    param
    (
        [Alias('Query')]
        [ValidateLength(1, 500)]
        [Parameter(Mandatory=$true, ParameterSetName='Translation')]
        [string] $InputObject,

        [Alias('From')]
        [ValidateSet([SourceLanguage])]
        [Parameter(ParameterSetName='Translation')]
        [string] $SourceLanguage = 'Autodetect',

        [Alias('To')]
        [ValidateSet([TargetLanguage])]
        [Parameter(ParameterSetName='Translation')]
        [string] $TargetLanguage,

        [ValidateSet('Translation', 'DetectedLanguage')]
        [Parameter(ParameterSetName='Translation')]
        [string] $ReturnType = 'Translation',

        [Parameter(ParameterSetName='AvailableLanguages')]
        [switch] $AvailableLanguages
    )

    if ($AvailableLanguages)
    {
        return $script:LanguagesCsv
    }

    if ($ReturnType -in $ListOfReturnTypeThatTheTargetLanguageIsRequired -and -not $TargetLanguage)
    {
        Write-Error "You must specify a the TargetLanguage if the ReturnType is '$ReturnType'."
    }

    $sourceLanguageCode, $targetCountryLanguageCode = TryConvertLanguageToCode $SourceLanguage $TargetLanguage

    $query = [uri]::EscapeDataString($InputObject)

    $uri = "https://api.mymemory.translated.net/get?q=$query&langpair=$sourceLanguageCode|$targetCountryLanguageCode"

    $response = Invoke-WebRequest -Uri $uri -Method Get

    Write-Verbose -Message $response.Content

    $data = $response.Content | ConvertFrom-Json

    $detectedLanguage = $data.responseData.detectedLanguage

    $sourceLanguageAndCountryCodes = $detectedLanguage ? $detectedLanguage : $sourceLanguageCode

    $actualSourceLanguage, $actualSourceCountry = $sourceLanguageAndCountryCodes.Split('-')

    if ($ReturnType -eq 'DetectedLanguage')
    {
        return [PSCustomObject]@{
            SourceLanguage              = $actualSourceLanguage
            SourceLanguageAsEnglishWord = $CodeToLanguage[$actualSourceLanguage]
        }
    }

    return [PSCustomObject]@{
        Translation                 = $data.responseData.translatedText
        SourceLanguage              = $actualSourceLanguage
        SourceCountry               = $actualSourceCountry
        SourceCountryLanguage       = $sourceLanguageAndCountryCodes
        SourceLanguageAsEnglishWord = $CodeToLanguage[$actualSourceLanguage]
        TargetCountryLanguage       = $targetCountryLanguageCode
        TargetLanguageAsEnglishWord = $CodeToLanguage[$targetCountryLanguageCode]

        Matches = $data.matches | ForEach-Object {

                $splittedSourceLanguageCode, $splittedSourceCountryCode = $_.source ? $_.source.Split('-') : ''
                $splittedTargetLanguageCode, $splittedTargetCountryCode = $_.target ? $_.target.Split('-') : ''

                [PSCustomObject]@{
                    Segment                     = $_.segment
                    Translation                 = $_.translation
                    SourceLanguage              = $splittedSourceLanguageCode
                    SourceLanguageAsEnglishWord = $CodeToLanguage[$splittedSourceLanguageCode]
                    SourceCountry               = $splittedSourceCountryCode
                    SourceLanguageAndCountry    = $_.source ? $_.source : ''
                    TargetLanguage              = $splittedTargetLanguageCode
                    TargetLanguageAsEnglishWord = $CodeToLanguage[$splittedTargetLanguageCode]
                    TargetCountry               = $splittedTargetCountryCode
                    TargetLanguageAndCountry    = $_.target
                }
            }
    }
}



function TryConvertLanguageToCode([string] $SourceLanguage, [string] $TargetLanguage)
{
    $languageCodes = @($SourceLanguage, $TargetLanguage)

    if ($LanguageToCode.ContainsKey($SourceLanguage))
    {
        $languageCodes[0] = $LanguageToCode[$SourceLanguage]
    }
    if ($LanguageToCode.ContainsKey($TargetLanguage))
    {
        $languageCodes[1] = $LanguageToCode[$TargetLanguage]
    }

    return $languageCodes
}


$ListOfReturnTypeThatTheTargetLanguageIsRequired = @('Translation')



Export-ModuleMember -Function *-*
