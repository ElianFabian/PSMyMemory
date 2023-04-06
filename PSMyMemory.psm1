$global:languagesCsv = ConvertFrom-Csv -InputObject (Get-Content "$PSScriptRoot/Languages.csv" -Raw)

$languageToCode = @{}
$codeToLanguage = @{}
foreach ($row in $global:languagesCsv)
{
    $languageToCode[$row.Language] = $row.CountryLanguageCode
    $codeToLanguage[$row.CountryLanguageCode] = $row.Language

    $languageCode = $row.CountryLanguageCode.Split('-')[0]

    $codeToLanguage[$languageCode] = $row.Language
}

$global:pairOfSourceLanguageAndCode = $global:languagesCsv | ForEach-Object { $_.Language, $_.CountryLanguageCode }
$global:pairOfTargetLanguageAndCode = $global:languagesCsv | Where-Object { $_.CountryLanguageCode -ne 'Autodetect' } | ForEach-Object { $_.Language, $_.CountryLanguageCode } 

class SourceLanguage : System.Management.Automation.IValidateSetValuesGenerator
{
    [String[]] GetValidValues()
    {
        return $global:pairOfSourceLanguageAndCode
    }
}

class TargetLanguage : System.Management.Automation.IValidateSetValuesGenerator
{
    [String[]] GetValidValues()
    {
        return $global:pairOfTargetLanguageAndCode
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

    .OUTPUTS
    PSCustomObject

    .NOTES
    More information on https://mymemory.translated.net/doc/spec.php
#>
function Invoke-MyMemory
{
    param
    (
        [Alias('Query')]
        [ValidateLength(1, 500)]
        [Parameter(Mandatory=$true)]
        [string] $InputObject,

        [Alias('From')]
        [ValidateSet([SourceLanguage])]
        [string] $SourceLanguage = 'Autodetect',

        [Alias('To')]
        [ValidateSet([TargetLanguage])]
        [string] $TargetLanguage,

        [ValidateSet('Translation', 'DetectedLanguage')]
        [string] $ReturnType = 'Translation'
    )

    if ($ReturnType -in $ListOfReturnTypeThatTheTargetLanguageIsRequired -and -not $TargetLanguage)
    {
        Write-Error "You must specify a the TargetLanguage if the ReturnType is '$ReturnType'."
    }

    $sourceLanguageCode, $targetLanguageCode = TryConvertLanguageToCode $SourceLanguage $TargetLanguage

    $query = [uri]::EscapeDataString($InputObject)

    $uri = "https://api.mymemory.translated.net/get?q=$query&langpair=$sourceLanguageCode|$targetLanguageCode"

    $response = Invoke-WebRequest -Uri $uri -Method Get

    Write-Verbose -Message $response.Content

    $data = $response.Content | ConvertFrom-Json

    $detectedLanguage = $data.responseData.detectedLanguage

    $sourceLanguageAndCountryCodes = $detectedLanguage ? $detectedLanguage : $sourceLanguageCode

    $sourceDetectedLanguage, $sourceDetectedCountry = $sourceLanguageAndCountryCodes.Split('-')

    if ($ReturnType -eq 'DetectedLanguage')
    {
        return [PSCustomObject]@{
            SourceLanguage              = $sourceDetectedLanguage
            SourceLanguageAsEnglishWord = $codeToLanguage[$sourceDetectedLanguage]
        }
    }

    return [PSCustomObject]@{
        Translation                 = $data.responseData.translatedText
        SourceLanguage              = $sourceDetectedLanguage
        SourceLanguageAsEnglishWord = $codeToLanguage[$sourceDetectedLanguage]
        TargetCountry               = $targetLanguageCode
        TargetLanguageAndCountry    = $codeToLanguage[$targetLanguageCode]

        Matches = $data.matches | ForEach-Object {

                $splittedSourceLanguageCode, $splittedSourceCountryCode = $_.source ? $_.source.Split('-') : ''
                $splittedTargetLanguageCode, $splittedTargetCountryCode = $_.target ? $_.target.Split('-') : ''

                [PSCustomObject]@{
                    Segment                     = $_.segment
                    Translation                 = $_.translation
                    SourceLanguage              = $splittedSourceLanguageCode
                    SourceLanguageAsEnglishWord = $codeToLanguage[$splittedSourceLanguageCode]
                    SourceCountry               = $splittedSourceCountryCode
                    SourceLanguageAndCountry    = $_.source ? $_.source : ''
                    TargetLanguage              = $splittedTargetLanguageCode
                    TargetLanguageAsEnglishWord = $codeToLanguage[$splittedTargetLanguageCode]
                    TargetCountry               = $splittedTargetCountryCode
                    TargetLanguageAndCountry    = $_.target
                }
            }
    }
}



function TryConvertLanguageToCode([string] $SourceLanguage, [string] $TargetLanguage)
{
    $languageCodes = @($SourceLanguage, $TargetLanguage)

    if ($languageToCode.ContainsKey($SourceLanguage))
    {
        $languageCodes[0] = $languageToCode[$SourceLanguage]
    }
    if ($languageToCode.ContainsKey($TargetLanguage))
    {
        $languageCodes[1] = $languageToCode[$TargetLanguage]
    }

    return $languageCodes
}


$ListOfReturnTypeThatTheTargetLanguageIsRequired = @('Translation')



Export-ModuleMember -Function *-*
