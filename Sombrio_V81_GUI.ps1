#Requires -Version 5.1

# ============================================================
# EL SOMBRIO IF - FORENSIC SCANNER (MASTER V81 UNIFICADO) - EDICIÓN APP (GUI)
#   V81 UNIFICADO (V79 + V80 en un solo script) - Novedades:
#     Base V80 (menú de herramientas + revisión manual) con el método de descarga
#          del Doomsday de V79 (repositorio/git) como segunda opción.
#     VENTANAS NUEVAS: Registro de actividad en vivo (Ctrl+L), Visor de resultados
#          por pestañas (Ctrl+R) e Información del sistema (Ctrl+I).
#     Todo lo que hace la app queda escrito en %APPDATA%\ElSombrio\logs\.
#   V79 UNIFICADO - Novedades:
#     Unifica V76 + V79: todas las opciones (01-12) en un solo script.
#     Interfaz renovada: menú lateral por secciones, buscador y filtro por nivel,
#          columna NIVEL (CRÍTICO / ALERTA / OK / INFO), menú contextual (clic derecho),
#          exportar la vista a CSV, atajos de teclado y dos temas (Slate / Sombrio).
#     MODS ordenados: por versión de Minecraft y, dentro de cada una,
#          RENOMBRADOS > SOSPECHOSOS > APROBADOS (orden alfabético).
#     El panel de resultados se abre desde que empieza el análisis.
#   V76 - Novedades:
#     [ANTI-BYPASS] Detección de archivos renombrados:
#          - Metadatos PE internos (OriginalFilename, ProductName...).
#          - Contenido interno de .jar/.zip (entradas que delatan cheats).
#          - Extensión falsa por cabecera (MZ/PK).
#          - Alternate Data Streams (ADS) con macros ocultas.
#          - Ventanas activas con títulos de cheats/clients.
#          - Autoarranque (claves Run/RunOnce).
#     Interfaz renovada: paleta rojo / negro / verde.
#   V75 - Novedades:
#     [11] LILITH SERVICES (lilith-ps) integrado en el menú.
#     MODS separados por versión de Minecraft (detectada del nombre,
#          de la carpeta y del interior del .jar: fabric.mod.json,
#          mods.toml, mcmod.info, quilt.mod.json).
#     Detección de MACROS mejorada: procesos, software instalado
#          (registro), tareas programadas, servicios, archivos en
#          carpetas del usuario y carpeta de Inicio.
#   NUEVO: Opción 13 - Anti-Bypass Forense (Procesos, Hashes, Defender, Firmas)
# ============================================================

$script:AutoElevate     = $true   # $true = pedir permisos de Administrador (UAC) al abrir
# Doomsday: dos fuentes. [A] URL directa (V80)  |  [B] repositorio de GitHub (V79)
$script:DoomsdayUrl      = "https://raw.githubusercontent.com/zedoonvm1/powershell-scripts/refs/heads/main/DoomsDayDetector.ps1"
$script:DoomsdayRepo     = "https://github.com/jgonzalo17/Doomsday-Detector.git"
$script:DoomsdayScript   = "elsombrio.ps1"   # nombre exacto del detector dentro del repo
$script:SystemInformerUrl = "https://sourceforge.net/projects/systeminformer/files/latest/download"
$script:JournalTraceUrl   = "https://github.com/ponei/JournalTrace/releases/download/1.0/JournalTrace.exe"
$script:LilithServicesUrl = "https://raw.githubusercontent.com/praiselily/lilith-ps/refs/heads/main/Services.ps1"
# URL raw de ESTE script en tu GitHub (para poder abrirlo con un solo comando y pedir UAC).
# Cambia el nombre del archivo si lo subes con otro nombre.
$script:SelfUrl         = "https://raw.githubusercontent.com/jgonzalo17/Doomsday-Detector/main/Sombrio_V81_GUI.ps1"
$script:IsChild         = (($args -contains "--sombrio-child") -or [bool]$global:SombrioChild)

# ------------------------------------------------------------
# RELANZAR OCULTO: abre la app sin ventana de consola (y con UAC si se desea)
# ------------------------------------------------------------
if (-not $script:IsChild -and $PSCommandPath -and $Host.Name -eq 'ConsoleHost') {
    $launched = $false
    try {
        $psExe   = (Get-Process -Id $PID).Path
        $argLine = "-NoLogo -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$PSCommandPath`" --sombrio-child"
        $isAdm   = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

        if ($script:AutoElevate -and -not $isAdm) {
            try {
                Start-Process -FilePath $psExe -ArgumentList $argLine -Verb RunAs -ErrorAction Stop
                $launched = $true
            } catch { }   # UAC cancelado: se abre igual, sin privilegios
        }
        if (-not $launched) {
            Start-Process -FilePath $psExe -ArgumentList $argLine -WindowStyle Hidden -ErrorAction Stop
            $launched = $true
        }
    } catch { $launched = $false }
    if ($launched) { exit }
}

# ------------------------------------------------------------
# EJECUTADO CON "irm ... | iex": pedir UAC y abrir la app oculta en un proceso elevado
# ------------------------------------------------------------
if (-not $script:IsChild -and -not $PSCommandPath -and $script:AutoElevate -and $script:SelfUrl -and $Host.Name -eq 'ConsoleHost') {
    $isAdmIex = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmIex) {
        try {
            $cmdIex = "`$global:SombrioChild = `$true; iex ((irm '$($script:SelfUrl)') -replace '^\uFEFF')"
            $encIex = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($cmdIex))
            Start-Process -FilePath "powershell.exe" -Verb RunAs -WindowStyle Hidden -ErrorAction Stop `
                -ArgumentList "-NoLogo -NoProfile -ExecutionPolicy Bypass -STA -EncodedCommand $encIex"
            return   # la app ya se abrió en el proceso elevado
        } catch { }  # UAC cancelado: se abre igual, sin privilegios
    }
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if (-not ([System.Management.Automation.PSTypeName]'Sombrio.WinApi').Type) {
    try {
        Add-Type -Namespace Sombrio -Name WinApi -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder text, int count);
'@
    } catch { }
}
try { [void][Sombrio.WinApi]::SetProcessDPIAware() } catch { }
[System.Windows.Forms.Application]::EnableVisualStyles()

# Si se ejecuta en esta misma consola (irm | iex siendo administrador), se oculta mientras la app está abierta.
$script:HiddenConsole = [IntPtr]::Zero
if (-not $script:IsChild) {
    try {
        $hwnd = [Sombrio.WinApi]::GetConsoleWindow()
        if ($hwnd -ne [IntPtr]::Zero -and [Sombrio.WinApi]::IsWindowVisible($hwnd)) { [void][Sombrio.WinApi]::ShowWindow($hwnd, 0); $script:HiddenConsole = $hwnd }
    } catch { }
}

# ============================================================
# ESTADO GLOBAL
# ============================================================
$script:DefaultModsPath = "$env:APPDATA\.minecraft\mods"
$script:Busy            = $false
$script:CancelRequested = $false
$script:CloseAfter      = $false
$script:ProgressPct     = 0
$script:ScanCount       = 0
$script:DeepHits        = 0
$script:LastReport      = $null
$script:ViewMode        = 'live'      # 'live' = resultados | 'registry' = registro de sesión
$script:ActiveCat       = 'Stats'
$script:CatData         = @{}
$script:RegData         = @{}
$script:RecycleMeta     = @{}
$script:CatButtons      = @{}
$script:NavButtons      = [System.Collections.Generic.List[object]]::new()
$script:JarVersionProbes = 0           # límite de aperturas de .jar para detectar versión
$script:ContentProbes   = 0           # V76 - límite de lecturas de contenido/metadatos
$script:FilterText      = ""          # buscador de la tabla de resultados
$script:FilterLevel     = 'all'       # all | red | warn
$script:SuppressFilter  = $false
$script:FilterBar = $null; $script:TxtFilter = $null; $script:CmbLevel = $null; $script:LblCount = $null

# ------------------------------------------------------------
# MEMORIA DE SESIÓN INDEPENDIENTE (Para la Opción 09)
# ------------------------------------------------------------
$script:LogMods      = [System.Collections.Generic.List[string]]::new()
$script:LogPrefetch  = [System.Collections.Generic.List[string]]::new()
$script:LogMemoria   = [System.Collections.Generic.List[string]]::new()
$script:LogMacros    = [System.Collections.Generic.List[string]]::new()
$script:LogServicios = [System.Collections.Generic.List[string]]::new()
$script:LogDisco     = [System.Collections.Generic.List[string]]::new()
$script:LogPapelera  = [System.Collections.Generic.List[string]]::new()
$script:LogHistorial = [System.Collections.Generic.List[string]]::new()
$script:LogAntiBypass = [System.Collections.Generic.List[string]]::new()

# ------------------------------------------------------------
# V81 - REGISTRO DE ACTIVIDAD (para ver qué está pasando en cada momento)
# Todo Set-Status / acción / error se anota aquí y en un archivo .log
# ------------------------------------------------------------
$script:Activity      = [System.Collections.Generic.List[object]]::new()
$script:ActivityLast  = ""
$script:LogForm       = $null
$script:LogBox        = $null
$script:LogAutoScroll = $true
$script:LogOnlyIssues = $false
$script:LogDir        = Join-Path $env:APPDATA 'ElSombrio\logs'
$script:LogFile       = Join-Path $script:LogDir ("sesion_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))

function Get-LogLevel([string]$Text) {
    if ($Text -match '(?i)error|no se pudo|fall[oó]') { return 'ERROR' }
    if ($Text -match '(?i)cancel|advertencia|no se encontr|no existe|sin privilegios') { return 'WARN' }
    if ($Text -match '(?i)abierto|completado|guardad|exportad|copiad|listo') { return 'OK' }
    return 'INFO'
}

function Get-LogColor([string]$Level) {
    switch ($Level) {
        'ERROR' { return $script:C.Red }
        'WARN'  { return $script:C.Yellow }
        'OK'    { return $script:C.Green }
        default { return $script:C.Text }
    }
}

function Format-LogLine($Entry) {
    return ("[{0:HH:mm:ss}] {1,-5}  {2}" -f $Entry.Time, $Entry.Level, $Entry.Text)
}

function Add-LogLine($Entry) {
    $box = $script:LogBox
    if ($null -eq $box -or $box.IsDisposed) { return }
    if ($script:LogOnlyIssues -and $Entry.Level -notin @('ERROR', 'WARN')) { return }
    $box.SelectionStart  = $box.TextLength
    $box.SelectionLength = 0
    $box.SelectionColor  = $script:C.Muted
    $box.AppendText(("[{0:HH:mm:ss}] " -f $Entry.Time))
    $box.SelectionColor  = (Get-LogColor $Entry.Level)
    $box.AppendText(("{0,-5}  {1}`r`n" -f $Entry.Level, $Entry.Text))
    if ($script:LogAutoScroll) { $box.SelectionStart = $box.TextLength; $box.ScrollToCaret() }
}

function Write-Log {
    param([string]$Text, [string]$Level = '')
    if ([string]::IsNullOrWhiteSpace($Text)) { return }
    $Text = ($Text -replace '\s*\r?\n\s*', ' ').Trim()
    if (-not $Level) { $Level = Get-LogLevel $Text }
    $entry = [pscustomobject]@{ Time = (Get-Date); Level = $Level; Text = $Text }
    $script:Activity.Add($entry)
    if ($script:Activity.Count -gt 5000) { $script:Activity.RemoveRange(0, 1000) }
    try {
        if (-not (Test-Path -LiteralPath $script:LogDir)) { [void](New-Item -ItemType Directory -Path $script:LogDir -Force) }
        Add-Content -LiteralPath $script:LogFile -Value (Format-LogLine $entry) -Encoding UTF8
    } catch { }
    try { Add-LogLine $entry } catch { }
}

function Add-ToLog([System.Collections.Generic.List[string]]$LogList, [array]$Items) {
    if ($null -ne $Items) {
        foreach ($item in $Items) {
            if ($item -notmatch "======" -and $item -notmatch "Sin hallazgos") {
                if (-not $LogList.Contains($item)) {
                    $LogList.Add($item)
                }
            }
        }
    }
}

# ------------------------------------------------------------
# TEMAS: Slate (V79) y Sombrio (V76: rojo / negro / verde)
# Se elige en el menú [13]; se guarda en %APPDATA%\ElSombrio\theme.txt
# ------------------------------------------------------------
function New-Rgb([int]$R, [int]$G, [int]$B) { return [System.Drawing.Color]::FromArgb($R, $G, $B) }
$script:Themes = @{
    Slate = @{
        Bg = (New-Rgb 13 17 23);  Panel = (New-Rgb 19 24 32);  Panel2 = (New-Rgb 27 34 45);  Row2 = (New-Rgb 23 29 39)
        Border = (New-Rgb 52 63 80);  Hover = (New-Rgb 38 48 63);  Select = (New-Rgb 47 60 79)
        Accent = (New-Rgb 96 165 250);  Pink = (New-Rgb 226 130 150);  Blue = (New-Rgb 94 200 170);  DBlue = (New-Rgb 58 145 120)
        Text = (New-Rgb 228 233 240);  Muted = (New-Rgb 145 158 178)
        Red = (New-Rgb 240 118 118);  RedDark = (New-Rgb 150 62 68);  Green = (New-Rgb 118 208 152)
        Yellow = (New-Rgb 232 200 122);  TealDim = (New-Rgb 126 178 162)
    }
    Sombrio = @{
        Bg = (New-Rgb 8 4 6);  Panel = (New-Rgb 16 8 10);  Panel2 = (New-Rgb 28 12 14);  Row2 = (New-Rgb 20 10 12)
        Border = (New-Rgb 140 40 46);  Hover = (New-Rgb 70 20 24);  Select = (New-Rgb 95 26 30)
        Accent = (New-Rgb 255 84 92);  Pink = (New-Rgb 255 84 92);  Blue = (New-Rgb 80 220 140);  DBlue = (New-Rgb 45 150 95)
        Text = (New-Rgb 245 235 235);  Muted = (New-Rgb 190 140 145)
        Red = (New-Rgb 255 70 84);  RedDark = (New-Rgb 150 30 40);  Green = (New-Rgb 80 255 140)
        Yellow = (New-Rgb 255 200 90);  TealDim = (New-Rgb 140 200 170)
    }
}
$script:ThemeFile = Join-Path $env:APPDATA 'ElSombrio\theme.txt'
$script:ThemeName = 'Slate'
try {
    if (Test-Path -LiteralPath $script:ThemeFile) {
        $tn = (Get-Content -LiteralPath $script:ThemeFile -ErrorAction Stop | Select-Object -First 1).Trim()
        if ($script:Themes.ContainsKey($tn)) { $script:ThemeName = $tn }
    }
} catch { }
$script:C = $script:Themes[$script:ThemeName]


# ------------------------------------------------------------
# ARTE ORIGINAL: EL SOMBRIO GIRL
# ------------------------------------------------------------
$script:sideGirl = @(
    "                                                     .::---:               ::"
    "                                                    =-..-::-*=            -+.   -+-"
    "                                                   -: =.     :+          :=+   ==="
    "                                                  :+ .*       =:        ===-::.==."
    "                               -: +                :. ..:. -.=.     .."
    "                                                    =--=       .....  =:   .=  ==+-   .:++."
    "                                                     .-==.    =:...::-:    -.   :*-. :==-."
    "                                                        -=-. .+       :=-     :-: .=:=.+"
    "                                                          .:=---::::.   -=+:  .  .--.=.  "
    "                                                       :----:  ::.  :=:   :=-:   -  :=:::."
    "                                                     :-.:...::- :- ::::=:  -=.: :-.=-----+"
    "                                                    =. -: :..   . .:    ==  .-.  +-::+."
    "                                                  --. =.  .   :    =:    *+  -+=:..:=:"
    "                                            :---::. -:  -   :+:  =  =:    ++  .+ ..---"
    "                                             .---::...-.  :-:=  .+   =    .==  --. ..++"
    "                                            ---:.   :. .--..-+  :=    --.   =+.  +.:-:-+"
    "                                            =..: :=--=+-===..-  -..: = :--:.:=-  .=. *+."
    "                                            *.* -=  *-*..**=  : =..+.=:.   ..=.   .+ :*-"
    "                                            .--.+:  =-*.  .    :--@*=+=:.-=  :=    =:+:+"
    "                                              =:*:-. .+=     .    --.-=:  :-  +    -:=-"
    "                                              :.  ..=-  =-  :::    :-=-    .+=-    --+"
    "                                                   =-..  .-::..::--= ...-:-.-.     ==."
    "                                                  .=: :. -+:::+-..+..+. -==.      :+"
    "                                                    ::=--=.---+- .-=:=.. ..       :"
    "                                               .:-::--=: :+:.--*--+=. .:=:::"
    "                                              =:-:..:.:.  -..-.... :.:  .  --"
    "                                          .-=-  +=:.=::: .+: .==:=.:-+      =:"
    "                                          =-:. .+ ..  .  .+-:  .-=.=:-     ..+:"
    "                                              ::--. .:.    .-:.    .:-.   .      :-"
    "                                               .--=:.     =-.    .+:          .:"
    "                                                .-::.    .+:     =.          ."
    "                                                 .-==:  .=.     =.        .:"
    "                                                    :=--+     -=      .-:"
    "                                                      .+:    .+.    .:"
    "                                                      :=    .=.   .-"
    "                                                       =.   +."
    "                                                       -=  -=  .:"
    "                                                        +. +.  ="
    "                                                       -=+  .+"
    "                                                         +:  ="
    "                                                         :=  +"
    "                                                          +:-"
    "                                                          :=."
    "                                                         .::"
)

$script:BannerText = @'
███████╗ ██████╗ ███╗   ███╗██████╗ ██████╗ ██╗ ██████╗
██╔════╝██╔═══██╗████╗ ████║██╔══██╗██╔══██╗██║██╔═══██╗
███████╗██║   ██║██╔████╔██║██████╔╝██████╔╝██║██║   ██║
╚════██║██║   ██║██║╚██╔╝██║██╔══██╗██╔══██╗██║██║   ██║
███████║╚██████╔╝██║ ╚═╝ ██║██████╔╝██║  ██║██║╚██████╔╝
╚══════╝ ╚═════╝ ╚═╝     ╚═╝╚═════╝ ╚═╝  ╚═╝╚═╝ ╚═════╝
'@

# ------------------------------------------------------------
# REGLAS DE DETECCIÓN
# ------------------------------------------------------------
$script:IllegalKeywords = @(
    "antighosttotem", "fasttotem", "totemhelper", "autototem", "totem", "switchtotems",
    "acurateblock", "fastplace", "attacktroughgrass", "periodicattack", "toroautoattack",
    "maceattack", "autoclicker", "autoclick", "clicker", "macros", "freecam",
    "tweakeroo", "inventorynext", "hotbaroptimizer", "fastxp", "slotcycler",
    "quickhotkeys", "itemscroller", "autoswitch", "xray",
    "nojumpdelay", "noinputlag", "nohitdelay", "elytrabugfix", "firerocketkey",
    "marrowcrystal", "anchoroptimizer", "quickelytra", "clickcrystals",
    "radarbro", "zansmap", "voxelmap", "xaerosmap",
    "aimbot", "killaura", "reach", "fly", "scaffold", "criticals", "jclicker", "ghostclicker",
    "meteor", "wurst", "aristois", "bleachhack", "mathax", "liquidbounce", 
    "raven", "vape", "novoline", "flux", "impact", "inertia", "kami", "krypton"
)

$script:RegexHacks = (($script:IllegalKeywords | ForEach-Object {
    if ($_.Length -le 5) { "\b$_\b" } else { $_ }
}) -join "|")

# V75 - Lista de macros/autoclickers ampliada y mejorada
$script:MacroAutoclickCritical = @(
    "autoclicker", "auto-clicker", "auto_click", "autoclick", "clickbot", "click-bot",
    "gsautoclick", "gs auto clicker", "opautoclick", "op auto clicker",
    "fastclick", "fast clicker", "perfectclick", "perfect clicker", "clickstorm",
    "speed autoclicker", "extreme auto clicker", "super fast clicker",
    "freeautoclicker", "free auto clicker", "auto clicker typer",
    "jitbit", "murgee", "tinytask",
    "automouseclick", "auto mouse click", "mouserecorder", "robomouse", "ghost mouse",
    "supermouse", "super mouse", "mini mouse macro", "x-mouse", "xmouse",
    "macrorecorder", "macro-recorder", "macro_recorder", "macro creator",
    "macro express", "mouse and keyboard recorder",
    "pulover", "pulovers macro", "macroscheduler",
    "autohotkey", "ahk_", "\.ahk", "autoit", "\.au3", "\.vbs", "\.scr",
    "logitech gaming software", "lghub", "g hub", "razer synapse", "synapse3", "synapse2",
    "icue", "corsair icue", "steelseries engine", "bloody7", "a4tech", "redragon"
)
$script:RegexMacroCritical  = ($script:MacroAutoclickCritical -join "|")
$script:PathWhitelistPatterns = "site-packages|dist-packages|\\lib\\python|\\Lib\\|\\venv\\|\\\.venv\\|\\conda\\|node_modules|\\Scripts\\|pydevd"

$script:RxOpts            = [System.Text.RegularExpressions.RegexOptions]'IgnoreCase, Compiled'
$script:RxHacks           = [regex]::new($script:RegexHacks, $script:RxOpts)
$script:RxMacroCritical   = [regex]::new($script:RegexMacroCritical, $script:RxOpts)
$script:RxPathWhitelist   = [regex]::new($script:PathWhitelistPatterns, $script:RxOpts)
$script:RxMcProcess       = [regex]::new("java|javaw|lunarclient|craft", $script:RxOpts)
$script:RxJavaNames       = [regex]::new("javaw?\.exe|lunarclient|minecraft|craft", $script:RxOpts)
$script:RxMcVersion       = [regex]::new("(?<![\d._])1[._](\d{1,2})([._]\d+)?", $script:RxOpts)
# V76 - Títulos de ventana de clients/cheats conocidos
$script:RxCheatWindows    = [regex]::new("meteor client|meteorclient|wurst|aristois|bleachhack|liquidbounce|kami|impact client|inertia client|vape(?!r)|flux client|mathax|jclicker|killaura|scaffold", $script:RxOpts)
# V76 - Entradas internas de .jar que delatan un cheat renombrado
$script:RxCheatInner      = [regex]::new("meteor|wurstclient|wurst/client|aristois|bleachhack|liquidbounce|kami/client|killaura|scaffold|autototem|autoclick|freecam|xray|jesus|flight", $script:RxOpts)

$script:WindowsServices = @("dps", "appinfo", "pcasvc", "eventlog", "sysmain", "dusmsvc", "bam")

# ============================================================
# DETECCIÓN DE VERSIÓN DE MINECRAFT DE UN MOD (V75)
#   Orden: 1) nombre del archivo  2) carpeta padre  3) metadatos dentro del .jar
# ============================================================
function Get-JarMcVersion {
    param([string]$Path, [string]$FileName)
    # 1) Metadatos dentro del .jar (lo más fiable: evita confundir la versión del mod con la de Minecraft)
    if (-not [string]::IsNullOrWhiteSpace($Path) -and $script:JarVersionProbes -lt 600 -and (Test-Path -LiteralPath $Path)) {
        try {
            $len = (Get-Item -LiteralPath $Path -ErrorAction Stop).Length
            if ($len -lt 80MB) {
                $script:JarVersionProbes++
                Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
                $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
                try {
                    foreach ($metaName in @('fabric.mod.json', 'quilt.mod.json', 'neoforge.mods.toml', 'META-INF/neoforge.mods.toml', 'META-INF/mods.toml', 'mcmod.info')) {
                        $entry = $zip.GetEntry($metaName)
                        if (-not $entry) { continue }
                        $sr = New-Object System.IO.StreamReader($entry.Open())
                        try { $txt = $sr.ReadToEnd() } finally { $sr.Dispose() }
                        $m = [regex]::Match($txt, '"minecraft"\s*:\s*(?:"|\[\s*")[^"]*?(1[._]\d{1,2}(?:[._]\d+)?)')
                        if (-not $m.Success) { $m = [regex]::Match($txt, 'modId\s*=\s*"minecraft"[\s\S]{0,300}?versionRange\s*=\s*"[\[\(~>=<\s]*(1[._]\d{1,2}(?:[._]\d+)?)') }
                        if (-not $m.Success) { $m = [regex]::Match($txt, 'acceptedMinecraftVersions\s*=\s*"?[\[\(~>=<\s]*(1[._]\d{1,2}(?:[._]\d+)?)') }
                        if (-not $m.Success) { $m = [regex]::Match($txt, '"mcversion"\s*:\s*"(1[._]\d{1,2}(?:[._]\d+)?)') }
                        if ($m.Success) { return ($m.Groups[1].Value -replace '_', '.') }
                    }
                } finally { $zip.Dispose() }
            }
        } catch { }
    }
    # 2) Nombre del archivo
    if ($FileName -and $script:RxMcVersion.IsMatch($FileName)) {
        return (($script:RxMcVersion.Match($FileName).Value) -replace '_', '.')
    }
    # 3) Carpeta padre
    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        $parent = Split-Path -Path $Path -Parent -ErrorAction SilentlyContinue
        if ($parent -and $script:RxMcVersion.IsMatch($parent)) {
            return (($script:RxMcVersion.Match($parent).Value) -replace '_', '.')
        }
    }
    return "Desconocida"
}

# ------------------------------------------------------------
# V75 - Agrupa los mods por versión de Minecraft y pone los
# ilegales primero dentro de cada grupo.
# ------------------------------------------------------------
function Group-ModsByVersion {
    param([array]$ModItems)
    $groups = [ordered]@{}
    foreach ($raw in @($ModItems)) {
        # Normaliza ítems que ya traen "[MC x - ETIQUETA]" (por ejemplo al regenerar desde el registro)
        $it = ([string]$raw) -replace '^\[MC\s+[^\]]*?\s-\s', '['
        if ($it -match '^=+') { continue }
        $path = ""
        if ($it -match '\|\s*Ruta:\s*(.+?)(?=\s+\|\s|\s*$)') { $path = $Matches[1].Trim() }
        $name = if ($path) { [IO.Path]::GetFileName($path) } else { "" }
        $ver  = Get-JarMcVersion -Path $path -FileName $name
        if (-not $groups.Contains($ver)) { $groups[$ver] = [System.Collections.Generic.List[string]]::new() }
        $groups[$ver].Add($it)
    }
    $sortedKeys = @($groups.Keys | Sort-Object -Descending {
        if ($_ -eq 'Desconocida') { [version]'0.0.0' } else { try { [version]$_ } catch { [version]'0.0.1' } }
    })
    $result = [System.Collections.Generic.List[string]]::new()
    # Orden alfabético por nombre del archivo (ignora la etiqueta [..] del inicio)
    $byName = { ([string]$_ -replace '^\[[^\]]*\]\s*', '') }
    foreach ($vk in $sortedKeys) {
        $items = @($groups[$vk])
        $ren = @($items | Where-Object { $_ -match 'RENOMBRADO' } | Sort-Object $byName)
        $sus = @($items | Where-Object { $_ -match 'ILEGAL|SOSPECHOSO' -and $_ -notmatch 'RENOMBRADO' } | Sort-Object $byName)
        $apr = @($items | Where-Object { $_ -notmatch 'ILEGAL|SOSPECHOSO|RENOMBRADO' } | Sort-Object $byName)
        $result.Add("====== MINECRAFT $vk  -  $($items.Count) mods  -  $($ren.Count + $sus.Count) sospechosos ======")
        foreach ($blk in @(@('RENOMBRADOS', $ren), @('SOSPECHOSOS', $sus), @('APROBADOS', $apr))) {
            $list = @($blk[1])
            if ($list.Count -eq 0) { continue }
            $result.Add("====== > $($blk[0]) ($($list.Count)) ======")
            foreach ($m in $list) {
                # Conserva la etiqueta original ([MOD ILEGAL], [MOD APROBADO]...) y le añade la versión
                if ($m -match '^\[[^\]]+\]') { $result.Add(($m -replace '^\[([^\]]+)\]', "[MC $vk - `$1]")) }
                else                         { $result.Add("[MC $vk - MOD] $m") }
            }
        }
    }
    return $result
}

# ============================================================
# V76 - ANTI-BYPASS: DETECCIÓN DE ARCHIVOS RENOMBRADOS
# ============================================================

# Metadatos internos PE: un .exe/.dll renombrado sigue delatando
# su nombre original (OriginalFilename, ProductName...).
function Test-PeSuspicious {
    param([string]$Path)
    try {
        $vi = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($Path)
        $blob = ("$($vi.OriginalFilename) $($vi.InternalName) $($vi.ProductName) $($vi.FileDescription) $($vi.CompanyName)").Trim()
        if ($blob -and ($script:RxMacroCritical.IsMatch($blob) -or $script:RxHacks.IsMatch($blob))) { return $blob }
    } catch { }
    return $null
}

# Contenido interno de .jar/.zip: aunque el archivo se renombre,
# las entradas (clases, carpetas) delatan el cheat.
function Test-JarContentSuspicious {
    param([string]$Path)
    if ($script:ContentProbes -ge 600) { return $null }
    try {
        $len = (Get-Item -LiteralPath $Path -ErrorAction Stop).Length
        if ($len -gt 40MB) { return $null }
        $script:ContentProbes++
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
        $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
        try {
            $innerHits = [System.Collections.Generic.List[string]]::new()
            foreach ($entry in $zip.Entries) {
                $en = $entry.FullName
                if ($script:RxCheatInner.IsMatch($en) -and $en -notmatch '^META-INF/maven') {
                    if ($innerHits.Count -lt 4) { $innerHits.Add($en) }
                }
            }
            if ($innerHits.Count -gt 0) { return ($innerHits -join "; ") }
        } finally { $zip.Dispose() }
    } catch { }
    return $null
}

# Extensión falsa por cabecera: MZ en .jar/.zip/.png = ejecutable camuflado.
function Test-MagicMismatch {
    param([string]$Path, [string]$Extension)
    try {
        $fs = [System.IO.File]::OpenRead($Path)
        try {
            $b = [byte[]]::new(2); [void]$fs.Read($b, 0, 2)
            $isMz = ($b[0] -eq 0x4D -and $b[1] -eq 0x5A)
            $isPk = ($b[0] -eq 0x50 -and $b[1] -eq 0x4B)
            if ($isMz -and $Extension -in '.jar','.zip','.png','.jpg','.jpeg','.txt','.log','.json','.mp3','.mp4') {
                return "Ejecutable PE (MZ) oculto con extensión $Extension"
            }
            if ($isPk -and $Extension -in '.exe','.dll','.sys','.scr','.com') {
                return "Contenedor ZIP/JAR (PK) con extensión de ejecutable"
            }
        } finally { $fs.Dispose() }
    } catch { }
    return $null
}

# Alternate Data Streams: zonas ocultas donde se esconden macros.
function Get-SuspiciousAds {
    param([string]$Path)
    $hits = [System.Collections.Generic.List[string]]::new()
    try {
        foreach ($s in (Get-Item -LiteralPath $Path -Stream * -ErrorAction SilentlyContinue)) {
            if ($s.Stream -eq '::$DATA') { continue }
            $suspect = $false
            if ($script:RxMacroCritical.IsMatch($s.Stream) -or $script:RxHacks.IsMatch($s.Stream)) { $suspect = $true }
            if (-not $suspect -and $s.Length -gt 0 -and $s.Length -lt 2MB) {
                try {
                    $txt = Get-Content -LiteralPath $Path -Stream $s.Stream -Raw -ErrorAction Stop
                    if ($txt -and ($script:RxMacroCritical.IsMatch($txt) -or $script:RxHacks.IsMatch($txt))) { $suspect = $true }
                } catch { }
            }
            if ($suspect) { $hits.Add($s.Stream) }
        }
    } catch { }
    return $hits
}

# V76 - Ventanas activas del escritorio con títulos de cheats.
function Find-CheatWindows {
    $hits = [System.Collections.Generic.List[string]]::new()
    try {
        $cb = [Sombrio.WinApi+EnumWindowsProc]{
            param($hWnd, $lParam)
            try {
                if ([Sombrio.WinApi]::IsWindowVisible($hWnd)) {
                    $sb = New-Object System.Text.StringBuilder 512
                    [void][Sombrio.WinApi]::GetWindowText($hWnd, $sb, $sb.Capacity)
                    $t = $sb.ToString().Trim()
                    if ($t.Length -gt 3 -and $script:RxCheatWindows.IsMatch($t)) { $hits.Add($t) }
                }
            } catch { }
            return $true
        }
        [void][Sombrio.WinApi]::EnumWindows($cb, [IntPtr]::Zero)
    } catch { }
    return $hits
}

# ============================================================
# MOTOR DECOMPRESSOR SEGURO (se compila al abrir la ventana)
# ============================================================
$script:DecompressorSource = @'
using System;
using System.Runtime.InteropServices;
public class SombrioDecompressor {
    [DllImport("ntdll.dll")]
    public static extern uint RtlDecompressBufferEx(ushort CompressionFormat, byte[] UncompressedBuffer, int UncompressedBufferSize, byte[] CompressedBuffer, int CompressedBufferSize, out int FinalUncompressedSize, IntPtr WorkSpace);
    [DllImport("ntdll.dll")]
    public static extern uint RtlGetCompressionWorkSpaceSize(ushort CompressionFormat, out uint CompressBufferWorkSpaceSize, out uint CompressFragmentWorkSpaceSize);
    public static byte[] Decompress(byte[] compressed) {
        if (compressed == null || compressed.Length < 8) return null;
        if (compressed[0] != 0x4D || compressed[1] != 0x41 || compressed[2] != 0x43) return null;
        int uncompSize = BitConverter.ToInt32(compressed, 4);
        uint wsComp, wsFrag;
        if (RtlGetCompressionWorkSpaceSize(4, out wsComp, out wsFrag) != 0) return null;
        IntPtr workspace = Marshal.AllocHGlobal((int)wsFrag);
        byte[] result = new byte[uncompSize];
        try {
            int finalSize;
            byte[] compData = new byte[compressed.Length - 8];
            Array.Copy(compressed, 8, compData, 0, compData.Length);
            if (RtlDecompressBufferEx(4, result, uncompSize, compData, compData.Length, out finalSize, workspace) != 0) return null;
            return result;
        } finally { Marshal.FreeHGlobal(workspace); }
    }
}
'@

function Initialize-Decompressor {
    if (-not ([System.Management.Automation.PSTypeName]'SombrioDecompressor').Type) {
        try { Add-Type -TypeDefinition $script:DecompressorSource } catch { }
    }
}

# ============================================================
# UTILIDADES
# ============================================================
function Test-Administrator {
    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-ItemColor {
    param([string]$Text)
    if ($Text -match 'ILEGAL|MALICIOSO|AUTOCLICK|AUTOCICK|HACK\b|PELIGRO|CRITICO|CRÍTICO|MACRO|RENOMBRADO|EXTENSIÓN FALSA|ADS SOSPECHOSO|VENTANA CHEAT|AUTOARRANQUE|SPOOF|ELIMINADO SOSPECHOSO') { return "Red" }
    if ($Text -match 'SOSPECHOSO|ALERTA') { return "Yellow" }
    if ($script:RxJavaNames.IsMatch($Text) -or $Text -match '\[JAVA\]') { return "Green" }
    if ($Text -match 'APROBADO|NORMAL|RUNNING|\bOK\b|\[MOD') { return "Green" }
    if ($Text -match '======') { return "DarkCyan" }
    if ($Text -match 'Total:|Resumen') { return "Yellow" }
    return "Cyan"
}

function ConvertTo-UiColor([string]$Name) {
    switch ($Name) {
        "Red"      { return $script:C.Red }
        "Green"    { return $script:C.Green }
        "Yellow"   { return $script:C.Yellow }
        "DarkCyan" { return $script:C.TealDim }
        default    { return $script:C.Accent }
    }
}

function Split-ReportItem([string]$Item) {
    $left = $Item
    $right = "---"
    $tag = ""
    $isHeader = $false

    $idx = $Item.IndexOf(" | ")
    if ($idx -ge 0) {
        $left  = $Item.Substring(0, $idx).Trim()
        $right = $Item.Substring($idx + 3).Trim()
    }
    if ($left -match '^=+\s*(.*?)\s*=+$') {
        $left = $Matches[1]; $right = ""; $isHeader = $true
    } elseif ($left -match '^\[(.+?)\]\s*(.*)$') {
        $tag = $Matches[1]; $left = $Matches[2]
    }
    return [pscustomobject]@{ Tag = $tag; Name = $left; Detail = $right; Header = $isHeader }
}

function Invoke-UiPump { [System.Windows.Forms.Application]::DoEvents() }

function Show-Info([string]$Text, [string]$Title = "EL SOMBRIO IF") {
    Write-Log ("[{0}] {1}" -f $Title, $Text)
    [void][System.Windows.Forms.MessageBox]::Show($Text, $Title, 'OK', 'Information')
}

# ------------------------------------------------------------
# PAPELERA: abrir directamente la ubicación con confirmación
# ------------------------------------------------------------
function Open-SelectedPath([string]$Path, [string]$OriginalPath = "", [string]$DeletedAt = "", [string]$RecyclePath = "", [string]$Name = "") {
    if ([string]::IsNullOrWhiteSpace($Path) -and [string]::IsNullOrWhiteSpace($OriginalPath) -and [string]::IsNullOrWhiteSpace($RecyclePath)) {
        Show-Info "No se encontró una ruta válida para este elemento." "PAPELERA"
        return
    }

    $target = if (-not [string]::IsNullOrWhiteSpace($OriginalPath) -and (Test-Path -LiteralPath $OriginalPath)) {
        $OriginalPath
    } elseif (-not [string]::IsNullOrWhiteSpace($Path) -and (Test-Path -LiteralPath $Path)) {
        $Path
    } elseif (-not [string]::IsNullOrWhiteSpace($RecyclePath) -and (Test-Path -LiteralPath $RecyclePath)) {
        $RecyclePath
    } else {
        $OriginalPath
    }

    $displayName = if ($Name) { $Name } else { [IO.Path]::GetFileName($target) }
    $dateLine = if ($DeletedAt) { "Eliminado: $DeletedAt`n" } else { "" }
    $originalLine = if ($OriginalPath) { "Ruta original: $OriginalPath`n" } else { "" }
    $recycleLine = if ($RecyclePath) { "Ruta en Papelera: $RecyclePath`n" } else { "" }

    $ans = [System.Windows.Forms.MessageBox]::Show(
        "Archivo: $displayName`n`n$dateLine$originalLine$recycleLine`n¿Deseas abrir la ubicación seleccionada?",
        "CONFIRMAR APERTURA",
        'YesNo',
        'Question'
    )
    if ($ans -ne 'Yes') { return }

    try {
        # 1) Archivo original: abrir directamente seleccionándolo en el Explorador.
        if (-not [string]::IsNullOrWhiteSpace($OriginalPath) -and (Test-Path -LiteralPath $OriginalPath)) {
            Start-Process -FilePath "explorer.exe" -ArgumentList ('/select,"' + $OriginalPath + '"')
            return
        }

        # 2) Archivo físico de la Papelera: abrir la carpeta y seleccionar el elemento.
        if (-not [string]::IsNullOrWhiteSpace($RecyclePath) -and (Test-Path -LiteralPath $RecyclePath)) {
            Start-Process -FilePath "explorer.exe" -ArgumentList ('/select,"' + $RecyclePath + '"')
            return
        }

        # 3) Ruta normal de otro módulo.
        if (-not [string]::IsNullOrWhiteSpace($Path) -and (Test-Path -LiteralPath $Path)) {
            Start-Process -FilePath "explorer.exe" -ArgumentList ('/select,"' + $Path + '"')
            return
        }

        $parent = if ($OriginalPath) { Split-Path -Path $OriginalPath -Parent -ErrorAction SilentlyContinue } else { Split-Path -Path $Path -Parent -ErrorAction SilentlyContinue }
        if ($parent -and (Test-Path -LiteralPath $parent)) {
            Start-Process -FilePath "explorer.exe" -ArgumentList @($parent)
        } else {
            Show-Info "La ruta ya no está disponible:`n`n$OriginalPath" "PAPELERA"
        }
    } catch {
        Show-Info "No se pudo abrir la ubicación:`n`n$target`n`n$($_.Exception.Message)" "PAPELERA"
    }
}

function Get-RowPath($Row) {
    if ($null -eq $Row) { return "" }
    if ($script:ActiveCat -eq 'Papelera' -and $Row.Tag) {
        $m = $Row.Tag
        foreach ($c in @($m.OriginalPath, $m.Path, $m.RecyclePath)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$c)) { return [string]$c }
        }
        return ""
    }
    $detail = [string]$Row.Cells['detalle'].Value
    if ($detail -match 'Ruta original:\s*(.*?)\s*\|\s*Eliminado:') { return $Matches[1].Trim() }
    if ($detail -match 'Ruta:\s*(.+?)(?=\s+\|\s|\s*$)') { return $Matches[1].Trim() }
    return ""
}

function Open-SelectedGridItem {
    $row = $script:Grid.CurrentRow
    if (-not $row) { return }

    # Las filas de Papelera llevan el objeto exacto en Tag, evitando depender del texto de la tabla.
    if ($script:ActiveCat -eq 'Papelera' -and $row.Tag) {
        $meta = $row.Tag
        Open-SelectedPath -Path ([string]$meta.Path) `
            -OriginalPath ([string]$meta.OriginalPath) `
            -DeletedAt ([string]$meta.DeletedAt) `
            -RecyclePath ([string]$meta.RecyclePath) `
            -Name ([string]$meta.Name)
        return
    }

    $path = Get-RowPath $row
    if ([string]::IsNullOrWhiteSpace($path)) {
        Show-Info "Esta fila no contiene una ruta de archivo abrible." "RUTA"
        return
    }
    Open-SelectedPath -Path $path
}

function Invoke-GridMenuAction([string]$Action) {
    $row = $script:Grid.CurrentRow
    if (-not $row) { return }
    try {
        switch ($Action) {
            'open' { Open-SelectedGridItem }
            'path' {
                $p = Get-RowPath $row
                if ($p) { [System.Windows.Forms.Clipboard]::SetText($p); Set-Status "Ruta copiada al portapapeles." }
                else    { Set-Status "Esta fila no tiene una ruta." }
            }
            'name' { [System.Windows.Forms.Clipboard]::SetText([string]$row.Cells['elemento'].Value); Set-Status "Nombre copiado al portapapeles." }
            'row'  {
                $parts = foreach ($i in 0..3) { [string]$row.Cells[$i].Value }
                [System.Windows.Forms.Clipboard]::SetText(($parts -join ' | '))
                Set-Status "Fila copiada al portapapeles."
            }
        }
    } catch { Set-Status ("No se pudo completar la acción: " + $_.Exception.Message) }
}

function Export-GridView {
    $g = $script:Grid
    if ($null -eq $g -or $g.Rows.Count -eq 0) { Show-Info "No hay datos para exportar." "EXPORTAR"; return }
    try {
        $path = Join-Path ([Environment]::GetFolderPath("Desktop")) ("Sombrio_{0}_{1}.csv" -f $script:ActiveCat, (Get-Date -Format 'yyyyMMdd_HHmmss'))
        $sb = [System.Text.StringBuilder]::new()
        [void]$sb.AppendLine('"NIVEL","TIPO","ELEMENTO","DETALLE"')
        foreach ($r in $g.Rows) {
            $vals = foreach ($i in 0..3) { '"' + (([string]$r.Cells[$i].Value) -replace '"', '""') + '"' }
            [void]$sb.AppendLine(($vals -join ','))
        }
        [System.IO.File]::WriteAllText($path, $sb.ToString(), [System.Text.UTF8Encoding]::new($true))
        Set-Status ("Vista exportada: " + $path)
        try { Start-Process -FilePath "explorer.exe" -ArgumentList ('/select,"' + $path + '"') } catch { }
    } catch { Show-Info ("No se pudo exportar:`n`n" + $_.Exception.Message) "EXPORTAR" }
}

function Clear-Filter {
    $script:SuppressFilter = $true
    $script:FilterText  = ""
    $script:FilterLevel = 'all'
    if ($script:TxtFilter) { $script:TxtFilter.Text = "" }
    if ($script:CmbLevel)  { $script:CmbLevel.SelectedIndex = 0 }
    $script:SuppressFilter = $false
}

# ============================================================
# PROGRESO / ESTADO
# ============================================================
function Set-Status([string]$Text) {
    if ($null -ne $script:LblStatus) { $script:LblStatus.Text = $Text }
    if ($Text -and $Text -ne $script:ActivityLast) { $script:ActivityLast = $Text; Write-Log $Text }
    Invoke-UiPump
}

function Set-Progress([int]$Pct) {
    $Pct = [math]::Max(0, [math]::Min(100, $Pct))
    $script:ProgressPct = $Pct
    if ($null -ne $script:LblPct)  { $script:LblPct.Text = "$Pct%" }
    if ($null -ne $script:BarFill -and $null -ne $script:BarTrack) {
        $script:BarFill.Width = [int]($script:BarTrack.ClientSize.Width * $Pct / 100)
    }
}

function Set-Phase([int]$Step, [int]$Total, [string]$Text) {
    Set-Status $Text
    if ($Total -gt 0) { Set-Progress ([int][math]::Round((($Step - 1) / $Total) * 100)) }
    Invoke-UiPump
}

function Update-ScanMonitor {
    param(
        [long]$Scanned, [int]$Hits, [string]$CurrentFile,
        [datetime]$StartTime, [int]$Percent
    )
    $elapsed = (Get-Date) - $StartTime
    $speed = 0
    if ($elapsed.TotalSeconds -gt 0.5) { $speed = [math]::Round($Scanned / $elapsed.TotalSeconds) }
    try { $ts = $elapsed.ToString("hh\:mm\:ss") } catch { $ts = "{0:hh\:mm\:ss}" -f $elapsed }
    if ($null -ne $script:LblDetail) {
        $script:LblDetail.Text = ("{0:N0} archivos  |  {1:N0} arch/s  |  Rojos: {2}  |  {3}   >   {4}" -f $Scanned, $speed, $Hits, $ts, $CurrentFile)
    }
    Set-Progress $Percent
    Invoke-UiPump
}

function Start-ScanSession([string]$Text, [switch]$ShowPanel) {
    $script:Busy = $true
    $script:CancelRequested = $false
    foreach ($b in $script:NavButtons) {
        if ($b.Tag -notin @('panic', 'exit', 'log', 'sysinfo')) { $b.Enabled = $false }
    }
    if ($null -ne $script:BtnCancel)      { $script:BtnCancel.Visible = $true }
    if ($null -ne $script:BtnReport)      { $script:BtnReport.Visible = $false }
    if ($null -ne $script:BtnOpenSelected){ $script:BtnOpenSelected.Visible = $false }
    if ($null -ne $script:LblDetail)      { $script:LblDetail.Text = "" }
    # Mostrar el panel de resultados desde el inicio (antes quedaba la pantalla de inicio sin nada)
    if ($ShowPanel -and $null -ne $script:Grid) {
        $script:HomeArt.Visible = $false
        $script:Chips.Visible   = $false
        if ($script:FilterBar) { $script:FilterBar.Visible = $false }
        $script:Grid.Visible    = $true
        $script:Grid.Rows.Clear()
        $ri = $script:Grid.Rows.Add("INFO", "", $Text, "Los resultados aparecerán aquí al terminar el análisis...")
        $script:Grid.Rows[$ri].DefaultCellStyle.ForeColor = $script:C.Yellow
        $script:Grid.ClearSelection()
        $script:LblView.Text = "ANALIZANDO..."
    }
    Set-Progress 0
    Set-Status $Text
}

function Stop-ScanSession {
    $script:Busy = $false
    foreach ($b in $script:NavButtons) { $b.Enabled = $true }
    if ($null -ne $script:BtnCancel)      { $script:BtnCancel.Visible = $false }
    if ($script:LastReport -and (Test-Path -LiteralPath $script:LastReport) -and $null -ne $script:BtnReport) { $script:BtnReport.Visible = $true }
    if ($null -ne $script:BtnOpenSelected){ $script:BtnOpenSelected.Visible = $true }
    Invoke-UiPump
    if ($script:CloseAfter) { $script:Form.Close() }
}

# ============================================================
# VISTAS: INICIO / RESULTADOS POR CATEGORÍA
# ============================================================
$script:CatDefs = @(
    @{ Key = "Stats";      Text = "ESTADÍSTICAS" },
    @{ Key = "AntiBypass"; Text = "ANTI-BYPASS" },
    @{ Key = "Memoria";    Text = "MEMORIA" },
    @{ Key = "Prefetch";   Text = "PREFETCH" },
    @{ Key = "Papelera";   Text = "PAPELERA" },
    @{ Key = "Maliciosos"; Text = "MALICIOSOS" },
    @{ Key = "Mods";       Text = "MODS" },
    @{ Key = "Macros";     Text = "MACROS" },
    @{ Key = "Servicios";  Text = "SERVICIOS" },
    @{ Key = "Disco";      Text = "DISCO PROFUNDO" },
    @{ Key = "Historial";  Text = "HISTORIAL" }
)

function Get-CatItems([string]$Key) {
    $src = if ($script:ViewMode -eq 'registry') { $script:RegData } else { $script:CatData }
    if ($src.ContainsKey($Key) -and $src[$Key]) { return @($src[$Key]) }
    return @()
}

function Update-Chips {
    foreach ($def in $script:CatDefs) {
        $k   = $def.Key
        $btn = $script:CatButtons[$k]
        $real = @(Get-CatItems $k | Where-Object { $_ -notmatch '======' })
        $cnt  = $real.Count

        $btn.Text = if ($k -eq 'Stats') { $def.Text } else { "$($def.Text)   ·   $cnt" }

        $hasRed = $false
        if ($k -eq 'Maliciosos') { $hasRed = ($cnt -gt 0) }
        else { foreach ($it in $real) { if ((Get-ItemColor $it) -eq 'Red') { $hasRed = $true; break } } }

        $active = ($k -eq $script:ActiveCat)
        $btn.ForeColor = if ($active) { $script:C.Text } elseif ($hasRed) { $script:C.Red } else { $script:C.Muted }
        $btn.BackColor = if ($active) { $script:C.Select } else { $script:C.Panel2 }
        $btn.FlatAppearance.BorderColor = if ($active) { $script:C.Accent } elseif ($hasRed) { $script:C.RedDark } else { $script:C.Border }
    }
}

function Get-ItemLevel([string]$Item, [string]$Key) {
    $cn = if ($Key -eq 'Maliciosos') { 'Red' } else { Get-ItemColor $Item }
    if ($Key -eq 'Stats' -and $cn -ne 'Red') { return 'INFO' }
    switch ($cn) {
        'Red'    { return 'CRÍTICO' }
        'Yellow' { return 'ALERTA' }
        'Green'  { return 'OK' }
        default  { return 'INFO' }
    }
}

function Add-GridRow {
    param($G, [string]$Item, $P, [string]$Key, [string]$Level)
    $i = $G.Rows.Add($Level, $P.Tag, $P.Name, $P.Detail)
    $row = $G.Rows[$i]
    if ($Key -eq "Papelera" -and $script:RecycleMeta.ContainsKey($Item)) { $row.Tag = $script:RecycleMeta[$Item] }
    if ($P.Header) {
        # Encabezados: versión de Minecraft en verde, bloques RENOMBRADOS/SOSPECHOSOS en rojo, el resto en teal
        $row.DefaultCellStyle.ForeColor = if ($P.Name -match 'MINECRAFT') { $script:C.Green } elseif ($P.Name -match 'RENOMBRADOS|SOSPECHOSOS') { $script:C.Red } else { $script:C.TealDim }
        $row.DefaultCellStyle.Font = $script:FontBold
    } elseif ($Key -eq 'Maliciosos') {
        $row.DefaultCellStyle.ForeColor = $script:C.Red
    } else {
        $row.DefaultCellStyle.ForeColor = ConvertTo-UiColor (Get-ItemColor $Item)
    }
}

function Show-Category([string]$Key) {
    $script:ActiveCat = $Key
    $items = @(Get-CatItems $Key)
    $g = $script:Grid
    $g.SuspendLayout()
    $g.Rows.Clear()

    $text = [string]$script:FilterText
    $filtering = (-not [string]::IsNullOrWhiteSpace($text)) -or ($script:FilterLevel -ne 'all')
    $total = 0; $crit = 0; $warn = 0; $shown = 0
    $pendItem = $null; $pendP = $null

    foreach ($it in $items) {
        $str = [string]$it
        $p = Split-ReportItem $str
        if ($p.Header) {
            if ($filtering) { $pendItem = $str; $pendP = $p } else { Add-GridRow $g $str $p $Key '' }
            continue
        }
        $lvl = Get-ItemLevel $str $Key
        $total++
        if ($lvl -eq 'CRÍTICO') { $crit++ } elseif ($lvl -eq 'ALERTA') { $warn++ }
        if ($filtering) {
            if ($script:FilterLevel -eq 'red'  -and $lvl -ne 'CRÍTICO') { continue }
            if ($script:FilterLevel -eq 'warn' -and $lvl -notin @('CRÍTICO', 'ALERTA')) { continue }
            if ($text -and $str.IndexOf($text, [StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
            if ($null -ne $pendItem) { Add-GridRow $g $pendItem $pendP $Key ''; $pendItem = $null }
        }
        Add-GridRow $g $str $p $Key $lvl
        $shown++
    }

    if ($items.Count -eq 0) {
        $i = $g.Rows.Add("OK", "", "Sin hallazgos registrados.", "---")
        $g.Rows[$i].DefaultCellStyle.ForeColor = $script:C.Green
    } elseif ($shown -eq 0 -and $filtering) {
        $i = $g.Rows.Add("INFO", "", "Ningún registro coincide con el filtro.", "Prueba con otro texto o cambia el nivel (Esc limpia el buscador).")
        $g.Rows[$i].DefaultCellStyle.ForeColor = $script:C.Muted
    }
    if ($script:LblCount) {
        $script:LblCount.Text = ("Mostrando {0} de {1}   ·   Críticos: {2}   ·   Alertas: {3}" -f $shown, $total, $crit, $warn)
        if ($items.Count -eq 0) { $script:LblCount.Text = "Sin registros en esta categoría" }
    }
    $g.ClearSelection()
    $g.ResumeLayout()
    Update-Chips
}

function Move-HomeArt {
    if ($script:HomeArt -and $script:HostPanel) {
        $script:HomeArt.Left = [math]::Max(0, [int](($script:HostPanel.ClientSize.Width  - $script:HomeArt.Width)  / 2))
        $script:HomeArt.Top  = [math]::Max(0, [int](($script:HostPanel.ClientSize.Height - $script:HomeArt.Height) / 2))
    }
}

function Show-Home {
    if ($script:BtnOpenSelected) { $script:BtnOpenSelected.Visible = $false }
    $script:Grid.Visible  = $false
    $script:Chips.Visible = $false
    if ($script:FilterBar) { $script:FilterBar.Visible = $false }
    $script:HomeArt.Visible  = $true
    $script:LblView.Text  = "CONSOLA CENTRAL DE OPERACIONES FORENSES"
    Move-HomeArt
}

function Show-Results {
    if ($script:BtnOpenSelected) { $script:BtnOpenSelected.Visible = $true }
    $script:HomeArt.Visible  = $false
    $script:Grid.Visible  = $true
    $script:Chips.Visible = $true
    Clear-Filter
    if ($script:FilterBar) { $script:FilterBar.Visible = $true }
    $script:LblView.Text  = if ($script:ViewMode -eq 'registry') { "REGISTRO DE ANÁLISIS  ·  MEMORIA ACUMULADA DE SESIÓN" } else { "PANEL DE RESULTADOS" }
    Show-Category $script:ActiveCat
}

function Publish-Results {
    param([hashtable]$Data, [string]$Focus)
    foreach ($k in $Data.Keys) { $script:CatData[$k] = @($Data[$k]) }
    foreach ($def in $script:CatDefs) {
        try {
            $its = @($script:CatData[$def.Key] | Where-Object { $_ -and ([string]$_) -notmatch '======' })
            $nr  = @($its | Where-Object { (Get-ItemColor ([string]$_)) -eq 'Red' }).Count
            Write-Log ("Resultado {0}: {1} elementos, {2} críticos" -f $def.Text, $its.Count, $nr) $(if ($nr -gt 0) { 'WARN' } else { 'INFO' })
        } catch { }
    }
    $script:ViewMode  = 'live'
    $script:ActiveCat = $Focus
    Show-Results
}
# ============================================================
# EL SOMBRIO IF - MEJORAS DE INTERFAZ (bloque para pegar)
#
# DÓNDE PEGARLO: justo ANTES de la línea
#     # REPORTE FORENSE (Escritorio)
# (es decir, después de la función Publish-Results).
# Redefine funciones que ya existen (Update-Chips, Add-GridRow,
# Show-Category, Show-Results): en PowerShell gana la definición
# que aparece después, así que no hace falta borrar las originales.
#
# QUÉ AÑADE:
#   1. Columna NIVEL como insignia de color (CRÍTICO / ALERTA / OK / INFO).
#   2. Franja de tarjetas arriba de la tabla: Críticos, Alertas,
#      Elementos y VEREDICTO global (LIMPIO / REVISAR / SOSPECHOSO).
#   3. Ordenar la tabla con clic en el encabezado (NIVEL ordena por gravedad).
#   4. Punto rojo (●) en las categorías con hallazgos críticos.
#   5. Encabezado de tabla, altura de fila y líneas más limpias.
# ============================================================

# Escala de pantalla (DPI) para que los tamaños en píxeles se vean bien en pantallas 125% / 150%
$script:UiScale = 1.0
try { $gfx = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero); $script:UiScale = [math]::Max(1.0, $gfx.DpiY / 96.0); $gfx.Dispose() } catch { }
function Px([double]$n) { return [int][math]::Round($n * $script:UiScale) }

$script:UiEnhanced   = $false
$script:Strip        = $null
$script:StripCards   = @{}
$script:SortCol      = -1
$script:SortAsc      = $true
$script:VerdictKey   = ""
$script:VerdictCache = $null

# Mezcla dos colores (Alpha 0..1 = cuánto pesa Fg sobre Bg)
function Merge-Color([System.Drawing.Color]$Fg, [System.Drawing.Color]$Bg, [double]$Alpha) {
    $r = [int]($Bg.R + ($Fg.R - $Bg.R) * $Alpha)
    $g = [int]($Bg.G + ($Fg.G - $Bg.G) * $Alpha)
    $b = [int]($Bg.B + ($Fg.B - $Bg.B) * $Alpha)
    return [System.Drawing.Color]::FromArgb($r, $g, $b)
}

function Get-LevelRank([string]$Level) {
    switch ($Level) {
        'CRÍTICO' { return 0 }
        'ALERTA'  { return 1 }
        'INFO'    { return 2 }
        'OK'      { return 3 }
        default   { return 4 }
    }
}

function Get-LevelStyle([string]$Level) {
    $c = $script:C
    switch ($Level) {
        'CRÍTICO' { return @{ Fore = $c.Red;    Back = (Merge-Color $c.Red    $c.Panel 0.24) } }
        'ALERTA'  { return @{ Fore = $c.Yellow; Back = (Merge-Color $c.Yellow $c.Panel 0.20) } }
        'OK'      { return @{ Fore = $c.Green;  Back = (Merge-Color $c.Green  $c.Panel 0.14) } }
        default   { return @{ Fore = $c.Accent; Back = (Merge-Color $c.Accent $c.Panel 0.12) } }
    }
}

# ------------------------------------------------------------
# Veredicto global (con caché para no recalcular al cambiar de pestaña)
# ------------------------------------------------------------
function Get-GlobalVerdict {
    $key = $script:ViewMode
    $anyData = $false
    foreach ($def in $script:CatDefs) {
        $n = @(Get-CatItems $def.Key).Count
        if ($n -gt 0) { $anyData = $true }
        $key += "|$n"
    }
    if ($key -eq $script:VerdictKey -and $script:VerdictCache) { return $script:VerdictCache }

    $crit = @(Get-CatItems 'Maliciosos' | Where-Object { $_ -notmatch '======' }).Count
    $warn = 0
    if ($crit -eq 0) {
        foreach ($def in $script:CatDefs) {
            if ($def.Key -in @('Stats', 'Maliciosos')) { continue }
            foreach ($it in @(Get-CatItems $def.Key)) {
                $s = [string]$it
                if ($s -match '======') { continue }
                $cn = Get-ItemColor $s
                if ($cn -eq 'Red') { $crit++ } elseif ($cn -eq 'Yellow') { $warn++ }
            }
        }
    }

    $res = if (-not $anyData)  { @{ Text = 'SIN DATOS';    Color = 'Muted'  } }
           elseif ($crit -gt 0) { @{ Text = 'SOSPECHOSO';  Color = 'Red'    } }
           elseif ($warn -gt 0) { @{ Text = 'REVISAR';     Color = 'Yellow' } }
           else                 { @{ Text = 'LIMPIO';      Color = 'Green'  } }
    $script:VerdictKey   = $key
    $script:VerdictCache = $res
    return $res
}

# ------------------------------------------------------------
# Franja de tarjetas (se crea una sola vez, la primera vez que se muestran resultados)
# ------------------------------------------------------------
function New-StripCard([string]$Caption) {
    $card = New-Object System.Windows.Forms.Panel
    $card.Dock = 'Fill'
    $card.Margin = [System.Windows.Forms.Padding]::new((Px 4), 0, (Px 4), 0)

    $val = New-Object System.Windows.Forms.Label
    $val.Dock = 'Fill'
    $val.TextAlign = 'MiddleLeft'
    $val.Padding = [System.Windows.Forms.Padding]::new((Px 14), 0, 0, 0)
    $val.Font = New-Object System.Drawing.Font('Segoe UI', [single]16, [System.Drawing.FontStyle]::Bold)
    $val.Text = '0'

    $cap = New-Object System.Windows.Forms.Label
    $cap.Dock = 'Top'
    $cap.Height = (Px 24)
    $cap.TextAlign = 'BottomLeft'
    $cap.Padding = [System.Windows.Forms.Padding]::new((Px 14), 0, 0, 0)
    $cap.Font = New-Object System.Drawing.Font('Segoe UI', [single]8, [System.Drawing.FontStyle]::Regular)
    $cap.Text = $Caption

    $bar = New-Object System.Windows.Forms.Panel
    $bar.Dock = 'Left'
    $bar.Width = (Px 4)

    $card.Controls.Add($val)   # Fill primero
    $card.Controls.Add($cap)
    $card.Controls.Add($bar)
    return @{ Card = $card; Value = $val; Caption = $cap; Bar = $bar }
}

function Initialize-UiEnhancements {
    if ($script:UiEnhanced -or $null -eq $script:Grid) { return }
    $script:UiEnhanced = $true
    $g = $script:Grid

    # --- Estilo general de la tabla ---
    try {
        $g.EnableHeadersVisualStyles = $false
        $g.ColumnHeadersBorderStyle  = 'Single'
        $g.ColumnHeadersHeightSizeMode = 'DisableResizing'
        $g.ColumnHeadersHeight = (Px 34)
        $g.RowTemplate.Height  = (Px 26)
        $g.CellBorderStyle     = 'SingleHorizontal'
        $g.GridColor           = $script:C.Border
        $hs = $g.ColumnHeadersDefaultCellStyle
        $hs.BackColor          = $script:C.Panel2
        $hs.ForeColor          = $script:C.Muted
        $hs.SelectionBackColor = $script:C.Panel2
        $hs.SelectionForeColor = $script:C.Text
        $hs.Alignment          = 'MiddleLeft'
        $hs.Padding            = [System.Windows.Forms.Padding]::new((Px 8), 0, 0, 0)
        $hs.Font               = New-Object System.Drawing.Font('Segoe UI', [single]9, [System.Drawing.FontStyle]::Bold)
        foreach ($col in $g.Columns) { $col.SortMode = 'Programmatic' }
    } catch { }

    # --- Ordenar con clic en el encabezado ---
    try {
        $g.add_SortCompare({
            param($s, $e)
            try {
                $a = [string]$e.CellValue1; $b = [string]$e.CellValue2
                if ($e.Column.Index -eq 0) {
                    $e.SortResult = (Get-LevelRank $a) - (Get-LevelRank $b)
                } else {
                    $e.SortResult = [string]::Compare($a, $b, [StringComparison]::OrdinalIgnoreCase)
                }
                $e.Handled = $true
            } catch { }
        })
        $g.add_ColumnHeaderMouseClick({
            param($s, $e)
            try {
                if ($script:ActiveCat -eq 'Mods') {
                    Set-Status "MODS se mantiene agrupado por versión de Minecraft (no se reordena)."
                    return
                }
                if ($script:SortCol -eq $e.ColumnIndex) { $script:SortAsc = -not $script:SortAsc }
                else { $script:SortCol = $e.ColumnIndex; $script:SortAsc = $true }
                $dir = if ($script:SortAsc) { 'Ascending' } else { 'Descending' }
                foreach ($c in $s.Columns) { $c.HeaderCell.SortGlyphDirection = 'None' }
                $s.Sort($s.Columns[$e.ColumnIndex], [System.ComponentModel.ListSortDirection]$dir)
                $s.Columns[$e.ColumnIndex].HeaderCell.SortGlyphDirection = if ($script:SortAsc) { 'Ascending' } else { 'Descending' }
            } catch { }
        })
    } catch { }

    # --- Franja de tarjetas arriba de la tabla ---
    try {
        $hp = $g.Parent
        if ($hp -and $g.Dock -eq 'Fill') {
            $strip = New-Object System.Windows.Forms.TableLayoutPanel
            $strip.Dock = 'Top'
            $strip.Height = (Px 76)
            $strip.ColumnCount = 4
            $strip.RowCount = 1
            $strip.Padding = [System.Windows.Forms.Padding]::new(0, (Px 6), 0, (Px 6))
            for ($i = 0; $i -lt 4; $i++) {
                [void]$strip.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 25)))
            }
            [void]$strip.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 100)))

            $names = @(@('Crit', 'CRÍTICOS'), @('Warn', 'ALERTAS'), @('Total', 'ELEMENTOS'), @('Verdict', 'VEREDICTO'))
            for ($i = 0; $i -lt 4; $i++) {
                $cd = New-StripCard $names[$i][1]
                $script:StripCards[$names[$i][0]] = $cd
                $strip.Controls.Add($cd.Card, $i, 0)
            }
            $hp.Controls.Add($strip)
            $script:Strip = $strip
            $strip.Visible = $g.Visible

            # La franja sigue a los chips: visible solo en el panel de resultados
            if ($script:Chips) {
                $script:Chips.add_VisibleChanged({
                    if ($script:Strip -and $script:Chips) { $script:Strip.Visible = $script:Chips.Visible }
                })
            }
        }
    } catch { $script:Strip = $null }
}

function Update-SummaryStrip([int]$Total, [int]$Crit, [int]$Warn) {
    if ($null -eq $script:Strip) { return }
    try {
        $c = $script:C
        $script:Strip.BackColor = $c.Bg
        $verdict = Get-GlobalVerdict
        $vColor = switch ($verdict.Color) { 'Red' { $c.Red } 'Yellow' { $c.Yellow } 'Green' { $c.Green } default { $c.Muted } }
        $data = @{
            Crit    = @{ Text = "$Crit";  Color = $(if ($Crit -gt 0) { $c.Red }    else { $c.Muted }) }
            Warn    = @{ Text = "$Warn";  Color = $(if ($Warn -gt 0) { $c.Yellow } else { $c.Muted }) }
            Total   = @{ Text = "$Total"; Color = $c.Accent }
            Verdict = @{ Text = $verdict.Text; Color = $vColor }
        }
        foreach ($k in $data.Keys) {
            $cd = $script:StripCards[$k]
            $cd.Card.BackColor    = $c.Panel2
            $cd.Value.BackColor   = $c.Panel2
            $cd.Caption.BackColor = $c.Panel2
            $cd.Caption.ForeColor = $c.Muted
            $cd.Value.Text        = $data[$k].Text
            $cd.Value.ForeColor   = $data[$k].Color
            $cd.Bar.BackColor     = $data[$k].Color
        }
    } catch { }
}

# ============================================================
# FUNCIONES REDEFINIDAS (sobrescriben a las originales)
# ============================================================

function Update-Chips {
    foreach ($def in $script:CatDefs) {
        $k   = $def.Key
        $btn = $script:CatButtons[$k]
        $real = @(Get-CatItems $k | Where-Object { $_ -notmatch '======' })
        $cnt  = $real.Count

        $hasRed = $false
        if ($k -eq 'Maliciosos') { $hasRed = ($cnt -gt 0) }
        else { foreach ($it in $real) { if ((Get-ItemColor $it) -eq 'Red') { $hasRed = $true; break } } }

        $label = if ($k -eq 'Stats') { $def.Text } else { "$($def.Text)   ·   $cnt" }
        if ($hasRed -and $k -ne 'Stats') { $label = "●  $label" }   # punto rojo = hay críticos
        $btn.Text = $label

        $active = ($k -eq $script:ActiveCat)
        $btn.ForeColor = if ($active) { $script:C.Text } elseif ($hasRed) { $script:C.Red } else { $script:C.Muted }
        $btn.BackColor = if ($active) { $script:C.Select } else { $script:C.Panel2 }
        $btn.FlatAppearance.BorderColor = if ($active) { $script:C.Accent } elseif ($hasRed) { $script:C.RedDark } else { $script:C.Border }
    }
}

function Add-GridRow {
    param($G, [string]$Item, $P, [string]$Key, [string]$Level)
    $i = $G.Rows.Add($Level, $P.Tag, $P.Name, $P.Detail)
    $row = $G.Rows[$i]
    if ($Key -eq "Papelera" -and $script:RecycleMeta.ContainsKey($Item)) { $row.Tag = $script:RecycleMeta[$Item] }

    if ($P.Header) {
        $row.DefaultCellStyle.ForeColor = if ($P.Name -match 'MINECRAFT') { $script:C.Green } elseif ($P.Name -match 'RENOMBRADOS|SOSPECHOSOS') { $script:C.Red } else { $script:C.TealDim }
        $row.DefaultCellStyle.BackColor = $script:C.Panel2
        $row.DefaultCellStyle.Font = $script:FontBold
        $row.Height = (Px 30)
        return
    }

    if ($Key -eq 'Maliciosos') { $row.DefaultCellStyle.ForeColor = $script:C.Red }
    else { $row.DefaultCellStyle.ForeColor = ConvertTo-UiColor (Get-ItemColor $Item) }

    # Insignia de color en la columna NIVEL
    if ($Level) {
        $st = Get-LevelStyle $Level
        $cell = $row.Cells[0]
        $cell.Style.ForeColor          = $st.Fore
        $cell.Style.BackColor          = $st.Back
        $cell.Style.SelectionForeColor = $st.Fore
        $cell.Style.SelectionBackColor = $st.Back
        $cell.Style.Alignment          = 'MiddleCenter'
        if ($script:FontBold) { $cell.Style.Font = $script:FontBold }
    }
}

function Show-Category([string]$Key) {
    $script:ActiveCat = $Key
    $items = @(Get-CatItems $Key)
    $g = $script:Grid
    $g.SuspendLayout()
    $g.Rows.Clear()

    # Al cambiar de categoría se reinicia el orden manual
    $script:SortCol = -1; $script:SortAsc = $true
    try { foreach ($c in $g.Columns) { $c.HeaderCell.SortGlyphDirection = 'None' } } catch { }

    $text = [string]$script:FilterText
    $filtering = (-not [string]::IsNullOrWhiteSpace($text)) -or ($script:FilterLevel -ne 'all')
    $total = 0; $crit = 0; $warn = 0; $shown = 0
    $pendItem = $null; $pendP = $null

    foreach ($it in $items) {
        $str = [string]$it
        $p = Split-ReportItem $str
        if ($p.Header) {
            if ($filtering) { $pendItem = $str; $pendP = $p } else { Add-GridRow $g $str $p $Key '' }
            continue
        }
        $lvl = Get-ItemLevel $str $Key
        $total++
        if ($lvl -eq 'CRÍTICO') { $crit++ } elseif ($lvl -eq 'ALERTA') { $warn++ }
        if ($filtering) {
            if ($script:FilterLevel -eq 'red'  -and $lvl -ne 'CRÍTICO') { continue }
            if ($script:FilterLevel -eq 'warn' -and $lvl -notin @('CRÍTICO', 'ALERTA')) { continue }
            if ($text -and $str.IndexOf($text, [StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
            if ($null -ne $pendItem) { Add-GridRow $g $pendItem $pendP $Key ''; $pendItem = $null }
        }
        Add-GridRow $g $str $p $Key $lvl
        $shown++
    }

    if ($items.Count -eq 0) {
        $i = $g.Rows.Add("OK", "", "Sin hallazgos registrados.", "---")
        $g.Rows[$i].DefaultCellStyle.ForeColor = $script:C.Green
        $st = Get-LevelStyle 'OK'
        $g.Rows[$i].Cells[0].Style.ForeColor = $st.Fore
        $g.Rows[$i].Cells[0].Style.BackColor = $st.Back
        $g.Rows[$i].Cells[0].Style.Alignment = 'MiddleCenter'
    } elseif ($shown -eq 0 -and $filtering) {
        $i = $g.Rows.Add("INFO", "", "Ningún registro coincide con el filtro.", "Prueba con otro texto o cambia el nivel (Esc limpia el buscador).")
        $g.Rows[$i].DefaultCellStyle.ForeColor = $script:C.Muted
    }
    if ($script:LblCount) {
        $script:LblCount.Text = ("Mostrando {0} de {1}   ·   Críticos: {2}   ·   Alertas: {3}" -f $shown, $total, $crit, $warn)
        if ($items.Count -eq 0) { $script:LblCount.Text = "Sin registros en esta categoría" }
    }
    $g.ClearSelection()
    $g.ResumeLayout()
    Update-Chips
    Update-SummaryStrip $total $crit $warn
}

function Show-Results {
    if ($script:BtnOpenSelected) { $script:BtnOpenSelected.Visible = $true }
    Initialize-UiEnhancements
    $script:HomeArt.Visible  = $false
    $script:Grid.Visible  = $true
    $script:Chips.Visible = $true
    Clear-Filter
    if ($script:FilterBar) { $script:FilterBar.Visible = $true }
    if ($script:Strip)     { $script:Strip.Visible = $true }
    $script:LblView.Text  = if ($script:ViewMode -eq 'registry') { "REGISTRO DE ANÁLISIS  ·  MEMORIA ACUMULADA DE SESIÓN" } else { "PANEL DE RESULTADOS" }
    Show-Category $script:ActiveCat
}

# ============================================================
# FIN DEL BLOQUE DE MEJORAS
# ============================================================


# ============================================================
# REPORTE FORENSE (Escritorio)
# ============================================================
function Save-Report {
    param($Sections)
    $path = Join-Path ([Environment]::GetFolderPath("Desktop")) "Reporte_Sombrio_V81.txt"
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("===============================================================")
    [void]$sb.AppendLine(" REPORTE FORENSE - EL SOMBRIO IF V81")
    [void]$sb.AppendLine((" Fecha: {0}  |  Equipo: {1}  |  Usuario: {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $env:COMPUTERNAME, $env:USERNAME))
    [void]$sb.AppendLine("===============================================================")
    foreach ($title in $Sections.Keys) {
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("--- $title ---")
        $items = @($Sections[$title])
        if ($items.Count -eq 0) { [void]$sb.AppendLine("  (sin hallazgos)") }
        else { foreach ($it in $items) { [void]$sb.AppendLine("  $it") } }
    }
    [System.IO.File]::WriteAllText($path, $sb.ToString(), [System.Text.UTF8Encoding]::new($true))
    return $path
}

# ============================================================
# MÓDULOS DE ESCANEO
# ============================================================
function Invoke-DiskScan {
    param($Disco, $Maliciosos, $Mods = $null, [datetime]$StartTime, [int]$BasePct, [int]$SpanPct)

    $script:DiskModCount = 0

    $targetExt = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@('.jar','.zip','.exe','.dll','.ahk','.au3','.msi','.bat','.cmd','.ps1','.vbs','.scr','.hta','.com'),
        [System.StringComparer]::OrdinalIgnoreCase)

    $sysDrive = ($env:SystemDrive + "\")
    $drives = [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady -and $_.DriveType -eq 'Fixed' }

    $dirsToScan = @()
    $expectedBytes = 0L
    foreach ($drive in $drives) {
        $used = $drive.TotalSize - $drive.AvailableFreeSpace
        if ($drive.Name -eq $sysDrive) {
            $dirsToScan += "$env:USERPROFILE"
            if (Test-Path "${sysDrive}ProgramData") { $dirsToScan += "${sysDrive}ProgramData" }
            $expectedBytes += [math]::Min($used, 20000000000)   # estimación para el disco del sistema
        } else {
            $dirsToScan += $drive.RootDirectory.FullName
            $expectedBytes += $used
        }
    }
    if ($expectedBytes -lt 1000000000) { $expectedBytes = 1000000000 }

    $scannedBytes = 0L
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $lastMs = 0L

    foreach ($root in $dirsToScan) {
        if ($script:CancelRequested) { break }
        if (-not (Test-Path -LiteralPath $root)) { continue }

        $stack = [System.Collections.Generic.Stack[string]]::new()
        $stack.Push($root)

        while ($stack.Count -gt 0) {
            if ($script:CancelRequested) { break }
            $cur = $stack.Pop()
            $di  = [System.IO.DirectoryInfo]::new($cur)

            try {
                foreach ($sd in $di.GetDirectories()) {
                    if (-not ($sd.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) { $stack.Push($sd.FullName) }
                }
            } catch { }

            $files = $null
            try { $files = $di.GetFiles() } catch { continue }

            foreach ($f in $files) {
                $script:ScanCount++
                $scannedBytes += $f.Length

                if (($script:ScanCount % 60) -eq 0 -and ($sw.ElapsedMilliseconds - $lastMs) -gt 100) {
                    $diskPct = [math]::Min(99, [math]::Round(($scannedBytes / $expectedBytes) * 100))
                    $overall = $BasePct + [math]::Round($diskPct * $SpanPct / 100)
                    Update-ScanMonitor -Scanned $script:ScanCount -Hits $script:DeepHits `
                        -CurrentFile $f.FullName -StartTime $StartTime -Percent $overall
                    $lastMs = $sw.ElapsedMilliseconds
                    if ($script:CancelRequested) { break }
                }

                if (-not $targetExt.Contains($f.Extension)) { continue }
                $full = $f.FullName
                if ($script:RxPathWhitelist.IsMatch($full)) { continue }
                # V76 - Extensión falsa por cabecera (MZ/PK camuflado)
                $magicHit = Test-MagicMismatch -Path $full -Extension $f.Extension
                if ($magicHit) {
                    $script:DeepHits++
                    $Disco.Add("[EXTENSIÓN FALSA] $($f.Name) | Ruta: $full | Motivo: $magicHit")
                    $Maliciosos.Add("[EXTENSIÓN FALSA] $($f.Name) | Ruta: $full | Motivo: $magicHit")
                }
                # V76 - Metadatos PE internos (ejecutables renombrados)
                if ($f.Extension -in '.exe','.dll','.sys','.scr','.com') {
                    $peHit = Test-PeSuspicious -Path $full
                    if ($peHit) {
                        $script:DeepHits++
                        $Disco.Add("[ARCHIVO RENOMBRADO] $($f.Name) | Ruta: $full | Nombre interno: $peHit")
                        $Maliciosos.Add("[ARCHIVO RENOMBRADO] $($f.Name) | Ruta: $full | Nombre interno: $peHit")
                    }
                }
                # .jar de cualquier carpeta del disco = posible mod (la carpeta .minecraft\mods se audita aparte)
                $isJar = ($null -ne $Mods -and $f.Extension -eq '.jar' -and -not $full.StartsWith($script:DefaultModsPath, [StringComparison]::OrdinalIgnoreCase))
                if ($isJar) { $script:DiskModCount++ }
                # V76 - Contenido interno de .jar/.zip renombrados
                if ($f.Extension -in '.jar','.zip') {
                    $jarHit = Test-JarContentSuspicious -Path $full
                    if ($jarHit) {
                        $script:DeepHits++
                        if ($isJar) {
                            $Mods.Add("[MOD ILEGAL RENOMBRADO] $($f.Name) | Ruta: $full | Contenido: $jarHit")
                            $Maliciosos.Add("[MOD ILEGAL RENOMBRADO] $($f.Name) | Ruta: $full | Contenido: $jarHit")
                        } else {
                            $Disco.Add("[ARCHIVO RENOMBRADO] $($f.Name) | Ruta: $full | Contenido: $jarHit")
                            $Maliciosos.Add("[ARCHIVO RENOMBRADO] $($f.Name) | Ruta: $full | Contenido: $jarHit")
                        }
                    }
                }
                $hit  = ($script:RxHacks.IsMatch($f.Name) -or $script:RxMacroCritical.IsMatch($f.Name))
                $tiny = ($isJar -and $f.Length -lt 15KB -and $full -match 'mods|minecraft')
                if ($hit -or $tiny) {
                    $script:DeepHits++
                    # V76 - Alternate Data Streams ocultos (macros escondidas)
                    foreach ($ads in @(Get-SuspiciousAds -Path $full)) {
                        $Disco.Add("[ADS SOSPECHOSO] $($f.Name) | Ruta: $full | Stream: $ads")
                        $Maliciosos.Add("[ADS SOSPECHOSO] $($f.Name) | Ruta: $full | Stream: $ads")
                    }
                    if ($hit) { $Disco.Add("[ARCHIVO ILEGAL] $($f.Name) | Ruta: $full") }
                    if ($isJar) {
                        if ($hit) {
                            $Mods.Add("[MOD ILEGAL] $($f.Name) | Ruta: $full")
                            $Maliciosos.Add("[MOD ILEGAL] $($f.Name) | Ruta: $full")
                        } else {
                            $Mods.Add("[MOD SOSPECHOSO] $($f.Name) | Ruta: $full | Motivo: tamaño anómalo ($([math]::Round($f.Length/1KB,1)) KB)")
                            $Maliciosos.Add("[MOD SOSPECHOSO] $($f.Name) | Ruta: $full | Motivo: tamaño anómalo")
                        }
                    } else {
                        $Maliciosos.Add("[EN DISCO] $($f.Name) | Ruta: $full")
                    }
                } elseif ($isJar) {
                    $Mods.Add("[MOD APROBADO] $($f.Name) | Ruta: $full")
                }
            }
        }
    }
    Update-ScanMonitor -Scanned $script:ScanCount -Hits $script:DeepHits -CurrentFile "COMPLETADO" -StartTime $StartTime -Percent 100
}

function Start-GlobalScan {
    Start-ScanSession "Iniciando auditoría global..." -ShowPanel
    try {
        $memoria     = [System.Collections.Generic.List[string]]::new()
        $prefetchHoy = [System.Collections.Generic.List[string]]::new()
        $maliciosos  = [System.Collections.Generic.List[string]]::new()
        $mods        = [System.Collections.Generic.List[string]]::new()
        $macros      = [System.Collections.Generic.List[string]]::new()
        $servicios   = [System.Collections.Generic.List[string]]::new()
        $disco       = [System.Collections.Generic.List[string]]::new()
        $statsBox    = [System.Collections.Generic.List[string]]::new()

        $script:ScanCount = 0
        $script:DeepHits  = 0
        $script:JarVersionProbes = 0
        $script:ContentProbes   = 0
        $papeleraData = [System.Collections.Generic.List[string]]::new()
        $script:RecycleMeta = @{}
        $scanStart = Get-Date
        $cRam = 0; $cPref = 0; $cPap = 0; $cMods = 0; $cSvc = 3

        # 1 - Memoria
        if (-not $script:CancelRequested) {
            try {
                Set-Phase 1 7 "1/7  Analizando Memoria RAM..."
                $allProcs = Get-Process -ErrorAction SilentlyContinue
                $cRam = @($allProcs).Count
                foreach ($proc in ($allProcs | Where-Object { $script:RxMcProcess.IsMatch($_.Name) })) {
                    $memoria.Add("[JAVA] INSTANCIA ACTIVA : $($proc.Name).exe | Ruta: Memoria (PID: $($proc.Id))")
                }
                foreach ($proc in ($allProcs | Where-Object { $script:RxMacroCritical.IsMatch($_.Name) })) {
                    $memoria.Add("[PROCESO MACRO MALICIOSO] $($proc.Name).exe | Ruta: Memoria (PID: $($proc.Id))")
                    $maliciosos.Add("[EN MEMORIA] $($proc.Name).exe | PID: $($proc.Id)")
                }
                # V76 - Procesos cuyo archivo fue renombrado (metadatos PE internos)
                foreach ($proc in ($allProcs | Where-Object { $_.Path -and -not $script:RxPathWhitelist.IsMatch($_.Path) })) {
                    $viProc = Test-PeSuspicious -Path $proc.Path
                    if ($viProc) {
                        $memoria.Add("[PROCESO RENOMBRADO] $($proc.Name).exe | Nombre interno: $viProc | Ruta: $($proc.Path)")
                        $maliciosos.Add("[PROCESO RENOMBRADO] $($proc.Name).exe | Nombre interno: $viProc")
                    }
                }
                # V76 - Ventanas activas del escritorio con títulos de cheats/clients
                foreach ($wt in @(Find-CheatWindows)) {
                    if (-not $memoria.Contains("[VENTANA CHEAT] $wt")) {
                        $memoria.Add("[VENTANA CHEAT] $wt | Ruta: Ventana activa en el escritorio")
                        $maliciosos.Add("[VENTANA CHEAT] $wt")
                    }
                }
                Add-ToLog $script:LogMemoria $memoria
            } catch { }
        }

        # 2 - Prefetch
        if (-not $script:CancelRequested) {
            try {
                Set-Phase 2 7 "2/7  Extrayendo Prefetch..."
                $hoy = (Get-Date).Date
                $pfFiles = @(Get-ChildItem -Path "C:\Windows\Prefetch" -Filter "*.pf" -ErrorAction SilentlyContinue)
                $cPref = $pfFiles.Count
                foreach ($item in ($pfFiles | Where-Object { $_.LastWriteTime.Date -ge $hoy } | Sort-Object LastWriteTime -Descending)) {
                    if ($script:RxHacks.IsMatch($item.Name)) {
                        $prefetchHoy.Add("[PREFETCH MALICIOSO] $($item.Name) | Hora: $($item.LastWriteTime)")
                        $maliciosos.Add("[PREFETCH HACK] $($item.Name) | Hora: $($item.LastWriteTime)")
                    } else {
                        $prefetchHoy.Add("[PREFETCH] $($item.Name) | Hora: $($item.LastWriteTime)")
                    }
                }
                Add-ToLog $script:LogPrefetch $prefetchHoy
            } catch { }
        }

        # 3 - Papelera
        if (-not $script:CancelRequested) {
            try {
                Set-Phase 3 7 "3/7  Analizando Papelera de Reciclaje..."
                $shell    = New-Object -ComObject Shell.Application
                $papelera = $shell.NameSpace(10)

                if ($papelera) {
                    $cPap = $papelera.Items().Count

                    foreach ($item in $papelera.Items()) {
                        $name = [string]$item.Name
                        $originalPath = ""
                        $deletedAt = $null
                        $recyclePath = [string]$item.Path

                        try { $originalPath = [string]$item.ExtendedProperty("System.Recycle.ItemPathDisplay") } catch { }
                        try { $deletedAt = $item.ExtendedProperty("System.Recycle.DateDeleted") } catch { }

                        if ([string]::IsNullOrWhiteSpace($originalPath)) {
                            try { $originalPath = [string]$item.ExtendedProperty("System.ItemPathDisplay") } catch { }
                        }

                        $deletedText = if ($deletedAt -is [datetime]) {
                            $deletedAt.ToString("yyyy-MM-dd HH:mm:ss")
                        } elseif ($deletedAt) {
                            [string]$deletedAt
                        } else {
                            "Fecha no disponible"
                        }

                        $entry = "[PAPELERA] $name | Ruta original: $originalPath | Eliminado: $deletedText | Papelera: $recyclePath"
                        $papeleraData.Add($entry)
                        $script:RecycleMeta[$entry] = [pscustomobject]@{
                            Name = $name
                            OriginalPath = $originalPath
                            DeletedAt = $deletedText
                            RecyclePath = $recyclePath
                            Path = $recyclePath
                        }

                        if ($script:RxHacks.IsMatch($name)) {
                            $maliciosos.Add("[PAPELERA HACK] $name | Ruta original: $originalPath | Eliminado: $deletedText")
                        }
                    }

                    Add-ToLog $script:LogPapelera $papeleraData
                }
            } catch { }
        }

        # 4 - Mods
        if (-not $script:CancelRequested) {
            try {
                Set-Phase 4 7 "4/7  Auditando .minecraft/mods (el resto de mods del disco se detecta en el paso 7)..."
                if (Test-Path $script:DefaultModsPath) {
                    $localMods = @(Get-ChildItem -Path $script:DefaultModsPath -Recurse -File -Include "*.jar","*.zip","*.dll" -ErrorAction SilentlyContinue)
                    $cMods = $localMods.Count
                    foreach ($mod in $localMods) {
                        $innerMod = Test-JarContentSuspicious -Path $mod.FullName
                        if ($innerMod) {
                            $mods.Add("[MOD ILEGAL RENOMBRADO] $($mod.Name) | Ruta: $($mod.FullName) | Contenido: $innerMod")
                            $maliciosos.Add("[MOD RENOMBRADO] $($mod.Name) | Ruta: $($mod.FullName) | Contenido: $innerMod")
                        } elseif ($script:RxHacks.IsMatch($mod.Name)) {
                            $mods.Add("[MOD ILEGAL] $($mod.Name) | Ruta: $($mod.FullName)")
                            $maliciosos.Add("[MOD ILEGAL] $($mod.Name) | Ruta: $($mod.FullName)")
                        } elseif ($mod.Length -lt 15KB) {
                            $mods.Add("[MOD SOSPECHOSO] $($mod.Name) | Ruta: $($mod.FullName) | Motivo: tamaño anómalo ($([math]::Round($mod.Length/1KB,1)) KB)")
                            $maliciosos.Add("[MOD SOSPECHOSO] $($mod.Name) | Ruta: $($mod.FullName) | Motivo: tamaño anómalo")
                        } else {
                            $mods.Add("[MOD APROBADO] $($mod.Name) | Ruta: $($mod.FullName)")
                        }
                    }
                }
            } catch { }
        }

        # 5 - Macros (V75: procesos + software instalado + startup)
        if (-not $script:CancelRequested) {
            try {
                Set-Phase 5 7 "5/7  Verificando Macros, Autoclickers y software de periféricos..."
                foreach ($proc in (Get-Process -ErrorAction SilentlyContinue | Where-Object { $script:RxMacroCritical.IsMatch($_.Name) })) {
                    $maliciosos.Add("[EN MEMORIA] $($proc.Name).exe | PID: $($proc.Id)")
                }

                # Software de macros instalado (registro de Windows)
                $uninstKeys = @(
                    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
                )
                foreach ($app in @(Get-ItemProperty -Path $uninstKeys -ErrorAction SilentlyContinue)) {
                    $dn = [string]$app.DisplayName
                    if ([string]::IsNullOrWhiteSpace($dn)) { continue }
                    if ($script:RxPeriph.IsMatch($dn)) {
                        $macros.Add("[PERIFÉRICO ALERTA] $dn | Software de periférico instalado (puede guardar macros) | Ruta: $($app.InstallLocation)")
                    } elseif ($script:RxMacroStrict.IsMatch($dn)) {
                        $macros.Add("[SOFTWARE DE MACROS] $dn | Ruta: $($app.InstallLocation)")
                        $maliciosos.Add("[SOFTWARE DE MACROS] $dn | Ruta: $($app.InstallLocation)")
                    }
                }
                Invoke-UiPump

                # Tareas programadas (se omiten las de Microsoft)
                try {
                    foreach ($t in @(Get-ScheduledTask -ErrorAction Stop)) {
                        if ($t.TaskPath -like '\Microsoft\*') { continue }
                        $acts = (@($t.Actions) | ForEach-Object { "$($_.Execute) $($_.Arguments)" }) -join ' '
                        $blob = "$($t.TaskName) $acts"
                        if ($script:RxMacroStrict.IsMatch($blob) -and -not $script:RxPathWhitelist.IsMatch($blob)) {
                            $macros.Add("[TAREA PROGRAMADA MACRO] $($t.TaskName) | Ruta: $($acts.Trim())")
                            $maliciosos.Add("[TAREA PROGRAMADA MACRO] $($t.TaskName) | Ruta: $($acts.Trim())")
                        }
                    }
                } catch { }

                # Servicios instalados con nombre de macro/autoclicker
                foreach ($svc in @(Get-Service -ErrorAction SilentlyContinue)) {
                    if ($script:RxMacroStrict.IsMatch("$($svc.Name) $($svc.DisplayName)")) {
                        $macros.Add("[SERVICIO MACRO] $($svc.DisplayName) | Estado: $($svc.Status)")
                        $maliciosos.Add("[SERVICIO MACRO] $($svc.DisplayName) | Estado: $($svc.Status)")
                    }
                }

                # Autoarranque: claves Run / RunOnce
                $runKeys = @(
                    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
                    'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce',
                    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run',
                    'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
                )
                foreach ($rk in $runKeys) {
                    if (-not (Test-Path -Path $rk)) { continue }
                    $rkProps = Get-ItemProperty -Path $rk -ErrorAction SilentlyContinue
                    if ($null -eq $rkProps) { continue }
                    foreach ($rp in $rkProps.PSObject.Properties) {
                        if ($rp.Name -like 'PS*') { continue }
                        $rv = [string]$rp.Value
                        $blob = "$($rp.Name) $rv"
                        if ($script:RxMacroStrict.IsMatch($blob) -or $script:RxHacks.IsMatch($blob)) {
                            $macros.Add("[AUTOARRANQUE] $($rp.Name) | Ruta: $rv | Clave: $rk")
                            $maliciosos.Add("[AUTOARRANQUE] $($rp.Name) | Ruta: $rv")
                        }
                    }
                }

                # Carpetas de Inicio (Startup)
                foreach ($sd in @("$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup", "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup")) {
                    if (-not (Test-Path -LiteralPath $sd)) { continue }
                    foreach ($sf in @(Get-ChildItem -LiteralPath $sd -File -ErrorAction SilentlyContinue)) {
                        if ($script:RxMacroStrict.IsMatch($sf.Name) -or $script:RxHacks.IsMatch($sf.Name)) {
                            $macros.Add("[AUTOARRANQUE] $($sf.Name) | Ruta: $($sf.FullName)")
                            $maliciosos.Add("[AUTOARRANQUE] $($sf.Name) | Ruta: $($sf.FullName)")
                        }
                    }
                }

                # Archivos de macros en carpetas del usuario
                $macroExt = [System.Collections.Generic.HashSet[string]]::new(
                    [string[]]@('.exe', '.ahk', '.au3', '.vbs', '.scr', '.bat', '.cmd', '.ps1', '.lnk', '.jar', '.dll'),
                    [System.StringComparer]::OrdinalIgnoreCase)
                $userDirs = @(
                    "$env:USERPROFILE\Desktop", "$env:USERPROFILE\Downloads", "$env:USERPROFILE\Documents",
                    "$env:APPDATA", "$env:LOCALAPPDATA\Temp"
                )
                foreach ($ud in $userDirs) {
                    if ($script:CancelRequested) { break }
                    if (-not (Test-Path -LiteralPath $ud)) { continue }
                    Set-Status "5/7  Revisando archivos en $ud ..."
                    foreach ($mf in @(Get-ChildItem -LiteralPath $ud -Recurse -Depth 3 -File -ErrorAction SilentlyContinue)) {
                        if (-not $macroExt.Contains($mf.Extension)) { continue }
                        if ($script:RxPathWhitelist.IsMatch($mf.FullName)) { continue }
                        if ($script:RxMacroStrict.IsMatch($mf.Name)) {
                            $macros.Add("[ARCHIVO MACRO] $($mf.Name) | Ruta: $($mf.FullName)")
                            $maliciosos.Add("[ARCHIVO MACRO] $($mf.Name) | Ruta: $($mf.FullName)")
                            foreach ($adsName in @(Get-SuspiciousAds -Path $mf.FullName)) {
                                $macros.Add("[ADS SOSPECHOSO] $($mf.Name) | Ruta: $($mf.FullName) | Stream: $adsName")
                                $maliciosos.Add("[ADS SOSPECHOSO] $($mf.Name) | Ruta: $($mf.FullName) | Stream: $adsName")
                            }
                        }
                    }
                    Invoke-UiPump
                }
                Add-ToLog $script:LogMacros $macros
            } catch { }
        }

        # 6 - Servicios de Windows + historial reciente
        $historial = [System.Collections.Generic.List[string]]::new()
        if (-not $script:CancelRequested) {
            try {
                Set-Phase 6 7 "6/7  Verificando servicios de Windows y historial reciente..."
                $cSvc = 0
                foreach ($svcName in $script:WindowsServices) {
                    $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
                    if ($svc) {
                        $cSvc++
                        $st = ""
                        try { $st = " | Inicio: $($svc.StartType)" } catch { }
                        if ($svc.Status -eq 'Running') {
                            $servicios.Add("[SERVICIO NORMAL] $($svc.DisplayName) ($svcName) | Estado: Running$st")
                        } else {
                            $servicios.Add("[SERVICIO ALERTA] $($svc.DisplayName) ($svcName) | Estado: $($svc.Status)$st | Un servicio detenido puede indicar manipulación")
                        }
                    } elseif (Test-Path -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$svcName") {
                        $cSvc++
                        $servicios.Add("[SERVICIO NORMAL] $svcName | Controlador del sistema presente")
                    } else {
                        $servicios.Add("[SERVICIO INFO] $svcName | No existe en este equipo")
                    }
                }

                # Registros de eventos borrados en los últimos 7 días (requiere administrador)
                foreach ($logDef in @(@('Security', 1102, 'seguridad'), @('System', 104, 'del sistema'))) {
                    try {
                        $evs = @(Get-WinEvent -FilterHashtable @{ LogName = $logDef[0]; Id = $logDef[1]; StartTime = (Get-Date).AddDays(-7) } -MaxEvents 3 -ErrorAction Stop)
                        foreach ($ev in $evs) {
                            $servicios.Add("[ALERTA] Registro de eventos $($logDef[2]) borrado | Fecha: $($ev.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'))")
                        }
                    } catch { }
                }
                Add-ToLog $script:LogServicios $servicios

                # Historial: accesos recientes (carpeta Recent)
                $recentDir = Join-Path $env:APPDATA 'Microsoft\Windows\Recent'
                if (Test-Path -LiteralPath $recentDir) {
                    foreach ($lnk in @(Get-ChildItem -LiteralPath $recentDir -Filter '*.lnk' -File -ErrorAction SilentlyContinue)) {
                        $nm = [IO.Path]::GetFileNameWithoutExtension($lnk.Name)
                        if ($script:RxMacroStrict.IsMatch($nm) -or $script:RxHacks.IsMatch($nm)) {
                            $historial.Add("[HISTORIAL SOSPECHOSO] $nm | Último acceso: $($lnk.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')) | Ruta: $($lnk.FullName)")
                        }
                    }
                }
                Add-ToLog $script:LogHistorial $historial
            } catch { }
        }

        # 7 - Disco profundo (también detecta mods fuera de .minecraft)
        if (-not $script:CancelRequested) {
            try {
                Set-Phase 7 7 "7/7  Escaneo profundo de disco (puede tardar varios minutos)..."
                Invoke-DiskScan -Disco $disco -Maliciosos $maliciosos -Mods $mods -StartTime $scanStart -BasePct 86 -SpanPct 14
                $cMods += $script:DiskModCount
                Add-ToLog $script:LogDisco $disco
            } catch { }
        }

        # --- Consolidación de resultados ---
        Set-Status "Consolidando resultados..."
        $maliciososU = @($maliciosos | Select-Object -Unique)
        $modsGrouped = @(Group-ModsByVersion $mods)
        Add-ToLog $script:LogMods $modsGrouped

        $rxAb = 'RENOMBRADO|EXTENSIÓN FALSA|ADS SOSPECHOSO|VENTANA CHEAT|AUTOARRANQUE'
        $antiBypass = @((@($memoria) + @($mods) + @($macros) + @($disco)) | Where-Object { ([string]$_) -match $rxAb } | Select-Object -Unique)
        Add-ToLog $script:LogAntiBypass $antiBypass
        Add-ToLog $script:LogMods @($mods)

        $isAdm = Test-Administrator
        try { $elapsedTxt = ((Get-Date) - $scanStart).ToString("hh\:mm\:ss") } catch { $elapsedTxt = "-" }
        $statsBox.Add("[INFO] Fecha del análisis | $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))")
        $statsBox.Add("[INFO] Equipo / Usuario | $env:COMPUTERNAME / $env:USERNAME")
        $statsBox.Add("[INFO] Duración | $elapsedTxt")
        $statsBox.Add("[INFO] Procesos en memoria | $cRam")
        $statsBox.Add("[INFO] Archivos Prefetch | $cPref")
        $statsBox.Add("[INFO] Elementos en la Papelera | $cPap")
        $statsBox.Add("[INFO] Mods revisados | $cMods")
        $statsBox.Add("[INFO] Servicios de Windows revisados | $cSvc")
        $statsBox.Add("[INFO] Archivos recorridos en disco | $($script:ScanCount)")
        $statsBox.Add("[INFO] Hallazgos rojos | $($maliciososU.Count)")
        if (-not $isAdm) {
            $statsBox.Add("[ALERTA] Sin privilegios de administrador | Prefetch, servicios y registros de eventos pueden quedar incompletos")
        }
        if ($script:CancelRequested) {
            $statsBox.Add("[ALERTA] Análisis cancelado por el usuario | Los resultados son parciales")
        }

        $focus = if ($maliciososU.Count -gt 0) { 'Maliciosos' } else { 'Stats' }
        Publish-Results -Data @{
            Stats      = $statsBox
            AntiBypass = $antiBypass
            Memoria    = $memoria
            Prefetch   = $prefetchHoy
            Papelera   = $papeleraData
            Maliciosos = $maliciososU
            Mods       = $modsGrouped
            Macros     = $macros
            Servicios  = $servicios
            Disco      = $disco
            Historial  = $historial
        } -Focus $focus

        try {
            $script:LastReport = Save-Report ([ordered]@{
                'ESTADÍSTICAS'       = @($statsBox)
                'MALICIOSOS'         = $maliciososU
                'ANTI-BYPASS'        = $antiBypass
                'MEMORIA'            = @($memoria)
                'PREFETCH (HOY)'     = @($prefetchHoy)
                'PAPELERA'           = @($papeleraData)
                'MODS'               = $modsGrouped
                'MACROS'             = @($macros)
                'SERVICIOS'          = @($servicios)
                'DISCO PROFUNDO'     = @($disco)
                'HISTORIAL'          = @($historial)
            })
        } catch { }

        Set-Progress 100
        if ($script:CancelRequested) { Set-Status "Análisis cancelado. Se muestran los resultados parciales." }
        else { Set-Status ("Análisis completado  ·  {0} hallazgos rojos  ·  Duración {1}" -f $maliciososU.Count, $elapsedTxt) }
        if ($null -ne $script:LblDetail) { $script:LblDetail.Text = "Reporte guardado en el Escritorio (Reporte_Sombrio_V81.txt). Ctrl+E exporta la vista actual a CSV." }
    } catch {
        Show-Info ("Error durante el análisis:`n`n" + $_.Exception.Message) "ERROR"
    } finally {
        Stop-ScanSession
    }
}

# ============================================================
# EXPRESIONES AUXILIARES (macros reales vs. software de periféricos)
# ============================================================
$script:RxPeriph = [regex]::new('lghub|\bg hub\b|logitech gaming|synapse|\bicue\b|steelseries|bloody7|a4tech|redragon', $script:RxOpts)
$script:RxMacroStrict = [regex]::new((($script:MacroAutoclickCritical | Where-Object { $_ -notmatch 'logitech|lghub|g hub|synapse|icue|steelseries|bloody7|a4tech|redragon' }) -join '|'), $script:RxOpts)

# ============================================================
# REGISTRO DE SESIÓN (memoria acumulada de todos los análisis)
# ============================================================
function Show-Registry {
    if ($script:Busy) { return }
    $logs = [ordered]@{
        Memoria    = $script:LogMemoria
        Prefetch   = $script:LogPrefetch
        Papelera   = $script:LogPapelera
        Macros     = $script:LogMacros
        Servicios  = $script:LogServicios
        Disco      = $script:LogDisco
        Historial  = $script:LogHistorial
        AntiBypass = $script:LogAntiBypass
    }
    $total = 0
    foreach ($k in $logs.Keys) { $total += $logs[$k].Count }
    $total += $script:LogMods.Count
    if ($total -eq 0) {
        Show-Info "El registro de sesión está vacío.`n`nEjecuta primero la auditoría global (F5)." "REGISTRO"
        return
    }
    $reg = @{}
    foreach ($k in $logs.Keys) { $reg[$k] = @($logs[$k]) }
    $reg['Mods'] = @(Group-ModsByVersion @($script:LogMods))

    $red = [System.Collections.Generic.List[string]]::new()
    foreach ($k in @('Memoria', 'Macros', 'Disco', 'Historial', 'AntiBypass')) {
        foreach ($it in $reg[$k]) { if ((Get-ItemColor ([string]$it)) -eq 'Red' -and -not $red.Contains([string]$it)) { $red.Add([string]$it) } }
    }
    foreach ($it in $script:LogMods) { if ((Get-ItemColor ([string]$it)) -eq 'Red' -and -not $red.Contains([string]$it)) { $red.Add([string]$it) } }
    $reg['Maliciosos'] = @($red)
    $reg['Stats'] = @(
        "[INFO] Registro acumulado de la sesión | Memoria de todos los análisis hechos desde que se abrió la app",
        "[INFO] Hallazgos rojos acumulados | $($red.Count)",
        "[INFO] Entradas en total | $total"
    )
    $script:RegData   = $reg
    $script:ViewMode  = 'registry'
    $script:ActiveCat = if ($red.Count -gt 0) { 'Maliciosos' } else { 'Stats' }
    Show-Results
}

# ============================================================
# HERRAMIENTAS EXTERNAS
# ============================================================
function Confirm-Action([string]$Text, [string]$Title = "CONFIRMAR") {
    return ([System.Windows.Forms.MessageBox]::Show($Text, $Title, 'YesNo', 'Question') -eq 'Yes')
}

function Get-FileMagic([string]$Path) {
    try {
        $fs = [System.IO.File]::OpenRead($Path)
        try { $b = [byte[]]::new(2); [void]$fs.Read($b, 0, 2); return [System.Text.Encoding]::ASCII.GetString($b) } finally { $fs.Dispose() }
    } catch { return "" }
}

function Show-DoomsdayChooser {
    # Devuelve 'url' (V80), 'repo' (V79) o $null si se cancela
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "DOOMSDAY DETECTOR"
    $dlg.StartPosition = 'CenterParent'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false; $dlg.MinimizeBox = $false; $dlg.ShowInTaskbar = $false
    $dlg.BackColor = $script:C.Bg
    $dlg.ClientSize = New-Object System.Drawing.Size((Px 520), (Px 276))
    $script:DoomsChoice = $null

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "Elige de dónde descargar el Doomsday Detector"
    $lbl.ForeColor = $script:C.Red; $lbl.Font = $script:FontBold; $lbl.TextAlign = 'MiddleCenter'
    $lbl.SetBounds((Px 10), (Px 10), (Px 500), (Px 28))
    $dlg.Controls.Add($lbl)

    $defs = @(
        @{ Id = 'url';  Text = "A)  URL directa  (método V80)";            Info = $script:DoomsdayUrl },
        @{ Id = 'repo'; Text = "B)  Repositorio de GitHub  (método V79)";  Info = $script:DoomsdayRepo }
    )
    $y = 46
    foreach ($d in $defs) {
        $b = New-FlatButton $d.Text 480 40
        $b.Location = New-Object System.Drawing.Point((Px 20), (Px $y))
        $b.FlatAppearance.BorderColor = $script:C.Red
        $b.Tag = $d.Id
        $b.Add_Click({ param($s,$e) $script:DoomsChoice = [string]$s.Tag; $s.FindForm().Close() })
        $dlg.Controls.Add($b)
        $i = New-Object System.Windows.Forms.Label
        $i.Text = $d.Info; $i.Font = $script:FontBase; $i.ForeColor = $script:C.Muted; $i.AutoEllipsis = $true
        $i.SetBounds((Px 24), (Px ($y + 42)), (Px 472), (Px 20))
        $dlg.Controls.Add($i)
        $y += 72
    }
    $bc = New-FlatButton "Cancelar" 480 32
    $bc.Location = New-Object System.Drawing.Point((Px 20), (Px 232))
    $bc.ForeColor = $script:C.Muted
    $bc.Add_Click({ param($s,$e) $s.FindForm().Close() })
    $dlg.Controls.Add($bc)
    $dlg.CancelButton = $bc
    [void]$dlg.ShowDialog($script:Form)
    $dlg.Dispose()
    return $script:DoomsChoice
}

function Start-DoomsdayFromUrl {
    Set-Status "Abriendo Doomsday Detector (URL directa)..."
    # Equivale a: Set-ExecutionPolicy -Scope Process Bypass; iex (irm <url>)
    # Se descarga forzando UTF-8 para que no se rompan los acentos en PowerShell 5.1.
    $cmd = "Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force; " +
           "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; " +
           "`$wc = New-Object Net.WebClient; `$wc.Encoding = [System.Text.Encoding]::UTF8; " +
           "Invoke-Expression (`$wc.DownloadString('$($script:DoomsdayUrl)'))"
    $enc = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($cmd))
    $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $psExe)) { $psExe = 'powershell.exe' }
    Start-Process -FilePath $psExe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -NoExit -EncodedCommand $enc"
    Set-Status "Doomsday Detector abierto en otra ventana."
}

function Start-DoomsdayFromRepo {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Set-Status "Descargando Doomsday Detector (repositorio)..."
    $dir = Join-Path $env:TEMP 'Sombrio_Doomsday'
    if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }
    if (Get-Command git -ErrorAction SilentlyContinue) {
        Write-Log "git encontrado: clonando el repositorio..."
        try { & git clone --depth 1 $script:DoomsdayRepo $dir 2>&1 | Out-Null } catch { }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $dir $script:DoomsdayScript))) {
        Write-Log "Descargando el repositorio como .zip..."
        $zip  = Join-Path $env:TEMP 'Sombrio_Doomsday.zip'
        $tmpx = Join-Path $env:TEMP 'Sombrio_Doomsday_x'
        if (Test-Path -LiteralPath $tmpx) { Remove-Item -LiteralPath $tmpx -Recurse -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $dir)  { Remove-Item -LiteralPath $dir  -Recurse -Force -ErrorAction SilentlyContinue }
        Invoke-WebRequest -Uri 'https://github.com/jgonzalo17/Doomsday-Detector/archive/refs/heads/main.zip' -OutFile $zip -UseBasicParsing
        Expand-Archive -LiteralPath $zip -DestinationPath $tmpx -Force
        $inner = Get-ChildItem -LiteralPath $tmpx -Directory | Select-Object -First 1
        if ($inner) { Move-Item -LiteralPath $inner.FullName -Destination $dir -Force }
    }
    $target = Join-Path $dir $script:DoomsdayScript
    if (-not (Test-Path -LiteralPath $target)) {
        Show-Info "No se encontró $($script:DoomsdayScript) dentro del repositorio descargado." "DOOMSDAY DETECTOR"
        Set-Status "No se pudo preparar el Doomsday Detector."
        return
    }
    Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -NoExit -File `"$target`""
    Set-Status "Doomsday Detector abierto en otra ventana."
}

function Start-DoomsdayTool {
    $choice = Show-DoomsdayChooser
    if (-not $choice) { Write-Log "Doomsday Detector: cancelado por el usuario." 'WARN'; return }
    $origen = if ($choice -eq 'url') { $script:DoomsdayUrl } else { $script:DoomsdayRepo }
    if (-not (Confirm-Action "Se descargará y ejecutará el Doomsday Detector desde:`n$origen`n`nSe abrirá en una ventana de PowerShell.`n`n¿Continuar?" "DOOMSDAY DETECTOR")) { return }
    try {
        if ($choice -eq 'url') { Start-DoomsdayFromUrl } else { Start-DoomsdayFromRepo }
    } catch {
        Show-Info ("No se pudo abrir el Doomsday Detector:`n`n" + $_.Exception.Message) "DOOMSDAY DETECTOR"
        Set-Status "Error al abrir el Doomsday Detector."
    }
}

function Start-SystemInformerTool {
    if (-not (Confirm-Action "Se descargará System Informer desde SourceForge.`n`n¿Continuar?" "SYSTEM INFORMER")) { return }
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Set-Status "Descargando System Informer..."
        $dl = Join-Path $env:TEMP 'SystemInformer_download.bin'
        Invoke-WebRequest -Uri $script:SystemInformerUrl -OutFile $dl -UseBasicParsing -UserAgent 'Wget/1.21' -MaximumRedirection 10
        $magic = Get-FileMagic $dl
        if ($magic -eq 'PK') {
            $dest = Join-Path $env:TEMP 'SystemInformer'
            if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force -ErrorAction SilentlyContinue }
            Expand-Archive -LiteralPath $dl -DestinationPath $dest -Force
            $exe = Get-ChildItem -LiteralPath $dest -Recurse -Filter 'SystemInformer.exe' -File -ErrorAction SilentlyContinue |
                   Sort-Object { if ($_.FullName -match 'amd64|x64') { 0 } else { 1 } } | Select-Object -First 1
            if ($exe) { Start-Process -FilePath $exe.FullName; Set-Status "System Informer abierto." }
            else { Show-Info "Se descargó el paquete pero no se encontró SystemInformer.exe." "SYSTEM INFORMER" }
        } elseif ($magic -eq 'MZ') {
            $exePath = Join-Path $env:TEMP 'SystemInformer_setup.exe'
            Copy-Item -LiteralPath $dl -Destination $exePath -Force
            Start-Process -FilePath $exePath
            Set-Status "Instalador de System Informer abierto."
        } else {
            Show-Info "La descarga no es un archivo válido (SourceForge pudo devolver una página web)." "SYSTEM INFORMER"
        }
    } catch {
        Show-Info ("No se pudo descargar System Informer:`n`n" + $_.Exception.Message) "SYSTEM INFORMER"
        Set-Status "Error al descargar System Informer."
    }
}

function Start-JournalTraceTool {
    if (-not (Confirm-Action "Se descargará JournalTrace desde GitHub:`n$($script:JournalTraceUrl)`n`n¿Continuar?" "JOURNALTRACE")) { return }
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Set-Status "Descargando JournalTrace..."
        $exePath = Join-Path $env:TEMP 'JournalTrace.exe'
        Invoke-WebRequest -Uri $script:JournalTraceUrl -OutFile $exePath -UseBasicParsing
        if ((Get-FileMagic $exePath) -ne 'MZ') { Show-Info "La descarga no es un ejecutable válido." "JOURNALTRACE"; return }
        Start-Process -FilePath $exePath
        Set-Status "JournalTrace abierto."
    } catch {
        Show-Info ("No se pudo abrir JournalTrace:`n`n" + $_.Exception.Message) "JOURNALTRACE"
        Set-Status "Error al abrir JournalTrace."
    }
}

function Start-LilithTool {
    if (-not (Confirm-Action "Se ejecutará Lilith Services (lilith-ps) descargándolo desde:`n$($script:LilithServicesUrl)`n`nSe abrirá en una ventana de PowerShell.`n`n¿Continuar?" "LILITH SERVICES")) { return }
    try {
        $cmd = "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; irm '$($script:LilithServicesUrl)' | iex"
        $enc = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($cmd))
        Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -NoExit -EncodedCommand $enc"
        Set-Status "Lilith Services abierto en otra ventana."
    } catch {
        Show-Info ("No se pudo abrir Lilith Services:`n`n" + $_.Exception.Message) "LILITH SERVICES"
    }
}



# ============================================================
# V81 - VENTANAS NUEVAS
#   1) Registro de actividad en vivo      (Ctrl+L)
#   2) Visor de resultados por pestañas   (Ctrl+R)
#   3) Información del sistema            (Ctrl+I)
# Son ventanas independientes (no modales): se pueden dejar abiertas
# al lado de la principal mientras corre el análisis.
# ============================================================
$script:ViewerForm = $null
$script:ViewerTabs = $null
$script:SysForm    = $null
$script:SysList    = $null

function New-ToolWindow([string]$Title, [int]$W, [int]$H, [int]$MinW = 560, [int]$MinH = 360) {
    $f = New-Object System.Windows.Forms.Form
    $f.Text = $Title
    $f.StartPosition = 'Manual'
    $f.BackColor = $script:C.Bg
    $f.ForeColor = $script:C.Text
    $f.Font = $script:FontBase
    $f.ClientSize = New-Object System.Drawing.Size((Px $W), (Px $H))
    $f.MinimumSize = New-Object System.Drawing.Size((Px $MinW), (Px $MinH))
    try {
        $off = (Px 40) * (1 + ([System.Windows.Forms.Application]::OpenForms.Count % 4))
        $f.Location = New-Object System.Drawing.Point(($script:Form.Left + $off), ($script:Form.Top + $off))
    } catch { $f.StartPosition = 'CenterScreen' }
    return $f
}

function New-ToolbarPanel([int]$H = 46) {
    $p = New-Object System.Windows.Forms.Panel
    $p.Dock = 'Top'
    $p.Height = (Px $H)
    $p.BackColor = $script:C.Panel
    $p.Padding = [System.Windows.Forms.Padding]::new((Px 8), (Px 6), (Px 8), (Px 6))
    return $p
}

function New-ToolbarButton([string]$Text, [int]$Width, [int]$Left) {
    $b = New-FlatButton $Text $Width 32
    $b.Location = New-Object System.Drawing.Point((Px $Left), (Px 7))
    return $b
}

# ------------------------------------------------------------
# 1) REGISTRO DE ACTIVIDAD EN VIVO
# ------------------------------------------------------------
function Update-LogView {
    $box = $script:LogBox
    if ($null -eq $box -or $box.IsDisposed) { return }
    $box.SuspendLayout()
    $box.Clear()
    foreach ($e in @($script:Activity)) { Add-LogLine $e }
    $box.ResumeLayout()
}

function Show-ActivityLog {
    if ($null -ne $script:LogForm -and -not $script:LogForm.IsDisposed) {
        if ($script:LogForm.WindowState -eq 'Minimized') { $script:LogForm.WindowState = 'Normal' }
        $script:LogForm.Activate()
        return
    }
    $f = New-ToolWindow "REGISTRO DE ACTIVIDAD  ·  en vivo" 920 520 640 320
    $script:LogForm = $f

    $box = New-Object System.Windows.Forms.RichTextBox
    $box.Dock = 'Fill'
    $box.ReadOnly = $true
    $box.BorderStyle = 'None'
    $box.BackColor = $script:C.Panel
    $box.ForeColor = $script:C.Text
    $box.Font = New-Object System.Drawing.Font('Consolas', [single]9.5)
    $box.WordWrap = $true
    $box.DetectUrls = $false
    $script:LogBox = $box

    $foot = New-Object System.Windows.Forms.Label
    $foot.Dock = 'Bottom'
    $foot.Height = (Px 24)
    $foot.BackColor = $script:C.Panel
    $foot.ForeColor = $script:C.Muted
    $foot.TextAlign = 'MiddleLeft'
    $foot.Padding = [System.Windows.Forms.Padding]::new((Px 10), 0, 0, 0)
    $foot.Text = "Archivo de esta sesión:  " + $script:LogFile
    $foot.AutoEllipsis = $true

    $bar = New-ToolbarPanel 46
    $chkAuto = New-Object System.Windows.Forms.CheckBox
    $chkAuto.Text = "Auto-desplazar"; $chkAuto.Checked = $script:LogAutoScroll
    $chkAuto.ForeColor = $script:C.Text; $chkAuto.AutoSize = $true
    $chkAuto.Location = New-Object System.Drawing.Point((Px 10), (Px 12))
    $chkAuto.Add_CheckedChanged({ param($s,$e) $script:LogAutoScroll = $s.Checked })
    $bar.Controls.Add($chkAuto)

    $chkIss = New-Object System.Windows.Forms.CheckBox
    $chkIss.Text = "Solo errores y alertas"; $chkIss.Checked = $script:LogOnlyIssues
    $chkIss.ForeColor = $script:C.Text; $chkIss.AutoSize = $true
    $chkIss.Location = New-Object System.Drawing.Point((Px 140), (Px 12))
    $chkIss.Add_CheckedChanged({ param($s,$e) $script:LogOnlyIssues = $s.Checked; Update-LogView })
    $bar.Controls.Add($chkIss)

    $bCopy = New-ToolbarButton "Copiar" 80 330
    $bCopy.Add_Click({
        try {
            $txt = (@($script:Activity) | ForEach-Object { Format-LogLine $_ }) -join "`r`n"
            if ($txt) { [System.Windows.Forms.Clipboard]::SetText($txt); Write-Log "Registro copiado al portapapeles." }
        } catch { Write-Log ("No se pudo copiar el registro: " + $_.Exception.Message) 'ERROR' }
    })
    $bar.Controls.Add($bCopy)

    $bSave = New-ToolbarButton "Guardar..." 90 418
    $bSave.Add_Click({
        try {
            $dlg = New-Object System.Windows.Forms.SaveFileDialog
            $dlg.Filter = "Texto (*.txt)|*.txt|Log (*.log)|*.log"
            $dlg.FileName = ("Actividad_Sombrio_{0:yyyyMMdd_HHmmss}.txt" -f (Get-Date))
            $dlg.InitialDirectory = [Environment]::GetFolderPath('Desktop')
            if ($dlg.ShowDialog() -eq 'OK') {
                Set-Content -LiteralPath $dlg.FileName -Value (@($script:Activity) | ForEach-Object { Format-LogLine $_ }) -Encoding UTF8
                Write-Log ("Registro guardado: " + $dlg.FileName)
            }
        } catch { Write-Log ("No se pudo guardar el registro: " + $_.Exception.Message) 'ERROR' }
    })
    $bar.Controls.Add($bSave)

    $bClr = New-ToolbarButton "Limpiar" 80 516
    $bClr.Add_Click({ $script:Activity.Clear(); $script:LogBox.Clear() })
    $bar.Controls.Add($bClr)

    $bDir = New-ToolbarButton "Abrir carpeta" 110 604
    $bDir.Add_Click({
        try {
            if (Test-Path -LiteralPath $script:LogDir) { Start-Process -FilePath 'explorer.exe' -ArgumentList ('"' + $script:LogDir + '"') }
        } catch { }
    })
    $bar.Controls.Add($bDir)

    # Orden de apilado: primero el control que rellena
    $f.Controls.Add($box)
    $f.Controls.Add($foot)
    $f.Controls.Add($bar)

    $f.Add_FormClosed({ $script:LogForm = $null; $script:LogBox = $null })
    Update-LogView
    $f.Show($script:Form)
}

# ------------------------------------------------------------
# 2) VISOR DE RESULTADOS POR PESTAÑAS (ventana aparte)
# ------------------------------------------------------------
function New-ViewerGrid {
    param([string[]]$Headers, [int[]]$Widths)
    $g = New-Object System.Windows.Forms.DataGridView
    $g.Dock = 'Fill'
    $g.BackgroundColor = $script:C.Panel
    $g.BorderStyle = 'None'
    $g.GridColor = $script:C.Border
    $g.ReadOnly = $true
    $g.AllowUserToAddRows = $false
    $g.AllowUserToDeleteRows = $false
    $g.AllowUserToResizeRows = $false
    $g.RowHeadersVisible = $false
    $g.SelectionMode = 'FullRowSelect'
    $g.MultiSelect = $false
    $g.DefaultCellStyle.BackColor = $script:C.Panel
    $g.DefaultCellStyle.ForeColor = $script:C.Text
    $g.DefaultCellStyle.SelectionBackColor = $script:C.Select
    $g.DefaultCellStyle.SelectionForeColor = $script:C.Text
    $g.DefaultCellStyle.Font = $script:FontBase
    $g.AlternatingRowsDefaultCellStyle.BackColor = $script:C.Row2
    $g.EnableHeadersVisualStyles = $false
    $g.ColumnHeadersDefaultCellStyle.BackColor = $script:C.Panel2
    $g.ColumnHeadersDefaultCellStyle.ForeColor = $script:C.Muted
    $g.ColumnHeadersDefaultCellStyle.Font = $script:FontBold
    $g.ColumnHeadersHeight = (Px 32)
    $g.ColumnHeadersHeightSizeMode = 'DisableResizing'
    $g.RowTemplate.Height = (Px 26)
    for ($i = 0; $i -lt $Headers.Count; $i++) {
        $col = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
        $col.Name = "c$i"
        $col.HeaderText = $Headers[$i]
        if ($Widths[$i] -gt 0) { $col.AutoSizeMode = 'None'; $col.Width = (Px $Widths[$i]) }
        else { $col.AutoSizeMode = 'Fill'; $col.MinimumWidth = (Px 200) }
        [void]$g.Columns.Add($col)
    }
    return $g
}

function Update-ViewerTabs {
    $tc = $script:ViewerTabs
    if ($null -eq $tc -or $tc.IsDisposed) { return }
    $tc.SuspendLayout()
    $tc.TabPages.Clear()

    # --- Pestaña RESUMEN ---
    $pg = New-Object System.Windows.Forms.TabPage "RESUMEN"
    $pg.BackColor = $script:C.Panel
    $gs = New-ViewerGrid @('CATEGORÍA', 'ELEMENTOS', 'CRÍTICOS', 'ALERTAS') @(240, 120, 120, 0)
    foreach ($def in $script:CatDefs) {
        $its = @()
        if ($script:CatData.ContainsKey($def.Key) -and $script:CatData[$def.Key]) {
            $its = @(@($script:CatData[$def.Key]) | Where-Object { $_ -and ([string]$_) -notmatch '======' })
        }
        $nr = 0; $nw = 0
        foreach ($it in $its) {
            $lv = Get-ItemLevel ([string]$it) $def.Key
            if ($lv -eq 'CRÍTICO') { $nr++ } elseif ($lv -eq 'ALERTA') { $nw++ }
        }
        $ri = $gs.Rows.Add($def.Text, $its.Count, $nr, $nw)
        $gs.Rows[$ri].DefaultCellStyle.ForeColor = if ($nr -gt 0) { $script:C.Red } elseif ($nw -gt 0) { $script:C.Yellow } else { $script:C.Text }
    }
    $gs.ClearSelection()
    $pg.Controls.Add($gs)
    [void]$tc.TabPages.Add($pg)

    # --- Una pestaña por categoría ---
    foreach ($def in $script:CatDefs) {
        $its = @()
        if ($script:CatData.ContainsKey($def.Key) -and $script:CatData[$def.Key]) { $its = @($script:CatData[$def.Key]) }
        $real = @($its | Where-Object { ([string]$_) -notmatch '======' })
        $pg = New-Object System.Windows.Forms.TabPage ("{0}  ·  {1}" -f $def.Text, $real.Count)
        $pg.BackColor = $script:C.Panel
        $hasRed = ($def.Key -eq 'Maliciosos' -and $real.Count -gt 0)
        if (-not $hasRed) { foreach ($it in $real) { if ((Get-ItemColor ([string]$it)) -eq 'Red') { $hasRed = $true; break } } }
        $pg.Tag = if ($hasRed) { 'red' } else { '' }
        $g = New-ViewerGrid @('NIVEL', 'TIPO', 'ELEMENTO', 'DETALLE') @(100, 170, 320, 0)
        if ($its.Count -eq 0) {
            $ri = $g.Rows.Add("INFO", "", "Sin datos. Ejecuta primero la auditoría global (F5).", "---")
            $g.Rows[$ri].DefaultCellStyle.ForeColor = $script:C.Muted
        } else {
            foreach ($it in $its) {
                $str = [string]$it
                $p = Split-ReportItem $str
                $lvl = if ($p.Header) { '' } else { Get-ItemLevel $str $def.Key }
                Add-GridRow $g $str $p $def.Key $lvl
            }
        }
        $g.ClearSelection()
        $pg.Controls.Add($g)
        [void]$tc.TabPages.Add($pg)
    }
    $tc.ResumeLayout()
    $tc.Invalidate()
}

function Show-ResultsViewer {
    if ($script:CatData.Count -eq 0) {
        Show-Info "Todavía no hay resultados.`n`nEjecuta primero la auditoría global (F5)." "VISOR DE RESULTADOS"
        return
    }
    if ($null -ne $script:ViewerForm -and -not $script:ViewerForm.IsDisposed) {
        Update-ViewerTabs
        if ($script:ViewerForm.WindowState -eq 'Minimized') { $script:ViewerForm.WindowState = 'Normal' }
        $script:ViewerForm.Activate()
        return
    }
    $f = New-ToolWindow "VISOR DE RESULTADOS  ·  por pestañas" 1100 640 760 420
    $script:ViewerForm = $f

    $tc = New-Object System.Windows.Forms.TabControl
    $tc.Dock = 'Fill'
    $tc.DrawMode = 'OwnerDrawFixed'
    $tc.SizeMode = 'Normal'
    $tc.Padding = New-Object System.Drawing.Point((Px 14), (Px 6))
    $tc.Multiline = $true
    $tc.ItemSize = New-Object System.Drawing.Size((Px 160), (Px 30))
    $tc.Font = $script:FontBold
    $tc.Add_DrawItem({
        param($s, $e)
        $page = $s.TabPages[$e.Index]
        $sel  = ($e.Index -eq $s.SelectedIndex)
        $bg = if ($sel) { $script:C.Select } else { $script:C.Panel2 }
        $fg = if ($page.Tag -eq 'red') { $script:C.Red } elseif ($sel) { $script:C.Text } else { $script:C.Muted }
        $br = New-Object System.Drawing.SolidBrush($bg)
        $e.Graphics.FillRectangle($br, $e.Bounds)
        $br.Dispose()
        $fb = New-Object System.Drawing.SolidBrush($fg)
        $sf = New-Object System.Drawing.StringFormat
        $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'; $sf.Trimming = 'EllipsisCharacter'
        $rf = New-Object System.Drawing.RectangleF([single]$e.Bounds.X, [single]$e.Bounds.Y, [single]$e.Bounds.Width, [single]$e.Bounds.Height)
        $e.Graphics.DrawString($page.Text, $script:FontBase, $fb, $rf, $sf)
        $fb.Dispose(); $sf.Dispose()
    })
    $script:ViewerTabs = $tc

    $bar = New-ToolbarPanel 46
    $bRef = New-ToolbarButton "Actualizar" 100 10
    $bRef.Add_Click({ Update-ViewerTabs; Write-Log "Visor de resultados actualizado." })
    $bar.Controls.Add($bRef)
    $bCsv = New-ToolbarButton "Exportar pestaña (CSV)" 190 118
    $bCsv.Add_Click({
        try {
            $sel = $script:ViewerTabs.SelectedTab
            $g = if ($sel) { $sel.Controls | Where-Object { $_ -is [System.Windows.Forms.DataGridView] } | Select-Object -First 1 } else { $null }
            if (-not $g -or $g.Rows.Count -eq 0) { return }
            $dlg = New-Object System.Windows.Forms.SaveFileDialog
            $dlg.Filter = "CSV (*.csv)|*.csv"
            $dlg.FileName = ("Sombrio_{0:yyyyMMdd_HHmmss}.csv" -f (Get-Date))
            $dlg.InitialDirectory = [Environment]::GetFolderPath('Desktop')
            if ($dlg.ShowDialog() -ne 'OK') { return }
            $lines = [System.Collections.Generic.List[string]]::new()
            $hd = @(); foreach ($c in $g.Columns) { $hd += ('"' + ([string]$c.HeaderText -replace '"', '""') + '"') }
            $lines.Add(($hd -join ','))
            foreach ($r in $g.Rows) {
                $vals = @(); foreach ($c in $r.Cells) { $vals += ('"' + ([string]$c.Value -replace '"', '""') + '"') }
                $lines.Add(($vals -join ','))
            }
            [System.IO.File]::WriteAllLines($dlg.FileName, $lines, (New-Object System.Text.UTF8Encoding($true)))
            Write-Log ("Pestaña exportada: " + $dlg.FileName)
        } catch { Write-Log ("No se pudo exportar la pestaña: " + $_.Exception.Message) 'ERROR' }
    })
    $bar.Controls.Add($bCsv)

    $f.Controls.Add($tc)
    $f.Controls.Add($bar)
    $f.Add_FormClosed({ $script:ViewerForm = $null; $script:ViewerTabs = $null })
    Update-ViewerTabs
    $f.Show($script:Form)
}

# ------------------------------------------------------------
# 3) INFORMACIÓN DEL SISTEMA
# ------------------------------------------------------------
function Get-SystemInfoRows {
    $rows = [System.Collections.Generic.List[object]]::new()
    $add = { param($k, $v) $rows.Add([pscustomobject]@{ K = $k; V = [string]$v }) }

    & $add "Aplicación" "EL SOMBRIO IF · Forensic Scanner V81 (unificado V79 + V80)"
    & $add "Administrador" $(if (Test-Administrator) { "SÍ" } else { "NO (Prefetch, servicios y eventos pueden quedar incompletos)" })
    & $add "PowerShell" $PSVersionTable.PSVersion.ToString()
    $os = $null
    try { $os = (Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop) } catch { }
    if ($os) {
        & $add "Sistema operativo" ("{0}  (build {1})" -f $os.Caption, $os.BuildNumber)
        try { & $add "Encendido desde" ($os.LastBootUpTime.ToString('yyyy-MM-dd HH:mm:ss')) } catch { }
    } else {
        & $add "Sistema operativo" ([Environment]::OSVersion.VersionString)
    }
    & $add "Equipo / Usuario" ("{0} / {1}" -f $env:COMPUTERNAME, $env:USERNAME)
    $mods = $script:DefaultModsPath
    & $add "Carpeta de mods" ("{0}   [{1}]" -f $mods, $(if (Test-Path -LiteralPath $mods) { "existe" } else { "no existe" }))
    & $add "Tema actual" $script:ThemeName
    & $add "Estado del análisis" $(if ($script:Busy) { "EN CURSO ({0}%)" -f $script:ProgressPct } else { "En reposo" })
    & $add "Archivos recorridos (último)" ("{0:N0}" -f $script:ScanCount)
    $cats = @(); foreach ($def in $script:CatDefs) { if ($script:CatData.ContainsKey($def.Key) -and $script:CatData[$def.Key]) { $cats += $def.Text } }
    & $add "Categorías con datos" $(if ($cats.Count) { $cats -join ", " } else { "(ninguna todavía)" })
    $reg = $script:LogMods.Count + $script:LogPrefetch.Count + $script:LogMemoria.Count + $script:LogMacros.Count + $script:LogServicios.Count + $script:LogDisco.Count + $script:LogPapelera.Count + $script:LogHistorial.Count + $script:LogAntiBypass.Count
    & $add "Entradas del registro de sesión" $reg
    & $add "Último reporte" $(if ($script:LastReport) { $script:LastReport } else { "(aún no se generó)" })
    & $add "Log de actividad (archivo)" $script:LogFile
    & $add "Doomsday · A) URL directa" $script:DoomsdayUrl
    & $add "Doomsday · B) Repositorio" $script:DoomsdayRepo
    return $rows
}

function Update-SysInfo {
    $lv = $script:SysList
    if ($null -eq $lv -or $lv.IsDisposed) { return }
    $lv.BeginUpdate()
    $lv.Items.Clear()
    foreach ($r in (Get-SystemInfoRows)) {
        $it = New-Object System.Windows.Forms.ListViewItem($r.K)
        [void]$it.SubItems.Add($r.V)
        $it.ForeColor = $script:C.Text
        if ($r.K -eq 'Administrador' -and $r.V -like 'NO*') { $it.SubItems[1].ForeColor = $script:C.Yellow }
        $lv.Items.Add($it) | Out-Null
    }
    $lv.EndUpdate()
}

function Show-SystemInfo {
    if ($null -ne $script:SysForm -and -not $script:SysForm.IsDisposed) {
        Update-SysInfo
        if ($script:SysForm.WindowState -eq 'Minimized') { $script:SysForm.WindowState = 'Normal' }
        $script:SysForm.Activate()
        return
    }
    $f = New-ToolWindow "INFORMACIÓN DEL SISTEMA" 860 520 620 360
    $script:SysForm = $f

    $lv = New-Object System.Windows.Forms.ListView
    $lv.Dock = 'Fill'
    $lv.View = 'Details'
    $lv.FullRowSelect = $true
    $lv.HideSelection = $false
    $lv.BorderStyle = 'None'
    $lv.BackColor = $script:C.Panel
    $lv.ForeColor = $script:C.Text
    $lv.Font = $script:FontBase
    $lv.UseCompatibleStateImageBehavior = $false
    [void]$lv.Columns.Add("DATO", (Px 230))
    [void]$lv.Columns.Add("VALOR", (Px 600))
    $lv.Add_Resize({ param($s,$e) try { if ($s.Columns.Count -eq 2) { $s.Columns[1].Width = [math]::Max((Px 300), $s.ClientSize.Width - $s.Columns[0].Width - (Px 4)) } } catch { } })
    $script:SysList = $lv

    $bar = New-ToolbarPanel 46
    $bRef = New-ToolbarButton "Actualizar" 100 10
    $bRef.Add_Click({ Update-SysInfo })
    $bar.Controls.Add($bRef)
    $bCp = New-ToolbarButton "Copiar todo" 110 118
    $bCp.Add_Click({
        try {
            $txt = (Get-SystemInfoRows | ForEach-Object { "{0}: {1}" -f $_.K, $_.V }) -join "`r`n"
            [System.Windows.Forms.Clipboard]::SetText($txt)
            Write-Log "Información del sistema copiada al portapapeles."
        } catch { Write-Log ("No se pudo copiar: " + $_.Exception.Message) 'ERROR' }
    })
    $bar.Controls.Add($bCp)

    $f.Controls.Add($lv)
    $f.Controls.Add($bar)
    $f.Add_FormClosed({ $script:SysForm = $null; $script:SysList = $null })
    Update-SysInfo
    $f.Show($script:Form)
}

# ============================================================
# MENÚ "SELECCIONA UNA HERRAMIENTA" (4 aplicaciones)
# ============================================================
function Show-ToolsMenu {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "HERRAMIENTAS"
    $dlg.StartPosition = 'CenterParent'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false; $dlg.MinimizeBox = $false; $dlg.ShowInTaskbar = $false
    $dlg.BackColor = $script:C.Bg
    $dlg.ClientSize = New-Object System.Drawing.Size((Px 400), (Px 300))

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "Selecciona una herramienta (se descarga y ejecuta)"
    $lbl.ForeColor = $script:C.Red
    $lbl.Font = $script:FontBase
    $lbl.TextAlign = 'MiddleCenter'
    $lbl.SetBounds((Px 10), (Px 10), (Px 380), (Px 28))
    $dlg.Controls.Add($lbl)

    $defs = @(
        @{ Text = "Doomsday Detector  (elegir fuente A / B)"; Id = 'doomsday' },
        @{ Text = "System Informer  (descargar y ejecutar)";  Id = 'sysinformer' },
        @{ Text = "JournalTrace  (descargar y ejecutar)";     Id = 'journal' },
        @{ Text = "Lilith Services  (descargar y ejecutar)";  Id = 'lilith' }
    )
    $y = 46
    foreach ($d in $defs) {
        $b = New-FlatButton $d.Text 360 40
        $b.Location = New-Object System.Drawing.Point((Px 20), (Px $y))
        $b.FlatAppearance.BorderColor = $script:C.Red
        $b.Tag = $d.Id
        $b.Add_Click({ param($s,$e) $id = [string]$s.Tag; $s.FindForm().Close(); Invoke-NavAction $id })
        $dlg.Controls.Add($b)
        $y += 50
    }
    $bc = New-FlatButton "Cerrar" 360 34
    $bc.Location = New-Object System.Drawing.Point((Px 20), (Px $y))
    $bc.ForeColor = $script:C.Muted
    $bc.Add_Click({ param($s,$e) $s.FindForm().Close() })
    $dlg.Controls.Add($bc)
    $dlg.CancelButton = $bc
    [void]$dlg.ShowDialog($script:Form)
    $dlg.Dispose()
}

# ============================================================
# REVISIÓN MANUAL (equivale a los comandos Win+R)
# ============================================================
function Get-ManualChecks {
    $la = $env:LOCALAPPDATA
    return @(
        @{ Cmd = 'C:\$Recycle.Bin';                                            Info = 'Archivos eliminados';                                   Kind = 'folder'; Target = 'C:\$Recycle.Bin' },
        @{ Cmd = 'regedit';                                                    Info = 'Registro de Windows';                                   Kind = 'exe';    Target = 'regedit.exe' },
        @{ Cmd = 'prefetch';                                                   Info = 'Programas ejecutados (requiere SysMain y EnablePrefetcher activos) -> Javaw.pf'; Kind = 'folder'; Target = "$env:SystemRoot\Prefetch" },
        @{ Cmd = '%temp%';                                                     Info = 'JNativeHook -> dependencia de autoclickers viejos';     Kind = 'folder'; Target = $env:TEMP },
        @{ Cmd = '%appdata%\.minecraft';                                       Info = 'mods / versions / logs / resourcepacks: buscar hacked client, xray, mods ilegales'; Kind = 'folder'; Target = "$env:APPDATA\.minecraft" },
        @{ Cmd = 'shell:recent';                                               Info = 'Archivos ejecutados recientemente';                     Kind = 'shell';  Target = 'shell:recent' },
        @{ Cmd = '...\PowerShell\PSReadLine';                                  Info = 'Historial de comandos de PowerShell';                   Kind = 'folder'; Target = "$env:APPDATA\Microsoft\Windows\PowerShell\PSReadLine" },
        @{ Cmd = 'msinfo32';                                                   Info = 'Información del sistema: Virtual Machine = BAN';        Kind = 'exe';    Target = 'msinfo32.exe' },
        @{ Cmd = 'C:\Windows\System32\drivers\etc';                            Info = 'Archivo hosts: dominios bloqueados';                    Kind = 'folder'; Target = "$env:SystemRoot\System32\drivers\etc" },
        @{ Cmd = '%LOCALAPPDATA%\Microsoft\Windows\History';                   Info = 'Páginas y archivos ejecutados (historial)';             Kind = 'folder'; Target = "$la\Microsoft\Windows\History" }
    )
}

function Invoke-ManualCheck($Check) {
    try {
        switch ($Check.Kind) {
            'exe'    { Start-Process -FilePath $Check.Target }
            'shell'  { Start-Process -FilePath 'explorer.exe' -ArgumentList $Check.Target }
            'folder' {
                if (Test-Path -LiteralPath $Check.Target -ErrorAction SilentlyContinue) {
                    Start-Process -FilePath 'explorer.exe' -ArgumentList ('"' + $Check.Target + '"')
                } elseif ($Check.Target -like '*$Recycle.Bin*') {
                    Start-Process -FilePath 'explorer.exe' -ArgumentList 'shell:RecycleBinFolder'   # alternativa si no hay acceso a la carpeta real
                } else {
                    Show-Info "No existe o no se puede acceder a:`n$($Check.Target)" "REVISIÓN MANUAL"
                }
            }
        }
    } catch {
        Show-Info ("No se pudo abrir:`n$($Check.Target)`n`n" + $_.Exception.Message) "REVISIÓN MANUAL"
    }
}

function Show-ManualChecks {
    $checks = Get-ManualChecks
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "REVISIÓN MANUAL (Win+R)"
    $dlg.StartPosition = 'CenterParent'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false; $dlg.MinimizeBox = $false; $dlg.ShowInTaskbar = $false
    $dlg.BackColor = $script:C.Bg
    $dlg.ClientSize = New-Object System.Drawing.Size((Px 760), (Px 560))

    $title = New-Object System.Windows.Forms.Label
    $title.Text = "Revisión manual: abre cada ubicación directamente"
    $title.ForeColor = $script:C.Red; $title.Font = $script:FontBold
    $title.SetBounds((Px 16), (Px 10), (Px 728), (Px 26))
    $dlg.Controls.Add($title)

    $pnl = New-Object System.Windows.Forms.Panel
    $pnl.SetBounds((Px 10), (Px 42), (Px 740), (Px 462))
    $pnl.AutoScroll = $true
    $pnl.BackColor = $script:C.Panel
    $dlg.Controls.Add($pnl)

    $y = 6
    foreach ($c in $checks) {
        $b = New-FlatButton "Abrir" 70 34
        $b.Location = New-Object System.Drawing.Point((Px 8), (Px $y))
        $b.Tag = $c
        $b.Add_Click({ param($s,$e) Invoke-ManualCheck $s.Tag })
        $pnl.Controls.Add($b)

        $l1 = New-Object System.Windows.Forms.Label
        $l1.Text = "Win+R  ›  " + $c.Cmd
        $l1.Font = $script:FontBold; $l1.ForeColor = $script:C.Accent
        $l1.AutoEllipsis = $true
        $l1.SetBounds((Px 90), (Px $y), (Px 630), (Px 18))
        $pnl.Controls.Add($l1)

        $l2 = New-Object System.Windows.Forms.Label
        $l2.Text = $c.Info
        $l2.Font = $script:FontBase; $l2.ForeColor = $script:C.Muted
        $l2.AutoEllipsis = $true
        $l2.SetBounds((Px 90), (Px ($y + 18)), (Px 630), (Px 18))
        $pnl.Controls.Add($l2)

        $y += 44
    }

    $bc = New-FlatButton "Cerrar" 120 32
    $bc.Location = New-Object System.Drawing.Point((Px 630), (Px 516))
    $bc.Add_Click({ param($s,$e) $s.FindForm().Close() })
    $dlg.Controls.Add($bc)
    $dlg.CancelButton = $bc
    [void]$dlg.ShowDialog($script:Form)
    $dlg.Dispose()
}

function Switch-Theme {
    $new = if ($script:ThemeName -eq 'Slate') { 'Sombrio' } else { 'Slate' }
    try {
        $dir = Split-Path -Path $script:ThemeFile -Parent
        if (-not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
        Set-Content -LiteralPath $script:ThemeFile -Value $new -Encoding UTF8
        Show-Info "Tema '$new' guardado.`n`nCierra y vuelve a abrir la aplicación para verlo aplicado." "TEMA"
    } catch {
        Show-Info ("No se pudo guardar el tema:`n`n" + $_.Exception.Message) "TEMA"
    }
}

function Invoke-Panic {
    $script:CancelRequested = $true
    $script:CloseAfter = $true
    if ($script:Busy) { Set-Status "Cerrando: se está terminando el archivo en curso..." }
    else { $script:Form.Close() }
}

function Invoke-NavAction([string]$Id) {
    Write-Log ("Acción: " + $Id) 'INFO'
    try {
        switch ($Id) {
            'global'      { if (-not $script:Busy) { Start-GlobalScan } }
            'live'        {
                if ($script:Busy) { return }
                if ($script:CatData.Count -gt 0) { $script:ViewMode = 'live'; Show-Results }
                else { Show-Info "Todavía no hay resultados.`n`nEjecuta primero la auditoría global (F5)." "RESULTADOS" }
            }
            'registry'    { Show-Registry }
            'log'         { Show-ActivityLog }
            'viewer'      { Show-ResultsViewer }
            'sysinfo'     { Show-SystemInfo }
            'doomsday'    { if (-not $script:Busy) { Start-DoomsdayTool } }
            'sysinformer' { if (-not $script:Busy) { Start-SystemInformerTool } }
            'journal'     { if (-not $script:Busy) { Start-JournalTraceTool } }
            'lilith'      { if (-not $script:Busy) { Start-LilithTool } }
            'tools'       { if (-not $script:Busy) { Show-ToolsMenu } }
            'manual'      { Show-ManualChecks }
            'theme'       { Switch-Theme }
            'panic'       { Invoke-Panic }
            'exit'        { $script:Form.Close() }
        }
    } catch {
        Write-Log ("Error en la acción '$Id': " + $_.Exception.Message) 'ERROR'
        Show-Info ("Ocurrió un error:`n`n" + $_.Exception.Message) "EL SOMBRIO IF"
    }
}

function Update-FilterView {
    if ($script:SuppressFilter) { return }
    if ($script:Grid -and $script:Grid.Visible -and $script:FilterBar -and $script:FilterBar.Visible) { Show-Category $script:ActiveCat }
}

# ============================================================
# CONSTRUCCIÓN DE LA VENTANA
# ============================================================
function New-FlatButton([string]$Text, [int]$Width, [int]$Height = 30) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text
    $b.Width = (Px $Width)
    $b.Height = (Px $Height)
    $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderSize = 1
    $b.FlatAppearance.BorderColor = $script:C.Border
    $b.FlatAppearance.MouseOverBackColor = $script:C.Hover
    $b.FlatAppearance.MouseDownBackColor = $script:C.Select
    $b.UseVisualStyleBackColor = $false
    $b.BackColor = $script:C.Panel2
    $b.ForeColor = $script:C.Text
    $b.Font = $script:FontBase
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    return $b
}

Initialize-Decompressor
$script:FontBase  = New-Object System.Drawing.Font('Segoe UI', [single]9.5, [System.Drawing.FontStyle]::Regular)
$script:FontBold  = New-Object System.Drawing.Font('Segoe UI', [single]9.5, [System.Drawing.FontStyle]::Bold)
$fontSmall        = New-Object System.Drawing.Font('Segoe UI', [single]8, [System.Drawing.FontStyle]::Bold)
$fontTitle        = New-Object System.Drawing.Font('Segoe UI', [single]16, [System.Drawing.FontStyle]::Bold)
$fontHeader       = New-Object System.Drawing.Font('Segoe UI', [single]10.5, [System.Drawing.FontStyle]::Bold)
$fontMono         = New-Object System.Drawing.Font('Consolas', [single]10, [System.Drawing.FontStyle]::Bold)
$fontArt          = New-Object System.Drawing.Font('Consolas', [single]6.5, [System.Drawing.FontStyle]::Regular)
$isAdminNow       = Test-Administrator

# --- Ventana principal ---
$script:Form = New-Object System.Windows.Forms.Form
$script:Form.Text = "EL SOMBRIO IF  ·  Forensic Scanner V81"
$script:Form.StartPosition = 'CenterScreen'
$script:Form.ClientSize = New-Object System.Drawing.Size((Px 1320), (Px 800))
$script:Form.MinimumSize = New-Object System.Drawing.Size((Px 1040), (Px 660))
$script:Form.BackColor = $script:C.Bg
$script:Form.ForeColor = $script:C.Text
$script:Form.Font = $script:FontBase
$script:Form.KeyPreview = $true

# --- Panel derecho (cabecera + contenido + barra de estado) ---
$mainRight = New-Object System.Windows.Forms.Panel
$mainRight.Dock = 'Fill'
$mainRight.BackColor = $script:C.Bg

# Contenedor central (tabla, chips, filtros, portada)
$script:HostPanel = New-Object System.Windows.Forms.Panel
$script:HostPanel.Dock = 'Fill'
$script:HostPanel.BackColor = $script:C.Bg
$script:HostPanel.Padding = [System.Windows.Forms.Padding]::new((Px 16), (Px 6), (Px 16), (Px 6))

# Tabla de resultados (se añade primero: es el control que rellena)
$script:Grid = New-Object System.Windows.Forms.DataGridView
$grid = $script:Grid
$grid.Dock = 'Fill'
$grid.Visible = $false
$grid.BackgroundColor = $script:C.Panel
$grid.BorderStyle = 'None'
$grid.GridColor = $script:C.Border
$grid.ReadOnly = $true
$grid.AllowUserToAddRows = $false
$grid.AllowUserToDeleteRows = $false
$grid.AllowUserToResizeRows = $false
$grid.RowHeadersVisible = $false
$grid.SelectionMode = 'FullRowSelect'
$grid.MultiSelect = $false
$grid.AutoSizeRowsMode = 'None'
$grid.DefaultCellStyle.BackColor = $script:C.Panel
$grid.DefaultCellStyle.ForeColor = $script:C.Text
$grid.DefaultCellStyle.SelectionBackColor = $script:C.Select
$grid.DefaultCellStyle.SelectionForeColor = $script:C.Text
$grid.DefaultCellStyle.Font = $script:FontBase
$grid.DefaultCellStyle.Padding = [System.Windows.Forms.Padding]::new((Px 6), 0, (Px 6), 0)
$grid.AlternatingRowsDefaultCellStyle.BackColor = $script:C.Row2
$grid.EnableHeadersVisualStyles = $false
$grid.ColumnHeadersDefaultCellStyle.BackColor = $script:C.Panel2
$grid.ColumnHeadersDefaultCellStyle.ForeColor = $script:C.Muted
$grid.ColumnHeadersDefaultCellStyle.Font = $script:FontBold
$grid.ColumnHeadersHeight = (Px 34)
$grid.ColumnHeadersHeightSizeMode = 'DisableResizing'
$grid.RowTemplate.Height = (Px 26)
try {
    $pi = [System.Windows.Forms.DataGridView].GetProperty('DoubleBuffered', [System.Reflection.BindingFlags]'Instance,NonPublic')
    $pi.SetValue($grid, $true, $null)
} catch { }
foreach ($cdef in @(@('nivel', 'NIVEL', 100), @('tipo', 'TIPO', 190), @('elemento', 'ELEMENTO', 330), @('detalle', 'DETALLE', 0))) {
    $col = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $col.Name = $cdef[0]
    $col.HeaderText = $cdef[1]
    if ($cdef[2] -gt 0) { $col.AutoSizeMode = 'None'; $col.Width = (Px $cdef[2]) }
    else { $col.AutoSizeMode = 'Fill'; $col.MinimumWidth = (Px 240) }
    [void]$grid.Columns.Add($col)
}

# Menú contextual (clic derecho)
$ctx = New-Object System.Windows.Forms.ContextMenuStrip
$ctx.BackColor = $script:C.Panel2
$ctx.ForeColor = $script:C.Text
foreach ($mi in @(@('Abrir ubicación', 'open'), @('Copiar ruta', 'path'), @('Copiar nombre', 'name'), @('Copiar fila completa', 'row'))) {
    $item = New-Object System.Windows.Forms.ToolStripMenuItem
    $item.Text = $mi[0]
    $item.Tag = $mi[1]
    $item.Add_Click({ param($s, $e) Invoke-GridMenuAction ([string]$s.Tag) })
    [void]$ctx.Items.Add($item)
}
$grid.ContextMenuStrip = $ctx
$grid.Add_CellMouseDown({
    param($s, $e)
    if ($e.Button -eq 'Right' -and $e.RowIndex -ge 0) {
        $s.ClearSelection()
        $s.Rows[$e.RowIndex].Selected = $true
        try { $s.CurrentCell = $s.Rows[$e.RowIndex].Cells[2] } catch { }
    }
})
$grid.Add_CellDoubleClick({ param($s, $e) if ($e.RowIndex -ge 0) { Open-SelectedGridItem } })

# Barra de filtros (buscador + nivel + contador)
$script:FilterBar = New-Object System.Windows.Forms.Panel
$script:FilterBar.Dock = 'Top'
$script:FilterBar.Height = (Px 44)
$script:FilterBar.BackColor = $script:C.Bg
$script:FilterBar.Visible = $false

$lblSearch = New-Object System.Windows.Forms.Label
$lblSearch.Text = "BUSCAR"
$lblSearch.Font = $fontSmall
$lblSearch.ForeColor = $script:C.Muted
$lblSearch.AutoSize = $true
$lblSearch.Left = 0
$lblSearch.Top = (Px 14)

$script:TxtFilter = New-Object System.Windows.Forms.TextBox
$script:TxtFilter.Left = (Px 64)
$script:TxtFilter.Top = (Px 9)
$script:TxtFilter.Width = (Px 300)
$script:TxtFilter.BackColor = $script:C.Panel2
$script:TxtFilter.ForeColor = $script:C.Text
$script:TxtFilter.BorderStyle = 'FixedSingle'
$script:TxtFilter.Font = $script:FontBase
$script:TxtFilter.Add_TextChanged({
    if (-not $script:SuppressFilter) { $script:FilterText = $script:TxtFilter.Text; Update-FilterView }
})

$script:CmbLevel = New-Object System.Windows.Forms.ComboBox
$script:CmbLevel.Left = (Px (64 + 300 + 12))
$script:CmbLevel.Top = (Px 9)
$script:CmbLevel.Width = (Px 200)
$script:CmbLevel.DropDownStyle = 'DropDownList'
$script:CmbLevel.FlatStyle = 'Flat'
$script:CmbLevel.BackColor = $script:C.Panel2
$script:CmbLevel.ForeColor = $script:C.Text
$script:CmbLevel.Font = $script:FontBase
[void]$script:CmbLevel.Items.AddRange(@('Todos los niveles', 'Solo críticos', 'Críticos y alertas'))
$script:CmbLevel.SelectedIndex = 0
$script:CmbLevel.Add_SelectedIndexChanged({
    if (-not $script:SuppressFilter) {
        $script:FilterLevel = @('all', 'red', 'warn')[$script:CmbLevel.SelectedIndex]
        Update-FilterView
    }
})

$script:LblCount = New-Object System.Windows.Forms.Label
$script:LblCount.Dock = 'Right'
$script:LblCount.Width = (Px 480)
$script:LblCount.TextAlign = 'MiddleRight'
$script:LblCount.ForeColor = $script:C.Muted
$script:LblCount.Font = $script:FontBase
$script:LblCount.Text = ""

$script:FilterBar.Controls.Add($lblSearch)
$script:FilterBar.Controls.Add($script:TxtFilter)
$script:FilterBar.Controls.Add($script:CmbLevel)
$script:FilterBar.Controls.Add($script:LblCount)

# Categorías (chips)
$script:Chips = New-Object System.Windows.Forms.FlowLayoutPanel
$script:Chips.Dock = 'Top'
$script:Chips.AutoSize = $true
$script:Chips.AutoSizeMode = 'GrowAndShrink'
$script:Chips.WrapContents = $true
$script:Chips.BackColor = $script:C.Bg
$script:Chips.Padding = [System.Windows.Forms.Padding]::new(0, (Px 4), 0, (Px 2))
$script:Chips.Visible = $false
foreach ($def in $script:CatDefs) {
    $chip = New-Object System.Windows.Forms.Button
    $chip.Text = $def.Text
    $chip.Tag = $def.Key
    $chip.AutoSize = $true
    $chip.AutoSizeMode = 'GrowAndShrink'
    $chip.MinimumSize = New-Object System.Drawing.Size(0, (Px 32))
    $chip.Padding = [System.Windows.Forms.Padding]::new((Px 8), 0, (Px 8), 0)
    $chip.Margin = [System.Windows.Forms.Padding]::new(0, 0, (Px 6), (Px 6))
    $chip.FlatStyle = 'Flat'
    $chip.FlatAppearance.BorderSize = 1
    $chip.FlatAppearance.BorderColor = $script:C.Border
    $chip.FlatAppearance.MouseOverBackColor = $script:C.Hover
    $chip.UseVisualStyleBackColor = $false
    $chip.BackColor = $script:C.Panel2
    $chip.ForeColor = $script:C.Muted
    $chip.Font = $fontSmall
    $chip.Cursor = [System.Windows.Forms.Cursors]::Hand
    $chip.Add_Click({ param($s, $e) if (-not $script:Busy) { Show-Category ([string]$s.Tag) } })
    $script:CatButtons[$def.Key] = $chip
    $script:Chips.Controls.Add($chip)
}

# Portada (arte + atajos)
$script:HomeArt = New-Object System.Windows.Forms.Panel
$script:HomeArt.BackColor = $script:C.Bg

$lblBanner = New-Object System.Windows.Forms.Label
$lblBanner.AutoSize = $true
$lblBanner.Font = $fontMono
$lblBanner.ForeColor = $script:C.Accent
$lblBanner.Text = ($script:BannerText.TrimEnd())

$lblTag = New-Object System.Windows.Forms.Label
$lblTag.AutoSize = $true
$lblTag.Font = $fontHeader
$lblTag.ForeColor = $script:C.Text
$lblTag.Text = "FORENSIC SCANNER  ·  V81"

$lblKeys = New-Object System.Windows.Forms.Label
$lblKeys.AutoSize = $true
$lblKeys.Font = $script:FontBase
$lblKeys.ForeColor = $script:C.Muted
$lblKeys.Text = "F5       Auditoría global`r`nCtrl+F   Buscar en la tabla`r`nCtrl+E   Exportar la vista a CSV`r`nEsc      Limpiar el buscador`r`nDoble clic / clic derecho sobre una fila: abrir ubicación o copiar"

$lblArt = New-Object System.Windows.Forms.Label
$lblArt.AutoSize = $true
$lblArt.Font = $fontArt
$lblArt.ForeColor = $script:C.Pink
$lblArt.Text = ($script:sideGirl -join "`r`n")

$szBanner = $lblBanner.GetPreferredSize([System.Drawing.Size]::Empty)
$szTag    = $lblTag.GetPreferredSize([System.Drawing.Size]::Empty)
$szKeys   = $lblKeys.GetPreferredSize([System.Drawing.Size]::Empty)
$szArt    = $lblArt.GetPreferredSize([System.Drawing.Size]::Empty)
$leftW = [math]::Max($szBanner.Width, $szKeys.Width)
$leftH = $szBanner.Height + (Px 14) + $szTag.Height + (Px 22) + $szKeys.Height
$totW  = $leftW + (Px 36) + $szArt.Width
$totH  = [math]::Max($leftH, $szArt.Height)
$script:HomeArt.Size = New-Object System.Drawing.Size($totW, $totH)
$offY = [int](($totH - $leftH) / 2)
$lblBanner.Location = New-Object System.Drawing.Point(0, $offY)
$lblTag.Location    = New-Object System.Drawing.Point(0, ($offY + $szBanner.Height + (Px 14)))
$lblKeys.Location   = New-Object System.Drawing.Point(0, ($offY + $szBanner.Height + (Px 14) + $szTag.Height + (Px 22)))
$lblArt.Location    = New-Object System.Drawing.Point(($leftW + (Px 36)), [int](($totH - $szArt.Height) / 2))
$script:HomeArt.Controls.AddRange(@($lblBanner, $lblTag, $lblKeys, $lblArt))

# Orden de apilado: el control que rellena va primero; el último "Top" queda arriba del todo
$script:HostPanel.Controls.Add($grid)
$script:HostPanel.Controls.Add($script:FilterBar)
$script:HostPanel.Controls.Add($script:Chips)
$script:HostPanel.Controls.Add($script:HomeArt)
$script:HostPanel.Add_Resize({ Move-HomeArt })

# --- Cabecera (título de la vista + botones) ---
$header = New-Object System.Windows.Forms.Panel
$header.Dock = 'Top'
$header.Height = (Px 54)
$header.BackColor = $script:C.Panel
$header.Padding = [System.Windows.Forms.Padding]::new((Px 20), 0, (Px 16), 0)

$script:LblView = New-Object System.Windows.Forms.Label
$script:LblView.Dock = 'Fill'
$script:LblView.TextAlign = 'MiddleLeft'
$script:LblView.Font = $fontHeader
$script:LblView.ForeColor = $script:C.Accent
$script:LblView.Text = "CONSOLA CENTRAL DE OPERACIONES FORENSES"

$script:BtnOpenSelected = New-FlatButton "ABRIR UBICACIÓN" 150 32
$script:BtnOpenSelected.Dock = 'Right'
$script:BtnOpenSelected.Visible = $false
$script:BtnOpenSelected.Add_Click({ Open-SelectedGridItem })

$script:BtnExport = New-FlatButton "EXPORTAR CSV" 130 32
$script:BtnExport.Dock = 'Right'
$script:BtnExport.Visible = $false
$script:BtnExport.Add_Click({ Export-GridView })

$header.Controls.Add($script:LblView)
$header.Controls.Add($script:BtnOpenSelected)
$header.Controls.Add($script:BtnExport)

# El botón EXPORTAR solo se ve cuando el panel de resultados está visible
$script:Chips.Add_VisibleChanged({ if ($script:BtnExport) { $script:BtnExport.Visible = $script:Chips.Visible } })

# --- Barra de estado inferior (estado + botones + progreso + detalle) ---
$statusPanel = New-Object System.Windows.Forms.Panel
$statusPanel.Dock = 'Bottom'
$statusPanel.Height = (Px 92)
$statusPanel.BackColor = $script:C.Panel

$row3 = New-Object System.Windows.Forms.Panel
$row3.Dock = 'Fill'
$row3.Padding = [System.Windows.Forms.Padding]::new((Px 20), 0, (Px 16), 0)
$script:LblDetail = New-Object System.Windows.Forms.Label
$script:LblDetail.Dock = 'Fill'
$script:LblDetail.TextAlign = 'MiddleLeft'
$script:LblDetail.ForeColor = $script:C.Muted
$script:LblDetail.Font = $script:FontBase
$row3.Controls.Add($script:LblDetail)

$row2 = New-Object System.Windows.Forms.Panel
$row2.Dock = 'Top'
$row2.Height = (Px 24)
$barHolder = New-Object System.Windows.Forms.Panel
$barHolder.Dock = 'Fill'
$barHolder.Padding = [System.Windows.Forms.Padding]::new((Px 20), (Px 8), (Px 8), (Px 8))
$script:BarTrack = New-Object System.Windows.Forms.Panel
$script:BarTrack.Dock = 'Fill'
$script:BarTrack.BackColor = $script:C.Panel2
$script:BarFill = New-Object System.Windows.Forms.Panel
$script:BarFill.Dock = 'Left'
$script:BarFill.Width = 0
$script:BarFill.BackColor = $script:C.Accent
$script:BarTrack.Controls.Add($script:BarFill)
$barHolder.Controls.Add($script:BarTrack)
$script:LblPct = New-Object System.Windows.Forms.Label
$script:LblPct.Dock = 'Right'
$script:LblPct.Width = (Px 70)
$script:LblPct.TextAlign = 'MiddleCenter'
$script:LblPct.Font = $script:FontBold
$script:LblPct.ForeColor = $script:C.Text
$script:LblPct.Text = "0%"
$row2.Controls.Add($barHolder)
$row2.Controls.Add($script:LblPct)

$row1 = New-Object System.Windows.Forms.Panel
$row1.Dock = 'Top'
$row1.Height = (Px 38)
$row1.Padding = [System.Windows.Forms.Padding]::new((Px 20), (Px 4), (Px 16), (Px 2))
$script:LblStatus = New-Object System.Windows.Forms.Label
$script:LblStatus.Dock = 'Fill'
$script:LblStatus.TextAlign = 'MiddleLeft'
$script:LblStatus.Font = $script:FontBold
$script:LblStatus.ForeColor = $script:C.Text
$script:LblStatus.Text = if ($isAdminNow) { "Listo. Presiona F5 para iniciar la auditoría global." } else { "Listo (sin permisos de administrador: algunos módulos quedarán incompletos). F5 inicia la auditoría." }
$script:BtnCancel = New-FlatButton "CANCELAR" 110 28
$script:BtnCancel.Dock = 'Right'
$script:BtnCancel.Visible = $false
$script:BtnCancel.ForeColor = $script:C.Red
$script:BtnCancel.Add_Click({ $script:CancelRequested = $true; Set-Status "Cancelando... (termina el archivo en curso)" })
$script:BtnReport = New-FlatButton "ABRIR REPORTE" 140 28
$script:BtnReport.Dock = 'Right'
$script:BtnReport.Visible = $false
$script:BtnReport.Add_Click({
    try { if ($script:LastReport -and (Test-Path -LiteralPath $script:LastReport)) { Start-Process -FilePath "explorer.exe" -ArgumentList ('/select,"' + $script:LastReport + '"') } } catch { }
})
$row1.Controls.Add($script:LblStatus)
$row1.Controls.Add($script:BtnCancel)
$row1.Controls.Add($script:BtnReport)

$statusPanel.Controls.Add($row3)
$statusPanel.Controls.Add($row2)
$statusPanel.Controls.Add($row1)

$mainRight.Controls.Add($script:HostPanel)
$mainRight.Controls.Add($statusPanel)
$mainRight.Controls.Add($header)

# --- Menú lateral ---
$navPanel = New-Object System.Windows.Forms.Panel
$navPanel.Dock = 'Left'
$navPanel.Width = (Px 268)
$navPanel.BackColor = $script:C.Panel

$navTitle = New-Object System.Windows.Forms.Panel
$navTitle.Dock = 'Top'
$navTitle.Height = (Px 84)
$lblNavT = New-Object System.Windows.Forms.Label
$lblNavT.Text = "EL SOMBRIO IF"
$lblNavT.Font = $fontTitle
$lblNavT.ForeColor = $script:C.Accent
$lblNavT.AutoSize = $true
$lblNavT.Location = New-Object System.Drawing.Point((Px 20), (Px 18))
$lblNavS = New-Object System.Windows.Forms.Label
$lblNavS.Text = "FORENSIC SCANNER  ·  V81"
$lblNavS.Font = $fontSmall
$lblNavS.ForeColor = $script:C.Muted
$lblNavS.AutoSize = $true
$lblNavS.Location = New-Object System.Drawing.Point((Px 22), (Px 52))
$navTitle.Controls.Add($lblNavT)
$navTitle.Controls.Add($lblNavS)

$navFooter = New-Object System.Windows.Forms.Label
$navFooter.Dock = 'Bottom'
$navFooter.Height = (Px 38)
$navFooter.TextAlign = 'MiddleLeft'
$navFooter.Padding = [System.Windows.Forms.Padding]::new((Px 20), 0, 0, 0)
$navFooter.Font = $fontSmall
if ($isAdminNow) { $navFooter.Text = "●  ADMINISTRADOR"; $navFooter.ForeColor = $script:C.Green }
else             { $navFooter.Text = "●  SIN PERMISOS DE ADMIN"; $navFooter.ForeColor = $script:C.Yellow }

$navFlow = New-Object System.Windows.Forms.FlowLayoutPanel
$navFlow.Dock = 'Fill'
$navFlow.FlowDirection = 'TopDown'
$navFlow.WrapContents = $false
$navFlow.AutoScroll = $true
$navFlow.Padding = [System.Windows.Forms.Padding]::new((Px 12), (Px 4), (Px 8), 0)
$navFlow.BackColor = $script:C.Panel

function Add-NavSection([string]$Text) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text
    $l.Font = $fontSmall
    $l.ForeColor = $script:C.Muted
    $l.Width = (Px 236)
    $l.Height = (Px 30)
    $l.TextAlign = 'BottomLeft'
    $l.Padding = [System.Windows.Forms.Padding]::new((Px 6), 0, 0, (Px 4))
    $l.Margin = [System.Windows.Forms.Padding]::new(0, (Px 6), 0, 0)
    $navFlow.Controls.Add($l)
}

function Add-NavButton([string]$Id, [string]$Text, $Fore = $null) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text
    $b.Tag = $Id
    $b.Width = (Px 236)
    $b.Height = (Px 40)
    $b.Margin = [System.Windows.Forms.Padding]::new(0, 0, 0, (Px 3))
    $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderSize = 0
    $b.FlatAppearance.MouseOverBackColor = $script:C.Hover
    $b.FlatAppearance.MouseDownBackColor = $script:C.Select
    $b.UseVisualStyleBackColor = $false
    $b.BackColor = $script:C.Panel
    $b.ForeColor = if ($null -ne $Fore) { $Fore } else { $script:C.Text }
    $b.Font = $script:FontBase
    $b.TextAlign = 'MiddleLeft'
    $b.Padding = [System.Windows.Forms.Padding]::new((Px 14), 0, 0, 0)
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    $b.Add_Click({ param($s, $e) Invoke-NavAction ([string]$s.Tag) })
    $script:NavButtons.Add($b)
    $navFlow.Controls.Add($b)
}

Add-NavSection "ANÁLISIS"
Add-NavButton 'global'      "01   Auditoría global  (F5)" $script:C.Accent
Add-NavButton 'live'        "02   Panel de resultados"
Add-NavButton 'registry'    "03   Registro de sesión"
Add-NavSection "VENTANAS"
Add-NavButton 'log'         "04   Registro de actividad  (Ctrl+L)"
Add-NavButton 'viewer'      "05   Visor de resultados  (Ctrl+R)"
Add-NavButton 'sysinfo'     "06   Información del sistema  (Ctrl+I)"
Add-NavSection "HERRAMIENTAS"
Add-NavButton 'doomsday'    "07   Doomsday Detector"
Add-NavButton 'sysinformer' "08   System Informer"
Add-NavButton 'journal'     "09   JournalTrace"
Add-NavButton 'lilith'      "10   Lilith Services"
Add-NavButton 'tools'       "11   Menú de herramientas"
Add-NavSection "REVISIÓN MANUAL"
Add-NavButton 'manual'      "12   Revisión manual (Win+R)"
Add-NavSection "SISTEMA"
Add-NavButton 'theme'       "13   Cambiar tema  ($($script:ThemeName))"
Add-NavButton 'panic'       "14   Cerrar ya (cancelar todo)" $script:C.Red
Add-NavButton 'exit'        "15   Salir" $script:C.Muted

$navPanel.Controls.Add($navFlow)
$navPanel.Controls.Add($navFooter)
$navPanel.Controls.Add($navTitle)

$script:Form.Controls.Add($mainRight)
$script:Form.Controls.Add($navPanel)

# --- Atajos de teclado ---
$script:Form.Add_KeyDown({
    param($s, $e)
    try {
        if ($e.KeyCode -eq 'F5') {
            if (-not $script:Busy) { Start-GlobalScan }
            $e.Handled = $true
        } elseif ($e.Control -and $e.KeyCode -eq 'F') {
            if ($script:FilterBar.Visible) { [void]$script:TxtFilter.Focus(); $script:TxtFilter.SelectAll() }
            $e.Handled = $true
        } elseif ($e.Control -and $e.KeyCode -eq 'L') {
            Invoke-NavAction 'log'
            $e.Handled = $true
        } elseif ($e.Control -and $e.KeyCode -eq 'R') {
            if (-not $script:Busy) { Invoke-NavAction 'viewer' }
            $e.Handled = $true
        } elseif ($e.Control -and $e.KeyCode -eq 'I') {
            Invoke-NavAction 'sysinfo'
            $e.Handled = $true
        } elseif ($e.Control -and $e.KeyCode -eq 'E') {
            if ($script:Grid.Visible) { Export-GridView }
            $e.Handled = $true
        } elseif ($e.KeyCode -eq 'Escape') {
            if ($script:FilterBar.Visible -and (($script:FilterText) -or $script:FilterLevel -ne 'all')) {
                Clear-Filter
                Show-Category $script:ActiveCat
                $e.Handled = $true
            }
        }
    } catch { }
})

# --- Cierre seguro: si hay un análisis en curso, lo cancela y cierra al terminar ---
$script:Form.Add_FormClosing({
    param($s, $e)
    if ($script:Busy) {
        $e.Cancel = $true
        $script:CancelRequested = $true
        $script:CloseAfter = $true
        Set-Status "Cerrando: se está terminando el archivo en curso..."
    }
})
$script:Form.Add_FormClosed({
    try { Write-Log "Aplicación cerrada." } catch { }
    try { if ($script:HiddenConsole -ne [IntPtr]::Zero) { [void][Sombrio.WinApi]::ShowWindow($script:HiddenConsole, 5) } } catch { }
})
$script:Form.Add_Shown({ Move-HomeArt })

# ============================================================
# ARRANQUE
# ============================================================
Show-Home
Write-Log ("Aplicación iniciada · V81 · Administrador: {0} · PowerShell {1}" -f $(if ($isAdminNow) { "sí" } else { "no" }), $PSVersionTable.PSVersion) 'INFO'
Write-Log ("Log de esta sesión: " + $script:LogFile) 'INFO'
[System.Windows.Forms.Application]::Run($script:Form)
