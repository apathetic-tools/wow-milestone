# Story Progress

A World of Warcraft addon to track your story progression.

## Structure

- **milestone.toc** - Addon manifest file (tells WoW about the addon)
- **Core.lua** - Main addon entry point
- **Libs/** - For embedded libraries (LibStub, etc.)
- **Locales/** - Localization files
- **Utils/** - Utility functions and helpers

## Installation

1. Copy the `Milestone` folder to your WoW `Addons` directory:
   - Windows: `C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\`
   - Mac: `/Applications/World of Warcraft/_retail_/Interface/AddOns/`
   - Linux: Your WoW installation directory

2. Restart World of Warcraft or type `/reload` in-game

3. Enable the addon in the AddOns list at character selection

## Development

- Edit files in the `Milestone/` folder
- Reload addon with `/reload` command in-game
- Check the chat for debug messages
