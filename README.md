# sol

A Lua script for ComputerCraft that recursively downloads and installs Lua files from a GitHub repository onto your computer.

## Requirements

- ComputerCraft mod installed in Minecraft.
- HTTP API enabled in ComputerCraft (check `config/computer.cfg` or use `/computercraft config` command).
- Internet access for the computer.

## Usage

Run the installer script with the following command:

```
installer.lua <repo_owner> <repo_name> [options]
```

### Arguments

- `<repo_owner>`: The GitHub username or organization that owns the repository (required).
- `<repo_name>`: The name of the GitHub repository (required).

### Options

- `-r <ref>`, `--ref <ref>`: Optional. Specifies the branch, tag, or commit SHA to download from. If not provided, defaults to the repository's default branch.
- `-e <exts>`, `--extensions <exts>`: Optional. Comma-separated list of file extensions to include (whitelist) or exclude (if `-b` is used). Defaults to `lua` if not specified.
- `-b`, `--blacklist`: Optional. Treat the extensions list as a blacklist instead of whitelist.
- `-h`, `--help`: Optional. Displays usage information and exits.

### Examples

- Download the latest version from the default branch (only Lua files):
  ```
  installer.lua dan200 ComputerCraft
  ```

- Download from a specific branch:
  ```
  installer.lua dan200 ComputerCraft --ref master
  ```

- Download from a tag:
  ```
  installer.lua dan200 ComputerCraft -r v1.0
  ```

- Download only .txt and .md files:
  ```
  installer.lua someuser somerepo -e txt,md
  ```

- Download all files except .png and .jpg:
  ```
  installer.lua someuser somerepo -e png,jpg -b
  ```

- Show help:
  ```
  installer.lua --help
  ```

## How It Works

The script fetches the repository contents from GitHub's API, recursively traverses directories, and downloads files based on the specified extensions. By default, it downloads only `.lua` files. You can customize the file types using the `-e` and `-b` options. It recreates the directory structure on your ComputerCraft computer and saves the files accordingly.

**Note:** File filtering is based on extensions. Use `-e` to specify extensions and `-b` to treat them as exclusions.

## Installation

1. Place `installer.lua` on your ComputerCraft computer.
2. Run the script as shown in the Usage section.
