#!/usr/bin/env bash
# The trust ladder (scripts/desktop-mcp.py: trust_gate, `trust` commands)
# against a real `nixbook-desktop-mcp helper` (tests/trust-tests.py):
#   - reads pass silently, acting steps pass and are told ({told});
#   - a risky step of another server is asked ({approval}), Allow → allow,
#     No → deny; a risky desktop step is left to the server's own ask;
#   - the user's `trust set` (the helper's stdin: Always, Settings) stops
#     the asking, even for a Discord send (to tell at most, never silent);
#   - an agent (Claude Code's Bash) can't set a level;
#   - three yeses in a row offer to stop asking ({trustSuggest}).
# Needs python3. Run: bash tests/trust.sh
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
unset NIXBOOK_DESKTOP_MCP_CONFIG NIRI_SOCKET
python3 -I "$root/tests/trust-tests.py" "$root/scripts/desktop-mcp.py"
