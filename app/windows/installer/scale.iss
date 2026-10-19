; Instalador de Scale para Windows (Inno Setup 6).
;
; Antes: flutter build windows --release, y copiar junto a scale.exe las
; librerías de Visual C++ (vcruntime140.dll, vcruntime140_1.dll, msvcp140.dll)
; para que funcione en equipos que no las tienen.
; Compilar: iscc /DMyAppVersion=0.1.0 windows\installer\scale.iss

#ifndef MyAppVersion
  #define MyAppVersion "0.1.0"
#endif
#define MyAppName "Scale"
#define MyAppExeName "scale.exe"

[Setup]
AppId={{8F2B6C1E-5A4D-4E7B-9C3A-2D1F0E6B7A91}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=sergiovegam41
AppPublisherURL=https://github.com/sergiovegam41/Scale
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=..\..\build\dist
OutputBaseFilename=Scale-{#MyAppVersion}-windows-setup
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequiredOverridesAllowed=dialog
WizardStyle=modern

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent
