Broker: Slash Commands is a LibDataBroker plugin that lists every registered slash command, grouped by addon. It hooks SlashCmdList early to capture ownership reliably, then presents the results in a compact, scrollable tooltip.

Features
- Lists all slash commands by addon, including Blizzard and unknown sources
- Collapsible sections per addon with a total count
- Click a slash command to insert it into chat
- Search, list, and debug output via built-in slash commands
- Uses LibQTip for a scrollable tooltip

Commands
- `/slashcmds` or `/bsc` shows help and totals
- `/slashcmds <search>` finds commands by addon name or slash text
- `/slashcmds list` prints all commands to chat
- `/slashcmds unknown` shows commands that could not be matched
- `/slashcmds dump` detailed dump of unknowns
- `/slashcmds hooks` show hook captures
- `/slashcmds debug` show hook stats

Dependencies
- LibDataBroker-1.1 display addon (e.g. Bazooka, ChocolateBar, etc.)
- LibStub, CallbackHandler-1.0, LibQTip-1.0

Notes
- Slash command ownership is inferred by stack traces and heuristics; most addons resolve cleanly, but some may appear as Unknown depending on how they register commands.
