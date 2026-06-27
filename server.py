"""
Employee Leave Management MCP Server
=====================================
An MCP server built with FastMCP that connects to a Supabase database and
exposes employee leave management capabilities to any MCP-compatible AI host
(Claude Desktop, Cursor, VS Code Copilot Agent, etc.).

Exposed Tools
-------------
  get_employee_info       — look up an employee by code or email
  list_employees          — list all active employees (optional dept filter)
  get_leave_balance       — remaining/used leaves by employee & year
  apply_for_leave         — submit a new leave request
  get_leave_history       — past + pending requests for an employee
  get_leave_request       — details of a single request
  cancel_leave_request    — withdraw a pending leave request
  approve_leave_request   — manager: approve a pending request
  reject_leave_request    — manager: reject a pending request
  list_leave_types        — all available leave categories

Connect to Claude Desktop
--------------------------
Add the following block to your claude_desktop_config.json:

  macOS  : ~/Library/Application Support/Claude/claude_desktop_config.json
  Windows: %APPDATA%\\Claude\\claude_desktop_config.json

{
  "mcpServers": {
    "employee-leave": {
      "command": "uv",
      "args": [
        "--directory",
        "/absolute/path/to/mcp/database_supabase",
        "run",
        "python"
        "server.py"
      ]
    }
  }
}

Note: Use the full path to the uv executable if needed (run `which uv` to find it).

Test without Claude Desktop
----------------------------
  uv run fastmcp dev server.py
  # Opens MCP Inspector at http://localhost:6274
"""

import os
from datetime import date, timedelta
from typing import Any

from dotenv import load_dotenv
from fastmcp import FastMCP
from supabase import Client, create_client

load_dotenv()

# ── Supabase client ────────────────────────────────────────────────────────────
SUPABASE_URL: str = os.environ["SUPABASE_URL"]
SUPABASE_KEY: str = os.environ["SUPABASE_KEY"]

supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

# ── FastMCP server ─────────────────────────────────────────────────────────────
mcp = FastMCP(
    name="employee-leave",
    instructions=(
        "You help employees manage their leave requests. "
        "Use get_employee_info() or list_employees() to identify the employee first. "
        "Use get_leave_balance() to check current balances before applying. "
        "Use apply_for_leave() to submit requests and get_leave_history() to review them. "
        "Only call approve_leave_request() / reject_leave_request() when the user is a manager."
    ),
)


# ══════════════════════════════════════════════════════════════════════════════
# Internal helpers
# ══════════════════════════════════════════════════════════════════════════════

def _business_days(start: date, end: date) -> int:
    """Count Monday-Friday days between start and end (inclusive)."""
    if end < start:
        return 0
    total = 0
    current = start
    while current <= end:
        if current.weekday() < 5:  # 0=Mon … 4=Fri
            total += 1
        current += timedelta(days=1)
    return total


def _resolve_employee(identifier: str) -> dict[str, Any] | None:
    """Return employee row matching employee_code or email (case-insensitive)."""
    ident = identifier.strip()
    res = (
        supabase.table("employees")
        .select("*")
        .or_(f"employee_code.ilike.{ident},email.ilike.{ident}")
        .eq("is_active", True)
        .limit(1)
        .execute()
    )
    return res.data[0] if res.data else None


def _get_leave_type_id(leave_type_name: str) -> int | None:
    """Return leave_type.id for the given name (case-insensitive)."""
    res = (
        supabase.table("leave_types")
        .select("id")
        .ilike("name", leave_type_name)
        .limit(1)
        .execute()
    )
    return res.data[0]["id"] if res.data else None


# ══════════════════════════════════════════════════════════════════════════════
# MCP Tools
# ══════════════════════════════════════════════════════════════════════════════

@mcp.tool()
def list_leave_types() -> list[dict[str, Any]]:
    """
    Return all available leave categories with their yearly default allocation.
    Call this to know valid leave_type values before applying for leave.
    """
    res = (
        supabase.table("leave_types")
        .select("name, description, default_days")
        .order("id")
        .execute()
    )
    return res.data


@mcp.tool()
def list_employees(department: str = "") -> list[dict[str, Any]]:
    """
    List all active employees, optionally filtered by department.

    Args:
        department: Filter by department name (partial match, case-insensitive).
                    Leave empty to return all employees.
    """
    query = (
        supabase.table("employees")
        .select("employee_code, full_name, email, department, position, joining_date")
        .eq("is_active", True)
        .order("employee_code")
    )
    if department:
        query = query.ilike("department", f"%{department}%")
    return query.execute().data


@mcp.tool()
def get_employee_info(identifier: str) -> dict[str, Any]:
    """
    Fetch details for a single employee.

    Args:
        identifier: Employee code (e.g. "EMP001") or email address.
    """
    emp = _resolve_employee(identifier)
    if not emp:
        return {"error": f"No active employee found for '{identifier}'."}
    # Remove internal UUID from public output
    emp.pop("id", None)
    return emp


@mcp.tool()
def get_leave_balance(identifier: str, year: int = 0) -> list[dict[str, Any]]:
    """
    Return the leave balance (total / used / remaining) for all leave types
    for the specified employee and year.

    Args:
        identifier: Employee code or email.
        year:       Calendar year (e.g. 2025). Defaults to the current year.
    """
    if year == 0:
        year = date.today().year

    emp = _resolve_employee(identifier)
    if not emp:
        return [{"error": f"No active employee found for '{identifier}'."}]

    res = (
        supabase.table("leave_balances_view")
        .select("leave_type, year, total_days, used_days, remaining_days")
        .eq("employee_id", emp["id"])
        .eq("year", year)
        .order("leave_type")
        .execute()
    )

    if not res.data:
        return [{"message": f"No leave balances found for {emp['full_name']} in {year}."}]

    return [
        {
            "employee": emp["full_name"],
            "employee_code": emp["employee_code"],
            "year": year,
            "leave_type": row["leave_type"],
            "total_days": row["total_days"],
            "used_days": row["used_days"],
            "remaining_days": row["remaining_days"],
        }
        for row in res.data
    ]


@mcp.tool()
def apply_for_leave(
    identifier: str,
    leave_type: str,
    start_date: str,
    end_date: str,
    reason: str = "",
) -> dict[str, Any]:
    """
    Submit a leave request on behalf of an employee.

    Args:
        identifier: Employee code (e.g. "EMP001") or email.
        leave_type: Type of leave — use list_leave_types() for valid values
                    (e.g. "Annual", "Sick", "Casual").
        start_date: First day of leave in YYYY-MM-DD format.
        end_date:   Last  day of leave in YYYY-MM-DD format.
        reason:     Optional reason for the leave request.
    """
    # ── Resolve employee ──────────────────────────────────────────────────────
    emp = _resolve_employee(identifier)
    if not emp:
        return {"error": f"No active employee found for '{identifier}'."}

    # ── Validate dates ────────────────────────────────────────────────────────
    try:
        s_date = date.fromisoformat(start_date)
        e_date = date.fromisoformat(end_date)
    except ValueError:
        return {"error": "Dates must be in YYYY-MM-DD format (e.g. '2025-08-04')."}

    if e_date < s_date:
        return {"error": "end_date must be on or after start_date."}

    days = _business_days(s_date, e_date)
    if days == 0:
        return {"error": "The selected date range contains no business days (Mon-Fri)."}

    # ── Resolve leave type ────────────────────────────────────────────────────
    lt_id = _get_leave_type_id(leave_type)
    if lt_id is None:
        return {"error": f"Unknown leave type '{leave_type}'. Call list_leave_types() for valid options."}

    # ── Check balance ─────────────────────────────────────────────────────────
    year = s_date.year
    bal = (
        supabase.table("leave_balances")
        .select("id, total_days, used_days")
        .eq("employee_id", emp["id"])
        .eq("leave_type_id", lt_id)
        .eq("year", year)
        .limit(1)
        .execute()
    )

    if not bal.data:
        return {
            "error": (
                f"No '{leave_type}' balance found for {emp['full_name']} in {year}. "
                "Contact HR to allocate leave for this year."
            )
        }

    balance = bal.data[0]
    remaining = balance["total_days"] - balance["used_days"]
    if days > remaining:
        return {
            "error": (
                f"Insufficient balance. Requested {days} day(s) but only "
                f"{remaining} '{leave_type}' day(s) remain in {year}."
            )
        }

    # ── Check for overlapping pending/approved requests ───────────────────────
    overlap = (
        supabase.table("leave_requests")
        .select("id, start_date, end_date, status")
        .eq("employee_id", emp["id"])
        .in_("status", ["pending", "approved"])
        .lte("start_date", end_date)
        .gte("end_date", start_date)
        .execute()
    )
    if overlap.data:
        return {
            "error": (
                f"Overlapping leave request already exists "
                f"(ID: {overlap.data[0]['id']}, "
                f"from {overlap.data[0]['start_date']} to {overlap.data[0]['end_date']}, "
                f"status: {overlap.data[0]['status']})."
            )
        }

    # ── Insert request ────────────────────────────────────────────────────────
    insert_res = (
        supabase.table("leave_requests")
        .insert({
            "employee_id":   emp["id"],
            "leave_type_id": lt_id,
            "start_date":    start_date,
            "end_date":      end_date,
            "days_count":    days,
            "reason":        reason or None,
            "status":        "pending",
        })
        .execute()
    )

    new_req = insert_res.data[0]
    return {
        "success": True,
        "request_id":    new_req["id"],
        "employee":      emp["full_name"],
        "leave_type":    leave_type,
        "start_date":    start_date,
        "end_date":      end_date,
        "days_requested": days,
        "status":        "pending",
        "message": (
            f"Leave request submitted successfully. "
            f"{remaining - days} '{leave_type}' day(s) will remain after approval."
        ),
    }


@mcp.tool()
def get_leave_history(
    identifier: str,
    year: int = 0,
    status: str = "",
) -> list[dict[str, Any]]:
    """
    Retrieve all leave requests for an employee, optionally filtered by year or status.

    Args:
        identifier: Employee code or email.
        year:       Filter by calendar year. 0 = all years.
        status:     Filter by status: "pending", "approved", "rejected", "cancelled".
                    Leave empty to return all statuses.
    """
    emp = _resolve_employee(identifier)
    if not emp:
        return [{"error": f"No active employee found for '{identifier}'."}]

    query = (
        supabase.table("leave_requests")
        .select(
            "id, leave_type_id, start_date, end_date, days_count, "
            "reason, status, manager_note, created_at"
        )
        .eq("employee_id", emp["id"])
        .order("start_date", desc=True)
    )

    if year:
        # Filter requests that start in the given year
        query = query.gte("start_date", f"{year}-01-01").lte("start_date", f"{year}-12-31")

    if status:
        valid = {"pending", "approved", "rejected", "cancelled"}
        if status.lower() not in valid:
            return [{"error": f"Invalid status '{status}'. Valid values: {sorted(valid)}."}]
        query = query.eq("status", status.lower())

    rows = query.execute().data
    if not rows:
        return [{"message": f"No leave requests found for {emp['full_name']}."}]

    # Enrich with leave type names
    lt_ids = list({r["leave_type_id"] for r in rows})
    lt_res = supabase.table("leave_types").select("id, name").in_("id", lt_ids).execute()
    lt_map: dict[int, str] = {lt["id"]: lt["name"] for lt in lt_res.data}

    return [
        {
            "request_id":  row["id"],
            "employee":    emp["full_name"],
            "leave_type":  lt_map.get(row["leave_type_id"], "Unknown"),
            "start_date":  row["start_date"],
            "end_date":    row["end_date"],
            "days":        row["days_count"],
            "reason":      row["reason"],
            "status":      row["status"],
            "manager_note": row["manager_note"],
            "applied_on":  row["created_at"][:10],
        }
        for row in rows
    ]


@mcp.tool()
def get_leave_request(request_id: int) -> dict[str, Any]:
    """
    Fetch full details of a single leave request by its ID.

    Args:
        request_id: The numeric ID of the leave request (returned by apply_for_leave or get_leave_history).
    """
    res = (
        supabase.table("leave_requests")
        .select(
            "id, employee_id, leave_type_id, start_date, end_date, "
            "days_count, reason, status, manager_note, created_at, updated_at"
        )
        .eq("id", request_id)
        .limit(1)
        .execute()
    )
    if not res.data:
        return {"error": f"Leave request #{request_id} not found."}

    row = res.data[0]

    # Enrich: employee name
    emp = supabase.table("employees").select("employee_code, full_name").eq("id", row["employee_id"]).limit(1).execute()
    emp_name = emp.data[0]["full_name"] if emp.data else "Unknown"
    emp_code = emp.data[0]["employee_code"] if emp.data else "Unknown"

    # Enrich: leave type name
    lt = supabase.table("leave_types").select("name").eq("id", row["leave_type_id"]).limit(1).execute()
    lt_name = lt.data[0]["name"] if lt.data else "Unknown"

    return {
        "request_id":   row["id"],
        "employee_code": emp_code,
        "employee":     emp_name,
        "leave_type":   lt_name,
        "start_date":   row["start_date"],
        "end_date":     row["end_date"],
        "days":         row["days_count"],
        "reason":       row["reason"],
        "status":       row["status"],
        "manager_note": row["manager_note"],
        "applied_on":   row["created_at"][:10],
        "last_updated": row["updated_at"][:10],
    }


@mcp.tool()
def cancel_leave_request(request_id: int, identifier: str) -> dict[str, Any]:
    """
    Cancel a pending leave request. Only the employee who applied can cancel.

    Args:
        request_id: Numeric ID of the leave request to cancel.
        identifier: Employee code or email of the requester (for authorisation).
    """
    emp = _resolve_employee(identifier)
    if not emp:
        return {"error": f"No active employee found for '{identifier}'."}

    res = (
        supabase.table("leave_requests")
        .select("id, employee_id, status, leave_type_id, days_count")
        .eq("id", request_id)
        .limit(1)
        .execute()
    )
    if not res.data:
        return {"error": f"Leave request #{request_id} not found."}

    req = res.data[0]

    if req["employee_id"] != emp["id"]:
        return {"error": "You can only cancel your own leave requests."}

    if req["status"] != "pending":
        return {
            "error": (
                f"Cannot cancel a request with status '{req['status']}'. "
                "Only 'pending' requests can be cancelled."
            )
        }

    supabase.table("leave_requests").update({"status": "cancelled"}).eq("id", request_id).execute()

    return {
        "success": True,
        "request_id": request_id,
        "message": f"Leave request #{request_id} has been cancelled.",
    }


@mcp.tool()
def approve_leave_request(request_id: int, manager_note: str = "") -> dict[str, Any]:
    """
    Approve a pending leave request and deduct days from the employee's balance.
    Call this only when acting as an HR manager or team lead.

    Args:
        request_id:   Numeric ID of the leave request to approve.
        manager_note: Optional note from the manager (visible to the employee).
    """
    res = (
        supabase.table("leave_requests")
        .select("id, employee_id, leave_type_id, days_count, status, start_date")
        .eq("id", request_id)
        .limit(1)
        .execute()
    )
    if not res.data:
        return {"error": f"Leave request #{request_id} not found."}

    req = res.data[0]
    if req["status"] != "pending":
        return {"error": f"Request #{request_id} is already '{req['status']}'. Only pending requests can be approved."}

    year = int(req["start_date"][:4])

    # Deduct from balance
    bal = (
        supabase.table("leave_balances")
        .select("id, used_days, total_days")
        .eq("employee_id", req["employee_id"])
        .eq("leave_type_id", req["leave_type_id"])
        .eq("year", year)
        .limit(1)
        .execute()
    )

    if bal.data:
        new_used = bal.data[0]["used_days"] + req["days_count"]
        supabase.table("leave_balances").update({"used_days": new_used}).eq("id", bal.data[0]["id"]).execute()

    # Update request status
    supabase.table("leave_requests").update({
        "status":       "approved",
        "manager_note": manager_note or None,
    }).eq("id", request_id).execute()

    return {
        "success":     True,
        "request_id":  request_id,
        "status":      "approved",
        "days_deducted": req["days_count"],
        "message":     f"Leave request #{request_id} approved. {req['days_count']} day(s) deducted from balance.",
    }


@mcp.tool()
def reject_leave_request(request_id: int, manager_note: str = "") -> dict[str, Any]:
    """
    Reject a pending leave request.
    Call this only when acting as an HR manager or team lead.

    Args:
        request_id:   Numeric ID of the leave request to reject.
        manager_note: Reason for rejection (recommended — visible to employee).
    """
    res = (
        supabase.table("leave_requests")
        .select("id, status")
        .eq("id", request_id)
        .limit(1)
        .execute()
    )
    if not res.data:
        return {"error": f"Leave request #{request_id} not found."}

    req = res.data[0]
    if req["status"] != "pending":
        return {"error": f"Request #{request_id} is already '{req['status']}'. Only pending requests can be rejected."}

    supabase.table("leave_requests").update({
        "status":       "rejected",
        "manager_note": manager_note or None,
    }).eq("id", request_id).execute()

    return {
        "success":    True,
        "request_id": request_id,
        "status":     "rejected",
        "message":    f"Leave request #{request_id} has been rejected.",
    }


# ── MCP Resource ──────────────────────────────────────────────────────────────
@mcp.resource("leave://schema")
def schema_overview() -> str:
    """Full schema overview of the leave management system."""
    return """
Employee Leave Management — Database Schema
===========================================

employees          : employee_code, full_name, email, department, position, joining_date
leave_types        : name, description, default_days
leave_balances     : employee_id, leave_type_id, year, total_days, used_days
leave_balances_view: denormalised view adding employee name, leave type name, remaining_days
leave_requests     : employee_id, leave_type_id, start_date, end_date, days_count,
                     reason, status (pending|approved|rejected|cancelled), manager_note

Workflow:
  1. Use list_employees() to find the employee.
  2. Use get_leave_balance() to check available days.
  3. Use apply_for_leave() to submit a request (status = pending).
  4. Manager uses approve_leave_request() or reject_leave_request().
  5. Balance is deducted automatically on approval.
  6. Employee can cancel_leave_request() while still pending.
"""


# ── MCP Prompt ────────────────────────────────────────────────────────────────
@mcp.prompt()
def leave_assistant() -> str:
    """Structured conversation starter for the leave management assistant."""
    return (
        "You are a helpful HR leave management assistant. "
        "When an employee wants to check their leaves, first confirm their employee code or email. "
        "Always show current balances before letting them apply for leave. "
        "Summarise leave requests neatly with dates, type, days, and current status. "
        "Be empathetic and professional."
    )


if __name__ == "__main__":
    mcp.run(transport="stdio")
