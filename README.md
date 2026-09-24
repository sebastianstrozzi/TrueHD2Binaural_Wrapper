# TrueHD2Binaural Wrapper

## Overview

The standard downmix of Dolby TrueHD Atmos tracks (e.g. using Dolby Atmos for Headphones in a compatible player) inherently loses the spatial Object-Based Audio metadata and so most of the 3D positioning.

This script solves this problem by automating a non-real-time rendering pipeline that translates the full 3D soundscape into a bit-perfect Binaural (HRTF) stereo track. This preserves the spatial cues, elevation, and dynamic objects for headphone listening, providing a true holographic audio experience. Finally, the rendered track is safely remuxed into an MKV file as a lossless 24-bit FLAC. This allows the user to play their TrueHD tracks in every player they want as a stereo track. It is greatly recommended that the users disable Windows Spatial Audio when playing such tracks (if not in exclusive mode) as this can introduce artifacts and ruin the rendered stereo tracks.

## Requirements

* **FFmpeg & FFprobe**: Must be installed and added to your system's PATH. You can easily install them via Windows Package Manager: `winget install ffmpeg`.
* **Mpv-omniphony**: A patched portable build of the `mpv` player that embeds the `orender` spatial audio decoder.
* **Harletty-bridge**: The `harletty_bridge.dll` file must be placed next to your `mpv` executable. This bridge is strictly required to decode TrueHD and extract the Atmos (JOC) metadata.

## Windows 11 Smart App Control (Troubleshooting)

Because Mpv-Omniphony and `harletty_bridge.dll` are unsigned files, Windows 11's **Smart App Control** may block them from loading. If this happens, the audio rendering will fail or fall back to a standard, non-spatial downmix.

To prevent this, you have two options:

1. **Unblock the archive**: Locate the folder where you placed mpv and the harletty_bridge.dll and use the PowerShell line: `Get-ChildItem -Path "path to the mpv folder" -Recurse | Unblock-File` (where *"path to the mpv folder"* must be changed with your actual path, e.g.: *"C:\\Tools\\MPV"*).
2. **Manage SAC Settings**: If the DLL is still being blocked, you may need to temporarily set Smart App Control to **Off**. Thanks to the **April 2026 Windows 11 Security Update**, users with an up-to-date Windows 11 can now safely toggle Smart App Control on/off directly from the Windows Security app without needing to reset or reinstall the operating system. This is generally a dangerous practice, so do this only if you know what you're doing!

## Usage

After downloading the script, place it in a folder you like (you can also execute it while in the Downloads folder and delete it after). You can run the script interactively or provide arguments via the command line.

In File Explorer locate the folder containing the script, right-click on an empty area and select "Open in Terminal". There, simply write `.\TrueHD2Binaural_wrapper.ps1` and press ENTER. The script will automatically ask for what it needs (e.g. if it cannot find `mpv.exe` in your PATH, it will prompt you for the exact absolute paths). Remember to use absolute paths as inputs.

If you prefer, you can add arguments directly to the script, here's an example:

```powershell
.\TrueHD2Binaural_wrapper.ps1 -FilePath "C:\Movies\film.mkv" -MpvPath "C:\Tools\mpv.exe" [-KeepTemp]
```

The arguments are:

* `-FilePath`: The absolute path to your source media file.
* `-MpvPath`: The absolute path to your `mpv.exe` executable, if not installed in PATH.
* `-KeepTemp`: Retains the intermediate temporary files after the remuxing is complete.

## Credits & Acknowledgments

This script relies on the incredible work of the open-source community:

* [**Omniphony / liborender**](https://github.com/mgth/Omniphony) by `mgth` for the spatial audio rendering engine and the `mpv-omniphony` fork.
* [**harletty-bridge**](https://github.com/harletty/harletty-bridge) for the TrueHD Atmos metadata extraction plugin.
* The [**mpv**](https://mpv.io/) and [**FFmpeg**](https://ffmpeg.org/) teams for the core multimedia playback and processing frameworks.
