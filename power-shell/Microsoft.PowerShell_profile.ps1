Clear-Host

Import-Module PSReadLine
Set-PSReadLineOption -PredictionSource History
Set-PSReadLineOption -PredictionViewStyle ListView
Set-PSReadLineOption -Colors @{
    Command = 'White'
    Parameter = 'White'
    Operator = 'White'
    Variable = 'White'
    String = 'White'
    Number = 'White'
    Comment = 'DarkGray'
    Error = 'Red'
    InlinePrediction = 'DarkGray'
    ListPrediction = 'DarkGray'
}

function prompt {
    $Esc = [char]27
    $Reset = "${Esc}[0m"

    $Green = "${Esc}[32m"
    $White = "${Esc}[37m"
    $Blue  = "${Esc}[36m"

    $user = $env:USERNAME
    $currentPath = (Get-Location).Path
    $psVersion = $PSVersionTable.PSVersion.ToString()

    $homePath = $env:USERPROFILE
    if ($currentPath.StartsWith($homePath)) {
        $currentPath = $currentPath.Replace($homePath, "~")
    }

    $pathParts = $currentPath -split '[/\\]'

    if ($pathParts.Length -gt 1) {
        $abbreviatedParts = @()

        $abbreviatedParts += $pathParts[0]

        for ($i = 1; $i -lt $pathParts.Length - 1; $i++) {
            if ($pathParts[$i] -ne "") {
                $abbreviatedParts += $pathParts[$i].Substring(0, 1)
            }
        }

        if ($pathParts[-1] -ne "") {
            $abbreviatedParts += $pathParts[-1]
        }

        $location = $abbreviatedParts -join "/"
    } else {
        $location = $currentPath
    }

    return "$Green@Windows(PowerShell $psVersion) $White$location`n$ $Reset"
}

function .. {
    Set-Location ..
}

function ... {
    Set-Location ../..
}

Set-PSReadlineKeyHandler -Key "Ctrl+;" -Function BeginningOfLine
Set-PSReadlineKeyHandler -Key "Ctrl+'" -Function EndOfLine
