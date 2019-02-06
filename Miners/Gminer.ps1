﻿using module ..\Include.psm1

param(
    [PSCustomObject]$Pools,
    [Bool]$InfoOnly
)

$Path = ".\Bin\NVIDIA-Gminer\miner.exe"
$Uri = "https://github.com/RainbowMiner/miner-binaries/releases/download/v1.31-gminer/gminer_1_31_minimal_windows64.zip"
$ManualUri = "https://bitcointalk.org/index.php?topic=5034735.0"
$Port = "329{0:d2}"
$DevFee = 2.0
$Cuda = "9.0"

if (-not $Session.DevicesByTypes.NVIDIA -and -not $InfoOnly) {return} # No NVIDIA present in system

$Commands = [PSCustomObject[]]@(
    [PSCustomObject]@{MainAlgorithm = "Aeternity";    MinMemGB = 8; Params = "--algo aeternity"; ExtendInterval = 2; Penalty = 0; NoCPUMining = $true} #Equihash Cuckoo29/Aeternity
    [PSCustomObject]@{MainAlgorithm = "Cuckaroo29";   MinMemGB = 8; Params = "--algo grin29"; ExtendInterval = 2; Penalty = 0; NoCPUMining = $true} #Equihash Cuckaroo29/GRIN
    [PSCustomObject]@{MainAlgorithm = "Cuckatoo31";   MinMemGB = 9; Params = "--algo grin31"; ExtendInterval = 2; Penalty = 0; NoCPUMining = $true} #Equihash Cuckatoo31/GRIN31
    [PSCustomObject]@{MainAlgorithm = "Equihash965";  MinMemGB = 2; Params = "--algo 96_5"} #Equihash 96,5
    [PSCustomObject]@{MainAlgorithm = "Equihash1445"; MinMemGB = 2; Params = "--algo 144_5"} #Equihash 144,5
    [PSCustomObject]@{MainAlgorithm = "Equihash1505"; MinMemGB = 3; Params = "--algo 150_5"} #Equihash 150,5/BEAM
    [PSCustomObject]@{MainAlgorithm = "Equihash1927"; MinMemGB = 3.0; Params = "--algo 192_7"} #Equihash 192,7
    [PSCustomObject]@{MainAlgorithm = "Equihash2109"; MinMemGB = 0.5; Params = "--algo 210_9"} #Equihash 210,9
)

$Name = Get-Item $MyInvocation.MyCommand.Path | Select-Object -ExpandProperty BaseName

if ($InfoOnly) {
    [PSCustomObject]@{
        Type      = @("NVIDIA")
        Name      = $Name
        Path      = $Path
        Port      = $Miner_Port
        Uri       = $Uri
        DevFee    = $DevFee
        ManualUri = $ManualUri
        Commands  = $Commands
    }
    return
}

if (-not (Confirm-Cuda -ActualVersion $Session.Config.CUDAVersion -RequiredVersion $Cuda -Warning $Name)) {return}

$Session.DevicesByTypes.NVIDIA | Select-Object Vendor, Model -Unique | ForEach-Object {
    $Device = $Session.DevicesByTypes."$($_.Vendor)" | Where-Object Model -EQ $_.Model
    $Miner_Model = $_.Model

    $Commands | ForEach-Object {
        $Algorithm_Norm = Get-Algorithm $_.MainAlgorithm

        $MinMemGB = $_.MinMemGB        
        $Miner_Device = $Device | Where-Object {$_.OpenCL.GlobalMemsize -ge ($MinMemGB * 1gb)}
        $Miner_Port = $Port -f ($Miner_Device | Select-Object -First 1 -ExpandProperty Index)
        $Miner_Name = (@($Name) + @($Miner_Device.Name | Sort-Object) | Select-Object) -join '-'
        $Miner_Port = Get-MinerPort -MinerName $Name -DeviceName @($Miner_Device.Name) -Port $Miner_Port

        $DeviceIDsAll = $Miner_Device.Type_Vendor_Index -join ' '
        
        if ($Pools.$Algorithm_Norm.Host -and $Miner_Device) {
            $Pool_Port = if ($Pools.$Algorithm_Norm.Ports -ne $null -and $Pools.$Algorithm_Norm.Ports.GPU) {$Pools.$Algorithm_Norm.Ports.GPU} else {$Pools.$Algorithm_Norm.Port}
            [PSCustomObject]@{
                Name = $Miner_Name
                DeviceName = $Miner_Device.Name
                DeviceModel = $Miner_Model
                Path = $Path
                Arguments = "--api $($Miner_Port) --devices $($DeviceIDsAll) --server $($Pools.$Algorithm_Norm.Host) --port $($Pool_Port) --user $($Pools.$Algorithm_Norm.User)$(if ($Pools.$Algorithm_Norm.Pass) {" --pass $($Pools.$Algorithm_Norm.Pass)"})$(if ($Algorithm_Norm -match "^Equihash") {" --pers $(Get-EquihashCoinPers $Pools.$Algorithm_Norm.CoinSymbol -Default "auto")"})$(if ($Pools.$Algorithm_Norm.SSL) {" --ssl 1"}) --watchdog 0 $($_.Params)"
                HashRates = [PSCustomObject]@{$Algorithm_Norm = $($Session.Stats."$($Miner_Name)_$($Algorithm_Norm)_HashRate".Week * $(if ($_.Penalty) {1-$_.Penalty/100} else {1}))}
                API = "Gminer"
                Port = $Miner_Port
                DevFee = $DevFee
                Uri = $Uri
                FaultTolerance = $_.FaultTolerance
                ExtendInterval = $_.ExtendInterval
                ManualUri = $ManualUri
                NoCPUMining = $_.NoCPUMining
            }
        }
    }
}