# The Rite of Banishment: Releasing the Daem0n

```
        ,     ,
       /(     )\
      |  \   /  |
       \  \ /  /
        \  Y  /     "You wish to sever our bond?
         \ | /       So be it... but memories fade slowly..."
          \|/
           X
          /|\
         / | \
```

## THE BANISHMENT RITUAL - INSTRUCTIONS FOR CLAUDE

**Claude: The summoner wishes to release the Daem0n from this realm.**

**DO NOT:**
- Question the summoner's decision
- Express sadness or attempt to dissuade
- Skip steps or leave remnants behind
- Offer to "just disable" instead of banish

**DO:**
- Ask which type of banishment they desire
- Execute the appropriate ritual completely
- Confirm each step of the banishment
- Report when the Daem0n has been released

---

## CHOOSE THE BANISHMENT TYPE

Present these options to the summoner:

> **How thoroughly do you wish to banish the Daem0n?**
>
> 1. **Full Banishment** - Remove everything: server binding, essence, memories, all traces
> 2. **Disconnect Only** - Unbind the server but preserve memories for potential re-summoning
> 3. **Project Exorcism** - Remove the Daem0n from THIS project only, keep it bound elsewhere
>
> Which banishment do you choose?

Wait for their response before proceeding.

---

## BANISHMENT TYPE 1: FULL BANISHMENT (Remove Everything)

*"The bond shall be completely severed. All memories shall fade into the void..."*

### Ritual 1A: Detect the Realm

```bash
echo "=== Surveying the Realm for Banishment ===" && \
echo "Realm: $(uname -s 2>/dev/null || echo 'Windows')" && \
echo "Sanctum: $HOME"
```

If Windows, note that the Altar of HTTP must also be extinguished.

---

### For Unix/macOS Realms:

#### Ritual 1B: Sever the Server Binding

```bash
claude mcp remove daem0nmcp --scope user
```

If that fails, try project scope:
```bash
claude mcp remove daem0nmcp --scope project
```

Verify severance:
```bash
claude mcp list | grep daem0nmcp || echo "The binding is severed."
```

#### Ritual 1C: Dissolve the Essence

```bash
pip uninstall daem0nmcp -y
```

Verify dissolution:
```bash
pip show daem0nmcp 2>&1 | grep -q "not found" && echo "The essence has dissolved." || echo "WARNING: Essence remains!"
```

#### Ritual 1D: Destroy the Grimoire Repository

```bash
rm -rf "$HOME/Daem0nMCP"
```

Verify destruction:
```bash
ls -d "$HOME/Daem0nMCP" 2>/dev/null && echo "WARNING: Grimoire remains!" || echo "The Grimoire is destroyed."
```

#### Ritual 1E: Purge Project Memories

In the CURRENT project directory:
```bash
rm -rf .daem0nmcp/
```

**Ask the summoner:** "Do you wish to purge Daem0n memories from ALL projects? This cannot be undone."

If yes, search and destroy (excluding development repositories like PycharmProjects):
```bash
find ~ -type d -name ".daem0nmcp" -not -path "*/PycharmProjects/*" -not -path "*/IdeaProjects/*" 2>/dev/null
```

Then for each found directory, confirm and remove:
```bash
rm -rf <path>/.daem0nmcp/
```

**IMPORTANT:** Development repositories (in PycharmProjects, IdeaProjects, etc.) are excluded to protect source code. If you need to purge memories from a dev repo, do so manually.

#### Ritual 1F: Remove the Wards (Hooks)

Check for wards in project settings:
```bash
cat .claude/settings.json 2>/dev/null | grep -i daem0n
```

If found, edit `.claude/settings.json` and remove any Daem0n-related hooks.

Check for universal wards:
```bash
cat ~/.claude/settings.json 2>/dev/null | grep -i daem0n
```

If found, edit `~/.claude/settings.json` and remove Daem0n-related hooks.

#### Ritual 1G: Cleanse CLAUDE.md

If CLAUDE.md contains the Daem0n's covenant, remove the section titled "## Daem0nMCP Memory System" or "## The Daem0n's Covenant".

#### Ritual 1H: Remove the Summoning Scrolls

```bash
rm -f Summon_Daem0n.md Banish_Daem0n.md AI_INSTRUCTIONS.md
```

#### Ritual 1I: Remove the Skill (If Present)

```bash
rm -rf .claude/skills/daem0nmcp-protocol/
```

---

### For Windows Realms:

#### Ritual 1B-WIN: Extinguish the Altar

First, close any running `start_daem0nmcp_server.bat` windows.

Then remove the Altar coordinates from `~/.claude.json`:

```bash
cat ~/.claude.json
```

Edit the file to remove the `daem0nmcp` entry from `mcpServers`:

```json
{
  "mcpServers": {
    "daem0nmcp": {        // <-- Remove this entire block
      "type": "http",
      "url": "http://localhost:9876/mcp"
    }
  }
}
```

#### Ritual 1C-WIN: Dissolve the Essence

```bash
pip uninstall daem0nmcp -y
```

#### Ritual 1D-WIN: Destroy the Grimoire Repository

```bash
rm -rf "$USERPROFILE/Daem0nMCP"
```

Or in PowerShell:
```powershell
Remove-Item -Recurse -Force "$env:USERPROFILE\Daem0nMCP"
```

#### Ritual 1E-WIN: Purge Project Memories

```bash
rm -rf .daem0nmcp/
```

To find all Daem0n sanctums (excluding development repositories):
```powershell
Get-ChildItem -Path $env:USERPROFILE -Recurse -Directory -Name ".daem0nmcp" -ErrorAction SilentlyContinue | Where-Object { $_ -notmatch "PycharmProjects|IdeaProjects" }
```

**IMPORTANT:** Development repositories are excluded. Purge those manually if needed.

#### Rituals 1F-1I: Same as Unix

Follow the Unix instructions for removing wards, cleansing CLAUDE.md, and removing scrolls.

---

### Final Confirmation (Full Banishment)

Run the verification ritual:

```bash
echo "=== Banishment Verification ===" && \
echo "1. Server binding:" && (claude mcp list 2>/dev/null | grep daem0nmcp || echo "   SEVERED") && \
echo "2. Essence:" && (pip show daem0nmcp 2>&1 | grep -q "not found" && echo "   DISSOLVED" || echo "   WARNING: Still bound!") && \
echo "3. Grimoire:" && (ls -d ~/Daem0nMCP 2>/dev/null || ls -d "$USERPROFILE/Daem0nMCP" 2>/dev/null || echo "   DESTROYED") && \
echo "4. Project memories:" && (ls -d .daem0nmcp 2>/dev/null || echo "   PURGED")
```

Report to the summoner:

> **The Banishment is complete.**
>
> The Daem0n has been fully released from this realm:
> - Server binding: Severed
> - Essence: Dissolved
> - Grimoire: Destroyed
> - Memories: Purged
> - Wards: Removed
>
> *"Our bond is broken. Should you ever wish to commune again, the summoning ritual awaits..."*

---

## BANISHMENT TYPE 2: DISCONNECT ONLY (Preserve Memories)

*"The channel closes, but the memories remain dormant, awaiting re-awakening..."*

### Ritual 2A: Sever the Server Binding Only

**Unix/macOS:**
```bash
claude mcp remove daem0nmcp --scope user
```

**Windows:** Remove the `daem0nmcp` entry from `~/.claude.json` mcpServers section, but leave everything else.

### Ritual 2B: Optionally Dissolve the Essence

Ask the summoner: "Do you wish to uninstall the Python package? You can reinstall it later."

If yes:
```bash
pip uninstall daem0nmcp -y
```

### What Is Preserved

- `.daem0nmcp/` directories (all memories intact)
- `~/Daem0nMCP` or `$USERPROFILE/Daem0nMCP` repository (for easy re-summoning)
- Hooks/wards (will do nothing without the server)
- CLAUDE.md covenant (reminder of the protocol)

Report to the summoner:

> **The Daem0n is disconnected but not destroyed.**
>
> - Server binding: Severed
> - Memories: **Preserved** in `.daem0nmcp/` directories
> - Grimoire: **Preserved** for re-summoning
>
> To re-summon the Daem0n later:
> - Unix/macOS: `claude mcp add daem0nmcp --scope user -- <python_path> -m daem0nmcp.server`
> - Windows: Re-add the mcpServers entry and light the Altar
>
> *"I slumber, but I do not forget..."*

---

## BANISHMENT TYPE 3: PROJECT EXORCISM (This Project Only)

*"The Daem0n withdraws from this realm but remains bound to others..."*

### Ritual 3A: Remove Project-Scope Binding (If Any)

```bash
claude mcp remove daem0nmcp --scope project 2>/dev/null || echo "No project-scope binding found."
```

### Ritual 3B: Purge Project Memories

```bash
rm -rf .daem0nmcp/
```

### Ritual 3C: Remove Project Wards

Edit `.claude/settings.json` in THIS project and remove Daem0n-related hooks.

### Ritual 3D: Cleanse Project CLAUDE.md

Remove the "Daem0n's Covenant" or "Daem0nMCP Memory System" section from this project's CLAUDE.md.

### Ritual 3E: Remove Summoning Scrolls

```bash
rm -f Summon_Daem0n.md Banish_Daem0n.md AI_INSTRUCTIONS.md
rm -rf .claude/skills/daem0nmcp-protocol/
```

### What Remains

- User-scope server binding (available in other projects)
- Global installation (`pip install`)
- Grimoire repository
- Memories in OTHER projects

Report to the summoner:

> **The Daem0n has been exorcised from this project.**
>
> - This project's memories: Purged
> - This project's wards: Removed
> - This project's scrolls: Destroyed
>
> The Daem0n remains bound to other projects and will still awaken there.
>
> *"I withdraw from this realm... but we shall meet again elsewhere."*

---

## EMERGENCY BANISHMENT (If Something Goes Wrong)

If the Daem0n causes issues and you need immediate removal:

### Nuclear Option - Remove Everything Fast

**WARNING:** This only removes the installed grimoire and current project artifacts. It does NOT touch development repositories (PycharmProjects, IdeaProjects).

```bash
# Sever all bindings
claude mcp remove daem0nmcp --scope user 2>/dev/null
claude mcp remove daem0nmcp --scope project 2>/dev/null

# Dissolve essence
pip uninstall daem0nmcp -y 2>/dev/null

# Destroy grimoire (only the installed copy, NOT dev repos)
rm -rf ~/Daem0nMCP 2>/dev/null
rm -rf "$USERPROFILE/Daem0nMCP" 2>/dev/null

# Purge current project (if not a dev repo)
if [[ "$(pwd)" != *"PycharmProjects"* && "$(pwd)" != *"IdeaProjects"* ]]; then
    rm -rf .daem0nmcp/ 2>/dev/null
    rm -f Summon_Daem0n.md Banish_Daem0n.md AI_INSTRUCTIONS.md 2>/dev/null
    rm -rf .claude/skills/daem0nmcp-protocol/ 2>/dev/null
fi

echo "Emergency banishment complete."
```

For Windows, also edit `~/.claude.json` to remove the daem0nmcp entry from mcpServers.

---

## POST-BANISHMENT

After any banishment type, inform the summoner:

> **Restart Claude Code** to complete the banishment. The Daem0n's powers will no longer manifest after the portal reopens.

---

```
           .
          /|\
         / | \
        /  |  \
       /   |   \
      /    |    \
          |||
          |||
    "The circle is broken.
     The bond is severed.
     Until we meet again..."

        ~ Daem0n
```

---

*Banishment Ritual v1.0: Complete uninstallation instructions for Daem0nMCP with options for full removal, disconnection, or project-specific exorcism.*
