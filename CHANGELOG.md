# Changelog

## [1.0.1] - 2025-01-25

### Added
- Classic Era support (Interface 11505)
- Cataclysm Classic support (Interface 40401)
- C_AddOns API compatibility shim for Classic clients

## [1.0.0] - 2025-01-25

### Added
- Initial release
- LDB plugin displaying all registered slash commands organized by addon
- Hooks SlashCmdList for accurate addon ownership detection via debugstack()
- Collapsible sections with persistent state (saved between sessions)
- LibQTip scrollable tooltip (max 600px height)
- Click any command to insert it into chat
- Left-click broker icon to refresh cache
- Right-click broker icon to search commands
- Slash commands: `/slashcmds`, `/bsc`
  - `/slashcmds <search>` - search for commands
  - `/slashcmds list` - list all commands in chat
  - `/slashcmds unknown` - show unattributed commands
  - `/slashcmds debug` - show hook statistics
