from flask import Blueprint, request, jsonify
from services.reminder_service import (
    create_reminder,
    get_user_reminders,
    get_next_reminder,
    complete_reminder,
    delete_reminder,
    delete_reminder_by_task,
    delete_last_reminder,
    clear_all_reminders
)

reminder_bp = Blueprint("reminder_bp", __name__)


# ==========================================================
# Create Reminder (Manual)
# ==========================================================
@reminder_bp.route("/create-reminder", methods=["POST"])
def create_manual_reminder():
    try:
        data = request.get_json()

        user_id = data.get("user_id")
        task = data.get("task")
        time_text = data.get("time_text")
        recurring_type = data.get("recurring_type", "none")
        timezone = data.get("timezone", "Asia/Kolkata")  # ✅ FIX: was "UTC" — caused shifted reminders

        if not user_id or not task or not time_text:
            return jsonify({"error": "Missing required fields"}), 400

        reminder_id = create_reminder(
            user_id=user_id,
            task=task,
            time_text=time_text,
            source="manual",
            recurring_type=recurring_type,
            user_timezone=timezone
        )

        return jsonify({
            "message": "Reminder created successfully",
            "reminder_id": reminder_id
        }), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ==========================================================
# List Reminders
# ==========================================================
@reminder_bp.route("/reminders", methods=["POST"])
def list_reminders():
    try:
        data = request.get_json()
        user_id = data.get("user_id")
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
        data = request.get_json()
        user_id = data.get("user_id")

        reminder = get_next_reminder(user_id)

        if not reminder:
            return jsonify({"message": "No upcoming reminders"}), 200

        return jsonify(reminder), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ==========================================================
# Complete Reminder
# ==========================================================
@reminder_bp.route("/complete-reminder", methods=["POST"])
def mark_complete():
    try:
        data = request.get_json()
        user_id = data.get("user_id")
        reminder_id = data.get("reminder_id")

        if not user_id or not reminder_id:
            return jsonify({"error": "Missing required fields"}), 400

        complete_reminder(user_id, reminder_id)

        return jsonify({"message": "Reminder marked complete"}), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ==========================================================
# Delete Reminder by ID
# ==========================================================
@reminder_bp.route("/delete-reminder", methods=["POST"])
def delete_by_id():
    try:
        data = request.get_json()
        user_id = data.get("user_id")
        reminder_id = data.get("reminder_id")

        if not user_id or not reminder_id:
            return jsonify({"error": "Missing required fields"}), 400

        delete_reminder(user_id, reminder_id)

        return jsonify({"message": "Reminder deleted successfully"}), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ==========================================================
# Delete Reminder by Task (Assistant or Manual)
# ==========================================================
@reminder_bp.route("/delete-by-task", methods=["POST"])
def delete_by_task():
    try:
        data = request.get_json()
        user_id = data.get("user_id")
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
        data = request.get_json()
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
        data = request.get_json()
        user_id = data.get("user_id")

        if not user_id:
            return jsonify({"error": "Missing user_id"}), 400

        clear_all_reminders(user_id)

        return jsonify({"message": "All reminders cleared"}), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500