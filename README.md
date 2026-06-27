# Employee Leave Management — MCP Server

### [Check out GenAI and System Design videos](https://www.youtube.com/@CodingJist)

An MCP (Model Context Protocol) server built with **FastMCP** that connects to a **Supabase** PostgreSQL database and lets Claude Desktop manage employee leave — checking balances, applying for leave, approvals, history, and more.

---

## Architecture

```
┌───────────────────────────────────────────────────────┐
│  Claude Desktop (MCP Host)                            │
│                                                       │
│  "How many leaves does EMP001 have left this year?"   │
│                                                       │
│  Claude ──► get_leave_balance("EMP001", 2025)         │
│          ◄── [{Annual: 13 remaining}, {Sick: 8}, …]   │
│                                                       │
│  Claude: "Aditya has 13 Annual, 8 Sick, and 5 Casual  │
│           leave days remaining for 2025."             │
└───────────────────────────────────────────────────────┘
          │ stdio (subprocess)
          ▼
┌─────────────────────┐        ┌──────────────────────┐
│  server.py          │        │  Supabase (Postgres)  │
│  FastMCP + tools    │◄──────►│  employees            │
│                     │  REST  │  leave_types          │
│                     │  API   │  leave_balances       │
└─────────────────────┘        │  leave_requests       │
                               └──────────────────────┘
```

---

## Exposed Tools

| Tool | What it does |
|---|---|
| `list_leave_types` | All leave categories (Annual, Sick, Casual, …) with default allocation |
| `list_employees` | Active employees, optional department filter |
| `get_employee_info` | Look up one employee by code or email |
| `get_leave_balance` | Remaining / used / total days by employee & year |
| `apply_for_leave` | Submit a leave request (validates balance & date overlaps) |
| `get_leave_history` | All requests for an employee, filterable by year/status |
| `get_leave_request` | Full details of a single request by ID |
| `cancel_leave_request` | Employee withdraws a pending request |
| `approve_leave_request` | Manager approves — auto-deducts days from balance |
| `reject_leave_request` | Manager rejects with optional note |

**Resources**
- `leave://schema` — full schema overview attachable as context

**Prompts**
- `leave_assistant` — structured conversation starter for the HR assistant

---

## Quick Start

### Step 1 — Create a Supabase project

1. Go to [https://supabase.com](https://supabase.com) and create a free project.
2. After the project is ready, go to **Project Settings → API** and copy:
   - **Project URL** → `SUPABASE_URL`
   - **Project API Keys → `anon` public key** (or `service_role` key for full access) → `SUPABASE_KEY`

### Step 2 — Set up the database

1. In the Supabase Dashboard, open the **SQL Editor** → **New Query**.
2. Paste the full contents of [`setup_database.sql`](setup_database.sql) and click **Run**.

This creates four tables (`employees`, `leave_types`, `leave_balances`, `leave_requests`) plus a convenience view (`leave_balances_view`) and seeds 8 employees with realistic 2025 balances.

### Step 3 — Configure environment variables

```bash
cd demo_projects/mcp
cp .env.example .env
# Edit .env with your Supabase URL and Key
```

`.env` contents:
```
SUPABASE_URL=https://your-project-ref.supabase.co
SUPABASE_KEY=your-anon-or-service-role-key
```

### Step 4 — Install dependencies

```bash
uv sync
```

### Step 5 — Test interactively (without Claude Desktop)

```bash
#uv run fastmcp dev server.py
uv run python server.py
# Opens MCP Inspector at http://localhost:6274
```

---

## Connect to Claude Desktop

### Locate the config file

| OS | Path |
|---|---|
| macOS | `~/Library/Application Support/Claude/claude_desktop_config.json` |
| Windows | `%APPDATA%\Claude\claude_desktop_config.json` |
| Linux | `~/.config/Claude/claude_desktop_config.json` |

### Add the server block

```json
{
  "mcpServers": {
    "employee-leave": {
      "command": "uv",
      "args": [
        "--directory",
        "/absolute/path/to/mcp/database_supabase",
        "run",
        "python",
        "server.py"
      ]
    }
  }
}
```

> **Important:** Use the **absolute path** in `--directory`. You can get it by running `pwd` in the project folder.

> **Note:** You may need to provide the full path to the `uv` executable in the `command` field. Run `which uv` (macOS/Linux) or `where uv` (Windows) to find it.

### Restart Claude Desktop

Quit and reopen Claude Desktop. Click the **+** ("Add files, connectors, and more") icon in the chat input area, then hover over **Connectors** — you should see `employee-leave` listed there.

> **Note:** Claude for Desktop is not yet available on Linux. Linux users can use the [MCP Inspector](#step-5--test-interactively-without-claude-desktop) or build a custom MCP client instead.

---

## Connect to VS Code (GitHub Copilot)

VS Code supports MCP servers natively through **GitHub Copilot agent mode**. The config format is different from Claude Desktop.

### Locate / create the config file

| Scope | File |
|---|---|
| Workspace (team-shared) | `.vscode/mcp.json` in your project root |
| User profile (all workspaces) | Run `MCP: Open User Configuration` from the Command Palette |

### Add the server block

Create or edit `.vscode/mcp.json`:

```json
{
  "servers": {
    "employee-leave": {
      "command": "uv",
      "args": [
        "--directory",
        "/absolute/path/to/mcp/database_supabase",
        "run",
        "python",
        "server.py"
      ]
    }
  }
}
```

> **Note:** VS Code uses `"servers"` (not `"mcpServers"`) and requires the `"type": "stdio"` field. Use the absolute path in `--directory`.

> **Tip:** You may need to provide the full path to `uv` in `"command"`. Run `which uv` to find it.

### Start the server

1. Open the Command Palette (`Ctrl+Shift+P`) and run **MCP: List Servers**.
2. Select `employee-leave` and choose **Start**.
3. When prompted, confirm you **trust** the server.
4. Open the Chat view (`Ctrl+Alt+I`), switch to **Agent mode**, and the `employee-leave` tools will be available.

### Verify tools are loaded

In the Chat view, select **Configure Tools** (or the tools icon) to see all tools provided by the `employee-leave` server and toggle individual tools on/off.

### Troubleshooting

If the server fails to start, run **MCP: List Servers** → select the server → **Show Output** to view logs.

---

## Example Conversations with Claude

```
You: How many leaves does Aditya have left for 2025?

Claude: [calls get_employee_info("EMP001"), then get_leave_balance("EMP001", 2025)]
        Aditya Sharma (EMP001) has:
        • Annual leave  : 13 days remaining (5 used of 18)
        • Sick leave    :  8 days remaining (2 used of 10)
        • Casual leave  :  5 days remaining (1 used of 6)
```

```
You: Apply for annual leave for EMP002 from 10th July to 18th July 2025.

Claude: [calls apply_for_leave("EMP002", "Annual", "2025-07-10", "2025-07-18")]
        Leave request submitted!
        • Employee   : Priya Nair (EMP002)
        • Type       : Annual
        • Dates      : 10 Jul – 18 Jul 2025  (7 business days)
        • Status     : Pending
        • Remaining after approval: 8 Annual days
```

```
You: Approve request ID 3.

Claude: [calls approve_leave_request(3)]
        Leave request #3 has been approved. 7 days deducted from Priya's Annual balance.
```

---

## Database Schema

```sql
employees          -- employee_code, full_name, email, department, position
leave_types        -- name, description, default_days
leave_balances     -- one row per (employee, leave_type, year)
leave_balances_view -- denormalised view with remaining_days computed
leave_requests     -- status: pending | approved | rejected | cancelled
```

---

## Project Files

```
demo_projects/mcp/
├── server.py             ← FastMCP server (all tools, resources, prompts)
├── setup_database.sql    ← Run once in Supabase SQL Editor
├── pyproject.toml        ← Dependencies (fastmcp, supabase, python-dotenv)
├── .env.example          ← Copy to .env and fill in credentials
└── README.md             ← This file
```
