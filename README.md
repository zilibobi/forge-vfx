![Banner](/forge-banner.png)

<div align="center">
  <img alt="View Documentation" src="https://img.shields.io/badge/Documentation-View?style=for-the-badge&label=View&color=c4a7e7&link=https%3A%2F%2Fdocs.zilibobi.dev%2Fvfx-forge%2F">
  <img alt="Join Discord" src="https://img.shields.io/discord/1401872327162986626?logo=discord&style=for-the-badge&color=c4a7e7&logoColor=ffffff&label=Join%20Discord">
</div>

# Emit Module

The is the official repository for the emit module provided by the <a href="https://devforum.roblox.com/t/3867553">VFX Forge</a> Roblox plugin.

## Installation

#### Using Wally

```sh
ForgeVFX = "zilibobi/forge-vfx"
```

#### Manual

Check the [releases page](https://github.com/zilibobi/forge-vfx/releases/latest) for prebuilt .rbxm files.

## Usage

The module needs to be initialized before emitting any effects.
After that the module is also exposed inside `shared.vfx`.

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local vfx = require(ReplicatedStorage.ForgeVFX)

vfx.init()
vfx.emit(workspace.Effect)
```

## License
The emit module is licensed under a custom source-available copyleft license which **<mark>only allows usage within Roblox games</mark>**. That said, feel free to contribute and report bugs.
