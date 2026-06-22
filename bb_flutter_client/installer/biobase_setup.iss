[Setup]
AppName=Biobase Client
AppVersion=0.2.0
AppPublisher=BioBase Live
DefaultDirName={autopf}\Biobase Client
DefaultGroupName=Biobase Client
OutputDir=output
OutputBaseFilename=biobase-client-setup
Compression=lzma2
SolidCompression=yes
PrivilegesRequired=lowest
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\biobase_client.exe
WizardStyle=modern
DisableProgramGroupPage=yes
DisableDirPage=yes

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs

[Icons]
Name: "{autodesktop}\Biobase Client"; Filename: "{app}\biobase_client.exe"
Name: "{group}\Biobase Client"; Filename: "{app}\biobase_client.exe"

[Run]
Filename: "{app}\biobase_client.exe"; Description: "Launch Biobase Client"; Flags: nowait postinstall skipifsilent
