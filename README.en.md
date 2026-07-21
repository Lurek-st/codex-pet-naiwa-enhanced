<div align="center">

# Enhanced Nai Frog Pet for Codex

**[简体中文](./README.md) · English**

A Windows Codex Desktop enhancement based on [timerring/codex-pet-naiwa](https://github.com/timerring/codex-pet-naiwa).

</div>

## Features

- Types on a small desktop keyboard while Codex is reasoning, running commands, or using tools.
- Loops the belly-laugh animation and a bundled local laugh sound for as long as the pointer remains hovered.
- Extends the hover hit region downward without moving the pet's visible top edge.
- Plays directional walking frames while dragging, with yellow-green fart clouds emitted behind the tail.
- Preserves idle, gaze, review, failure, and click behavior.
- Requires no OpenAI API key and no runtime network request for audio playback.

## Compatibility

The repository contains two variants:

- `naifrog/`: the standard upstream custom pet, installable by copying the folder.
- `naifrog-dev/`: the enhanced 12-row spritesheet, used together with the Windows host patch in `tools/patch-codex-pet-interactions-msix.ps1`.

The enhanced path has been validated on Windows 10/11 with Codex Desktop `26.715.7063.0`, PowerShell 5.1+, Node.js, and Python 3. The patcher validates exact bundle markers and stops on unknown Codex versions instead of applying blind replacements. Run a new dry run after every Microsoft Store update. The host patch is Windows-only.

## Install the Enhanced Version

```powershell
git clone https://github.com/Lurek-st/codex-pet-naiwa-enhanced.git
Set-Location .\codex-pet-naiwa-enhanced

powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\install_test_pet.ps1

powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\patch-codex-pet-interactions-msix.ps1 `
  -DryRun `
  -OutputRoot "D:\CodexPetBuild"
```

After the dry run passes, open a standalone Windows PowerShell session outside Codex and run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\patch-codex-pet-interactions-msix.ps1 `
  -Install -Launch -InstallPrerequisites `
  -OutputRoot "D:\CodexPetBuild"
```

The script copies the installed package, validates and patches its ASAR, rebuilds and signs an MSIX, then installs and relaunches Codex. It does not edit files in `C:\Program Files\WindowsApps` in place.

Refresh **Settings → Pets → Custom pets** and select the enhanced Nai Frog pet.

## Install Only the Standard Pet

If you do not need the Windows host enhancements, copy `naifrog/` into the Codex custom pets directory:

```powershell
$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME ".codex" }
$petDir = Join-Path $codexHome "pets\naifrog"
New-Item -ItemType Directory -Force $petDir | Out-Null
Copy-Item ".\naifrog\*" $petDir -Recurse -Force
```

## Acceptance Check

1. Reasoning and tool execution show the keyboard instead of the original hand-hesitation animation.
2. Hovering the pet or the expanded lower region starts the belly laugh and local audio.
3. A 20-second hover keeps both animation and audio looping; leaving stops both immediately.
4. Dragging right emits the cloud behind the left side of the tail; dragging left mirrors it.
5. Clicking does not trigger an additional action, and existing states remain intact.

See [DEVELOPMENT.md](./DEVELOPMENT.md) for implementation and validation details.

## Development Validation

```powershell
python .\tools\validate_pet.py .\naifrog-dev `
  --baseline .\naifrog\spritesheet.webp `
  --allowed-rows 1,2,6,11 `
  --require-changed-rows 1,2,6,11

node --check .\tools\patch-codex-pet-interactions.cjs
```

The validator must report `VALIDATION=PASS`. Build, extraction, signing, and verification output is written under the Git-ignored `work/` directory.

## Repository Layout

```text
assets/                         source/prepared animation assets and local audio
naifrog/                        standard upstream pet and previews
naifrog-dev/                    enhanced 12-row spritesheet and manifest
tools/                          build, validation, installation, and MSIX patch scripts
DEVELOPMENT.md                  technical implementation and complete test checklist
```

## Security Notes

- The source repository contains no OpenAI API key, GitHub token, private key, or user authentication data.
- Generated certificates and MSIX packages are excluded from source control.
- Review the scripts and always run the dry run before installation.
- A future Microsoft Store update may replace the developer-signed package.

## Credits

- Upstream: [timerring/codex-pet-naiwa](https://github.com/timerring/codex-pet-naiwa)
- [Nitrogen216/awesome_pets](https://github.com/Nitrogen216/awesome_pets)
- [LynnShaw/naiwa-pet](https://github.com/LynnShaw/naiwa-pet)

## License

Code modifications and original repository content are licensed under the [MIT License](./LICENSE). Upstream copyright and license notices must be preserved. Third-party assets listed under Credits may remain subject to their own terms.
