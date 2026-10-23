[CmdletBinding()]
param(
  [string]$DevEcoRoot = 'D:\data\devecostudionext\DevEco Studio',
  [string]$BuildRoot = 'D:\XJITApp-api26-simulator',
  [string]$Target = '127.0.0.1:5555',
  [switch]$Install,
  [ValidatePattern('^com[.][a-z0-9.]+$')][string]$BundleName = 'com.xjit.app.acceptance',
  [string]$AppLabel = '掌上新理工·验收',
  [ValidatePattern('^[a-z0-9-]+$')][string]$EvidenceName = 'emulator',
  [switch]$OfflinePreview,
  [switch]$NativeSchool,
  # 只是让验收包跳过登录直达 Tab 页，用来截取真正的运行态界面。
  # 只在模拟器副本里注入，正式源码永远不含这段。
  [switch]$PreviewLogin
)
$ErrorActionPreference = 'Stop'
if ($NativeSchool -and $OfflinePreview) { throw 'Native school acceptance cannot use synthetic preview data.' }
if ($OfflinePreview -and $BundleName -ne 'com.xjit.app.designreview') { throw 'Offline UI preview must use its isolated designreview bundle.' }
if ($PreviewLogin -and $BundleName -ne 'com.xjit.app.designreview') { throw 'Preview login must use its isolated designreview bundle.' }
if ($BundleName -eq 'com.xjit.app') { throw 'This tool is restricted to independent test bundles.' }
$artifactName = if ($NativeSchool) { 'entry-school-native-signed.hap' } elseif ($OfflinePreview) { 'entry-design-preview-signed.hap' } else { 'entry-acceptance-signed.hap' }
$sourceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\')
$stage = [IO.Path]::GetFullPath($BuildRoot).TrimEnd('\')
if ($stage -match '[^\x00-\x7F]' -or $stage -eq $sourceRoot -or $stage.StartsWith($sourceRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Select an independent ASCII directory.' }
if ((Test-Path -LiteralPath $stage) -and ((Get-Item -LiteralPath $stage).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Simulator stage must not be a junction.' }
$node = Join-Path $DevEcoRoot 'tools\node\node.exe'
$javaRoot = Join-Path $DevEcoRoot 'jbr'
$java = Join-Path $javaRoot 'bin\java.exe'
$keytool = Join-Path $javaRoot 'bin\keytool.exe'
$sdkRoot = Join-Path $DevEcoRoot 'sdk'
$toolRoot = Join-Path $sdkRoot 'default\openharmony\toolchains'
$hdc = Join-Path $toolRoot 'hdc.exe'
$signLib = Join-Path $toolRoot 'lib'
$signer = Join-Path $signLib 'hap-sign-tool.jar'
$keystore = Join-Path $signLib 'OpenHarmony.p12'
$hvigor = Join-Path $DevEcoRoot 'tools\hvigor\hvigor\bin\hvigor.js'
$buildRecord = Get-Content -LiteralPath (Join-Path $sourceRoot '.wolf\build-api26-inputs.json') -Raw | ConvertFrom-Json
$modules = $buildRecord.nodeModulesPath
foreach ($required in @($node, $java, $keytool, $hdc, $signer, $keystore, $hvigor, (Join-Path $modules '@ohos\hvigor-ohos-plugin\package.json'))) {
  if (-not (Test-Path -LiteralPath $required)) { throw "Existing tool missing: $required. No download attempted." }
}
if ((Get-Content -LiteralPath (Join-Path $modules '@ohos\hvigor-ohos-plugin\package.json') -Raw | ConvertFrom-Json).version -ne '6.26.8') { throw 'Existing API26 cache does not match 6.26.8.' }
# This signing and evidence pipeline supports API26 simulators only.
& (Join-Path $PSScriptRoot 'check-device-api.ps1') -Target $Target -ExpectedApi 26 -HdcPath $hdc
$udidText = & $hdc -t $Target shell bm get -u
$udid = ($udidText | Where-Object { $_ -match '^[A-Fa-f0-9]{32,128}$' } | Select-Object -First 1).Trim()
if (-not $udid) { throw 'Emulator UDID unavailable.' }
New-Item -ItemType Directory -Path $stage -Force | Out-Null
$marker = Join-Path $stage '.codex-xjit-simulator'
if (Test-Path -LiteralPath $marker) {
  if ((Get-Content -LiteralPath $marker -Raw).Trim() -ne $sourceRoot) { throw 'Stage belongs to another project.' }
} elseif ((Get-ChildItem -LiteralPath $stage -Force | Measure-Object).Count -gt 0) { throw 'Nonempty simulator directory without ownership marker.' }
Set-Content -LiteralPath $marker -Value $sourceRoot -Encoding utf8
$inputs = @()
foreach ($directory in @('AppScope','entry\src','hvigor')) {
  $inputs += Get-ChildItem -LiteralPath (Join-Path $sourceRoot $directory) -Recurse -File | ForEach-Object { $_.FullName.Substring($sourceRoot.Length + 1) }
}
$inputs += @('entry\build-profile.json5','entry\hvigorfile.ts','entry\oh-package.json5','hvigorfile.ts','build-profile.json5','oh-package.json5','local.properties')
$inputHashes = @()
foreach ($relative in $inputs) {
  $destination = Join-Path $stage $relative
  New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
  $sourceHash = (Get-FileHash -LiteralPath (Join-Path $sourceRoot $relative) -Algorithm SHA256).Hash
  Copy-Item -LiteralPath (Join-Path $sourceRoot $relative) -Destination $destination -Force
  if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ne $sourceHash) { throw "Source changed during snapshot: $relative" }
  $inputHashes += [ordered]@{ path = $relative; sha256 = $sourceHash }
}
# These four changes are restricted to the simulator copy. Formal source/API are untouched.
$appPath = Join-Path $stage 'AppScope\app.json5'
$app = Get-Content -LiteralPath $appPath -Raw | ConvertFrom-Json
$app.app.bundleName = $BundleName
$app | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $appPath -Encoding utf8
$labelPath = Join-Path $stage 'AppScope\resources\base\element\string.json'
$label = Get-Content -LiteralPath $labelPath -Raw | ConvertFrom-Json
($label.string | Where-Object name -eq 'app_name').value = $AppLabel
$label | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $labelPath -Encoding utf8
$constantsPath = Join-Path $stage 'entry\src\main\ets\utils\Constants.ets'
$constants = Get-Content -LiteralPath $constantsPath -Raw
if ($NativeSchool) {
  if ($constants -match 'API_BASE' -or $constants -notmatch 'https://cas[.]xjit[.]edu[.]cn/cas/login') { throw 'Native school configuration not found or contains a legacy gateway.' }
} elseif (-not $OfflinePreview) {
  if ($constants -notmatch 'export const API_BASE:') { throw 'Legacy fixture mode requires its legacy protocol; use -NativeSchool for the migrated app.' }
  $constants = [regex]::Replace($constants, "export const API_BASE: string = '[^']+'", "export const API_BASE: string = 'http://127.0.0.1:18765'")
}
Set-Content -LiteralPath $constantsPath -Value $constants -Encoding utf8
$materialPath = Join-Path $stage 'entry\src\main\ets\theme\Materials.ets'
$material = Get-Content -LiteralPath $materialPath -Raw
$material = $material.Replace('return uiMaterial.isImmersiveMaterialSupported()', "const supported = uiMaterial.isImmersiveMaterialSupported(); console.info('[ACCEPTANCE] ImmersiveMaterialSupported=' + String(supported) + ' level=' + String(uiMaterial.getGlobalMaterialLevel()) + ' state=' + String(uiMaterial.getMaterialInfo().state)); return supported")
Set-Content -LiteralPath $materialPath -Value $material -Encoding utf8
Set-Content -LiteralPath (Join-Path $stage 'local.properties') -Value ('sdk.dir=' + $sdkRoot.Replace('\','/')) -Encoding utf8
$records = Join-Path (Join-Path $sourceRoot '.wolf') $EvidenceName
New-Item -ItemType Directory -Path $records -Force | Out-Null
if ($OfflinePreview) {
  & $node (Join-Path $sourceRoot 'tools\design-preview-data.cjs') $stage
  if ($LASTEXITCODE -ne 0) { throw 'Offline preview stage injection failed.' }
}
if ($PreviewLogin) {
  # loadSession 是唯一的会话入口：任何页面在拿数据前都会先经它判断是否已登录。
  # 在这里短路成"已登录"，后续的 token 守卫仍然按正常逻辑跑，只是永远看不到登录页。
  $authPath = Join-Path $stage 'entry\src\main\ets\services\AuthManager.ets'
  $auth = Get-Content -LiteralPath $authPath -Raw
  $anchor = 'export async function loadSession(): Promise<boolean> {'
  if (-not $auth.Contains($anchor)) { throw 'Preview login anchor missing in AuthManager.loadSession.' }
  $injected = $anchor + @"

  savedUsername = '2026000001'; savedAccessToken = 'preview-only-not-a-real-token'
  savedTokenExpiresAt = Date.now() + 86400000; savedAuthSource = GATEWAY_AUTH_SOURCE
  setTodoOwner(savedUsername)
  return true
"@
  $auth = $auth.Replace($anchor, $injected)
  if (($auth -split 'return true').Count -lt 2) { throw 'Preview login injection did not apply.' }
  Set-Content -LiteralPath $authPath -Value $auth -Encoding utf8
  Write-Host '[preview-login] loadSession short-circuited for screenshot verification'
}
$prevSdk = $env:DEVECO_SDK_HOME; $prevJava = $env:JAVA_HOME; $prevModules = $env:NODE_PATH
try {
  $env:DEVECO_SDK_HOME = $sdkRoot.Replace('\','/'); $env:JAVA_HOME = $javaRoot.Replace('\','/'); $env:NODE_PATH = $modules
  Push-Location -LiteralPath $stage
  try {
    & $node $hvigor clean --no-daemon --no-parallel 2>&1 | Out-File -LiteralPath (Join-Path $records 'clean.log') -Encoding utf8
    if ($LASTEXITCODE -ne 0) { throw 'Simulator clean failed.' }
    & $node $hvigor --mode module -p product=default -p module=entry@default -p buildMode=debug assembleHap --no-daemon --no-parallel 2>&1 | Tee-Object -FilePath (Join-Path $records 'build.log')
    if ($LASTEXITCODE -ne 0) { throw 'Simulator build failed.' }
  } finally { Pop-Location }
} finally { $env:DEVECO_SDK_HOME = $prevSdk; $env:JAVA_HOME = $prevJava; $env:NODE_PATH = $prevModules }
$signRoot = Join-Path $stage 'acceptance-signing'
New-Item -ItemType Directory -Path $signRoot -Force | Out-Null
# Public SDK test certificates only; never load/export the user's private signing files.
$publicTemplate = Get-Content -LiteralPath (Join-Path $signLib 'UnsgnedDebugProfileTemplate.json') -Raw | ConvertFrom-Json
$publicChain = [regex]::Matches((Get-Content -LiteralPath (Join-Path $signLib 'OpenHarmonyProfileDebug.pem') -Raw), '(?s)-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----')
$caPem = ''; $rootPem = ''
foreach ($item in $publicChain) {
  $cert = [Security.Cryptography.X509Certificates.X509Certificate2]::CreateFromPem($item.Value)
  if ($cert.Subject.StartsWith('CN=OpenHarmony Application CA,')) { $caPem = $item.Value }
  if ($cert.Subject.StartsWith('CN=OpenHarmony Application Root CA,')) { $rootPem = $item.Value }
  $cert.Dispose()
}
if (-not $caPem -or -not $rootPem) { throw 'Complete SDK public certificate chain unavailable.' }
$chain = $publicTemplate.'bundle-info'.'development-certificate' + "`n" + $caPem + "`n" + $rootPem
$appCert = Join-Path $signRoot 'app-chain.pem'
Set-Content -LiteralPath $appCert -Value $chain -Encoding ascii
$profile = Get-Content -LiteralPath (Join-Path $signLib 'UnsgnedDebugProfileTemplate.json') -Raw | ConvertFrom-Json
$profile.'bundle-info'.'bundle-name' = $BundleName
$profile.'debug-info'.'device-ids' = @($udid)
$profile.'validity'.'not-before' = [DateTimeOffset]::UtcNow.AddDays(-1).ToUnixTimeSeconds()
$profile.'validity'.'not-after' = [DateTimeOffset]::UtcNow.AddDays(30).ToUnixTimeSeconds()
$profile.uuid = [guid]::NewGuid().ToString()
$profileJson = Join-Path $signRoot 'debug-profile.json'
$profile | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $profileJson -Encoding utf8
$signedProfile = Join-Path $signRoot 'debug-profile.p7b'
& $java -jar $signer sign-profile -mode localSign -keyAlias 'openharmony application profile debug' -keyPwd 123456 -profileCertFile (Join-Path $signLib 'OpenHarmonyProfileDebug.pem') -inFile $profileJson -signAlg SHA256withECDSA -keystoreFile $keystore -keystorePwd 123456 -outFile $signedProfile 2>&1 | Tee-Object -FilePath (Join-Path $records 'sign-profile.log')
if ($LASTEXITCODE -ne 0) { throw 'SDK debug profile signing failed.' }
$unsigned = Join-Path $stage 'entry\build\default\outputs\default\entry-default-unsigned.hap'
$signed = Join-Path $stage $artifactName
& $java -jar $signer sign-app -mode localSign -keyAlias 'openharmony application release' -keyPwd 123456 -appCertFile $appCert -profileFile $signedProfile -inFile $unsigned -signAlg SHA256withECDSA -keystoreFile $keystore -keystorePwd 123456 -outFile $signed -compatibleVersion 26 2>&1 | Tee-Object -FilePath (Join-Path $records 'sign-app.log')
if ($LASTEXITCODE -ne 0) { throw 'Simulator HAP signing failed.' }
& $java -jar $signer verify-app -inFile $signed -outCertChain (Join-Path $signRoot 'verified-chain.cer') -outProfile (Join-Path $signRoot 'verified-profile.p7b') 2>&1 | Tee-Object -FilePath (Join-Path $records 'verify-signature.log')
if ($LASTEXITCODE -ne 0) { throw 'Signed simulator HAP verification failed.' }
$delivered = Join-Path $records $artifactName
Copy-Item -LiteralPath $signed -Destination $delivered -Force
$hash = (Get-FileHash -LiteralPath $signed -Algorithm SHA256).Hash
if ((Get-FileHash -LiteralPath $delivered -Algorithm SHA256).Hash -ne $hash) { throw 'Simulator HAP copy integrity failure.' }
[ordered]@{ builtAt = (Get-Date).ToString('o'); bundleName = $BundleName; stageRoot = $stage; target = $Target; api = 26; nativeSchool = [bool]$NativeSchool; fixtures = $(if ($NativeSchool) { 'None; direct school HTTPS services with ordinary TLS verification' } elseif ($OfflinePreview) { 'Offline synthetic UI data, no HTTP server or port mapping' } else { '127.0.0.1:18765 (HDC reverse)' }); offlinePreview = [bool]$OfflinePreview; sha256 = $hash; signedHap = $delivered; inputHashes = $inputHashes; sourceDrift = @($inputHashes | Where-Object { (Get-FileHash -LiteralPath (Join-Path $sourceRoot $_.path) -Algorithm SHA256).Hash -ne $_.sha256 } | ForEach-Object { $_.path }) } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $records 'build-record.json') -Encoding utf8
if ($Install) {
  & $hdc -t $Target install -r $signed 2>&1 | Tee-Object -FilePath (Join-Path $records 'install.log')
  if ($LASTEXITCODE -ne 0) { throw 'Emulator install command failed.' }
  $bundle = & $hdc -t $Target shell bm dump -n $BundleName
  if (($bundle | Out-String) -notmatch [regex]::Escape($BundleName)) { throw 'Installed acceptance bundle not found.' }
  $bundle | Out-File -LiteralPath (Join-Path $records 'installed-bundle.json') -Encoding utf8
}
Write-Output "Verified simulator HAP: $delivered"
Write-Output "SHA256: $hash"




