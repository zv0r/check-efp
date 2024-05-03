<#
.DESCRIPTION
Проверка загруженного ЭФП в хранилищах ГКУ ЯО ГАЯО на корректность файловой стрктуры.
При наличии на компьютере бибилотеки ImageMagick может проверить корректность файлов изображений

.NOTES  
Author: Andrey Zvorygin
Version: 1.0.2 (2024-05-03) 

.PARAMETER Path
Список каталогов, в которых находится ЭФП, который нужно проверить

.PARAMETER DestinationPath
Список каталогов, в которых находится обработанный ЭФП. Если этот параметр указан, то происходит проверка наличия проверяемого дела в хранилище

.PARAMETER FileExtensions
Список допустимых расширений файлов

.PARAMETER NumberLength
Количество цифр в номере файла (лишнее дополняется ведущими нулями)

.PARAMETER AddPrefix
Нужно ли добавлять префикс. Если указано, то к имени файла нужно будет добавлять имя родительского каталога и префикс из параметра ArchivePrefix

.PARAMETER ArchivePrefix
Префикс архива. Указывается только совместно с параметром AddPrefix

.PARAMETER FundMask
Маска имени директории фонда в формате regex. Символы ^ и $ указывать не нужно

.PARAMETER InventoryMask
Маска имени директории описи в формате regex, при проверке складывается с параметром FundMask. Символы ^ и $ указывать не нужно

.PARAMETER UnitMask
Маска имени директории дела в формате regex, при проверке складывается с параметрами FundMask и InventoryMask. Символы ^ и $ указывать не нужно

.PARAMETER CheckImageFiles
Нужно ли проверять файлы изображений на корректность

.PARAMETER ImageMagickDirectory
Путь до директории с исполняемыми файлами ImageMagick, указывается только совместно с параметром CheckImageFiles

.PARAMETER ErrorLogPath
Путь к файлу с журналом ошибок

.PARAMETER ContinueOnError
Продолжить проверку ЭФП при ошибке
#> 

#requires -PSEdition Core

param (
    [Parameter(Mandatory = $true)] [string[]]$Path,
    [Parameter(Mandatory = $false)] [string[]]$DestinationPath,
    [Parameter(Mandatory = $false)] [string[]]$FileExtensions = @(".jpg"),
    [Parameter(Mandatory = $false)] [int]$NumberLength = 6,
    [Parameter(Mandatory = $false)] [switch]$AddPrefix,
    [Parameter(Mandatory = $false)] [string]$ArchivePrefix = "GAYO",
    [Parameter(Mandatory = $false)] [string]$FundMask = "(Р-)?[0-9]+(_[А-Я])?",
    [Parameter(Mandatory = $false)] [string]$InventoryMask = "[0-9]+(_[А-Я]+)?",
    [Parameter(Mandatory = $false)] [string]$UnitMask = "[0-9]+(_[А-Я]+)?",
    [Parameter(Mandatory = $false)] [string]$DirectoryDelimiter = "-",
    [Parameter(Mandatory = $false)] [switch]$CheckImageFiles,
    [Parameter(Mandatory = $false)] [string]$ImageMagickDirectory,
    [Parameter(Mandatory = $false)] [string]$ErrorLogPath,
    [Parameter(Mandatory = $false)] [switch]$ContinueOnError = $false
)

$NaturalSort = { [regex]::Replace($_, '\d+', { $args[0].Value.PadLeft(20) }) }
$InventoryMask = $FundMask + $DirectoryDelimiter + $InventoryMask
$UnitMask = $InventoryMask + $DirectoryDelimiter + $UnitMask
if ($CheckImageFiles) {
    $ImageMagickExecutablePath = $ImageMagickDirectory ? (Join-Path -Path "${ImageMagickDirectory}" -ChildPath "magick.exe") : (Get-Command -Name "magick.exe" -ErrorAction Stop).Path
}

function Show-Check-Error {
    param(
        [Parameter(Mandatory = $true)] $Message,
        [Parameter(Mandatory = $false)] [switch]$ForceContinue = $false
    )

    $Message = "[" + (Get-Date).ToString() + "] " + $Message

    Write-Error "${Message}"
    if ($ErrorLogPath) {
        Add-Content -Path "${ErrorLogPath}" -Value "${Message}"
    }
    if ((-not $ContinueOnError) -and (-not $ForceContinue)) {
        throw
    }
}

function Get-SortedDirectory {
    param(
        [Parameter(Mandatory = $true)] $Path
    )

    return Get-ChildItem -ErrorAction Stop -Force -Path "${Path}" | Sort-Object $NaturalSort
}

function Test-Directory {
    param(
        [Parameter(Mandatory = $true)] $Path,
        [Parameter(Mandatory = $true)] $Mask,
        [Parameter(Mandatory = $true)] $StartsWith
    )
    
    Write-Host "Checking ${Path}"

    $Directory = [System.IO.DirectoryInfo]"${Path}"

    if (-not $Directory.Exists) {
        Show-Check-Error -Message "${Directory} is not a directory"
    }
    if (-not ($Directory.Name -cmatch "^${Mask}$")) {
        Show-Check-Error -Message "${Directory} does not match pattern ${Mask}"
    }
    if (-not ($Directory.BaseName.StartsWith($StartsWith))) {
        Show-Check-Error -Message "${Directory} name should starts with ${StartsWith}"
    }
    if ((Get-ChildItem -ErrorAction Stop -Path "${_}" | Measure-Object).Count -eq 0) {
        Show-Check-Error -Message "${Directory} is empty"
    }
}

function Test-Images {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true)] $ImageFile
    )

    Begin {
        $ImageIndex = 0
    }

    Process {
        $File = [System.IO.FileInfo]$ImageFile
        Write-Verbose -Message "Checking ${File}"

        if (-not $File.Exists) {
            Show-Check-Error -Message "${File} is not a file"
        }
        if (-not ($FileExtensions -cmatch "\$($File.Extension)")) {
            Show-Check-Error -Message "${File} has incorrect extension $($File.Extension). It should be ${FileExtensions}"
        }

        $ParentDirectoryName = ([System.IO.DirectoryInfo](Split-Path -Path "${ImageFile}")).BaseName
        $FileNamePrefix = $AddPrefix ? "${ArchivePrefix}-${ParentDirectoryName}-" : ""
        $FileNameFormatted = $FileNamePrefix + ([string]$ImageIndex).PadLeft(${NumberLength}, '0') + $File.Extension
        if (-not ($File.Name -eq $FileNameFormatted)) {
            Show-Check-Error -Message "${File} has incorrect name. It should be ${FileNameFormatted}"
        }

        if ($CheckImageFiles) {
            Write-Verbose -Message "Checking image file ${File} with imagemagick"
            & "${ImageMagickExecutablePath}" identify -regard-warnings "${File}" 2>&1>$null
            if ($LASTEXITCODE -ne 0) {
                Show-Check-Error -Message "File ${File} is corrupted. Please check it"
            }
            else {
                Write-Verbose -Message "File ${File} is correct image file"
            }
        }

        Write-Verbose -Message "${File} is successfully checked"
        $ImageIndex++
    }
}

function Test-Unit-In-Destination-Path {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] $Path
    )

    if ($DestinationPath) {
        $UnitDirectory = Get-Item -Path "${Path}"
        $UnitDirectoryName = $UnitDirectory.Name
        $InventoryDirectoryName = $UnitDirectory.Parent.Name
        $FundDirectoryName = $UnitDirectory.Parent.Parent.Name
    
        $DestinationPath | ForEach-Object {
            $Directory = [System.IO.DirectoryInfo](Join-Path -Path "${_}" -ChildPath "${FundDirectoryName}" -AdditionalChildPath "${InventoryDirectoryName}", "${UnitDirectoryName}")
            Write-Verbose "Checking if ${Path} is exists in ${Directory}"
            if ($Directory.Exists) {
                Show-Check-Error -Message "${Directory} already exists"
            }
        }
    }
}

function Test-Units {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true)] $UnitDirectory
    )

    Process {
        Test-Unit-In-Destination-Path -Path "${UnitDirectory}"
        Test-Directory -Path "${UnitDirectory}" -Mask "${UnitMask}" -StartsWith $UnitDirectory.Parent.BaseName
        Get-SortedDirectory -Path $UnitDirectory | Test-Images
    }
}

function Test-Inventories {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true)] $InventoryDirectory
    )

    Process {
        Test-Directory -Path "${InventoryDirectory}" -Mask "${InventoryMask}" -StartsWith $InventoryDirectory.Parent.BaseName
        return Get-SortedDirectory -Path $InventoryDirectory
    }
}

function Test-Funds {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true)] $FundDirectory
    )

    Process {
        Test-Directory -Path "${FundDirectory}" -Mask "${FundMask}" -StartsWith ""
        return Get-SortedDirectory -Path $FundDirectory
    }
}

function Test-SourceDirectory {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true)] $SourceDirectory
    )

    Process {
        return Get-SortedDirectory -Path $SourceDirectory
    }
}

Show-Check-Error -Message "Start" -ForceContinue
$Path | Test-SourceDirectory | Test-Funds | Test-Inventories | Test-Units
Show-Check-Error -Message "End" -ForceContinue
