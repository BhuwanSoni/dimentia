from flask import Blueprint, request, jsonify
from services.reminder_service import (
    create_reminder,
    get_user_reminders,
    get_next_reminder,
    get_missed_reminders,
    complete_reminder,
    delete_reminder,
    delete_reminder_by_task,
    delete_last_reminder,
    clear_all_reminders,
    snooze_reminder,
    mark_reminder_missed,
    advance_recurring_reminder,   # ✅ imported so route can call it directly
)

reminder_bp = Blueprint("reminder_bp", __name__)


# ==========================================================
# Create Reminder (Manual)
# ==========================================================
@reminder_bp.route("/create-reminder", methods=["POST"])
def create_manual_reminder():
    try:
        data = request.get_json()

        user_id        = data.get("user_id")
        task           = data.get("task")
        time_text      = data.get("time_text")
        # ✅ now accepts: none | daily | weekly | monthly | custom
        recurring_type = data.get("recurring_type", "none")
        timezone       = data.get("timezone", "Asia/Kolkata")
        custom_days    = data.get("custom_days")   # list[int] for "custom" type

        if not user_id or not task or not time_text:
            return jsonify({"error": "Missing required fields"}), 400

        reminder_id = create_reminder(
            user_id=user_id,
            task=task,
            time_text=time_text,
            source="manual",
            recurring_type=recurring_type,
            user_timezone=timezone,
            custom_days=custom_days,
        )

        return jsonify({
            "message":     "Reminder created successfully",
            "reminder_id": reminder_id,
        }), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ==========================================================
# List Reminders
# ==========================================================
@reminder_bp.route("/reminders", methods=["POST"])
def list_reminders():
    try:
        data             = request.get_json()
        user_id          = data.get("user_id")
        include_completed = data.get("include_completed", False)

        reminders = get_user_reminders(user_id, include_completed)

        return jsonify(reminders), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ==========================================================
# Get Next Reminder
# ==========================================================
@reminder_bp.route("/next-reminder", methods=["POST"])
def next_reminder():
    try:
        data    = request.get_json()
        user_id = data.get("user_id")

        reminder = get_next_reminder(user_id)

        if not reminder:
            return jsonify({"message": "No upcoming reminders"}), 200

        return jsonify(reminder), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ==========================================================
# ✅ NEW: Get Missed Reminders
# ==========================================================
@reminder_bp.route("/missed-reminders", methods=["POST"])
def missed_reminders():
    """
    Returns reminders that are past-due and not completed.
    Flutter uses this to surface the 'You missed X — snooze?' banner.
    """
    try:
        data    = request.get_json()
        user_id = data.get("user_id")

        if not user_id:
            return jsonify({"error": "Missing user_id"}), 400

        missed = get_missed_reminders(user_id)

        return jsonify(missed), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ==========================================================
# ✅ NEW: Snooze Reminder
# ==========================================================
@reminder_bp.route("/snooze-reminder", methods=["POST"])
def snooze():
    """
    Reschedule a missed reminder by N minutes (default 10).
    Flutter calls this when the user taps 'Remind me again in 10 min'.
    """
    try:
        data           = request.get_json()
        user_id        = data.get("user_id")
        reminder_id    = data.get("reminder_id")
        snooze_minutes = data.get("snooze_minutes", 10)

        if not user_id or not reminder_id:
            return jsonify({"error": "Missing required fields"}), 400

        new_time = snooze_reminder(user_id, reminder_id, snooze_minutes)

        return jsonify({
            "message":  f"Reminder snoozed for {snooze_minutes} minutes",
            "new_time": new_time.isoformat(),
        }), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ==========================================================
# ✅ NEW: Mark Reminder as Missed
# ==========================================================
@reminder_bp.route("/mark-missed", methods=["POST"])
def mark_missed():
    """
    Explicitly flags a reminder as missed in Firestore.
    Flutter stream will pick this up and surface a snooze banner.
    """
    try:
        data        = request.get_json()
        user_id     = data.get("user_id")
        reminder_id = data.get("reminder_id")

        if not user_id or not reminder_id:
            return jsonify({"error": "Missing required fields"}), 400

        mark_reminder_missed(user_id, reminder_id)

        return jsonify({"message": "Reminder marked as missed"}), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ==========================================================
# Complete Reminder
# ==========================================================
@reminder_bp.route("/complete-reminder", methods=["POST"])
def mark_complete():
    try:
        data        = request.get_json()
        user_id     = data.get("user_id")
        reminder_id = data.get("reminder_id")

        if not user_id or not reminder_id:
            return jsonify({"error": "Missing required fields"}), 400

        complete_reminder(user_id, reminder_id)
        # ✅ advance_recurring_reminder() is called INSIDE complete_reminder()
        # in reminder_service.py. Do NOT call it here too — double-advancing
        # would skip days (daily → every 2 days, weekly → every 2 weeks, etc.)

        return jsonify({"message": "Reminder marked complete"}), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ==========================================================
# Delete Reminder by ID
# ==========================================================
@reminder_bp.route("/delete-reminder", methods=["POST"])
def delete_by_id():
    try:
        data        = request.get_json()
        user_id     = data.get("user_id")
        reminder_id = data.get("reminder_id")

        if not user_id or not reminder_id:
            return jsonify({"error": "Missing required fields"}), 400

        delete_reminder(user_id, reminder_id)

        return jsonify({"message": "Reminder deleted successfully"}), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ==========================================================
# Delete Reminder by Task
# ==========================================================
@reminder_bp.route("/delete-by-task", methods=["POST"])
def delete_by_task():
    try:
        data      = request.get_json()
        user_id   = data.get("user_id")
        task_text = data.get("task_text")

        if not user_id or not task_text:
            return jsonify({"error": "Missing required fields"}), 400

        deleted = delete_reminder_by_task(user_id, task_text)

        if deleted:
            return jsonify({"message": "Reminder deleted successfully"}), 200
        else:
            return jsonify({"message": "Reminder not found"}), 404

    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ==========================================================
# Delete Last Reminder
# ==========================================================
@reminder_bp.route("/delete-last", methods=["POST"])
def delete_last():
    try:
        data    = request.get_json()
        user_id = data.get("user_id")

        if not user_id:
            return jsonify({"error": "Missing user_id"}), 400

        deleted = delete_last_reminder(user_id)

        if deleted:
            return jsonify({"message": "Last reminder deleted"}), 200
        else:
            return jsonify({"message": "No reminders found"}), 404

    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ==========================================================
# Clear All Reminders
# ==========================================================
@reminder_bp.route("/clear-reminders", methods=["POST"])
def clear_reminders():
    try:
        data    = request.get_json()
        user_id = data.get("user_id")

        if not user_id:
            return jsonify({"error": "Missing user_id"}), 400

        clear_all_reminders(user_id)

        return jsonify({"message": "All reminders cleared"}), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500